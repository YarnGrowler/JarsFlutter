/**
 * Compact room narrative for process-ai-events (not raw JSON dumps).
 * Times use America/Chicago where noted (matches Flutter JarsTimezone).
 */

const CHICAGO = "America/Chicago";
const DIGEST_HOURS = 72;

export type ScoreMember = {
  user_id: string;
  username: string;
  total_score: number;
  daily_points: number;
  last_daily_reset: string | null;
  streak_current: number;
  streak_highest: number;
  streak_last_workout: string | null;
  rank: number;
};

export type RecentLogRow = {
  id: string;
  user_id: string;
  username: string;
  exercise_name: string;
  count: number;
  points_earned: number;
  created_at: string;
  count_unit: string | null;
};

/** YYYY-MM-DD in Chicago for an instant. */
export function chicagoYmd(iso: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: CHICAGO,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(iso));
}

export function formatChicagoDateTime(iso: string): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: CHICAGO,
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(new Date(iso));
}

/** 0–23 local Chicago hour for the instant. */
export function chicagoHour(iso: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: CHICAGO,
    hour: "numeric",
    hourCycle: "h23",
  }).formatToParts(new Date(iso));
  return parseInt(parts.find((p) => p.type === "hour")?.value ?? "0", 10);
}

function hoursAgo(iso: string, nowMs: number): number {
  return Math.round((nowMs - new Date(iso).getTime()) / 3600000);
}

function effectiveDailyForToday(
  lastDailyReset: string | null,
  dailyPoints: number,
  chicagoToday: string,
): number {
  if (!lastDailyReset) return 0;
  const d = String(lastDailyReset).slice(0, 10);
  if (d < chicagoToday) return 0;
  return dailyPoints;
}

function clampStr(s: string, max: number): string {
  const t = s.replace(/\s+/g, " ").trim();
  if (t.length <= max) return t;
  return t.slice(0, max - 1) + "…";
}

function parseAiPayload(rest: string): string {
  try {
    const j = JSON.parse(rest) as Record<string, unknown>;
    const text = j.text != null ? String(j.text) : "";
    const emoji = j.aiEmoji != null ? String(j.aiEmoji) : "";
    const mode = j.mode != null ? String(j.mode) : "";
    if (text) return clampStr(`JARS[${mode}] ${text}`, 140);
    if (emoji) return `JARS[${mode}] ${emoji}`;
    return `JARS[${mode}]`;
  } catch {
    return clampStr(rest, 100);
  }
}

/** Classify broadcast / AI lines into one human line for lore. */
function highlightFromExerciseName(
  username: string,
  exerciseName: string,
  points: number,
  createdAt: string,
): string | null {
  const t = formatChicagoDateTime(createdAt);
  if (exerciseName.startsWith("__OVERTAKE__|")) {
    return `[${t}] Overtake ${username}: ${clampStr(exerciseName.slice("__OVERTAKE__|".length), 100)}`;
  }
  if (exerciseName.startsWith("__RANKUP__|")) {
    return `[${t}] Rank up ${username}: ${clampStr(exerciseName.slice("__RANKUP__|".length), 100)}`;
  }
  if (exerciseName.startsWith("__STREAK__|")) {
    return `[${t}] Streak ${username}: ${clampStr(exerciseName.slice("__STREAK__|".length), 100)}`;
  }
  if (exerciseName.startsWith("__DEAD__|")) {
    return `[${t}] Dead streak ${username}: ${clampStr(exerciseName.slice("__DEAD__|".length), 100)}`;
  }
  if (exerciseName.startsWith("__PR__|")) {
    return `[${t}] PR ${username}: ${clampStr(exerciseName.slice("__PR__|".length), 100)}`;
  }
  if (exerciseName.startsWith("__FIRSTLOG__|")) {
    return `[${t}] First log ${username}: ${clampStr(exerciseName.slice("__FIRSTLOG__|".length), 100)}`;
  }
  if (exerciseName.startsWith("__CLOSEGAP__|")) {
    return `[${t}] Close gap: ${clampStr(exerciseName.slice("__CLOSEGAP__|".length), 100)}`;
  }
  if (exerciseName.startsWith("__AI__|")) {
    return `[${t}] ${parseAiPayload(exerciseName.slice("__AI__|".length))}`;
  }
  if (exerciseName.startsWith("__WAKE__|") || exerciseName.startsWith("__JOIN__|") || exerciseName.startsWith("__KICK__|")) {
    return `[${t}] Room event: ${exerciseName.split("|")[0]?.replace(/^__/, "") ?? "?"}`;
  }
  return null;
}

type UserAgg = {
  logs: number;
  pts: number;
  exercises: Map<string, number>;
  hours: number[];
  lastAt: string;
};

function modalChicagoHour(hours: number[]): number {
  if (!hours.length) return -1;
  const m = new Map<number, number>();
  for (const h of hours) m.set(h, (m.get(h) ?? 0) + 1);
  let bestH = hours[0]!;
  let bestC = 0;
  for (const [h, c] of m) {
    if (c > bestC) {
      bestC = c;
      bestH = h;
    }
  }
  return bestH;
}

function volumeLabel(count: number, unitRaw: string | null): string {
  const u = (unitRaw ?? "reps").toLowerCase();
  if (u === "seconds") {
    const s = Math.floor(Math.max(0, count));
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    const r = s % 60;
    return r === 0 ? `${m}m` : `${m}m${r}s`;
  }
  if (u === "minutes") return `${count}m`;
  return `${count}×`;
}

/**
 * Multi-section narrative: room meta, rank move, everyone’s scores+streaks, lore from feed, per-user digest.
 */
export function buildRichNarrativeContext(input: {
  roomName: string;
  roomCreatedAt: string;
  nowIso: string;
  triggerLogIso: string;
  actorUsername: string;
  rankBefore: number;
  rankAfter: number;
  pointsAdded: number;
  streakMin: number;
  events: Array<{ key: string; payload: Record<string, unknown> }>;
  members: ScoreMember[];
  recentLogs: RecentLogRow[];
  spamSessionDetail: string | null;
}): string {
  const nowMs = Date.now();
  const chicagoToday = chicagoYmd(input.nowIso);
  const roomAgeDays = Math.max(
    0,
    Math.floor((nowMs - new Date(input.roomCreatedAt).getTime()) / 86400000),
  );

  const lines: string[] = [];

  lines.push("=== ROOM ===");
  lines.push(
    `name: ${input.roomName} | room_age_days: ${roomAgeDays} | now_chicago: ${formatChicagoDateTime(input.nowIso)}`,
  );
  lines.push(
    `trigger_log_chicago: ${formatChicagoDateTime(input.triggerLogIso)} (hour ${chicagoHour(input.triggerLogIso)} CT)`,
  );

  lines.push("");
  lines.push("=== THIS MOMENT ===");
  lines.push(
    `actor: ${input.actorUsername} | rank_before→after: ${input.rankBefore}→${input.rankAfter} | delta: ${input.rankBefore - input.rankAfter} | pts_this_log: ${input.pointsAdded}`,
  );
  if (input.events.length > 0) {
    lines.push(
      `events_firing: ${input.events.map((e) => `${e.key}${Object.keys(e.payload).length ? `(${JSON.stringify(e.payload)})` : ""}`).join(" · ")}`,
    );
  }
  if (input.spamSessionDetail) {
    lines.push(`spam_session: ${input.spamSessionDetail}`);
  }

  lines.push("");
  lines.push("=== EVERYONE (rank, pts, streak, today vs minimum) ===");
  for (const m of input.members) {
    const eff = effectiveDailyForToday(m.last_daily_reset, m.daily_points, chicagoToday);
    const streakDay = m.streak_last_workout
      ? String(m.streak_last_workout).slice(0, 10)
      : "none";
    const todayOk = eff >= input.streakMin;
    const flag = m.total_score < 1 && m.streak_current < 1 ? " [quiet/never_on_board]" : "";
    lines.push(
      `#${m.rank} ${m.username}: ${Math.round(m.total_score)}pts | streak_current ${m.streak_current} (best ${m.streak_highest}) | last_streak_day ${streakDay} | today_pts ${Math.round(eff)}/${input.streakMin}${todayOk ? " OK" : " BELOW"}${flag}`,
    );
  }

  const cutoffMs = nowMs - DIGEST_HOURS * 3600000;
  const inDigest = input.recentLogs.filter((l) => new Date(l.created_at).getTime() >= cutoffMs);

  lines.push("");
  lines.push(`=== FEED LORE (from last ${input.recentLogs.length} logs, broadcasts & JARS) ===`);
  const highlights: string[] = [];
  for (const log of input.recentLogs) {
    const h = highlightFromExerciseName(log.username, log.exercise_name, log.points_earned, log.created_at);
    if (h) highlights.push(h);
  }
  if (highlights.length === 0) {
    lines.push("(no broadcast/JARS lines in window)");
  } else {
    for (const h of highlights.slice(0, 25)) {
      lines.push(`- ${h}`);
    }
    if (highlights.length > 25) {
      lines.push(`- … +${highlights.length - 25} more broadcast/JARS lines`);
    }
  }

  lines.push("");
  lines.push(`=== PER USER DIGEST (~${DIGEST_H}h within those logs) ===`);
  const byUser = new Map<string, UserAgg>();
  for (const log of inDigest) {
    if (log.exercise_name.startsWith("__")) continue;
    const u = log.username || "?";
    let agg = byUser.get(u);
    if (!agg) {
      agg = {
        logs: 0,
        pts: 0,
        exercises: new Map(),
        hours: [],
        lastAt: log.created_at,
      };
      byUser.set(u, agg);
    }
    agg.logs += 1;
    agg.pts += Number(log.points_earned ?? 0);
    const ex = log.exercise_name.slice(0, 40);
    agg.exercises.set(ex, (agg.exercises.get(ex) ?? 0) + 1);
    agg.hours.push(chicagoHour(log.created_at));
    if (new Date(log.created_at) > new Date(agg.lastAt)) agg.lastAt = log.created_at;
  }

  for (const [uname, agg] of [...byUser.entries()].sort((a, b) => b[1].pts - a[1].pts)) {
    const topEx = [...agg.exercises.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4);
    const exStr = topEx.map(([n, c]) => `${clampStr(n, 22)}×${c}`).join(", ");
    const modeHour = modalChicagoHour(agg.hours);
    const ha = hoursAgo(agg.lastAt, nowMs);
    lines.push(
      `${uname}: ${agg.logs} logs, ${Math.round(agg.pts)}pts | exercises: ${exStr || "—"} | typical_CT_hour~${modeHour >= 0 ? modeHour : "?"} | last ${ha}h ago`,
    );
  }

  const ghosts = input.members.filter((m) => !byUser.has(m.username) && m.total_score < 1);
  if (ghosts.length > 0) {
    lines.push(
      `no_logs_in_${DIGEST_HOURS}h_window (0pts on board): ${ghosts.map((g) => g.username).join(", ")}`,
    );
  }

  lines.push("");
  lines.push("=== CHRONO (newest first, real workouts only) ===");
  let chrono = 0;
  for (const log of input.recentLogs) {
    if (log.exercise_name.startsWith("__")) continue;
    if (chrono >= 18) break;
    const vol = volumeLabel(log.count, log.count_unit);
    lines.push(
      `- ${formatChicagoDateTime(log.created_at)} ${log.username} ${Math.round(log.points_earned)}pts ${vol} ${clampStr(log.exercise_name, 36)}`,
    );
    chrono++;
  }
  if (chrono === 0) lines.push("(only broadcast rows in sample)");

  return lines.join("\n");
}
