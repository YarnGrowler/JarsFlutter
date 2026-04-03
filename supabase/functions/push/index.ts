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

    // profiles.id === auth.users.id (notifications.user_id references auth.users)
    const profileUrl = new URL(`${supabaseUrl}/rest/v1/profiles`);
    profileUrl.searchParams.set("id", `eq.${userId}`);
    profileUrl.searchParams.set("select", "fcm_token");

    const profileRes = await fetch(profileUrl.toString(), {
      headers: {
        apikey: supabaseKey,
        Authorization: `Bearer ${supabaseKey}`,
      },
    });

    if (!profileRes.ok) {
      const errText = await profileRes.text();
      throw new Error(`profiles fetch ${profileRes.status}: ${errText}`);
    }

    const profiles = await profileRes.json() as Array<{ fcm_token: string | null }>;
    const fcmToken = profiles[0]?.fcm_token;

    if (!fcmToken) {
      console.log("push: no fcm_token for user", userId);
      return new Response(JSON.stringify({ ok: true, skipped: "no_fcm_token" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(serviceAccount);
    const projectId = serviceAccount.project_id;

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
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
                icon: "/icons/Icon-192.png",
              },
            },
          },
        }),
      }
    );

    const fcmData = await fcmRes.json();
    console.log("FCM response:", fcmRes.status, JSON.stringify(fcmData));

    if (!fcmRes.ok) {
      return new Response(JSON.stringify(fcmData), {
        status: 502,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify(fcmData), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error("push error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
