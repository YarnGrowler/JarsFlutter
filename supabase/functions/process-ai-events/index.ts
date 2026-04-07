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

function getPersonas(): Persona[] {
  // Tunable via env. Keep defaults sane.
  const common = Number(Deno.env.get("AI_PERSONA_COMMON_WEIGHT") ?? 82);
  const rare = Number(Deno.env.get("AI_PERSONA_RARE_WEIGHT") ?? 15);
  const legendary = Number(Deno.env.get("AI_PERSONA_LEGENDARY_WEIGHT") ?? 3);
  return [
    {
      label: "Coach",
      weight: common,
      style:
        "Warm competitor-coach. Short, punchy, no cringe, no emojis. Praise effort, nudge rivalry.",
    },
    {
      label: "Announcer",
      weight: rare,
      style:
        "Arena announcer vibe. Dramatic but not corny. One clever line max. No slang overload.",
    },
    {
      label: "Gremlin Jar",
      weight: legendary,
      style:
        "Chaotic mascot energy, but still tasteful. Teasing, never mean. No 'AI' references.",
    },
  ];
}

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
      .select("id, room_id, user_id, exercise_name, points_earned, created_at")
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

    const top3 = sorted.slice(0, 3).map((s, i) => ({
      rank: i + 1,
      username: safeUsername(s.profiles?.username),
      total: Number(s.total_score ?? 0),
    }));

    const persona = pickWeighted(getPersonas());
    const eventsForAi = events.map((e) => ({
      title: eventTitle(e.key),
      payload: e.payload ?? {},
    }));

    const userPrompt = JSON.stringify({
      room: (room as { name?: string })?.name ?? "Room",
      streakMinimum: streakMin,
      actorUserId: uid,
      log: { points: pointsEarned, rankBefore, rankAfter },
      top3,
      events: eventsForAi,
    });

    const system = [
      `You are "Jars", the room's mascot commentator.`,
      `Write as a fellow competitor/announcer, NOT as an AI.`,
      `ABSOLUTE RULES:`,
      `- Never say "I am an AI" or mention prompts/models.`,
      `- Never use second-person ("you/your"). Speak to the room in third-person.`,
      `- Never output internal codes/keys. Only natural language.`,
      `- 1–2 sentences. No bullet points. No hashtags.`,
      `- Keep it specific: usernames + ranks + points when relevant.`,
      `- Competitive, playful, not cruel.`,
      `STYLE: ${persona.style}`,
      `LENGTH: max 260 characters.`,
    ].join("\n");

    const { text, usage, responseId, modelReturned } = await openAiComplete(
      openaiKey,
      openaiModel,
      system,
      userPrompt,
      { logContext: { log_id: logId, room_id: roomId } },
    );

    // Extra safety in case the model slips.
    const cleaned = clampText(
      text
        .replaceAll(/\bspam_surge\b/gi, "rapid-fire session")
        .replaceAll(/\bAI\b/gi, "")
        .replaceAll(/\byou\b/gi, "they")
        .replaceAll(/\byour\b/gi, "their")
        .trim(),
      320,
    );

    const payload = {
      v: 1,
      text: cleaned,
      persona: persona.label,
      model: openaiModel,
      model_returned: modelReturned,
      openai_response_id: responseId,
      usage,
      events: events.map((e) => e.key),
      eventPayloads: events,
    };

    await sb.from("exercise_logs").insert({
      room_id: roomId,
      user_id: uid,
      exercise_id: null,
      exercise_name: `__AI__|${JSON.stringify(payload)}`,
      count: 0,
      weight: 0,
      points_earned: 0,
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
