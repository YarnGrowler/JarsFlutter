// Evening cron: notify users whose Chicago-day points are still below room streak_minimum
// while they have an active streak — before midnight Central.
//
// curl -X POST "$SUPABASE_URL/functions/v1/cron-streak-nudge" -H "Authorization: Bearer $CRON_SECRET"
//
// Secrets: CRON_SECRET, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto in hosted)
// Optional env:
//   STREAK_NUDGE_MIN_STREAK — default 2 (only nudge if streak_current >= this)
//   STREAK_NUDGE_CHICAGO_START_HOUR — default 18 (6 PM Central, 24h clock)
//   STREAK_NUDGE_CHICAGO_END_HOUR — default 23 (11 PM Central; still before midnight)
//   STREAK_NUDGE_SKIP_HOUR_CHECK — set to "true" to run any time (testing / manual)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonLog(phase: string, data: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ tag: "jars_streak_nudge", phase, t: new Date().toISOString(), ...data }));
}

/** 0–23 in America/Chicago */
function chicagoHour(): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Chicago",
    hour: "numeric",
    hourCycle: "h23",
  }).formatToParts(new Date());
  const h = parts.find((p) => p.type === "hour")?.value;
  return parseInt(h ?? "0", 10);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const cronSecret = Deno.env.get("CRON_SECRET")?.trim();
    const auth = req.headers.get("Authorization")?.replace("Bearer ", "").trim();
    if (!cronSecret || auth !== cronSecret) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const skipHour = Deno.env.get("STREAK_NUDGE_SKIP_HOUR_CHECK") === "true";
    const startH = Number(Deno.env.get("STREAK_NUDGE_CHICAGO_START_HOUR") ?? "18");
    const endH = Number(Deno.env.get("STREAK_NUDGE_CHICAGO_END_HOUR") ?? "23");
    const minStreak = Math.max(1, Number(Deno.env.get("STREAK_NUDGE_MIN_STREAK") ?? "2"));

    const hour = chicagoHour();
    if (!skipHour && (hour < startH || hour > endH)) {
      jsonLog("skip_outside_window", { hour_chicago: hour, startH, endH });
      return new Response(
        JSON.stringify({
          ok: true,
          skipped: true,
          reason: "outside_chicago_window",
          chicago_hour: hour,
          window: [startH, endH],
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(supabaseUrl, service);

    const { data, error } = await sb.rpc("cron_streak_nudge_execute", {
      p_min_streak: minStreak,
    });

    if (error) {
      jsonLog("rpc_error", { message: error.message, details: error });
      throw error;
    }

    const inserted = typeof data === "number" ? data : 0;
    jsonLog("done", { notifications_inserted: inserted, min_streak: minStreak, chicago_hour: hour });

    return new Response(
      JSON.stringify({ ok: true, notifications_inserted: inserted, chicago_hour: hour }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    jsonLog("error", { message: msg });
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
