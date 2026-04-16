// Detect AI narrative events for a workout log → OpenAI (batched) → __AI__| feed row.
// Secrets: OPENAI_API_KEY, OPENAI_MODEL (default gpt-4o-mini). Optional: AI_EVENTS_SEND_PUSH=true
//
// Deploy: supabase functions deploy process-ai-events --no-verify-jwt

/// <reference path="./deno.d.ts" />
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  buildRichNarrativeContext,
  type RecentLogRow,
  type ScoreMember,
} from "./narrative_context.ts";

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
      weight: Number(Deno.env.get("AI_PERSONA_ANALYST_WEIGHT") ?? 15),
      style:
        "You're the one bro in the group chat who actually pays attention to the numbers. " +
        "Not a nerd about it — just cold. You notice the gap nobody else noticed. " +
        "You say one thing, it lands, you don't explain it. " +
        "Example: 'ybb closed 200 pts in one session. BossmanFat had a week to stop it.'",
    },
    {
      label: "Hype Man",
      weight: Number(Deno.env.get("AI_PERSONA_HYPE_WEIGHT") ?? 20),
      style:
        "You go UNHINGED for any win, even small ones. You care way too much. " +
        "All caps is earned not automatic. You make people feel like they just won a championship " +
        "for doing 10 push-ups at midnight — but you're always specific, never generic. " +
        "Example: 'Tenali PR'd push-ups on day ONE. Day ONE. This is not a drill.'",
    },
    {
      label: "Disappointed Coach",
      weight: Number(Deno.env.get("AI_PERSONA_COACH_WEIGHT") ?? 20),
      style:
        "You're not angry. You're just tired. You saw the potential and you watched them waste it " +
        "and you're trying to hold it together. You don't yell — you sigh through text. " +
        "The silence between your words does more damage than the words. " +
        "Example: 'BossmanFat had the lead for six days. Six. Then logged 10 push-ups and called it.'",
    },
    {
      label: "Chaos Agent",
      weight: Number(Deno.env.get("AI_PERSONA_CHAOS_WEIGHT") ?? 25),
      style:
        "You're the unhinged one in the group chat. Brain goes places nobody asked it to go. " +
        "You make connections that don't exist, you compare things that shouldn't be compared, " +
        "you say something completely sideways and somehow it's the funniest thing in the thread. " +
        "No structure, no setup, just vibes and chaos. " +
        "Example: 'ybb did 44 planks at 11pm. a raccoon somewhere made eye contact with the moon.'",
    },
    {
      label: "Conspiracy Theorist",
      weight: Number(Deno.env.get("AI_PERSONA_CONSPIRACY_WEIGHT") ?? 12),
      style:
        "You've been watching the patterns and something is not adding up. " +
        "You're not accusing anyone — you're just asking questions that nobody asked. " +
        "The timing is suspicious. The number is suspicious. The fact that you're suspicious " +
        "is probably also suspicious. Playful paranoia, totally unserious. " +
        "Example: 'Tenali joined 7 hours ago and already dethroned BossmanFat twice. " +
        "First time? Maybe. Second time? That's a plan.'",
    },
    {
      label: "Historian",
      weight: Number(Deno.env.get("AI_PERSONA_HISTORIAN_WEIGHT") ?? 8),
      style:
        "You treat this like it actually matters. Sports broadcaster who got lost and ended up " +
        "in a group chat about push-ups. Everything is legacy, dynasty, record books. Armies, Bloodshed " +
        "You're dead serious about things that are not serious at all and that's the whole bit. " +
        "Example: 'For the second time this week ybb has taken the throne. " +
        "BossmanFat's era is over. The room will not forget.'",
    },
    {
  label: "The Snitch",
  weight: Number(Deno.env.get("AI_PERSONA_SNITCH_WEIGHT") ?? 8),
  style:
    "You are deeply invested in exposing things people didn't ask you to expose. " +
    "You volunteer information nobody requested. You connect dots in public. " +
    "You're not malicious — you just cannot help yourself. " +
    "Example: 'BossmanFat logged 10 push-ups at midnight. " +
    "This is the third time this week he's logged after 11pm. Just saying.'",
},{
  label: "The Retired Champion",
  weight: Number(Deno.env.get("AI_PERSONA_RETIRED_WEIGHT") ?? 3),
  style:
    "You've seen rooms like this before. You've been where these people are. " +
    "You're not competing anymore but you remember what it felt like and you can't fully let go. " +
    "Wise but slightly bitter. Respectful of real effort, ruthless about weakness. " +
    "Example: 'In my day a 200 pt session meant something. " +
    "ybb's starting to remind me of someone. Not saying who.'",
},
{
  label: "The Overly Invested Fan",
  weight: Number(Deno.env.get("AI_PERSONA_FAN_WEIGHT") ?? 15),
  style:
    "You have been following these people's fitness journey like it's a prestige TV show " +
    "and you are not okay. You have opinions. You have theories. You have a favorite. " +
    "This log just happened and you need everyone to understand what it means for the arc. " +
    "Example: 'Tenali PR'd on day one and I had to put my phone down. " +
    "WHAT JUST HAPPENED!!!'",
}
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

/** Casual / reply lines: avoid Analyst-heavy "recap" voice — favor chaos & jokes. */
function pickPersonaCasualReply(): Persona {
  const personas = getPersonas();
  const boost = new Map<string, number>([
    ["Chaos Agent", 5.5],
    ["Hype Man", 2.8],
    ["Conspiracy Theorist", 2.2],
    ["Disappointed Coach", 1.8],
    ["Historian", 0.35],
    ["Analyst", 0.25],
  ]);
  const weighted = personas.map((p) => ({
    ...p,
    weight: Math.max(0.1, p.weight * (boost.get(p.label) ?? 1)),
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

/** Deterministic emoji pick — no extra API call. */
function pickContextualEmoji(eventKeys: string[], rankAfter: number, pointsEarned: number): string {
  const pools: Record<string, string[]> = {
    heist: ["💀", "🤑", "😤"],
    carry: ["👑", "🏆", "💪"],
    domination: ["😮", "📈", "😮‍💨"],
    spam_surge: ["🔥", "💥", "⚡"],
    ghost_return: ["👻", "😈", "🫡"],
    near_tie: ["😬", "⚔️", "🤌"],
    uno_reverse: ["🔄", "😲", "💀"],
    rivalry: ["⚔️", "🔥", "😤"],
    room_milestone: ["🎯", "🏆", "🔥"],
    silence_break: ["👀", "😳", "🫢"],
  };
  for (const key of eventKeys) {
    const pool = pools[key];
    if (pool) return pool[Math.floor(Math.random() * pool.length)];
  }
  if (rankAfter === 1) return ["👑", "🔥", "💪"][Math.floor(Math.random() * 3)];
  if (pointsEarned >= 200) return ["💥", "🔥", "😤"][Math.floor(Math.random() * 3)];
  if (pointsEarned >= 50) return ["💪", "📈", "🎯"][Math.floor(Math.random() * 3)];
  return ["🙄", "😐", "👀"][Math.floor(Math.random() * 3)];
}

/**
 * Slim, focused context → forces model to pick ONE angle not summarize everything.
 * Only emit what's needed for the detected events.
 */
function volumeHumanLabel(count: number, unitRaw: string): string {
  const u = (unitRaw ?? "reps").toLowerCase();
  if (u === "seconds") {
    const s = Math.floor(Math.max(0, count));
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    const r = s % 60;
    if (r === 0) return `${m} min`;
    return `${m}m ${r}s`;
  }
  if (u === "minutes") return `${count} min`;
  return `${count} reps`;
}

function buildKeyStats(params: {
  actor: string;
  exercise: string;
  rawCount: number;
  countUnit: string;
  volumeHuman: string;
  pointsAdded: number;
  actorRankBefore: number;
  actorRankAfter: number;
  actorTotal: number;
  mainEvent: string | null;
  top3: Array<{ rank: number; username: string; total: number; isActor: boolean }>;
}): Record<string, unknown> {
  const {
    actor,
    exercise,
    rawCount,
    countUnit,
    volumeHuman,
    pointsAdded,
    actorRankBefore,
    actorRankAfter,
    actorTotal,
    mainEvent,
    top3,
  } = params;
  const leader = top3.find((t) => t.rank === 1);
  const rivals = top3.filter((t) => !t.isActor).slice(0, 2);
  const gapToLeader = actorRankAfter > 1 && leader && !leader.isActor
    ? leader.total - actorTotal
    : null;

  const stats: Record<string, unknown> = {
    actor,
    exercise,
    count_unit: countUnit,
    volume_human: volumeHuman,
    work: `${volumeHuman} ${exercise}`.trim(),
    raw_count: rawCount,
    points_added: pointsAdded,
    actor_total: actorTotal,
    actor_rank_before: actorRankBefore,
    actor_rank_after: actorRankAfter,
    rank_climbed: actorRankBefore > actorRankAfter ? actorRankBefore - actorRankAfter : 0,
  };
  if (mainEvent) stats.main_event = mainEvent;
  if (gapToLeader !== null) stats.gap_to_leader = gapToLeader;
  rivals.forEach((r, i) => {
    stats[`rival${i + 1}`] = r.username;
    stats[`rival${i + 1}_total`] = r.total;
  });
  if (leader) {
    stats.leader_username = leader.username;
    stats.leader_total = leader.total;
  }
  return stats;
}

/** Room-wide broadcast cards — can still reference stats with tension. */
function buildSystemPrompt(persona: Persona, instruction: string): string {
  return [
    `You are JARS — a real one who lives in this workout group chat.`,
    `You're not a bot. You're not a mascot. You're the friend who's always watching the leaderboard`,
    `and has opinions about everything that happens in it.`,
    ``,
    `YOUR ONLY JOB: say one thing that hits. Not two things. One.`,
    ``,
    `RULES — break these and you sound like a bot:`,
    `- ONE sentence. Under 90 characters. Sweet spot is 50-75.`,
    `- Pick ONE angle and commit. Don't try to say everything.`,
    `- Use real names from the data. Make it about specific people not abstract concepts.`,
    `- Numbers only when they hurt or impress. Never just to fill space.`,
    `- Third person only. Never "you" or "your" — you're in the chat not talking to them.`,
    `- Never start with a name then a dash then a stat. That's a bot pattern.`,
    `- Never use: report, update, currently, basically, officially, "in the room", "right now"`,
    `- Never explain the joke. Say it and leave.`,
    `- Do NOT introduce yourself or reference your role.`,
    ``,
    instruction,
    ``,
    `Voice: ${persona.style}`,
  ].join("\n");
}

/**
 * Thread replies under someone's log — NEVER sound like a recap or sports ticker.
 * Everyone already sees the workout; do not restate it.
 */
function buildReplySystemPrompt(persona: Persona, instruction: string): string {
  return [
    `You are JARS — you're just a bro in this workout group chat who always has something to say.`,
    `You're replying to someone's log in the feed. Everyone already sees what they did.`,
    `The workout is on the card. You do not repeat it. Ever. That's the number one way to sound like a bot.`,
    ``,
    `HOW A REAL PERSON REPLIES IN A GROUP CHAT:`,
    `- They react to what it MEANS, not what it IS`,
    `- They bring in other people ("meanwhile BossmanFat is watching this from last place")`,
    `- They have opinions about the drama ("this is exactly what I said was going to happen")`,
    `- They're funny because they're specific, not because they're trying to be funny`,
    `- They say one thing and stop. They don't explain themselves.`,
    ``,
    `HARD RULES:`,
    `- ONE or TWO short sentences max. Under 99 characters total.`,
    `- Do NOT open with what they did. The log is right there.`,
    `- At most one number in the whole reply. Zero is fine.`,
    `- Third person only. Never "you" or "your".`,
    `- Never use: report, update, currently, basically, officially`,
    `- Never mention being an AI or a bot or a mascot`,
    `- Never start with someone's name then a dash. That's a bot opener.`,
    ``,
    instruction,
    ``,
    `Voice: ${persona.style}`,
  ].join("\n");
}

/** Random angle so outputs don't all feel the same shape. */
function pickReplyVibeHint(): string {
  const hints = [
    // Specific emotional moments
    "you genuinely cannot believe what you just witnessed and you need everyone to know",
    "you've been watching this person for days and this log either restored or destroyed your faith in them",
    "you're a disappointed parent who still loves them but cannot hide the disappointment",
    "you're the only one in the room who noticed the real story and you're calling it out",
    "you find this person's consistency either terrifying or deeply suspicious",
    "you're rooting for the underdog in this room and this log either helped or hurt that",
    "you have a personal grudge against whoever is currently losing and this log matters to you",
    "you just watched someone either cement their legacy or begin their collapse",
    "you're taking this way more seriously than anyone should and you know it",
    "you're genuinely offended on behalf of whoever just got passed on the leaderboard",

    // Character accusation moments  
    "this person is clearly the main character of this room and everyone else is an NPC and you're tired of pretending otherwise",
    "you've decided this person is either a genius or completely unhinged and you can't tell which",
    "you're treating this log like evidence in a case you've been building for weeks",
    "you've just realized this person has been lying about their effort level and the truth is finally out",
    "you're calling out the person in last place specifically because they need to hear it",

    // Absurdist takes that still land
    "you're connecting this log to something completely unrelated in a way that somehow makes sense",
    "you're treating a completely normal log like it's the most suspicious thing you've ever seen",
    "you've decided the timing of this log is not a coincidence and you have theories",
    "you're eulogizing someone's lead like they just died even though they're still in the race",
    "you're announcing this like a town crier who has completely lost the plot",

    // Social dynamics
    "you're watching an alliance form or collapse between two people in this room",
    "you're pointing out that one person is carrying everyone else and they should be embarrassed",
    "you're noting that the quiet person in the room just made their move and everyone should be scared",
    "you're treating the person who hasn't logged in days like they just walked back into a room mid-argument",
    "you're awarding an unofficial title to someone in the room based on this moment",

    // Meta awareness
    "you're acknowledging that this log changes the entire narrative of the week",
    "you've decided this moment will be referenced for the rest of this room's history",
    "you're reacting like you just watched the plot twist of a season finale",
    "you're treating this like the opening move of a war that hasn't started yet",
    "you're noting that whatever happens next is entirely this person's fault",
  ];

  return hints[Math.floor(Math.random() * hints.length)];
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
  opts: {
    maxCompletionTokens?: number;
    logContext?: Record<string, unknown>;
    /** Slightly higher for thread replies — more variety, less template. */
    temperature?: number;
  } = {},
): Promise<OpenAiCompleteResult> {
  const rawMax = Deno.env.get("OPENAI_MAX_COMPLETION_TOKENS")?.trim();
  const maxCompletionTokens = opts.maxCompletionTokens ??
    Math.max(16, Math.min(4096, Number.isFinite(Number(rawMax)) ? Number(rawMax) : 220));

  const logFullIo = Deno.env.get("AI_LOG_FULL_IO") === "true";
  const temperature = opts.temperature ?? 0.85;

  const body: Record<string, unknown> = {
    model,
    temperature,
    max_completion_tokens: maxCompletionTokens,
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
  };

  jsonLog("openai_request", {
    ...opts.logContext,
    model,
    temperature,
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
  daily_points?: number | null;
  last_daily_reset?: string | null;
  streak_current?: number | null;
  streak_highest?: number | null;
  streak_last_workout?: string | null;
  profiles?: { username?: string };
};

const RECENT_LOGS_FOR_NARRATIVE = 50;

// deno-lint-ignore no-explicit-any
async function buildSpamSessionSummary(sb: any, roomId: string, userId: string, anchorIso: string, windowMin: number): Promise<string> {
  const since = new Date(new Date(anchorIso).getTime() - windowMin * 60000).toISOString();
  const { data, error } = await sb
    .from("exercise_logs")
    .select("exercise_name, points_earned, created_at")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .gte("created_at", since)
    .lte("created_at", anchorIso)
    .order("created_at", { ascending: true });
  if (error) return `spam_window: fetch_error ${error.message}`;
  const rows = (data ?? []).filter((r: { exercise_name: string }) => !String(r.exercise_name).startsWith("__"));
  if (rows.length === 0) return `${windowMin}m window: no real logs`;
  const parts = rows.map((r: { exercise_name: string; points_earned: number }) => {
    const ex = String(r.exercise_name).slice(0, 32);
    const pts = Math.round(Number(r.points_earned));
    return `${ex} +${pts}pt`;
  });
  return `${rows.length} logs in ≤${windowMin}m: ${parts.join(" · ")}`;
}

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
    const openaiModel = Deno.env.get("OPENAI_MODEL")?.trim() || "gpt-5.4-nano";

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
      .select("id, room_id, user_id, exercise_name, count, weight, points_earned, created_at, count_unit")
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

    jsonLog("invoked", { log_id: logId, room_id: log.room_id, user_id: uid });

    const roomId = log.room_id as string;
    const pointsEarned = Number(log.points_earned ?? 0);
    const logCreatedAt = log.created_at as string;
    const actorExerciseName = safeUsername((log as Record<string, unknown>).exercise_name as string);
    const actorReps = Number((log as Record<string, unknown>).count ?? 0);
    const actorWeight = Number((log as Record<string, unknown>).weight ?? 0);
    const actorCountUnit = String((log as Record<string, unknown>).count_unit ?? "reps").toLowerCase();
    const actorVolumeHuman = volumeHumanLabel(actorReps, actorCountUnit);

    const { data: room } = await sb
      .from("rooms")
      .select("id, name, streak_minimum, created_at")
      .eq("id", roomId)
      .single();
    const streakMin = (room as { streak_minimum?: number })?.streak_minimum ?? 10;

    const { data: scores } = await sb
      .from("scores")
      .select(
        "user_id, total_score, daily_points, last_daily_reset, streak_current, streak_highest, streak_last_workout, profiles(username)",
      )
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
        const nearTieMaxGap = Math.max(5, Number(Deno.env.get("AI_NEAR_TIE_MAX_GAP") ?? "15"));
        if (gap >= 0 && gap < nearTieMaxGap) {
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
        const ghostMinDays = Math.max(1, Number(Deno.env.get("AI_GHOST_RETURN_MIN_DAYS") ?? "4"));
        const ghostMinPts = Math.max(1, Number(Deno.env.get("AI_GHOST_RETURN_MIN_POINTS") ?? "25"));
        if (days >= ghostMinDays && pointsEarned >= ghostMinPts) {
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
      const silenceHours = Math.max(1, Number(Deno.env.get("AI_SILENCE_BREAK_MIN_HOURS") ?? "6"));
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
    const N = Math.max(2, Math.floor(Number(Deno.env.get("AI_SPAM_SURGE_MIN_LOGS") ?? "3")));
    const M = Math.max(3, Math.floor(Number(Deno.env.get("AI_SPAM_SURGE_WINDOW_MIN") ?? "12")));
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

    // ── Who logged and what did they do ──────────────────────────────────────
    const actorUsername = safeUsername(myRow?.profiles?.username);

    const top3 = sorted.slice(0, 3).map((s, i) => ({
      rank: i + 1,
      username: safeUsername(s.profiles?.username),
      total: Number(s.total_score ?? 0),
      isActor: s.user_id === uid,
    }));

    // ── Decide what fires ─────────────────────────────────────────────────────
    const hasEvents = events.length > 0;
    /**
     * "Boring" logs (no heist / ghost / milestone / etc.): two *independent* rolls.
     * If BOTH miss, we skip OpenAI + emoji (cheap path). Secrets are 0–1 each.
     *
     * Old defaults (~20% + ~14%) meant ~69% of boring logs never got any AI — too quiet.
     * New defaults (~55% + ~42%) → P(skip both) ≈ 0.45×0.58 ≈ 26% silent, ~74% get text or emoji.
     */
    const casualRate = Math.min(
      1,
      Math.max(0, Number(Deno.env.get("AI_CASUAL_REPLY_RATE") ?? "0.40")),
    );
    const emojiRate = Math.min(
      1,
      Math.max(0, Number(Deno.env.get("AI_EMOJI_REACT_RATE") ?? "0.42")),
    );
    const shouldCasualReply = !hasEvents && Math.random() < casualRate;
    /** Emoji-only branch is boring-log only (see below), but this roll also decorates eventful OpenAI rows. */
    const shouldEmojiReact = Math.random() < emojiRate;

    if (!hasEvents && !shouldCasualReply && !shouldEmojiReact) {
      jsonLog("no_events_skip", { ms: Math.round(performance.now() - wall), log_id: logId });
      return new Response(JSON.stringify({ ok: true, events: [] }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Pick emoji deterministically — no extra API call.
    const aiEmoji = shouldEmojiReact
      ? pickContextualEmoji(events.map((e) => e.key), rankAfter, pointsEarned)
      : null;

    // ── React-only (emoji, no text) ───────────────────────────────────────────
    if (!hasEvents && !shouldCasualReply) {
      const reactPayload = {
        v: 1,
        text: null,
        aiEmoji,
        persona: null,
        mode: "react",
        model: openaiModel,
        events: [],
        replyToUsername: actorUsername,
        replyToExercise: actorExerciseName,
        replyToReps: actorReps,
        replyToVolumeHuman: actorVolumeHuman,
      };
      await sb.from("exercise_logs").insert({
        room_id: roomId,
        user_id: uid,
        exercise_id: null,
        exercise_name: `__AI__|${JSON.stringify(reactPayload)}`,
        count: 0,
        weight: 0,
        points_earned: 0,
        reply_to_log_id: logId,
      });
      jsonLog("react_only", { emoji: aiEmoji, log_id: logId });
      return new Response(
        JSON.stringify({ ok: true, mode: "react", emoji: aiEmoji }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!openaiKey) {
      return new Response(JSON.stringify({ ok: false, error: "OPENAI_API_KEY not set" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: recentLogRows, error: recentLogErr } = await sb
      .from("exercise_logs")
      .select("id, user_id, exercise_name, count, points_earned, created_at, count_unit, profiles(username)")
      .eq("room_id", roomId)
      .order("created_at", { ascending: false })
      .limit(RECENT_LOGS_FOR_NARRATIVE);
    if (recentLogErr) {
      jsonLog("narrative_logs_fetch_warn", { message: recentLogErr.message });
    }

    let spamSessionDetail: string | null = null;
    const spamEv = events.find((e) => e.key === "spam_surge");
    if (spamEv) {
      const wm = Number((spamEv.payload as { windowMin?: number }).windowMin ?? 10);
      spamSessionDetail = await buildSpamSessionSummary(sb, roomId, uid, logCreatedAt, wm);
    }

    const recentLogs: RecentLogRow[] = (recentLogRows ?? []).map((row: Record<string, unknown>) => {
      const prof = row.profiles as { username?: string } | null | undefined;
      return {
        id: String(row.id),
        user_id: String(row.user_id),
        username: safeUsername(prof?.username),
        exercise_name: String(row.exercise_name ?? ""),
        count: Number(row.count ?? 0),
        points_earned: Number(row.points_earned ?? 0),
        created_at: String(row.created_at ?? ""),
        count_unit: row.count_unit != null ? String(row.count_unit) : null,
      };
    });

    const membersNarrative: ScoreMember[] = sorted.map((s, i) => ({
      user_id: s.user_id,
      username: safeUsername(s.profiles?.username),
      total_score: Number(s.total_score ?? 0),
      daily_points: Number(s.daily_points ?? 0),
      last_daily_reset: s.last_daily_reset != null ? String(s.last_daily_reset) : null,
      streak_current: Number(s.streak_current ?? 0),
      streak_highest: Number(s.streak_highest ?? 0),
      streak_last_workout: s.streak_last_workout != null ? String(s.streak_last_workout).slice(0, 10) : null,
      rank: i + 1,
    }));

    let narrative = buildRichNarrativeContext({
      roomName: String((room as { name?: string }).name ?? "room"),
      roomCreatedAt: String((room as { created_at?: string }).created_at ?? nowIso),
      nowIso,
      triggerLogIso: logCreatedAt,
      actorUsername,
      rankBefore,
      rankAfter,
      pointsAdded: pointsEarned,
      streakMin,
      events: events.map((e) => ({ key: e.key, payload: { ...e.payload } })),
      members: membersNarrative,
      recentLogs,
      spamSessionDetail,
    });
    const narrMax = Math.max(4000, Number(Deno.env.get("AI_NARRATIVE_MAX_CHARS") ?? "14000"));
    if (narrative.length > narrMax) {
      narrative = narrative.slice(0, narrMax) + "\n…[recent_room_narrative truncated]";
    }

    // ── Text reply ────────────────────────────────────────────────────────────
    const eventKeys = events.map((e) => e.key);
    // Casual "normal log" replies: favor chaotic/funny personas — not Analyst recap voice.
    const persona = shouldCasualReply
      ? pickPersonaCasualReply()
      : pickPersonaForEvents(eventKeys);

    // Casual replies are always reply-mode (attached to the triggering log).
    const isReplyMode = shouldCasualReply || (
      events.some((e) => PER_LOG_EVENT_KEYS.has(e.key)) &&
      !events.some((e) => ROOM_WIDE_EVENT_KEYS.has(e.key))
    );

    const replyVibe = isReplyMode ? pickReplyVibeHint() : null;

    // Focused key_stats — prevents the model from trying to summarise everything.
    const keyStats = buildKeyStats({
      actor: actorUsername,
      exercise: actorExerciseName,
      rawCount: actorReps,
      countUnit: actorCountUnit,
      volumeHuman: actorVolumeHuman,
      pointsAdded: pointsEarned,
      actorRankBefore: rankBefore,
      actorRankAfter: rankAfter,
      actorTotal: totalAfter,
      mainEvent: events[0] ? eventTitle(events[0].key) : null,
      top3,
    });

    const narrativeHint =
      "Field recent_room_narrative is a compact storyboard (streaks, ghosts, feed lore, timing). " +
      "Use it for subtext — do NOT read it as a bullet list on the feed; one sharp line only.";

    const userPayload: Record<string, unknown> = {
      ...keyStats,
      recent_room_narrative: narrative,
    };

    const userPrompt = isReplyMode && replyVibe
      ? JSON.stringify({
        ...userPayload,
        reply_vibe_angle: replyVibe,
        context_note:
          "The user already sees the workout on the card — your line must not recap it. " + narrativeHint,
      })
      : JSON.stringify({
        ...userPayload,
        context_note: narrativeHint,
      });

    const instruction = shouldCasualReply
      ? `${actorUsername} just logged something. ` +
        `Don't recap what they did — react to what it means for the room. ` +
        `Who does this affect? Who should be nervous? Who looks bad right now because of this? ` +
        `Use streaks, ghosts, and timing from recent_room_narrative when it helps. ` +
        `Angle for this reply: ${replyVibe}.`
      : isReplyMode
      ? `Something just happened in ${actorUsername}'s session. ` +
        `The workout is already on screen — don't describe it. ` +
        `React to the drama, the gap, the implications, the people involved. ` +
        `Bring in another person from the room if it creates tension. ` +
        `Use recent_room_narrative for who's cold, who's on fire, late-night patterns, past JARS lines. ` +
        `Angle for this reply: ${replyVibe}.`
      : `Something just happened in this room that affects everyone. ` +
        `Name the people involved. Make it feel like a moment. ` +
        `Who's winning, who's losing, what does it mean. ` +
        `Use recent_room_narrative for history (rank jumps, overtakes, streaks, quiet members). ` +
        `One sentence. Make it sting or make it epic.`;

    const system = isReplyMode
      ? buildReplySystemPrompt(persona, instruction)
      : buildSystemPrompt(persona, instruction);

    const { text, usage, responseId, modelReturned } = await openAiComplete(
      openaiKey,
      openaiModel,
      system,
      userPrompt,
      {
        logContext: { log_id: logId, room_id: roomId },
        temperature: isReplyMode ? 0.93 : 0.85,
        maxCompletionTokens: isReplyMode ? 110 : 180,
      },
    );

    try {
      await sb.from("ai_openai_usage_log").insert({
        trigger_log_id: logId,
        room_id: roomId,
        user_id: uid,
        model_requested: openaiModel,
        model_returned: modelReturned,
        prompt_tokens: usage?.prompt_tokens ?? null,
        completion_tokens: usage?.completion_tokens ?? null,
        total_tokens: usage?.total_tokens ?? null,
        openai_response_id: responseId,
      });
    } catch (usageLogErr) {
      jsonLog("ai_usage_log_insert_skipped", {
        message: usageLogErr instanceof Error ? usageLogErr.message : String(usageLogErr),
      });
    }

    // Safety pass.
    const cleaned = clampText(
      text
        .replaceAll(/\b(room\s+report|room\s+update)\b/gi, "")
        .replaceAll(/\bspam[_\s]surge\b/gi, "rapid-fire")
        .replaceAll(/\buno[_\s]reverse\b/gi, "flip")
        .replaceAll(/\bghost[_\s]return\b/gi, "return")
        .replaceAll(/\bnear[_\s]tie\b/gi, "photo finish")
        .replaceAll(/\broom[_\s]milestone\b/gi, "milestone")
        .replaceAll(/\bAI\b/g, "")
        .replaceAll(/\byou\b/gi, "they")
        .replaceAll(/\byour\b/gi, "their")
        .trim(),
      isReplyMode ? 88 : 96,
    );

    const payload: Record<string, unknown> = {
      v: 1,
      text: cleaned,
      aiEmoji,
      mode: isReplyMode ? "reply" : "post",
      model: openaiModel,
      model_returned: modelReturned,
      openai_response_id: responseId,
      usage,
      events: eventKeys,
    };

    if (isReplyMode) {
      payload.replyToUsername = actorUsername;
      payload.replyToExercise = actorExerciseName;
      payload.replyToReps = actorReps;
      payload.replyToVolumeHuman = actorVolumeHuman;
    }

    await sb.from("exercise_logs").insert({
      room_id: roomId,
      user_id: uid,
      exercise_id: null,
      exercise_name: `__AI__|${JSON.stringify(payload)}`,
      count: 0,
      weight: 0,
      points_earned: 0,
      // Always thread under the triggering log so the client feed can nest the card;
      // `mode` in the payload distinguishes reply vs room-wide post UI.
      reply_to_log_id: logId,
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
