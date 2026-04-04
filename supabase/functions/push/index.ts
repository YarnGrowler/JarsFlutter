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

Deno.serve(async (req) => {
  try {
    const payload: WebhookPayload = await req.json();

    const notification = payload.record;
    const userId = notification.user_id;
    // Name avoids TDZ with `const { …, body } = buildPushHTTPRequest(...)` below.
    const notificationBody = notification.body;

    if (!userId || !notificationBody) {
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

    const devicesUrl = new URL(`${supabaseUrl}/rest/v1/user_fcm_tokens`);
    devicesUrl.searchParams.set("user_id", `eq.${userId}`);
    devicesUrl.searchParams.set("select", "token");

    const devicesRes = await fetch(devicesUrl.toString(), { headers });
    let fcmTokens: string[] = [];

    if (devicesRes.ok) {
      const rows = await devicesRes.json() as Array<{ token: string }>;
      fcmTokens = rows.map((r) => r.token).filter((t) => t && t.length > 0);
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
      }
    }

    const webUrl = new URL(`${supabaseUrl}/rest/v1/user_web_push_subscriptions`);
    webUrl.searchParams.set("user_id", `eq.${userId}`);
    webUrl.searchParams.set("enabled", "eq.true");
    webUrl.searchParams.set("select", "endpoint,p256dh,auth");

    let webSubs: Array<{ endpoint: string; p256dh: string; auth: string }> = [];
    const webRes = await fetch(webUrl.toString(), { headers });
    if (webRes.ok) {
      const rows = await webRes.json() as Array<{
        endpoint: string;
        p256dh: string;
        auth: string;
      }>;
      webSubs = rows.filter((r) =>
        r.endpoint && r.p256dh && r.auth
      );
    } else {
      console.warn("push: user_web_push_subscriptions fetch", webRes.status, await webRes.text());
    }

    if (fcmTokens.length === 0 && webSubs.length === 0) {
      console.log("push: no FCM tokens or web push subs for user", userId);
      return new Response(
        JSON.stringify({ ok: true, skipped: "no_push_targets" }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    const fcmResults: Array<{ token: string; status: number; data: unknown }> = [];
    const webResults: Array<{ endpoint: string; status: number; ok: boolean; error?: string }> =
      [];

    if (fcmTokens.length > 0) {
      const serviceAccount = getServiceAccount();
      const accessToken = await getAccessToken(serviceAccount);
      const projectId = serviceAccount.project_id;
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

      for (const fcmToken of fcmTokens) {
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
        });
        const fcmData = await fcmRes.json();
        console.log("FCM response:", fcmRes.status, JSON.stringify(fcmData));
        fcmResults.push({
          token: `${fcmToken.slice(0, 12)}…`,
          status: fcmRes.status,
          data: fcmData,
        });
      }
    }

    if (webSubs.length > 0) {
      const vapidPrivateRaw = Deno.env.get("VAPID_PRIVATE_KEY")?.trim();
      const adminContact = Deno.env.get("VAPID_SUBJECT")?.trim() ?? "mailto:admin@localhost";

      let privateJWK: Record<string, unknown> | null = null;
      if (vapidPrivateRaw) {
        try {
          privateJWK = JSON.parse(vapidPrivateRaw) as Record<string, unknown>;
        } catch {
          console.error("push: VAPID_PRIVATE_KEY must be valid JSON (JWK from @pushforge/builder vapid)");
        }
      }

      if (!privateJWK) {
        console.error("push: VAPID_PRIVATE_KEY missing or invalid; skipping web push");
        for (const s of webSubs) {
          webResults.push({
            endpoint: `${s.endpoint.slice(0, 48)}…`,
            status: 0,
            ok: false,
            error: "vapid_private_jwk_not_configured",
          });
        }
      } else {
        for (const s of webSubs) {
          try {
            const subscription = {
              endpoint: s.endpoint,
              keys: { p256dh: s.p256dh, auth: s.auth },
            };
            const { endpoint, headers: pushHeaders, body: pushBody } =
              await buildPushHTTPRequest({
              privateJWK,
              subscription,
              message: {
                payload: {
                  title: "Jars",
                  body: notificationBody,
                  icon: PUSH_ICON_PATH,
                  tag: "jars",
                  data: { url: "/" },
                },
                adminContact,
                options: { ttl: 86400, urgency: "normal" },
              },
            });
            const res = await fetch(endpoint, {
              method: "POST",
              headers: pushHeaders,
              body: pushBody,
            });
            const errText = res.ok
              ? undefined
              : (await res.text().catch(() => res.statusText)).slice(0, 400);
            webResults.push({
              endpoint: `${s.endpoint.slice(0, 48)}…`,
              status: res.status,
              ok: res.ok,
              ...(errText != null && errText.length > 0 ? { error: errText } : {}),
            });
          } catch (e) {
            const msg = e instanceof Error ? e.message : String(e);
            console.error("web push (pushforge) error:", msg);
            webResults.push({
              endpoint: `${s.endpoint.slice(0, 48)}…`,
              status: 0,
              ok: false,
              error: msg,
            });
          }
        }
      }
    }

    const fcmSucceeded = fcmResults.some((r) => r.status >= 200 && r.status <= 299);
    const webSucceeded = webResults.some((r) => r.ok);
    const anyOk = fcmSucceeded || webSucceeded;

    return new Response(
      JSON.stringify({
        ok: anyOk,
        fcm_devices: fcmTokens.length,
        web_devices: webSubs.length,
        fcm_results: fcmResults,
        web_results: webResults,
      }),
      {
        status: anyOk ? 200 : 502,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error("push error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
