// Daily cron: Last Stand, Response Gap, random Retirement / Carry lore.
// curl -X POST "$SUPABASE_URL/functions/v1/cron-ai-daily" -H "Authorization: Bearer $CRON_SECRET"
//
// Secrets: CRON_SECRET, OPENAI_API_KEY, OPENAI_MODEL (optional)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonLog(phase: string, data: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ tag: "jars_ai_cron", phase, t: new Date().toISOString(), ...data }));
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

/** Event-affinity: multiply base weights for the cron event type. */
function pickPersonaForEvent(eventKey: string): Persona {
  const personas = getPersonas();
  const mult = new Map<string, number>(personas.map((p) => [p.label, 1.0]));
  switch (eventKey) {
    case "last_stand":
      mult.set("Disappointed Coach", 4);
      mult.set("Historian", 2);
      break;
    case "response_gap":
      mult.set("Conspiracy Theorist", 4);
      mult.set("Analyst", 2);
      break;
    case "retirement":
      mult.set("Historian", 3);
      mult.set("Disappointed Coach", 2);
      mult.set("Chaos Agent", 2);
      break;
    case "carry_lore":
      mult.set("Historian", 3);
      mult.set("Hype Man", 2);
      break;
  }
  const weighted = personas.map((p) => ({
    ...p,
    weight: Math.max(0.1, p.weight * (mult.get(p.label) ?? 1)),
  }));
  return pickWeighted(weighted);
}

function safeUsername(s: unknown): string {
  const v = typeof s === "string" ? s.trim() : "";
  if (!v) return "?";
  return v.slice(0, 24);
}

function clampText(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max - 1).trimEnd() + "…";
}

interface OpenAiUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  [k: string]: unknown;
}

async function openAiComplete(
  apiKey: string,
  model: string,
  system: string,
  user: string,
  logContext: Record<string, unknown> = {},
): Promise<{ text: string; usage: OpenAiUsage | null }> {
  const rawMax = Deno.env.get("OPENAI_MAX_COMPLETION_TOKENS")?.trim();
  const maxCompletionTokens = Math.max(
    16,
    Math.min(4096, Number.isFinite(Number(rawMax)) ? Number(rawMax) : 240),
  );

  const body: Record<string, unknown> = {
    model,
    temperature: 0.85,
    max_completion_tokens: maxCompletionTokens,
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
  };

  const logFullIo = Deno.env.get("AI_LOG_FULL_IO") === "true";

  jsonLog("openai_request", {
    ...logContext,
    model,
    max_completion_tokens: maxCompletionTokens,
    system_chars: system.length,
    user_chars: user.length,
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
    jsonLog("openai_http_error", { status: res.status, body_preview: rawText.slice(0, 1200), ...logContext });
    throw new Error(`OpenAI ${res.status}: ${rawText.slice(0, 400)}`);
  }

  const data = JSON.parse(rawText) as {
    id?: string;
    model?: string;
    choices?: Array<{ message?: { content?: string }; finish_reason?: string }>;
    usage?: OpenAiUsage;
  };

  const usage = data.usage ?? null;
  const text = data.choices?.[0]?.message?.content?.trim() ?? "";

  jsonLog("openai_response", {
    ...logContext,
    response_id: data.id ?? null,
    model_returned: data.model ?? null,
    usage,
    finish_reason: data.choices?.[0]?.finish_reason ?? null,
    completion_chars: text.length,
    completion_preview: text.slice(0, 400),
    completion_full: logFullIo ? text : undefined,
    cost_hint: usage
      ? {
          prompt_tokens: usage.prompt_tokens,
          completion_tokens: usage.completion_tokens,
          total_tokens: usage.total_tokens,
        }
      : null,
  });

  return { text, usage };
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const openaiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
    const openaiModel = Deno.env.get("OPENAI_MODEL")?.trim() || "gpt-4o-mini";

    const sb = createClient(supabaseUrl, service);

    const { data: rooms } = await sb.from("rooms").select("id, name, streak_minimum, admin_id");

    const results: string[] = [];

    for (const room of rooms ?? []) {
      const roomId = (room as { id: string }).id;
      const roomName = (room as { name: string }).name;
      const streakMin = (room as { streak_minimum?: number }).streak_minimum ?? 10;
      const adminId = (room as { admin_id?: string }).admin_id;

      const { data: rstate } = await sb
        .from("room_ai_state")
        .select(
          "last_carry_roll_date, last_retirement_roll_date, last_last_stand_date",
        )
        .eq("room_id", roomId)
        .maybeSingle();

      const today = new Date().toISOString().slice(0, 10);
      const lastCarry = (rstate as { last_carry_roll_date?: string })?.last_carry_roll_date;
      const lastRet = (rstate as { last_retirement_roll_date?: string })?.last_retirement_roll_date;
      const lastStand = (rstate as { last_last_stand_date?: string })?.last_last_stand_date;

      // --- Last stand (once per room per calendar day) ---
      const { data: scores } = await sb
        .from("scores")
        .select("user_id, daily_points, profiles(username)")
        .eq("room_id", roomId);

      type ScoreR = {
        user_id: string;
        daily_points?: number;
        profiles?: { username?: string };
      };
      const behind = (scores ?? []).filter((s: ScoreR) => {
        return Number(s.daily_points ?? 0) < streakMin;
      }) as ScoreR[];

      if (
        openaiKey &&
        adminId &&
        behind.length > 0 &&
        lastStand !== today
      ) {
        const names = behind.map((b) => safeUsername(b.profiles?.username)).join(", ");
        const persona = pickPersonaForEvent("last_stand");
        const prompt = JSON.stringify({
          kind: "last_stand",
          room: roomName,
          streakMinimum: streakMin,
          usersBehind: behind.map((b) => ({
            username: safeUsername(b.profiles?.username),
            dailyPoints: Number(b.daily_points ?? 0),
          })),
        });
        const system = [
          `You are "Jars", the competitive mascot commentator for a fitness tracking app room.`,
          `You are NOT an AI assistant — you are the room's character voice.`,
          `ABSOLUTE RULES:`,
          `- Never use second-person ("you/your"). Always third-person.`,
          `- 1–2 sentences. No bullet points, no hashtags.`,
          `- Reference the names naturally. Urgent but fun. Not cruel.`,
          `PERSONA: ${persona.label}`,
          `STYLE: ${persona.style}`,
          `LENGTH: max 260 characters.`,
          `NAMES BEHIND ON STREAK: ${names}`,
        ].join("\n");
        const { text } = await openAiComplete(openaiKey, openaiModel, system, prompt, {
          kind: "last_stand",
          room_id: roomId,
        });
        const cleaned = clampText(
          text
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
          events: ["last_stand"],
          kind: "last_stand",
        };
        await sb.from("exercise_logs").insert({
          room_id: roomId,
          user_id: adminId,
          exercise_id: null,
          exercise_name: `__AI__|${JSON.stringify(payload)}`,
          count: 0,
          weight: 0,
          points_earned: 0,
        });
        await sb.from("room_ai_state").upsert(
          {
            room_id: roomId,
            last_last_stand_date: today,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "room_id" },
        );
        results.push(`last_stand:${roomId}`);
      }

      // --- Response gap: open watches, victim still silent ≥6h ---
      if (openaiKey && adminId) {
        const { data: watches } = await sb
          .from("overtake_response_watch")
          .select("id, victim_user_id, actor_user_id, created_at")
          .eq("room_id", roomId)
          .is("response_gap_fired_at", null);

        for (const w of watches ?? []) {
          const wid = (w as { id: string }).id;
          const victim = (w as { victim_user_id: string }).victim_user_id;
          const actor = (w as { actor_user_id: string }).actor_user_id;
          const createdAt = new Date((w as { created_at: string }).created_at);
          const hours = (Date.now() - createdAt.getTime()) / 3600000;
          if (hours < 6) continue;

          const { data: lastReal } = await sb
            .from("exercise_logs")
            .select("created_at")
            .eq("room_id", roomId)
            .eq("user_id", victim)
            .not("exercise_name", "like", "__%")
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();

          const lastAt = lastReal ? new Date((lastReal as { created_at: string }).created_at) : null;
          if (lastAt && lastAt.getTime() > createdAt.getTime()) {
            await sb.from("overtake_response_watch").delete().eq("id", wid);
            continue;
          }

          const { data: actorProf } = await sb.from("profiles").select("username").eq("id", actor).maybeSingle();
          const { data: victimProf } = await sb.from("profiles").select("username").eq("id", victim).maybeSingle();
          const prompt = JSON.stringify({
            kind: "response_gap",
            room: roomName,
            hours: Math.round(hours),
            actor: safeUsername((actorProf as { username?: string })?.username),
            victim: safeUsername((victimProf as { username?: string })?.username),
          });
          const persona = pickPersonaForEvent("response_gap");
          const system = [
            `You are "Jars", the competitive mascot commentator for a fitness tracking app room.`,
            `You are NOT an AI assistant — you are the room's character voice.`,
            `ABSOLUTE RULES:`,
            `- Never use second-person ("you/your"). Always third-person.`,
            `- 1–2 sentences. No bullet points, no hashtags.`,
            `- Reference real names and stats. No generic filler.`,
            `- Fun, not cruel.`,
            `PERSONA: ${persona.label}`,
            `STYLE: ${persona.style}`,
            `LENGTH: max 240 characters.`,
          ].join("\n");
          const { text } = await openAiComplete(
            openaiKey,
            openaiModel,
            system,
            prompt,
            { kind: "response_gap", room_id: roomId, watch_id: wid },
          );
          const cleaned = clampText(
            text
              .replaceAll(/\bAI\b/gi, "")
              .replaceAll(/\byou\b/gi, "they")
              .replaceAll(/\byour\b/gi, "their")
              .trim(),
            320,
          );
          await sb.from("exercise_logs").insert({
            room_id: roomId,
            user_id: adminId,
            exercise_id: null,
            exercise_name: `__AI__|${JSON.stringify({
              v: 1,
              text: cleaned,
              persona: persona.label,
              model: openaiModel,
              events: ["response_gap"],
            })}`,
            count: 0,
            weight: 0,
            points_earned: 0,
          });
          await sb.from("overtake_response_watch").update({ response_gap_fired_at: new Date().toISOString() }).eq(
            "id",
            wid,
          );
          results.push(`response_gap:${roomId}:${wid}`);
        }
      }

      // --- Random retirement (once/day roll, 15% chance) ---
      if (openaiKey && lastRet !== today && Math.random() < 0.15 && adminId) {
        const since = new Date(Date.now() - 5 * 86400000).toISOString();
        const { data: mems } = await sb.from("room_members").select("user_id").eq("room_id", roomId);
        const ids = (mems ?? []).map((m: { user_id: string }) => m.user_id);
        const inactive: string[] = [];
        for (const uid of ids) {
          const { data: lastLog } = await sb
            .from("exercise_logs")
            .select("created_at")
            .eq("room_id", roomId)
            .eq("user_id", uid)
            .not("exercise_name", "like", "__%")
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();
          const la = lastLog && (lastLog as { created_at: string }).created_at;
          if (!la || new Date(la).getTime() < new Date(since).getTime()) {
            inactive.push(uid);
          }
        }
        if (inactive.length > 0) {
          const persona = pickPersonaForEvent("retirement");
          const prompt = JSON.stringify({ kind: "retirement", room: roomName, inactiveCount: inactive.length });
          const { text } = await openAiComplete(
            openaiKey,
            openaiModel,
            [
              `You are "Jars", the competitive mascot commentator for a fitness tracking app room.`,
              `You are NOT an AI assistant — you are the room's character voice.`,
              `ABSOLUTE RULES:`,
              `- Never use second-person ("you/your"). Always third-person.`,
              `- 1–2 sentences. No bullet points, no hashtags.`,
              `- Reference real names and stats. Funny/dramatic, not cruel.`,
              `PERSONA: ${persona.label}`,
              `STYLE: ${persona.style}`,
              `LENGTH: max 220 characters.`,
            ].join("\n"),
            prompt,
            { kind: "retirement", room_id: roomId },
          );
          const cleaned = clampText(
            text
              .replaceAll(/\bAI\b/gi, "")
              .replaceAll(/\byou\b/gi, "they")
              .replaceAll(/\byour\b/gi, "their")
              .trim(),
            320,
          );
          await sb.from("exercise_logs").insert({
            room_id: roomId,
            user_id: adminId,
            exercise_id: null,
            exercise_name: `__AI__|${JSON.stringify({
              v: 1,
              text: cleaned,
              persona: persona.label,
              model: openaiModel,
              events: ["retirement"],
            })}`,
            count: 0,
            weight: 0,
            points_earned: 0,
          });
          results.push(`retirement:${roomId}`);
        }
        await sb.from("room_ai_state").upsert(
          { room_id: roomId, last_retirement_roll_date: today, updated_at: new Date().toISOString() },
          { onConflict: "room_id" },
        );
      }

      // --- Random carry lore (once/day roll, 12% chance) ---
      if (openaiKey && lastCarry !== today && Math.random() < 0.12 && adminId) {
        const { data: sc } = await sb
          .from("scores")
          .select("user_id, total_score, profiles(username)")
          .eq("room_id", roomId)
          .order("total_score", { ascending: false })
          .limit(1)
          .maybeSingle();
        const top = sc as {
          user_id: string;
          total_score: number;
          profiles?: { username?: string };
        } | null;
        if (top) {
          const persona = pickPersonaForEvent("carry_lore");
          const prompt = JSON.stringify({
            kind: "carry_lore",
            room: roomName,
            leader: safeUsername(top.profiles?.username),
            points: top.total_score,
          });
          const { text } = await openAiComplete(
            openaiKey,
            openaiModel,
            [
              `You are "Jars", the competitive mascot commentator for a fitness tracking app room.`,
              `You are NOT an AI assistant — you are the room's character voice.`,
              `ABSOLUTE RULES:`,
              `- Never use second-person ("you/your"). Always third-person.`,
              `- 1–2 sentences. No bullet points, no hashtags.`,
              `- Reference the leader by name and points. Funny, competitive, not cruel.`,
              `PERSONA: ${persona.label}`,
              `STYLE: ${persona.style}`,
              `LENGTH: max 200 characters.`,
            ].join("\n"),
            prompt,
            { kind: "carry_lore", room_id: roomId },
          );
          const cleaned = clampText(
            text
              .replaceAll(/\bAI\b/gi, "")
              .replaceAll(/\byou\b/gi, "they")
              .replaceAll(/\byour\b/gi, "their")
              .trim(),
            320,
          );
          await sb.from("exercise_logs").insert({
            room_id: roomId,
            user_id: adminId,
            exercise_id: null,
            exercise_name: `__AI__|${JSON.stringify({
              v: 1,
              text: cleaned,
              persona: persona.label,
              model: openaiModel,
              events: ["carry_lore"],
            })}`,
            count: 0,
            weight: 0,
            points_earned: 0,
          });
          results.push(`carry_lore:${roomId}`);
        }
        await sb.from("room_ai_state").upsert(
          { room_id: roomId, last_carry_roll_date: today, updated_at: new Date().toISOString() },
          { onConflict: "room_id" },
        );
      }
    }

    return new Response(JSON.stringify({ ok: true, results }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
