// Wave-1 achievements after each real workout log → progress + bonus points + one __ACH__| feed row.
// Deploy: supabase functions deploy process-achievements --no-verify-jwt
//
/// <reference path="./deno.d.ts" />
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { ACHIEVEMENT_BY_KEY, type CatalogEntry } from "./achievement_catalog.ts";
import { buildUnlockFeed } from "./achievement_feed_lines.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const CHICAGO = "America/Chicago";
const ACH_PREFIX = "__ACH__|";
const SESSION_WINDOW_MIN = 20;
const SPAM_WINDOW_MIN = 5;
const WITNESS_SILENCE_HOURS = 8;

function jsonLog(tag: string, data: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ tag: "jars_achievements", phase: tag, t: new Date().toISOString(), ...data }));
}

function isBroadcastName(name: string): boolean {
  return name.startsWith("__");
}

function chicagoDateKey(iso: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: CHICAGO,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(iso));
}

function chicagoHour(iso: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: CHICAGO,
    hour: "numeric",
    hour12: false,
  }).formatToParts(new Date(iso));
  const h = parts.find((p) => p.type === "hour")?.value ?? "0";
  return parseInt(h, 10);
}

function isNightChicago(iso: string): boolean {
  const h = chicagoHour(iso);
  return h >= 23 || h < 5;
}

function chicagoYesterdayKey(iso: string): string {
  const key = chicagoDateKey(iso);
  const [y, m, d] = key.split("-").map(Number);
  const noonUtc = Date.UTC(y, m - 1, d, 17, 0, 0);
  return chicagoDateKey(new Date(noonUtc - 86400000).toISOString());
}

type ProgressRow = {
  room_id: string;
  user_id: string;
  achievement_key: string;
  tier_reached: number;
  progress: Record<string, unknown>;
  last_unlock_at: string | null;
};

type UnlockOut = {
  user_id: string;
  key: string;
  tier: number;
  /** Punchy feed line */
  line: string;
  /** Tier + points (subtitle) */
  meta: string;
  points: number;
};

type UnlockExtra = { targetUserId?: string; sessionPts?: number };

function nextTierThreshold(def: CatalogEntry, tierReached: number): number | null {
  if (tierReached >= def.tiers.length) return null;
  return def.tiers[tierReached].at;
}

type ScoreFull = { user_id: string; total_score: number; streak_current?: number | null };

function computeRankContext(
  scores: ScoreFull[],
  actorId: string,
  pointsEarned: number,
): {
  rankAfter: number;
  rankBefore: number;
  memberCount: number;
  actorTotal: number;
  pointsBefore: number;
  roomTotal: number;
  sharePercent: number;
} {
  const list = scores.map((s) => ({
    user_id: s.user_id,
    total: Number(s.total_score ?? 0),
  }));
  list.sort((a, b) => b.total - a.total || String(a.user_id).localeCompare(String(b.user_id)));
  const actorTotal = list.find((x) => x.user_id === actorId)?.total ?? 0;
  const pointsBefore = actorTotal - pointsEarned;
  const beforeList = list.map((x) => ({
    user_id: x.user_id,
    total: x.user_id === actorId ? pointsBefore : x.total,
  }));
  beforeList.sort((a, b) => b.total - a.total || String(a.user_id).localeCompare(String(b.user_id)));
  const rankAfter = list.findIndex((x) => x.user_id === actorId) + 1;
  const rankBefore = beforeList.findIndex((x) => x.user_id === actorId) + 1;
  const memberCount = list.length;
  const roomTotal = list.reduce((s, x) => s + x.total, 0);
  const sharePercent = roomTotal > 0 ? Math.floor((actorTotal / roomTotal) * 100) : 0;
  return { rankAfter, rankBefore, memberCount, actorTotal, pointsBefore, roomTotal, sharePercent };
}

function gapLeadWhenFirst(scores: ScoreFull[], actorId: string): number {
  const list = scores
    .map((s) => ({ user_id: s.user_id, total: Number(s.total_score ?? 0) }))
    .sort((a, b) => b.total - a.total || String(a.user_id).localeCompare(String(b.user_id)));
  if (list.length < 2) return 0;
  if (list[0].user_id !== actorId) return 0;
  return list[0].total - list[1].total;
}

function gapBehindLeaderWhenSecond(scores: ScoreFull[], actorId: string): number {
  const list = scores
    .map((s) => ({ user_id: s.user_id, total: Number(s.total_score ?? 0) }))
    .sort((a, b) => b.total - a.total || String(a.user_id).localeCompare(String(b.user_id)));
  if (list.length < 2) return 999;
  if (list[1].user_id !== actorId) return 999;
  return list[0].total - list[1].total;
}

function detectOvertakeVictim(
  scores: ScoreFull[],
  actorId: string,
  pointsBefore: number,
  pointsAfter: number,
): string | null {
  for (const s of scores) {
    if (s.user_id === actorId) continue;
    const t = Number(s.total_score ?? 0);
    if (t > pointsBefore && t <= pointsAfter) return s.user_id;
  }
  return null;
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
    const logCreatedAt = log.created_at as string;
    const pointsEarned = Number(log.points_earned ?? 0);
    const nowIso = new Date().toISOString();

    const { error: claimErr } = await sb.from("achievement_processed_logs").insert({ log_id: logId });
    if (claimErr) {
      const code = (claimErr as { code?: string }).code;
      if (code === "23505") {
        return new Response(JSON.stringify({ ok: true, skipped: "already_processed" }), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      jsonLog("claim_error", { message: claimErr.message });
      return new Response(JSON.stringify({ error: claimErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    try {
      const { data: progRows } = await sb
        .from("room_achievement_progress")
        .select("*")
        .eq("room_id", roomId);

      const progressByKey = new Map<string, ProgressRow>();
      const dirtyProgress = new Set<string>();
      for (const r of progRows ?? []) {
        const pr = r as ProgressRow;
        pr.tier_reached = Number(pr.tier_reached ?? 0);
        progressByKey.set(`${r.user_id}::${r.achievement_key}`, pr);
      }

      const getProg = (userId: string, key: string): ProgressRow => {
        const k = `${userId}::${key}`;
        const existing = progressByKey.get(k);
        if (existing) return existing;
        const fresh: ProgressRow = {
          room_id: roomId,
          user_id: userId,
          achievement_key: key,
          tier_reached: 0 as number,
          progress: {},
          last_unlock_at: null,
        };
        progressByKey.set(k, fresh);
        return fresh;
      };

      const markDirty = (userId: string, key: string) => dirtyProgress.add(`${userId}::${key}`);

      const { data: scoresFull } = await sb
        .from("scores")
        .select("user_id, total_score, streak_current")
        .eq("room_id", roomId);

      const scoreRows = (scoresFull ?? []) as ScoreFull[];

      const streakByUser = new Map<string, number>();
      for (const s of scoreRows) {
        streakByUser.set(s.user_id, Number(s.streak_current ?? 0));
      }

      const rk = computeRankContext(scoreRows, uid, pointsEarned);
      const victim = detectOvertakeVictim(scoreRows, uid, rk.pointsBefore, rk.actorTotal);
      const leadGap = gapLeadWhenFirst(scoreRows, uid);
      const gapSecond = gapBehindLeaderWhenSecond(scoreRows, uid);

      const { data: rai } = await sb.from("room_ai_state").select("last_room_log_at").eq("room_id", roomId).maybeSingle();
      const lastRoomLogAt = (rai as { last_room_log_at?: string } | null)?.last_room_log_at ?? null;

      const sinceSpam = new Date(new Date(logCreatedAt).getTime() - SPAM_WINDOW_MIN * 60000).toISOString();
      const { data: spamLogs } = await sb
        .from("exercise_logs")
        .select("exercise_name")
        .eq("room_id", roomId)
        .eq("user_id", uid)
        .gte("created_at", sinceSpam)
        .lte("created_at", logCreatedAt);

      const spamCount = (spamLogs ?? []).filter(
        (r: { exercise_name: string }) => !isBroadcastName(String(r.exercise_name)),
      ).length;

      const sinceSession = new Date(new Date(logCreatedAt).getTime() - SESSION_WINDOW_MIN * 60000).toISOString();
      const { data: sessionLogs } = await sb
        .from("exercise_logs")
        .select("points_earned, exercise_name")
        .eq("room_id", roomId)
        .eq("user_id", uid)
        .gte("created_at", sinceSession)
        .lte("created_at", logCreatedAt);

      let sessionPts = 0;
      for (const r of sessionLogs ?? []) {
        if (isBroadcastName(String((r as { exercise_name: string }).exercise_name))) continue;
        sessionPts += Number((r as { points_earned: number }).points_earned ?? 0);
      }

      const { count: prCountRaw } = await sb
        .from("exercise_logs")
        .select("id", { count: "exact", head: true })
        .eq("room_id", roomId)
        .eq("user_id", uid)
        .like("exercise_name", "__PR__|%");
      const prCount = prCountRaw ?? 0;

      const { count: prSessionRaw } = await sb
        .from("exercise_logs")
        .select("id", { count: "exact", head: true })
        .eq("room_id", roomId)
        .eq("user_id", uid)
        .like("exercise_name", "__PR__|%")
        .gte("created_at", sinceSession)
        .lte("created_at", logCreatedAt);
      const prSessionCount = prSessionRaw ?? 0;

      const recentSince = new Date(new Date(logCreatedAt).getTime() - 4 * 86400000).toISOString();
      const { data: recentUserLogs } = await sb
        .from("exercise_logs")
        .select("id, created_at, exercise_name, points_earned")
        .eq("room_id", roomId)
        .eq("user_id", uid)
        .gte("created_at", recentSince)
        .lte("created_at", logCreatedAt)
        .order("created_at", { ascending: false })
        .limit(80);

      const yesterdayKey = chicagoYesterdayKey(logCreatedAt);
      const todayKey = chicagoDateKey(logCreatedAt);
      let yesterdaySum = 0;
      let firstLogToday = true;
      for (const r of recentUserLogs ?? []) {
        const en = String((r as { exercise_name: string }).exercise_name);
        if (isBroadcastName(en)) continue;
        const ck = chicagoDateKey(String((r as { created_at: string }).created_at));
        if (ck === yesterdayKey) {
          yesterdaySum += Number((r as { points_earned: number }).points_earned ?? 0);
        }
        if (ck === todayKey && String((r as { id: string }).id) !== logId) {
          firstLogToday = false;
        }
      }

      const { data: members } = await sb
        .from("room_members")
        .select("user_id, joined_at")
        .eq("room_id", roomId);
      const memberRows = (members ?? []) as { user_id: string; joined_at: string }[];
      const memberIds = memberRows.map((m) => m.user_id);
      const joinedAtByUser = new Map<string, string>();
      for (const m of memberRows) joinedAtByUser.set(m.user_id, m.joined_at);

      const nameByUser = new Map<string, string>();
      if (memberIds.length > 0) {
        const { data: profRows } = await sb.from("profiles").select("id, username").in("id", memberIds);
        for (const p of profRows ?? []) {
          const id = String((p as { id: string }).id);
          const un = String((p as { username: string | null }).username ?? "").trim();
          nameByUser.set(id, un || id.slice(0, 8));
        }
      }
      const displayName = (userId: string) => nameByUser.get(userId) ?? "Someone";

      const sinceTroll = new Date(new Date(logCreatedAt).getTime() - 30 * 60000).toISOString();
      const { data: trollLogs } = await sb
        .from("exercise_logs")
        .select("points_earned, exercise_name")
        .eq("room_id", roomId)
        .eq("user_id", uid)
        .gte("created_at", sinceTroll)
        .lte("created_at", logCreatedAt);
      const trollTinyCount = (trollLogs ?? []).filter((r: { exercise_name: string; points_earned: number }) =>
        !isBroadcastName(String(r.exercise_name)) && Number(r.points_earned ?? 0) <= 8,
      ).length;

      const { data: recentRoomLogs } = await sb
        .from("exercise_logs")
        .select("user_id, created_at, exercise_name")
        .eq("room_id", roomId)
        .gte("created_at", new Date(new Date(logCreatedAt).getTime() - 14 * 86400000).toISOString())
        .lte("created_at", logCreatedAt)
        .order("created_at", { ascending: false })
        .limit(600);

      const lastRealByUser = new Map<string, string>();
      for (const r of recentRoomLogs ?? []) {
        const u = String((r as { user_id: string }).user_id);
        if (lastRealByUser.has(u)) continue;
        const en = String((r as { exercise_name: string }).exercise_name);
        if (isBroadcastName(en)) continue;
        lastRealByUser.set(u, String((r as { created_at: string }).created_at));
      }

      const unlocks: UnlockOut[] = [];
      const hints: string[] = [];

      const tryUnlock = (
        userId: string,
        def: CatalogEntry,
        newTier: number,
        pts: number,
        extra?: UnlockExtra,
      ) => {
        const row = getProg(userId, def.key);
        row.tier_reached = Number(row.tier_reached ?? 0);
        if (newTier <= row.tier_reached) return;
        if (newTier > def.tiers.length) return;
        row.tier_reached = newTier;
        row.last_unlock_at = nowIso;
        markDirty(userId, def.key);
        const { feed, meta } = buildUnlockFeed(def, newTier, pts, userId, displayName, extra);
        unlocks.push({
          user_id: userId,
          key: def.key,
          tier: newTier,
          line: feed,
          meta,
          points: pts,
        });
      };

      const pushHint = (s: string) => {
        if (!hints.includes(s)) hints.push(s);
      };

      // --- Night creature (actor) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("night_creature")!;
        const row = getProg(uid, "night_creature");
        const prevN = Number(row.progress.night_count ?? 0);
        let n = prevN;
        if (isNightChicago(logCreatedAt)) n += 1;
        row.progress = { ...row.progress, night_count: n };
        if (n !== prevN) markDirty(uid, "night_creature");
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          const need = def.tiers[ti].at;
          if (n >= need) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) pushHint(`Night Creature ${Math.min(n, next)}/${next} late logs`);
      }

      // --- Spam demon ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("spam_demon")!;
        const row = getProg(uid, "spam_demon");
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (spamCount >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) pushHint(`Spam Demon ${Math.min(spamCount, next)}/${next} logs in ${SPAM_WINDOW_MIN}m`);
      }

      // --- Breaker ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("breaker")!;
        const row = getProg(uid, "breaker");
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (prCount >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) pushHint(`Breaker ${Math.min(prCount, next)}/${next} PRs`);
      }

      // --- Exploded ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("exploded")!;
        const row = getProg(uid, "exploded");
        row.tier_reached = Number(row.tier_reached ?? 0);
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (sessionPts >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints, { sessionPts });
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) {
          pushHint(`Exploded ${Math.min(Math.round(sessionPts), next)}/${next} pts · ${SESSION_WINDOW_MIN}m`);
        }
      }

      // --- Engine / Machine ---
      {
        const streak = streakByUser.get(uid) ?? 0;
        for (const key of ["engine", "machine"] as const) {
          const def = ACHIEVEMENT_BY_KEY.get(key)!;
          const row = getProg(uid, key);
          let targetTier = row.tier_reached;
          for (let ti = 0; ti < def.tiers.length; ti++) {
            if (streak >= def.tiers[ti].at) targetTier = ti + 1;
          }
          if (targetTier > row.tier_reached) {
            for (let t = row.tier_reached + 1; t <= targetTier; t++) {
              tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
            }
          }
          const next = nextTierThreshold(def, row.tier_reached);
          if (next != null) pushHint(`${def.displayName} streak ${Math.min(streak, next)}/${next}`);
        }
      }

      // --- Warmup ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("warmup")!;
        const row = getProg(uid, "warmup");
        const lastAward = row.progress.warmup_award_date as string | undefined;
        const okBand = yesterdaySum >= 1 && yesterdaySum <= 5;
        if (
          okBand &&
          firstLogToday &&
          lastAward !== todayKey &&
          row.tier_reached < 1
        ) {
          tryUnlock(uid, def, 1, def.tiers[0].rewardPoints);
          row.progress = { ...row.progress, warmup_award_date: todayKey };
        }
      }

      // --- Witness (actor broke silence) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("witness")!;
        const row = getProg(uid, "witness");
        if (lastRoomLogAt) {
          const gapMs = new Date(logCreatedAt).getTime() - new Date(lastRoomLogAt).getTime();
          const gapHours = gapMs / 3600000;
          let targetTier = row.tier_reached;
          if (gapHours >= 24) targetTier = Math.max(targetTier, Math.min(def.tiers.length, 2));
          else if (gapHours >= 8) targetTier = Math.max(targetTier, Math.min(def.tiers.length, 1));
          if (targetTier > row.tier_reached) {
            for (let t = row.tier_reached + 1; t <= targetTier; t++) {
              tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
            }
          }
        }
      }

      // --- Ghost (other members idle when actor logs) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("ghost")!;
        const logT = new Date(logCreatedAt).getTime();
        for (const mid of memberIds) {
          if (mid === uid) continue;
          const last = lastRealByUser.get(mid);
          if (!last) continue;
          const idleMs = logT - new Date(last).getTime();
          const idleDays = Math.floor(idleMs / 86400000);
          const row = getProg(mid, "ghost");
          let targetTier = row.tier_reached;
          if (idleDays >= 7 && def.tiers.length >= 2) targetTier = Math.max(targetTier, 2);
          else if (idleDays >= 3) targetTier = Math.max(targetTier, 1);
          if (targetTier > row.tier_reached) {
            for (let t = row.tier_reached + 1; t <= targetTier; t++) {
              tryUnlock(mid, def, t, def.tiers[t - 1].rewardPoints);
            }
          }
        }
      }

      const rankJump = rk.rankBefore - rk.rankAfter;

      // --- Head Hunter ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("head_hunter")!;
        const row = getProg(uid, "head_hunter");
        let n = Number(row.progress.overtake_total ?? 0);
        if (victim) {
          n += 1;
          row.progress = { ...row.progress, overtake_total: n };
          markDirty(uid, "head_hunter");
        }
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (n >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          const extra = victim ? { targetUserId: victim } as UnlockExtra : undefined;
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints, extra);
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) pushHint(`Head Hunter ${Math.min(n, next)}/${next} overtakes`);
      }

      // --- Track last_overtaken_by on victim (enables Uno Reverse detection) ---
      if (victim) {
        const victimUnoRow = getProg(victim, "uno_reverse");
        victimUnoRow.progress = {
          ...victimUnoRow.progress,
          last_overtaken_by: uid,
          last_overtaken_at: logCreatedAt,
        };
        markDirty(victim, "uno_reverse");
      }

      // --- Executioner (distinct victims) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("executioner")!;
        const row = getProg(uid, "executioner");
        const arr = [...((row.progress.victim_ids as string[] | undefined) ?? [])];
        if (victim && !arr.includes(victim)) {
          arr.push(victim);
          row.progress = { ...row.progress, victim_ids: arr };
          markDirty(uid, "executioner");
        }
        const n = arr.length;
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (n >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          const extra = victim ? { targetUserId: victim } as UnlockExtra : undefined;
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints, extra);
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) pushHint(`Executioner ${Math.min(n, next)}/${next} unique passes`);
      }

      // --- Nemesis (max lead while #1) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("nemesis")!;
        const row = getProg(uid, "nemesis");
        const prevMax = Number(row.progress.max_lead_gap ?? 0);
        const newMax = Math.max(prevMax, leadGap);
        if (rk.rankAfter === 1 && leadGap > 0) {
          row.progress = { ...row.progress, max_lead_gap: newMax };
          markDirty(uid, "nemesis");
        }
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (newMax >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) pushHint(`Nemesis best lead ${Math.min(newMax, next)}/${next} pts`);
      }

      // --- Last to First ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("last_to_first")!;
        const row = getProg(uid, "last_to_first");
        let n = Number(row.progress.ltf_count ?? 0);
        if (rk.memberCount >= 2 && rk.rankBefore === rk.memberCount && rk.rankAfter === 1) {
          n += 1;
          row.progress = { ...row.progress, ltf_count: n };
          markDirty(uid, "last_to_first");
        }
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (n >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
      }

      // --- From the Dead ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("from_the_dead")!;
        const row = getProg(uid, "from_the_dead");
        let n = Number(row.progress.ftd_count ?? 0);
        const bottomStart = Math.max(3, Math.ceil(rk.memberCount * 0.75));
        if (rk.memberCount >= 4 && rk.rankBefore >= bottomStart && rk.rankAfter <= 3) {
          n += 1;
          row.progress = { ...row.progress, ftd_count: n };
          markDirty(uid, "from_the_dead");
        }
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (n >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
      }

      // --- Uno Reverse (revenge overtake: they overtook you, now you overtake them) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("uno_reverse")!;
        const row = getProg(uid, "uno_reverse");
        const prevOvertakenBy = row.progress.last_overtaken_by as string | null;
        const prevOvertakenAt = row.progress.last_overtaken_at as string | null;
        const WINDOW_MS = 14 * 86400000; // 14-day revenge window
        const isReverse =
          victim != null &&
          prevOvertakenBy === victim &&
          prevOvertakenAt != null &&
          new Date(logCreatedAt).getTime() - new Date(prevOvertakenAt).getTime() < WINDOW_MS;
        if (isReverse) {
          let rc = Number(row.progress.reverse_count ?? 0) + 1;
          row.progress = { ...row.progress, reverse_count: rc };
          markDirty(uid, "uno_reverse");
          let targetTier = row.tier_reached;
          for (let ti = 0; ti < def.tiers.length; ti++) {
            if (rc >= def.tiers[ti].at) targetTier = ti + 1;
          }
          if (targetTier > row.tier_reached) {
            const extra = victim ? { targetUserId: victim } as UnlockExtra : undefined;
            for (let t = row.tier_reached + 1; t <= targetTier; t++) {
              tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints, extra);
            }
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        const rc = Number(row.progress.reverse_count ?? 0);
        if (next != null) pushHint(`Uno Reverse ${Math.min(rc, next)}/${next} revenge overtakes`);
      }

      // --- Clutch ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("clutch")!;
        const row = getProg(uid, "clutch");
        let n = Number(row.progress.clutch_count ?? 0);
        if (pointsEarned >= 40 && rk.rankBefore >= 4 && rk.rankAfter < rk.rankBefore) {
          n += 1;
          row.progress = { ...row.progress, clutch_count: n };
          markDirty(uid, "clutch");
        }
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (n >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
      }

      // --- Reclaim throne ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("reclaim_throne")!;
        const row = getProg(uid, "reclaim_throne");
        let n = Number(row.progress.reclaim_count ?? 0);
        if (rk.rankBefore === 2 && rk.rankAfter === 1) {
          n += 1;
          row.progress = { ...row.progress, reclaim_count: n };
          markDirty(uid, "reclaim_throne");
        }
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (n >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
      }

      // --- Tyrant (max lead while #1 — milestone unlock) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("tyrant")!;
        const row = getProg(uid, "tyrant");
        if (rk.rankAfter === 1) {
          const prevMax = Number(row.progress.tyrant_max_lead ?? 0);
          const newMax = Math.max(prevMax, leadGap);
          if (newMax > prevMax) {
            row.progress = { ...row.progress, tyrant_max_lead: newMax };
            markDirty(uid, "tyrant");
          }
          let targetTier = row.tier_reached;
          for (let ti = 0; ti < def.tiers.length; ti++) {
            if (newMax >= def.tiers[ti].at) targetTier = ti + 1;
          }
          if (targetTier > row.tier_reached) {
            for (let t = row.tier_reached + 1; t <= targetTier; t++) {
              tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
            }
          }
          const next = nextTierThreshold(def, row.tier_reached);
          if (next != null) pushHint(`Tyrant lead ${Math.min(newMax, next)}/${next} pts`);
        }
      }

      // --- No Contest (massive lead milestone) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("no_contest")!;
        const row = getProg(uid, "no_contest");
        if (rk.rankAfter === 1) {
          let targetTier = row.tier_reached;
          for (let ti = 0; ti < def.tiers.length; ti++) {
            if (leadGap >= def.tiers[ti].at) targetTier = ti + 1;
          }
          if (targetTier > row.tier_reached) {
            for (let t = row.tier_reached + 1; t <= targetTier; t++) {
              tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
            }
          }
          const next = nextTierThreshold(def, row.tier_reached);
          if (next != null) pushHint(`No Contest lead ${Math.min(leadGap, next)}/${next} pts`);
        }
      }

      // --- Monopoly ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("monopoly")!;
        const row = getProg(uid, "monopoly");
        row.tier_reached = Number(row.tier_reached ?? 0);
        const p = rk.sharePercent;
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (p >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          const start = row.tier_reached;
          for (let t = start + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) pushHint(`Monopoly ${Math.min(p, next)}% / ${next}% room share`);
      }

      // --- Monster / One Hit Wonder (best single-log score milestone) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("one_hit_wonder")!;
        const row = getProg(uid, "one_hit_wonder");
        const prevBest = Number(row.progress.best_single_log ?? 0);
        const newBest = Math.max(prevBest, pointsEarned);
        if (newBest > prevBest) {
          row.progress = { ...row.progress, best_single_log: newBest };
          markDirty(uid, "one_hit_wonder");
        }
        let targetTier = row.tier_reached;
        for (let ti = 0; ti < def.tiers.length; ti++) {
          if (newBest >= def.tiers[ti].at) targetTier = ti + 1;
        }
        if (targetTier > row.tier_reached) {
          for (let t = row.tier_reached + 1; t <= targetTier; t++) {
            tryUnlock(uid, def, t, def.tiers[t - 1].rewardPoints);
          }
        }
        const next = nextTierThreshold(def, row.tier_reached);
        if (next != null) pushHint(`Monster best log ${Math.min(Math.round(newBest), next)}/${next} pts`);
      }

      // --- Late Entry ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("late_entry")!;
        const row = getProg(uid, "late_entry");
        const ja = joinedAtByUser.get(uid);
        if (ja && row.tier_reached < 1) {
          const days = (new Date(logCreatedAt).getTime() - new Date(ja).getTime()) / 86400000;
          if (days <= 14 && rk.rankAfter <= 5) {
            tryUnlock(uid, def, 1, def.tiers[0].rewardPoints);
          }
        }
      }

      // --- Almost ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("almost")!;
        const row = getProg(uid, "almost");
        if (rk.rankAfter === 2 && gapSecond <= 10 && row.tier_reached < 1) {
          tryUnlock(uid, def, 1, def.tiers[0].rewardPoints);
        }
      }

      // --- Troll (tiny logs) ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("troll_tiny")!;
        const row = getProg(uid, "troll_tiny");
        if (trollTinyCount >= 3 && row.tier_reached < 1) {
          tryUnlock(uid, def, 1, def.tiers[0].rewardPoints);
        }
      }

      // --- Perfect Storm ---
      {
        const def = ACHIEVEMENT_BY_KEY.get("perfect_storm")!;
        const row = getProg(uid, "perfect_storm");
        const stormOk =
          victim != null &&
          rankJump >= 2 &&
          (prSessionCount ?? 0) >= 1 &&
          rk.rankAfter <= 2;
        if (stormOk && row.tier_reached < 1) {
          tryUnlock(uid, def, 1, def.tiers[0].rewardPoints);
        }
      }

      // --- Persist progress + bonuses + feed ---
      const bonusByUser = new Map<string, number>();
      for (const u of unlocks) {
        bonusByUser.set(u.user_id, (bonusByUser.get(u.user_id) ?? 0) + u.points);
      }

      // Always upsert when dirty. Do NOT compare to `progRows` for "changes": those rows are the
      // same object references as progressByKey entries, so tier/progress mutations look identical
      // to "orig" and we would skip the write forever (e.g. Monopoly II repeating every log).
      for (const row of progressByKey.values()) {
        const pk = `${row.user_id}::${row.achievement_key}`;
        if (!dirtyProgress.has(pk)) continue;

        const { error: upErr } = await sb.from("room_achievement_progress").upsert(
          {
            room_id: row.room_id,
            user_id: row.user_id,
            achievement_key: row.achievement_key,
            tier_reached: row.tier_reached,
            progress: row.progress,
            last_unlock_at: row.last_unlock_at,
            updated_at: nowIso,
          },
          { onConflict: "room_id,user_id,achievement_key" },
        );
        if (upErr) jsonLog("progress_upsert_warn", { message: upErr.message, key: row.achievement_key });
      }

      for (const [userId, pts] of bonusByUser) {
        if (pts <= 0) continue;
        const { error: bErr } = await sb.rpc("achievement_apply_bonus", {
          p_room_id: roomId,
          p_user_id: userId,
          p_points: pts,
        });
        if (bErr) jsonLog("bonus_error", { message: bErr.message, userId });
      }

      let newLastUnlockAt: string | null = null;
      let title = "Achievements";

      if (unlocks.length > 0) {
        newLastUnlockAt = nowIso;
        const actorUnlocks = unlocks.filter((u) => u.user_id === uid);
        title =
          actorUnlocks.length === unlocks.length
            ? `${unlocks.length} achievement${unlocks.length === 1 ? "" : "s"} unlocked`
            : `${unlocks.length} room achievement${unlocks.length === 1 ? "" : "s"}`;

        const payload = {
          v: 1,
          title,
          unlocks: unlocks.map((u) => ({
            user_id: u.user_id,
            key: u.key,
            tier: u.tier,
            line: u.line,
            meta: u.meta,
            points: u.points,
          })),
          actor_id: uid,
        };

        await sb.from("exercise_logs").insert({
          room_id: roomId,
          user_id: uid,
          exercise_id: null,
          exercise_name: `${ACH_PREFIX}${JSON.stringify(payload)}`,
          count: 0,
          weight: 0,
          points_earned: 0,
          reply_to_log_id: logId,
        });
      }

      jsonLog("ok", {
        ms: Math.round(performance.now() - wall),
        unlocks: unlocks.length,
        log_id: logId,
      });

      return new Response(
        JSON.stringify({
          ok: true,
          unlocks,
          progress_hints: hints,
          new_last_unlock_at: newLastUnlockAt,
          title,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    } catch (e) {
      await sb.from("achievement_processed_logs").delete().eq("log_id", logId);
      throw e;
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    jsonLog("error", { error: msg });
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
