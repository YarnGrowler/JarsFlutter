// Supabase Edge Function: push
// Triggered by database webhook on notifications INSERT.
// Sends to native FCM tokens (user_fcm_tokens / profiles.fcm_token) and
// to Web Push subscriptions (user_web_push_subscriptions) via @pushforge/builder + fetch.
//
// Secrets (Supabase Dashboard or CLI):
//   - VAPID_PRIVATE_KEY (JSON string: JWK from `npx @pushforge/builder vapid`)
//   - VAPID_SUBJECT (mailto:you@domain)
//   - FIREBASE_SERVICE_ACCOUNT_JSON (optional; overrides bundled JSON for FCM)
//   - SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto)
//
// Deploy: supabase functions deploy push --no-verify-jwt

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { buildPushHTTPRequest } from "npm:@pushforge/builder@2.0.2";
import serviceAccountBundled from "./service-account.json" with { type: "json" };

/** One JSON line per event — filter Edge logs with `jars_push`. */
function pushLog(phase: string, data: Record<string, unknown> = {}) {
  console.log(
    JSON.stringify({
      tag: "jars_push",
      phase,
      t: new Date().toISOString(),
      ...data,
    }),
  );
}

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: {
    id: string;
    user_id: string;
    body: string;
    created_at: string;
  };
  schema: string;
  old_record: null | Record<string, unknown>;
}

async function getAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const encode = (obj: unknown) =>
    btoa(JSON.stringify(obj))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");

  const headerB64 = encode(header);
  const payloadB64 = encode(payload);
  const signingInput = `${headerB64}.${payloadB64}`;

  const pemKey = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");

  const binaryKey = Uint8Array.from(atob(pemKey), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );

  const signatureB64 = btoa(
    String.fromCharCode(...new Uint8Array(signature)),
  )
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const jwt = `${signingInput}.${signatureB64}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await tokenRes.json() as {
    access_token?: string;
    error?: string;
    error_description?: string;
  };
  if (!tokenRes.ok || !tokenData.access_token) {
    throw new Error(
      `OAuth token failed: ${tokenData.error ?? tokenRes.status} ${tokenData.error_description ?? JSON.stringify(tokenData)}`,
    );
  }
  return tokenData.access_token;
}

function getServiceAccount(): Record<string, string> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (raw?.trim()) {
    return JSON.parse(raw) as Record<string, string>;
  }
  return serviceAccountBundled as unknown as Record<string, string>;
}

const PUSH_ICON_PATH = "/icons/jars-notification.svg";

/** FCM HTTP v1 send timeout (OAuth is separate, inside try). */
const FCM_SEND_TIMEOUT_MS = 12_000;
/** Push gateway POST — fail fast; 410/404 are immediate when subscription is dead. */
const WEB_PUSH_FETCH_TIMEOUT_MS = 12_000;

interface WebSubRow {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
}

async function deleteWebPushRow(
  supabaseUrl: string,
  headers: Record<string, string>,
  rowId: string,
): Promise<boolean> {
  const url = new URL(`${supabaseUrl}/rest/v1/user_web_push_subscriptions`);
  url.searchParams.set("id", `eq.${rowId}`);
  const res = await fetch(url.toString(), {
    method: "DELETE",
    headers: { ...headers, Prefer: "return=minimal" },
  });
  return res.ok;
}

Deno.serve(async (req) => {
  const wallStart = performance.now();
  try {
    const payload: WebhookPayload = await req.json();

    const notification = payload.record;
    const userId = notification.user_id;
    // Name avoids TDZ with `const { …, body } = buildPushHTTPRequest(...)` below.
    const notificationBody = notification.body;

    pushLog("start", {
      notification_id: notification.id,
      user_id_prefix: userId ? `${userId.slice(0, 8)}…` : null,
      body_len: notificationBody?.length ?? 0,
      webhook_type: payload.type,
      webhook_table: payload.table,
    });

    if (!userId || !notificationBody) {
      pushLog("bad_request", { reason: "missing_user_or_body" });
      return new Response(JSON.stringify({ error: "Missing user_id or body" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    }

    const headers = {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
    };

    const tRest0 = performance.now();
    const devicesUrl = new URL(`${supabaseUrl}/rest/v1/user_fcm_tokens`);
    devicesUrl.searchParams.set("user_id", `eq.${userId}`);
    devicesUrl.searchParams.set("select", "token");

    const devicesRes = await fetch(devicesUrl.toString(), { headers });
    let fcmTokens: string[] = [];

    if (devicesRes.ok) {
      const rows = await devicesRes.json() as Array<{ token: string }>;
      fcmTokens = rows.map((r) => r.token).filter((t) => t && t.length > 0);
    } else {
      const errTxt = await devicesRes.text().catch(() => "");
      pushLog("rest_user_fcm_tokens_failed", {
        http_status: devicesRes.status,
        err_preview: errTxt.slice(0, 200),
      });
    }

    if (fcmTokens.length === 0) {
      const profileUrl = new URL(`${supabaseUrl}/rest/v1/profiles`);
      profileUrl.searchParams.set("id", `eq.${userId}`);
      profileUrl.searchParams.set("select", "fcm_token");

      const profileRes = await fetch(profileUrl.toString(), { headers });
      if (profileRes.ok) {
        const profiles = await profileRes.json() as Array<{ fcm_token: string | null }>;
        const legacy = profiles[0]?.fcm_token;
        if (legacy) fcmTokens = [legacy];
      } else {
        const errTxt = await profileRes.text().catch(() => "");
        pushLog("rest_profiles_fcm_failed", {
          http_status: profileRes.status,
          err_preview: errTxt.slice(0, 200),
        });
      }
    }

    const webUrl = new URL(`${supabaseUrl}/rest/v1/user_web_push_subscriptions`);
    webUrl.searchParams.set("user_id", `eq.${userId}`);
    webUrl.searchParams.set("enabled", "eq.true");
    webUrl.searchParams.set("select", "id,endpoint,p256dh,auth");

    let webSubs: WebSubRow[] = [];
    const webRes = await fetch(webUrl.toString(), { headers });
    if (webRes.ok) {
      const rows = await webRes.json() as WebSubRow[];
      webSubs = rows.filter((r) =>
        r.id && r.endpoint && r.p256dh && r.auth
      );
    } else {
      const errTxt = await webRes.text().catch(() => "");
      pushLog("rest_web_push_subs_failed", {
        http_status: webRes.status,
        err_preview: errTxt.slice(0, 200),
      });
    }

    pushLog("targets_loaded", {
      ms: Math.round(performance.now() - tRest0),
      fcm_token_count: fcmTokens.length,
      web_sub_count: webSubs.length,
    });

    if (fcmTokens.length === 0 && webSubs.length === 0) {
      pushLog("skip_no_targets", { user_id_prefix: `${userId.slice(0, 8)}…` });
      return new Response(
        JSON.stringify({ ok: true, skipped: "no_push_targets" }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    const fcmResults: Array<{ token: string; status: number; data: unknown }> = [];
    const webResults: Array<
      { endpoint: string; status: number; ok: boolean; error?: string; pruned?: boolean }
    > = [];

    if (fcmTokens.length > 0) {
      const tFcm0 = performance.now();
      try {
        const serviceAccount = getServiceAccount();
        const accessToken = await getAccessToken(serviceAccount);
        const projectId = serviceAccount.project_id;
        const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

        pushLog("fcm_batch_start", {
          token_count: fcmTokens.length,
          project_id: projectId,
        });

        for (let i = 0; i < fcmTokens.length; i++) {
          const fcmToken = fcmTokens[i];
          const tOne = performance.now();
          try {
            const fcmRes = await fetch(fcmUrl, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${accessToken}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                message: {
                  token: fcmToken,
                  notification: {
                    title: "Jars",
                    body: notificationBody,
                  },
                  webpush: {
                    notification: {
                      title: "Jars",
                      body: notificationBody,
                      icon: PUSH_ICON_PATH,
                    },
                  },
                },
              }),
              signal: AbortSignal.timeout(FCM_SEND_TIMEOUT_MS),
            });
            const fcmData = await fcmRes.json();
            pushLog("fcm_send_result", {
              index: i,
              http_status: fcmRes.status,
              ms: Math.round(performance.now() - tOne),
              token_prefix: `${fcmToken.slice(0, 12)}…`,
              error_preview: fcmRes.ok
                ? null
                : JSON.stringify(fcmData).slice(0, 280),
            });
            fcmResults.push({
              token: `${fcmToken.slice(0, 12)}…`,
              status: fcmRes.status,
              data: fcmData,
            });
          } catch (e) {
            const msg = e instanceof Error ? e.message : String(e);
            pushLog("fcm_send_throw", {
              index: i,
              ms: Math.round(performance.now() - tOne),
              token_prefix: `${fcmToken.slice(0, 12)}…`,
              error: msg,
            });
            fcmResults.push({
              token: `${fcmToken.slice(0, 12)}…`,
              status: 0,
              data: { error: msg },
            });
          }
        }
        pushLog("fcm_batch_done", { ms: Math.round(performance.now() - tFcm0) });
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        pushLog("fcm_batch_aborted", {
          ms: Math.round(performance.now() - tFcm0),
          error: msg,
        });
        fcmResults.push({
          token: "fcm_oauth_or_config",
          status: 0,
          data: { error: msg },
        });
      }
    }

    if (webSubs.length > 0) {
      const tWeb0 = performance.now();
      const vapidPrivateRaw = Deno.env.get("VAPID_PRIVATE_KEY")?.trim();
      const adminContact = Deno.env.get("VAPID_SUBJECT")?.trim() ?? "mailto:admin@localhost";

      let privateJWK: Record<string, unknown> | null = null;
      if (vapidPrivateRaw) {
        try {
          privateJWK = JSON.parse(vapidPrivateRaw) as Record<string, unknown>;
        } catch {
          pushLog("vapid_parse_failed", {});
        }
      }

      if (!privateJWK) {
        pushLog("web_push_skip_no_vapid", { web_sub_count: webSubs.length });
        for (const s of webSubs) {
          webResults.push({
            endpoint: `${s.endpoint.slice(0, 48)}…`,
            status: 0,
            ok: false,
            error: "vapid_private_jwk_not_configured",
          });
        }
      } else {
        pushLog("web_push_batch_start", { count: webSubs.length });
        for (let i = 0; i < webSubs.length; i++) {
          const s = webSubs[i];
          const tOne = performance.now();
          try {
            const subscription = {
              endpoint: s.endpoint,
              keys: { p256dh: s.p256dh, auth: s.auth },
            };
            const tBuild0 = performance.now();
            const { endpoint, headers: pushHeaders, body: pushBody } =
              await buildPushHTTPRequest({
              privateJWK,
              subscription,
              message: {
                payload: {
                  title: "Jars",
                  body: notificationBody,
                  icon: PUSH_ICON_PATH,
                  // Unique per DB row — same tag replaces prior toasts in Chrome (user only sees one).
                  tag: notification.id,
                  data: { url: "/", notificationId: notification.id },
                },
                adminContact,
                options: { ttl: 86400, urgency: "normal" },
              },
            });
            pushLog("web_push_built", {
              index: i,
              build_ms: Math.round(performance.now() - tBuild0),
              endpoint_host: (() => {
                try {
                  return new URL(endpoint).host;
                } catch {
                  return "invalid_endpoint";
                }
              })(),
            });
            const res = await fetch(endpoint, {
              method: "POST",
              headers: pushHeaders,
              body: pushBody,
              signal: AbortSignal.timeout(WEB_PUSH_FETCH_TIMEOUT_MS),
            });
            const errText = res.ok
              ? undefined
              : (await res.text().catch(() => res.statusText)).slice(0, 400);
            pushLog("web_push_fetch_result", {
              index: i,
              http_status: res.status,
              ok: res.ok,
              ms: Math.round(performance.now() - tOne),
              err_preview: errText ?? null,
            });

            let pruned = false;
            if (!res.ok && (res.status === 410 || res.status === 404)) {
              pruned = await deleteWebPushRow(supabaseUrl, headers, s.id);
              pushLog("web_sub_pruned", {
                index: i,
                row_id_prefix: `${s.id.slice(0, 8)}…`,
                http_status: res.status,
                delete_ok: pruned,
              });
            }

            webResults.push({
              endpoint: `${s.endpoint.slice(0, 48)}…`,
              status: res.status,
              ok: res.ok,
              ...(pruned ? { pruned: true } : {}),
              ...(errText != null && errText.length > 0 ? { error: errText } : {}),
            });
          } catch (e) {
            const msg = e instanceof Error ? e.message : String(e);
            pushLog("web_push_throw", {
              index: i,
              ms: Math.round(performance.now() - tOne),
              error: msg,
            });
            webResults.push({
              endpoint: `${s.endpoint.slice(0, 48)}…`,
              status: 0,
              ok: false,
              error: msg,
            });
          }
        }
        pushLog("web_push_batch_done", { ms: Math.round(performance.now() - tWeb0) });
      }
    }

    const fcmSucceeded = fcmResults.some((r) => r.status >= 200 && r.status <= 299);
    const webSucceeded = webResults.some((r) => r.ok);
    const anyOk = fcmSucceeded || webSucceeded;

    /** Every web attempt failed with gone/expired — no point returning 502 (webhook retries). */
    const webAllGone = webResults.length > 0 &&
      webResults.every((r) => !r.ok && (r.status === 410 || r.status === 404));
    const respond200StaleOnly = !anyOk && webAllGone && !fcmSucceeded;

    const fcmFailCount = fcmResults.filter((r) => r.status < 200 || r.status > 299).length;
    const webFailCount = webResults.filter((r) => !r.ok).length;

    const failureReason = anyOk
      ? null
      : [
        fcmResults.length ? `fcm_attempts=${fcmResults.length} ok=${fcmSucceeded}` : "fcm_skipped",
        webResults.length ? `web_attempts=${webResults.length} ok=${webSucceeded}` : "web_skipped",
        `fcm_failures=${fcmFailCount}`,
        `web_failures=${webFailCount}`,
        webAllGone ? "web_all_410_or_404_stale" : null,
      ].filter(Boolean).join("; ");

    const httpStatusOut = anyOk ? 200 : respond200StaleOnly ? 200 : 502;

    pushLog("finish", {
      ms_total: Math.round(performance.now() - wallStart),
      delivered: anyOk,
      http_status: httpStatusOut,
      stale_subscriptions_only: respond200StaleOnly,
      failure_reason: failureReason,
      fcm_succeeded: fcmSucceeded,
      web_succeeded: webSucceeded,
    });

    return new Response(
      JSON.stringify({
        ok: anyOk || respond200StaleOnly,
        delivered: anyOk,
        stale_subscriptions_only: respond200StaleOnly,
        failure_reason: failureReason,
        fcm_devices: fcmTokens.length,
        web_devices: webSubs.length,
        fcm_results: fcmResults,
        web_results: webResults,
      }),
      {
        status: httpStatusOut,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    pushLog("uncaught", {
      ms_total: Math.round(performance.now() - wallStart),
      error: message,
    });
    console.error("push error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
