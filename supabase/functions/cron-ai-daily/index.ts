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

async function openAiComplete(
  apiKey: string,
  model: string,
  system: string,
  user: string,
): Promise<string> {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      temperature: 0.85,
      max_tokens: 240,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`OpenAI ${res.status}: ${t.slice(0, 400)}`);
  }
  const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
  return data.choices?.[0]?.message?.content?.trim() ?? "";
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
        const names = behind.map((b) => b.profiles?.username ?? "?").join(", ");
        const prompt = JSON.stringify({
          kind: "last_stand",
          room: roomName,
          streakMinimum: streakMin,
          usersBehind: behind.map((b) => ({
            username: b.profiles?.username ?? "?",
            dailyPoints: Number(b.daily_points ?? 0),
          })),
        });
        const system =
          `Write ONE short Jars narrator message (max 280 chars) for lifters who still haven't hit the daily streak floor. ` +
          `Names: ${names}. Urgent but fun.`;
        const text = await openAiComplete(openaiKey, openaiModel, system, prompt);
        const payload = {
          v: 1,
          text,
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
            actor: (actorProf as { username?: string })?.username ?? "?",
            victim: (victimProf as { username?: string })?.username ?? "?",
          });
          const text = await openAiComplete(
            openaiKey,
            openaiModel,
            `One line (max 240 chars): tension because someone got passed and still hasn't answered.`,
            prompt,
          );
          await sb.from("exercise_logs").insert({
            room_id: roomId,
            user_id: adminId,
            exercise_id: null,
            exercise_name: `__AI__|${JSON.stringify({
              v: 1,
              text,
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
          const prompt = JSON.stringify({ kind: "retirement", room: roomName, inactiveCount: inactive.length });
          const text = await openAiComplete(
            openaiKey,
            openaiModel,
            `One short dramatic line (max 220 chars) about ghosts / missing lifters in ${roomName}.`,
            prompt,
          );
          await sb.from("exercise_logs").insert({
            room_id: roomId,
            user_id: adminId,
            exercise_id: null,
            exercise_name: `__AI__|${JSON.stringify({ v: 1, text, model: openaiModel, events: ["retirement"] })}`,
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
          const prompt = JSON.stringify({
            kind: "carry_lore",
            room: roomName,
            leader: top.profiles?.username ?? "?",
            points: top.total_score,
          });
          const text = await openAiComplete(
            openaiKey,
            openaiModel,
            `One funny line (max 200 chars) about one person carrying the room scoreboard.`,
            prompt,
          );
          await sb.from("exercise_logs").insert({
            room_id: roomId,
            user_id: adminId,
            exercise_id: null,
            exercise_name: `__AI__|${JSON.stringify({ v: 1, text, model: openaiModel, events: ["carry_lore"] })}`,
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
