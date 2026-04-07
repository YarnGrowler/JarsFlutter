// Detect AI narrative events for a workout log → OpenAI (batched) → __AI__| feed row.
// Secrets: OPENAI_API_KEY, OPENAI_MODEL (default gpt-4o-mini). Optional: AI_EVENTS_SEND_PUSH=true
//
// Deploy: supabase functions deploy process-ai-events --no-verify-jwt

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface DetectedEvent {
  key: string;
  payload: Record<string, unknown>;
}

type Persona = {
  label: string;
  style: string;
  weight: number;
};

function pickWeighted<T extends { weight: number }>(items: T[]): T {
  const total = items.reduce((a, b) => a + Math.max(0, b.weight), 0);
  if (total <= 0) return items[0];
  let r = Math.random() * total;
  for (const it of items) {
    r -= Math.max(0, it.weight);
    if (r <= 0) return it;
  }
  return items[items.length - 1];
}

// ─── 6 personas ──────────────────────────────────────────────────────────────

function getPersonas(): Persona[] {
  return [
    {
      label: "Analyst",
      weight: Number(Deno.env.get("AI_PERSONA_ANALYST_WEIGHT") ?? 35),
      style:
        "Sharp, precise, grounded. Reference exact stats: ranks, points, gaps. " +
        "No hype — just the cold hard truth laid out with confidence. Make it feel smart and real.",
    },
    {
      label: "Hype Man",
      weight: Number(Deno.env.get("AI_PERSONA_HYPE_WEIGHT") ?? 30),
      style:
        "Pure energy. Celebrates big plays and wins, keeps the dopamine high. " +
        "Short punchy lines, slightly theatrical. Never hollow — always tied to actual stats.",
    },
    {
      label: "Disappointed Coach",
      weight: Number(Deno.env.get("AI_PERSONA_COACH_WEIGHT") ?? 15),
      style:
        "Not angry — just notices the gap between potential and performance. " +
        "The quiet kind of pressure: 'you had it, you fumbled it, you know it.' No cruelty.",
    },
    {
      label: "Historian",
      weight: Number(Deno.env.get("AI_PERSONA_HISTORIAN_WEIGHT") ?? 10),
      style:
        "Makes the moment feel legendary. Sports-broadcaster gravitas — 'for the third time this week...', " +
        "'a dynasty forming...'. Weight and lore. Reserve for truly big moves.",
    },
    {
      label: "Chaos Agent",
      weight: Number(Deno.env.get("AI_PERSONA_CHAOS_WEIGHT") ?? 7),
      style:
        "Wildcard energy. Unpredictable, genuinely funny. Keeps the feed surprising. " +
        "Tasteful chaos — teasing, never mean, never edgy for its own sake.",
    },
    {
      label: "Conspiracy Theorist",
      weight: Number(Deno.env.get("AI_PERSONA_CONSPIRACY_WEIGHT") ?? 3),
      style:
        "Finds suspicious patterns in the timing and data. 'Coincidence? Doubt it.' " +
        "Playful paranoia — not actually accusing anyone, just dramatically suspicious.",
    },
  ];
}

/** Multiply base persona weights by event-affinity multipliers before picking. */
function pickPersonaForEvents(eventKeys: string[]): Persona {
  const personas = getPersonas();
  const mult = new Map<string, number>(personas.map((p) => [p.label, 1.0]));

  for (const key of eventKeys) {
    switch (key) {
      case "spam_surge":
        mult.set("Chaos Agent", (mult.get("Chaos Agent") ?? 1) * 3);
        mult.set("Hype Man", (mult.get("Hype Man") ?? 1) * 2);
        mult.set("Historian", (mult.get("Historian") ?? 1) * 0.2);
        break;
      case "heist":
        mult.set("Hype Man", (mult.get("Hype Man") ?? 1) * 2.5);
        mult.set("Conspiracy Theorist", (mult.get("Conspiracy Theorist") ?? 1) * 2.5);
        break;
      case "carry":
        mult.set("Historian", (mult.get("Historian") ?? 1) * 3);
        mult.set("Hype Man", (mult.get("Hype Man") ?? 1) * 2);
        break;
      case "domination":
        mult.set("Historian", (mult.get("Historian") ?? 1) * 4);
        mult.set("Disappointed Coach", (mult.get("Disappointed Coach") ?? 1) * 2);
        break;
      case "rivalry":
        mult.set("Analyst", (mult.get("Analyst") ?? 1) * 2.5);
        mult.set("Historian", (mult.get("Historian") ?? 1) * 2);
        break;
      case "near_tie":
        mult.set("Analyst", (mult.get("Analyst") ?? 1) * 2.5);
        mult.set("Hype Man", (mult.get("Hype Man") ?? 1) * 1.5);
        break;
      case "ghost_return":
        mult.set("Conspiracy Theorist", (mult.get("Conspiracy Theorist") ?? 1) * 4);
        mult.set("Historian", (mult.get("Historian") ?? 1) * 2);
        break;
      case "uno_reverse":
        mult.set("Chaos Agent", (mult.get("Chaos Agent") ?? 1) * 2.5);
        mult.set("Hype Man", (mult.get("Hype Man") ?? 1) * 2);
        break;
      case "room_milestone":
        mult.set("Historian", (mult.get("Historian") ?? 1) * 3);
        mult.set("Hype Man", (mult.get("Hype Man") ?? 1) * 2);
        break;
      case "silence_break":
        mult.set("Conspiracy Theorist", (mult.get("Conspiracy Theorist") ?? 1) * 2);
        mult.set("Disappointed Coach", (mult.get("Disappointed Coach") ?? 1) * 1.5);
        break;
    }
  }

  const weighted = personas.map((p) => ({
    ...p,
    weight: Math.max(0.1, p.weight * (mult.get(p.label) ?? 1)),
  }));
  return pickWeighted(weighted);
}

/** Events directly about one person's log action → get reply_to_log_id set. */
const PER_LOG_EVENT_KEYS = new Set([
  "heist", "ghost_return", "spam_surge", "near_tie", "uno_reverse", "carry", "silence_break",
]);

/** Events about the room's broader state → standalone post card. */
const ROOM_WIDE_EVENT_KEYS = new Set(["room_milestone", "domination", "rivalry"]);

function eventTitle(key: string): string {
  switch (key) {
    case "spam_surge":
      return "rapid-fire session";
    case "silence_break":
      return "silence snapped";
    case "heist":
      return "points heist";
    case "ghost_return":
      return "ghost return";
    case "near_tie":
      return "photo finish";
    case "uno_reverse":
      return "uno reverse";
    case "room_milestone":
      return "room milestone";
    case "domination":
      return "domination streak";
    case "rivalry":
      return "rivalry swing";
    case "carry":
      return "hard carry";
    default:
      return key.replaceAll("_", " ");
  }
}

function safeUsername(s: unknown): string {
  const v = typeof s === "string" ? s.trim() : "";
  if (!v) return "?";
  // Avoid weird prompt injection / giant names.
  return v.slice(0, 24);
}

function clampText(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max - 1).trimEnd() + "…";
}

function jsonLog(tag: string, data: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ tag: "jars_ai_events", phase: tag, t: new Date().toISOString(), ...data }));
}

function isBroadcastName(name: string): boolean {
  return name.startsWith("__");
}

/** Newer models (e.g. gpt-5.x) require max_completion_tokens, not max_tokens. */
interface OpenAiUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  [k: string]: unknown;
}

interface OpenAiCompleteResult {
  text: string;
  usage: OpenAiUsage | null;
  responseId: string | null;
  modelReturned: string | null;
}

async function openAiComplete(
  apiKey: string,
  model: string,
  system: string,
  user: string,
  opts: { maxCompletionTokens?: number; logContext?: Record<string, unknown> } = {},
): Promise<OpenAiCompleteResult> {
  const rawMax = Deno.env.get("OPENAI_MAX_COMPLETION_TOKENS")?.trim();
  const maxCompletionTokens = opts.maxCompletionTokens ??
    Math.max(16, Math.min(4096, Number.isFinite(Number(rawMax)) ? Number(rawMax) : 220));

  const logFullIo = Deno.env.get("AI_LOG_FULL_IO") === "true";

  const body: Record<string, unknown> = {
    model,
    temperature: 0.85,
    max_completion_tokens: maxCompletionTokens,
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
  };

  jsonLog("openai_request", {
    ...opts.logContext,
    model,
    temperature: body.temperature,
    max_completion_tokens: maxCompletionTokens,
    system_chars: system.length,
    user_chars: user.length,
    messages_total_chars: system.length + user.length,
    system_preview: system.slice(0, 800),
    user_preview: user.slice(0, 4000),
    ...(logFullIo ? { system_full: system, user_full: user } : {}),
  });

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const rawText = await res.text();

  if (!res.ok) {
    jsonLog("openai_http_error", {
      status: res.status,
      body_preview: rawText.slice(0, 1200),
    });
    throw new Error(`OpenAI HTTP ${res.status}: ${rawText.slice(0, 500)}`);
  }

  const data = JSON.parse(rawText) as {
    id?: string;
    model?: string;
    choices?: Array<{ message?: { content?: string }; finish_reason?: string }>;
    usage?: OpenAiUsage;
  };

  const usage = data.usage ?? null;
  const text = data.choices?.[0]?.message?.content?.trim() ?? "";
  const finishReason = data.choices?.[0]?.finish_reason;

  jsonLog("openai_response", {
    ...opts.logContext,
    response_id: data.id ?? null,
    model_requested: model,
    model_returned: data.model ?? null,
    usage,
    finish_reason: finishReason ?? null,
    completion_chars: text.length,
    completion_preview: text.slice(0, 400),
    completion_full: logFullIo ? text : undefined,
    /** Use `usage` with https://openai.com/api/pricing/ for your model (USD per 1M tokens). */
    cost_hint: usage
      ? {
          prompt_tokens: usage.prompt_tokens,
          completion_tokens: usage.completion_tokens,
          total_tokens: usage.total_tokens,
        }
      : null,
  });

  if (!text) throw new Error("OpenAI empty response");

  return {
    text,
    usage,
    responseId: data.id ?? null,
    modelReturned: data.model ?? null,
  };
}

type ScoreRow = {
  user_id: string;
  total_score: number;
  profiles?: { username?: string };
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const wall = performance.now();
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "POST only" }), {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
    const openaiModel = Deno.env.get("OPENAI_MODEL")?.trim() || "gpt-4o-mini";

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userClient = createClient(supabaseUrl, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      return new Response(JSON.stringify({ error: "Invalid session" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const uid = userData.user.id;

    const body = (await req.json()) as { log_id?: string };
    const logId = body.log_id?.trim();
    if (!logId) {
      return new Response(JSON.stringify({ error: "log_id required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const sb = createClient(supabaseUrl, service);

    const { data: log, error: logErr } = await sb
      .from("exercise_logs")
      .select("id, room_id, user_id, exercise_name, count, weight, points_earned, created_at")
      .eq("id", logId)
      .maybeSingle();

    if (logErr || !log) {
      return new Response(JSON.stringify({ error: "Log not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (log.user_id !== uid) {
      return new Response(JSON.stringify({ error: "Not your log" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (isBroadcastName(log.exercise_name as string)) {
      return new Response(JSON.stringify({ ok: true, skipped: "broadcast_log" }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const roomId = log.room_id as string;
    const pointsEarned = Number(log.points_earned ?? 0);
    const logCreatedAt = log.created_at as string;
    const actorExerciseName = safeUsername((log as Record<string, unknown>).exercise_name as string);
    const actorReps = Number((log as Record<string, unknown>).count ?? 0);
    const actorWeight = Number((log as Record<string, unknown>).weight ?? 0);

    const { data: room } = await sb.from("rooms").select("id, name, streak_minimum").eq("id", roomId).single();
    const streakMin = (room as { streak_minimum?: number })?.streak_minimum ?? 10;

    const { data: scores } = await sb
      .from("scores")
      .select("user_id, total_score, profiles(username)")
      .eq("room_id", roomId);

    const list = (scores ?? []) as ScoreRow[];
    const sorted = [...list].sort((a, b) => {
      const d = (b.total_score ?? 0) - (a.total_score ?? 0);
      if (d !== 0) return d;
      return String(a.user_id).localeCompare(String(b.user_id));
    });

    const myRow = sorted.find((s) => s.user_id === uid);
    const totalAfter = Number(myRow?.total_score ?? 0);
    const totalBefore = Math.max(0, totalAfter - pointsEarned);

    const beforeRows = sorted.map((s) => ({
      user_id: s.user_id,
      total: s.user_id === uid ? totalBefore : Number(s.total_score ?? 0),
    }));
    beforeRows.sort((a, b) => b.total - a.total);
    const rankBefore = beforeRows.findIndex((s) => s.user_id === uid) + 1;
    const rankAfter = sorted.findIndex((s) => s.user_id === uid) + 1;

    const roomTotal = sorted.reduce((s, r) => s + Number(r.total_score ?? 0), 0);

    const { data: rai } = await sb.from("room_ai_state").select("*").eq("room_id", roomId).maybeSingle();
    const { data: urs } = await sb.from("user_room_ai_state").select("*").eq("room_id", roomId).eq("user_id", uid).maybeSingle();
    const { data: cfgRows } = await sb.from("room_ai_config").select("event_key, enabled, settings").eq("room_id", roomId);

    const cfgMap = new Map<string, boolean>();
    for (const r of cfgRows ?? []) {
      const row = r as { event_key: string; enabled: boolean };
      cfgMap.set(row.event_key, row.enabled !== false);
    }
    const enabled = (key: string) => cfgMap.get(key) !== false;

    const ursRow = (urs ?? {}) as Record<string, unknown>;
    const raiRow = (rai ?? {}) as Record<string, unknown>;

    const events: DetectedEvent[] = [];

    const leaderId = sorted[0]?.user_id;
    const oldLeader = raiRow.leader_user_id as string | undefined;
    const oldLeaderSince = raiRow.leader_since as string | undefined;

    // --- Uno reverse ---
    if (enabled("uno_reverse")) {
      if (rankAfter === 1 && rankBefore > 1) {
        events.push({ key: "uno_reverse", payload: { rankBefore, rankAfter } });
      } else if (rankBefore - rankAfter >= 2) {
        events.push({
          key: "uno_reverse",
          payload: { rankBefore, rankAfter, jump: rankBefore - rankAfter },
        });
      }
    }

    // --- Near tie ---
    if (enabled("near_tie") && rankAfter > 1) {
      const ahead = sorted[rankAfter - 2];
      if (ahead) {
        const gap = Number(ahead.total_score ?? 0) - totalAfter;
        if (gap >= 0 && gap < 10) {
          events.push({ key: "near_tie", payload: { gap, rank: rankAfter } });
        }
      }
    }

    // --- Ghost return ---
    if (enabled("ghost_return")) {
      const { data: prevLogs } = await sb
        .from("exercise_logs")
        .select("created_at, exercise_name")
        .eq("room_id", roomId)
        .eq("user_id", uid)
        .lt("created_at", logCreatedAt)
        .order("created_at", { ascending: false })
        .limit(20);

      const prevReal = (prevLogs ?? []).find(
        (p: { exercise_name: string }) => !p.exercise_name.startsWith("__"),
      ) as { created_at: string } | undefined;

      if (prevReal?.created_at) {
        const days =
          (new Date(logCreatedAt).getTime() - new Date(prevReal.created_at).getTime()) /
          86400000;
        if (days >= 5 && pointsEarned >= 30) {
          events.push({
            key: "ghost_return",
            payload: { daysAway: Math.floor(days), points: pointsEarned },
          });
        }
      }
    }

    // --- Heist (overtakes in window + points) ---
    const heistWindowMin = 20;
    const sinceHeist = new Date(new Date(logCreatedAt).getTime() - heistWindowMin * 60000).toISOString();

    const { count: overtakeCount } = await sb
      .from("exercise_logs")
      .select("id", { count: "exact", head: true })
      .eq("room_id", roomId)
      .eq("user_id", uid)
      .like("exercise_name", "__OVERTAKE__%")
      .gte("created_at", sinceHeist);

    let heistWindowStart = (ursRow.heist_window_start as string | null) ?? null;
    let heistPts = Number(ursRow.heist_points_in_window ?? 0);
    if (
      !heistWindowStart ||
      new Date(logCreatedAt).getTime() - new Date(heistWindowStart).getTime() > heistWindowMin * 60000
    ) {
      heistWindowStart = logCreatedAt;
      heistPts = pointsEarned;
    } else {
      heistPts += pointsEarned;
    }

    const lastHeistFired = ursRow.heist_fired_at as string | null;
    const heistCooldownOk =
      !lastHeistFired || Date.now() - new Date(lastHeistFired).getTime() > 3600000;

    if (
      enabled("heist") &&
      heistCooldownOk &&
      (overtakeCount ?? 0) >= 2 &&
      heistPts >= 120
    ) {
      events.push({
        key: "heist",
        payload: {
          overtakesInWindow: overtakeCount,
          sessionPoints: Math.round(heistPts),
          windowMin: heistWindowMin,
        },
      });
    }

    // --- Silence break ---
    if (enabled("silence_break")) {
      const lastRoom = raiRow.last_room_log_at as string | undefined;
      const silenceHours = 8;
      if (lastRoom) {
        const gapMs = new Date(logCreatedAt).getTime() - new Date(lastRoom).getTime();
        if (gapMs > silenceHours * 3600000) {
          events.push({
            key: "silence_break",
            payload: { silentHours: Math.round(gapMs / 3600000) },
          });
        }
      }
    }

    // --- Spam surge: N logs in M minutes, once per burst ---
    const N = 4;
    const M = 10;
    let spamStart = (ursRow.spam_window_start as string | null) ?? null;
    let spamCount = Number(ursRow.spam_logs_in_window ?? 0);
    const lastSpamFired = ursRow.spam_surge_fired_at as string | null;

    if (
      !spamStart ||
      new Date(logCreatedAt).getTime() - new Date(spamStart).getTime() > M * 60000
    ) {
      spamStart = logCreatedAt;
      spamCount = 1;
    } else {
      spamCount += 1;
    }

    let newSpamFiredAt = lastSpamFired;
    if (enabled("spam_surge") && spamCount >= N) {
      const alreadyFiredThisBurst =
        lastSpamFired &&
        spamStart &&
        new Date(lastSpamFired).getTime() >= new Date(spamStart).getTime() - 5000;
      if (!alreadyFiredThisBurst) {
        events.push({
          key: "spam_surge",
          payload: { logsInWindow: spamCount, windowMin: M },
        });
        newSpamFiredAt = logCreatedAt;
      }
    }

    // --- Room milestone ---
    const milestones = [500, 1000, 2500, 5000, 10000];
    const lastM = Number(raiRow.last_milestone_points ?? 0);
    let newLastMilestone = lastM;
    if (enabled("room_milestone")) {
      for (const m of milestones) {
        if (lastM < m && roomTotal >= m) {
          events.push({ key: "room_milestone", payload: { milestone: m, roomTotal } });
          newLastMilestone = Math.max(newLastMilestone, m);
          break;
        }
      }
    }

    // --- Domination (leader 3+ days, max once / 24h per room) ---
    const lastDomAi = raiRow.last_domination_ai_at as string | undefined;
    if (
      enabled("domination") &&
      leaderId &&
      oldLeader === leaderId &&
      oldLeaderSince
    ) {
      const days = (Date.now() - new Date(oldLeaderSince).getTime()) / 86400000;
      const domOk =
        days >= 3 &&
        (!lastDomAi || Date.now() - new Date(lastDomAi).getTime() > 86400000);
      if (domOk) {
        events.push({ key: "domination", payload: { leaderDays: Math.floor(days) } });
      }
    }

    // --- Rivalry A-B-A (only record when #1 identity changes) ---
    const rivalryArr = (raiRow.rivalry_swaps as string[] | undefined) ?? [];
    let newRivalry = rivalryArr;
    if (leaderId && oldLeader !== leaderId) {
      newRivalry = [...rivalryArr, leaderId].slice(-5);
    }
    if (enabled("rivalry") && newRivalry.length >= 3) {
      const a = newRivalry[newRivalry.length - 3];
      const b = newRivalry[newRivalry.length - 2];
      const c = newRivalry[newRivalry.length - 1];
      if (a === c && a !== b) {
        events.push({ key: "rivalry", payload: { pattern: [a, b, c] } });
      }
    }

    // --- Carry (>60% once / 24h) ---
    const lastCarry = ursRow.last_carry_ai_at as string | null;
    const carryCooldown =
      !lastCarry || Date.now() - new Date(lastCarry).getTime() > 86400000;
    if (enabled("carry") && leaderId === uid && roomTotal > 0 && carryCooldown) {
      const share = totalAfter / roomTotal;
      if (share >= 0.6) {
        events.push({ key: "carry", payload: { share: Math.round(share * 100) } });
      }
    }

    const nowIso = new Date().toISOString();

    // Overtake watch: person immediately above before rank
    let victimToWatch: string | null = null;
    if (rankAfter < rankBefore && rankBefore >= 2) {
      victimToWatch = beforeRows[rankBefore - 2]?.user_id ?? null;
    }

    const leaderSinceNew =
      leaderId && oldLeader === leaderId && oldLeaderSince
        ? oldLeaderSince
        : nowIso;

    await sb.from("room_ai_state").upsert(
      {
        room_id: roomId,
        last_room_log_at: logCreatedAt,
        leader_user_id: leaderId ?? null,
        leader_since: leaderSinceNew,
        last_leader_user_id: oldLeader ?? null,
        rivalry_swaps: newRivalry,
        last_milestone_points: Math.max(lastM, newLastMilestone),
        last_domination_ai_at: events.some((e) => e.key === "domination") ? nowIso : lastDomAi ?? null,
        updated_at: nowIso,
      },
      { onConflict: "room_id" },
    );

    await sb.from("user_room_ai_state").upsert(
      {
        user_id: uid,
        room_id: roomId,
        spam_window_start: spamStart,
        spam_logs_in_window: spamCount,
        spam_surge_fired_at: newSpamFiredAt,
        heist_window_start: heistWindowStart,
        heist_points_in_window: heistPts,
        heist_fired_at: events.some((e) => e.key === "heist") ? logCreatedAt : lastHeistFired,
        last_carry_ai_at: events.some((e) => e.key === "carry") ? nowIso : lastCarry,
        last_log_at: logCreatedAt,
      },
      { onConflict: "user_id,room_id" },
    );

    if (victimToWatch && victimToWatch !== uid) {
      await sb.from("overtake_response_watch").upsert(
        {
          room_id: roomId,
          victim_user_id: victimToWatch,
          actor_user_id: uid,
          created_at: nowIso,
        },
        { onConflict: "room_id,victim_user_id,actor_user_id" },
      );
    }

    // Victim logged — clear pending overtake watches about them.
    await sb.from("overtake_response_watch").delete().eq("room_id", roomId).eq("victim_user_id", uid);

    if (events.length === 0) {
      jsonLog("no_events", { ms: Math.round(performance.now() - wall), log_id: logId });
      return new Response(JSON.stringify({ ok: true, events: [] }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!openaiKey) {
      return new Response(JSON.stringify({ ok: false, error: "OPENAI_API_KEY not set" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const actorUsername = safeUsername(myRow?.profiles?.username);

    const top3 = sorted.slice(0, 3).map((s, i) => ({
      rank: i + 1,
      username: safeUsername(s.profiles?.username),
      total: Number(s.total_score ?? 0),
      isActor: s.user_id === uid,
    }));

    const eventKeys = events.map((e) => e.key);
    const persona = pickPersonaForEvents(eventKeys);

    // Classify: is this about one person's action, or a room-wide development?
    const isReplyMode = events.some((e) => PER_LOG_EVENT_KEYS.has(e.key)) &&
      !events.some((e) => ROOM_WIDE_EVENT_KEYS.has(e.key));

    const eventsForAi = events.map((e) => ({
      title: eventTitle(e.key),
      payload: e.payload ?? {},
    }));

    const contextData = {
      room: (room as { name?: string })?.name ?? "Room",
      streakMinimum: streakMin,
      actor: {
        username: actorUsername,
        rankBefore,
        rankAfter,
        pointsThisLog: pointsEarned,
        totalPoints: totalAfter,
        exercise: actorExerciseName,
        reps: actorReps,
        ...(actorWeight > 0 ? { weightKg: actorWeight } : {}),
      },
      top3,
      events: eventsForAi,
    };

    const userPrompt = JSON.stringify(contextData);

    const replyModeInstruction = isReplyMode
      ? [
          `MODE: REPLY — you are reacting directly to ${actorUsername}'s log (${actorReps} ${actorExerciseName}).`,
          `React to what they just did. Be vivid and specific — name them, the exercise, the rank change.`,
          `Write as if calling the play live, not narrating history.`,
        ].join(" ")
      : [
          `MODE: POST — this is a room-wide development, not one person's single action.`,
          `Announce the state of the room. Name the relevant players. Make it feel like a broadcast update.`,
        ].join(" ");

    const system = [
      `You are "Jars", the competitive mascot commentator for a fitness tracking app room.`,
      `You are NOT an AI assistant — you're the room's character voice.`,
      ``,
      `ABSOLUTE RULES (never break these):`,
      `- Never say "I", "I am", or reference AI, prompts, or models.`,
      `- Never use second-person ("you" / "your"). Always third-person.`,
      `- Never output raw keys like spam_surge, uno_reverse etc — use natural language only.`,
      `- No bullet points, hashtags, or lists.`,
      `- ALWAYS reference real names, ranks, and numbers from the context. No generics.`,
      `- 1–2 sentences max. Tight. No filler words.`,
      `- Competitive, playful, never cruel.`,
      ``,
      replyModeInstruction,
      ``,
      `PERSONA: ${persona.label}`,
      `STYLE GUIDE: ${persona.style}`,
      `LENGTH: max 260 characters.`,
    ].join("\n");

    const { text, usage, responseId, modelReturned } = await openAiComplete(
      openaiKey,
      openaiModel,
      system,
      userPrompt,
      { logContext: { log_id: logId, room_id: roomId } },
    );

    // Safety pass — strip any leaked internal keys or second-person slippage.
    const cleaned = clampText(
      text
        .replaceAll(/\bspam[_\s]surge\b/gi, "rapid-fire session")
        .replaceAll(/\buno[_\s]reverse\b/gi, "flip")
        .replaceAll(/\bghost[_\s]return\b/gi, "return")
        .replaceAll(/\bnear[_\s]tie\b/gi, "photo finish")
        .replaceAll(/\broom[_\s]milestone\b/gi, "milestone")
        .replaceAll(/\bAI\b/g, "")
        .replaceAll(/\byou\b/gi, "they")
        .replaceAll(/\byour\b/gi, "their")
        .trim(),
      320,
    );

    const payload: Record<string, unknown> = {
      v: 1,
      text: cleaned,
      persona: persona.label,
      mode: isReplyMode ? "reply" : "post",
      model: openaiModel,
      model_returned: modelReturned,
      openai_response_id: responseId,
      usage,
      events: eventKeys,
      eventPayloads: events,
    };

    // Embed reply context so Flutter card doesn't need a second DB lookup.
    if (isReplyMode) {
      payload.replyToUsername = actorUsername;
      payload.replyToExercise = actorExerciseName;
      payload.replyToReps = actorReps;
      payload.replyToPoints = pointsEarned;
    }

    await sb.from("exercise_logs").insert({
      room_id: roomId,
      user_id: uid,
      exercise_id: null,
      exercise_name: `__AI__|${JSON.stringify(payload)}`,
      count: 0,
      weight: 0,
      points_earned: 0,
      ...(isReplyMode ? { reply_to_log_id: logId } : {}),
    });

    if (Deno.env.get("AI_EVENTS_SEND_PUSH") === "true") {
      const { data: members } = await sb.from("room_members").select("user_id").eq("room_id", roomId);
      for (const m of members ?? []) {
        const mid = (m as { user_id: string }).user_id;
        if (mid === uid) continue;
        await sb.from("notifications").insert({ user_id: mid, body: cleaned.slice(0, 500) });
      }
    }

    jsonLog("ok", { ms: Math.round(performance.now() - wall), events: events.map((e) => e.key) });

    return new Response(
      JSON.stringify({ ok: true, events: events.map((e) => e.key) }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    jsonLog("error", { error: msg });
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
