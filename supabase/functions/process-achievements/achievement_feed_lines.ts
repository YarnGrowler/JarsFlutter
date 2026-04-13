import type { CatalogEntry } from "./achievement_catalog.ts";

/** Punchy one-liners for the room feed (${user} ${target} ${points}). */
const FEED_QUIPS: Record<string, string[]> = {
  head_hunter: [
    "${user} keeps hunting ${target} like this is personal",
    "${target} might want to respond at some point",
  ],
  executioner: [
    "${target} has not recovered since ${user} passed them",
    "${user} didn’t just pass ${target}, they ended it",
  ],
  nemesis: [
    "${user} and ${target} are not competing anymore, this is a war",
    "#1 just keeps changing hands between the same two people",
  ],
  uno_reverse: [
    "${user} really said give that back",
    "took #1 back like it was borrowed",
  ],
  last_to_first: [
    "${user} just skipped the entire leaderboard",
    "that wasn’t climbing that was teleporting",
  ],
  from_the_dead: [
    "${user} went from last to #1 in one day what just happened",
    "that’s not a comeback that’s a takeover",
  ],
  clutch: [
    "${user} saved the streak at the last second",
    "that was desperation and it worked",
  ],
  reclaim_throne: [
    "${user} snatched #1 back",
    "crown’s back where it belongs",
  ],
  tyrant: [
    "${user} is not competing, they’re dominating",
    "this lead is getting out of hand",
  ],
  monopoly: [
    "${user} basically owns this room",
    "this is not a shared leaderboard anymore",
  ],
  no_contest: [
    "no one is even close to ${user}",
    "this isn’t competition anymore",
  ],
  night_creature: [
    "${user} only shows up at night",
    "late night sessions are becoming a pattern",
  ],
  ghost: [
    "${user} has been here… doing nothing",
    "still observing, still 0",
  ],
  one_hit_wonder: [
    "${user} logged once and that was enough",
    "one move, day over",
  ],
  spam_demon: [
    "${user} is spamming logs right now",
    "this is getting out of control",
  ],
  breaker: [
    "${user} keeps breaking their own records",
    "another PR, this is getting consistent",
  ],
  exploded: [
    "${user} just dropped ${points} pts in one session",
    "that was a massive session",
  ],
  engine: [
    "${user} is building a streak",
    "consistency starting to show",
  ],
  machine: [
    "${user} has been doing this every day",
    "this is discipline now",
  ],
  witness: [
    "${user} has watched everything and done nothing",
    "still observing",
  ],
  warmup: [
    "${user} logged… technically",
    "that barely counts",
  ],
  late_entry: [
    "${user} showing up after everyone else",
    "late again",
  ],
  almost: [
    "${user} keeps getting close but not taking it",
    "always right there",
  ],
  troll_tiny: [
    "${user} is trolling the feed with baby logs",
    "micro-logs, maximum chaos",
  ],
  scraps: [
    "${user} is stacking baby logs like it’s a strategy",
    "small reps, still counting",
  ],
  rear_guard: [
    "${user} keeps logging from the back of the pack",
    "the leaderboard bottom is still active",
  ],
  penny_stack: [
    "${user} is building points one small log at a time",
    "pennies add up eventually",
  ],
  perfect_storm: [
    "${user} just robbed the leaderboard",
    "everything just changed",
  ],
};

function tierMetaLine(def: CatalogEntry, tierIdx1: number, pts: number): string {
  const t = def.tiers[tierIdx1 - 1];
  const roman = t?.roman ?? String(tierIdx1);
  return `${def.displayName} ${roman} · +${pts} pts`;
}

export function buildUnlockFeed(
  def: CatalogEntry,
  tierIdx1: number,
  pts: number,
  userId: string,
  displayName: (id: string) => string,
  extra?: { targetUserId?: string; sessionPts?: number },
): { feed: string; meta: string } {
  const meta = tierMetaLine(def, tierIdx1, pts);
  const quips = FEED_QUIPS[def.key];
  const u = displayName(userId);
  const t = extra?.targetUserId ? displayName(extra.targetUserId) : "someone";
  const points =
    extra?.sessionPts != null ? String(Math.round(extra.sessionPts)) : "";
  if (quips && quips.length > 0) {
    const raw = quips[Math.floor(Math.random() * quips.length)]!;
    const feed = raw
      .replace(/\$\{user\}/g, u)
      .replace(/\$\{target\}/g, t)
      .replace(/\$\{points\}/g, points);
    return { feed, meta };
  }
  return { feed: meta, meta };
}
