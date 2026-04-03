// Supabase Edge Function: push
// Triggered by database webhook on notifications INSERT.
// Reads the FCM token from profiles and sends a push notification via FCM v1 API.
//
// Setup:
//   1. Put Firebase service-account.json in THIS folder (push/) — it is bundled on deploy.
//      Do not use Deno.readTextFile; edge runtime has no filesystem for that file.
//   2. Optional: set Supabase secret FIREBASE_SERVICE_ACCOUNT_JSON (full JSON string)
//      to override the bundled file (recommended for CI without committing the file).
//   3. supabase functions deploy push --no-verify-jwt
//   4. Database webhook: notifications INSERT → push

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// Bundled at deploy time (must exist locally when you run `functions deploy`).
import serviceAccountBundled from "./service-account.json" with { type: "json" };

// ── Types ──────────────────────────────────────────────────────────────────
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

// ── JWT helper (service account → access token) ─────────────────────────────
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

  // Import private key
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
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const signatureB64 = btoa(
    String.fromCharCode(...new Uint8Array(signature))
  )
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const jwt = `${signingInput}.${signatureB64}`;

  // Exchange JWT for access token
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
      `OAuth token failed: ${tokenData.error ?? tokenRes.status} ${tokenData.error_description ?? JSON.stringify(tokenData)}`
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

// Shown in browser/OS notification UI (app must serve this path, e.g. Vercel /web/icons).
const PUSH_ICON_PATH = "/icons/jars-notification.svg";

// ── Main handler ────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  try {
    const payload: WebhookPayload = await req.json();

    const notification = payload.record;
    const userId = notification.user_id;
    const body = notification.body;

    if (!userId || !body) {
      return new Response(JSON.stringify({ error: "Missing user_id or body" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const serviceAccount = getServiceAccount();

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    }

    const headers = {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
    };

    // Multi-device: user_fcm_tokens (one row per browser / phone install)
    const devicesUrl = new URL(`${supabaseUrl}/rest/v1/user_fcm_tokens`);
    devicesUrl.searchParams.set("user_id", `eq.${userId}`);
    devicesUrl.searchParams.set("select", "token");

    const devicesRes = await fetch(devicesUrl.toString(), { headers });
    let tokens: string[] = [];

    if (devicesRes.ok) {
      const rows = await devicesRes.json() as Array<{ token: string }>;
      tokens = rows.map((r) => r.token).filter((t) => t && t.length > 0);
    }

    // Legacy: single token on profiles before migration
    if (tokens.length === 0) {
      const profileUrl = new URL(`${supabaseUrl}/rest/v1/profiles`);
      profileUrl.searchParams.set("id", `eq.${userId}`);
      profileUrl.searchParams.set("select", "fcm_token");

      const profileRes = await fetch(profileUrl.toString(), { headers });
      if (!profileRes.ok) {
        const errText = await profileRes.text();
        throw new Error(`profiles fetch ${profileRes.status}: ${errText}`);
      }
      const profiles = await profileRes.json() as Array<{ fcm_token: string | null }>;
      const legacy = profiles[0]?.fcm_token;
      if (legacy) tokens = [legacy];
    }

    if (tokens.length === 0) {
      console.log("push: no FCM tokens for user", userId);
      return new Response(JSON.stringify({ ok: true, skipped: "no_fcm_token" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(serviceAccount);
    const projectId = serviceAccount.project_id;

    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const results: Array<{ token: string; status: number; data: unknown }> = [];

    for (const fcmToken of tokens) {
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
              body,
            },
            webpush: {
              notification: {
                title: "Jars",
                body,
                icon: PUSH_ICON_PATH,
              },
            },
          },
        }),
      });
      const fcmData = await fcmRes.json();
      console.log("FCM response:", fcmRes.status, JSON.stringify(fcmData));
      results.push({
        token: `${fcmToken.slice(0, 12)}…`,
        status: fcmRes.status,
        data: fcmData,
      });
    }

    const anyOk = results.some((r) => r.status >= 200 && r.status <= 299);

    return new Response(
      JSON.stringify({
        ok: anyOk,
        devices: tokens.length,
        results,
      }),
      {
        status: anyOk ? 200 : 502,
        headers: { "Content-Type": "application/json" },
      }
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
