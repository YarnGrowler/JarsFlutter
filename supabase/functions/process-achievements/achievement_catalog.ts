export type TierDef = {
  at: number;
  rewardPoints: number;
  roman: string;
  goal: string;
};

export type CatalogEntry = {
  key: string;
  displayName: string;
  family: string;
  emoji: string;
  description: string;
  wave: number;
  tiers: TierDef[];
};

export const ALL_ACHIEVEMENTS: CatalogEntry[] = [
  // ── Wave 1 ────────────────────────────────────────────────────────
  {
    key: "night_creature",
    displayName: "Night Creature",
    family: "habit",
    emoji: "🦉",
    description: "Log workouts between 11pm–5am Chicago.",
    wave: 1,
    tiers: [
      { at: 3,  rewardPoints: 15, roman: "I",   goal: "3 late-night logs" },
      { at: 7,  rewardPoints: 35, roman: "II",  goal: "7 late-night logs" },
      { at: 15, rewardPoints: 70, roman: "III", goal: "15 late-night logs" },
    ],
  },
  {
    key: "spam_demon",
    displayName: "Spam Demon",
    family: "volume",
    emoji: "👹",
    description: "Many real logs within 5 minutes.",
    wave: 1,
    tiers: [
      { at: 3, rewardPoints: 12, roman: "I",   goal: "3+ logs in 5m" },
      { at: 5, rewardPoints: 28, roman: "II",  goal: "5+ logs in 5m" },
      { at: 8, rewardPoints: 50, roman: "III", goal: "8+ logs in 5m" },
    ],
  },
  {
    key: "breaker",
    displayName: "Breaker",
    family: "prs",
    emoji: "💥",
    description: "PR broadcast cards in this room.",
    wave: 1,
    tiers: [
      { at: 1,  rewardPoints: 12, roman: "I",   goal: "1 PR card" },
      { at: 5,  rewardPoints: 30, roman: "II",  goal: "5 PR cards" },
      { at: 15, rewardPoints: 60, roman: "III", goal: "15 PR cards" },
    ],
  },
  {
    key: "exploded",
    displayName: "Exploded",
    family: "session",
    emoji: "🧨",
    description: "Session points inside a 20-minute window.",
    wave: 1,
    tiers: [
      { at: 100,  rewardPoints: 20,  roman: "I",   goal: "100+ pts in 20m" },
      { at: 250,  rewardPoints: 50,  roman: "II",  goal: "250+ pts in 20m" },
      { at: 500,  rewardPoints: 120, roman: "III", goal: "500+ pts in 20m" },
      { at: 1000, rewardPoints: 280, roman: "IV",  goal: "1000+ pts in 20m" },
    ],
  },
  {
    key: "engine",
    displayName: "Engine",
    family: "streak",
    emoji: "⚙️",
    description: "Current streak length.",
    wave: 1,
    tiers: [
      { at: 3,  rewardPoints: 18, roman: "I",   goal: "3-day streak" },
      { at: 7,  rewardPoints: 40, roman: "II",  goal: "7-day streak" },
      { at: 30, rewardPoints: 90, roman: "III", goal: "30-day streak" },
    ],
  },
  {
    key: "machine",
    displayName: "Machine",
    family: "streak",
    emoji: "🤖",
    description: "Long streak milestones.",
    wave: 1,
    tiers: [
      { at: 100, rewardPoints: 140, roman: "I",   goal: "100-day streak" },
      { at: 200, rewardPoints: 280, roman: "II",  goal: "200-day streak" },
      { at: 365, rewardPoints: 550, roman: "III", goal: "365-day streak" },
    ],
  },
  {
    key: "warmup",
    displayName: "Warmup",
    family: "comeback",
    emoji: "🌅",
    description: "Yesterday you logged only 1–5 pts; today's first log.",
    wave: 1,
    tiers: [{ at: 1, rewardPoints: 18, roman: "I", goal: "Micro-day yesterday, log today" }],
  },
  {
    key: "witness",
    displayName: "Witness",
    family: "room",
    emoji: "👁️",
    description: "Break a long stretch of room silence.",
    wave: 1,
    tiers: [
      { at: 1, rewardPoints: 18, roman: "I",  goal: "Break 8+ hours of silence" },
      { at: 1, rewardPoints: 45, roman: "II", goal: "Break 24+ hours of silence" },
    ],
  },
  {
    key: "ghost",
    displayName: "Ghost",
    family: "idle",
    emoji: "👻",
    description: "Stayed quiet while others logged (awarded when someone else logs).",
    wave: 1,
    tiers: [
      { at: 3, rewardPoints: 18, roman: "I",  goal: "3+ days without logging" },
      { at: 7, rewardPoints: 45, roman: "II", goal: "7+ days without logging" },
    ],
  },

  // ── Rivalry / comeback / dominance (Wave 2) ──────────────────────
  {
    key: "head_hunter",
    displayName: "Head Hunter",
    family: "rivalry",
    emoji: "🎯",
    description: "Times you passed someone on the leaderboard.",
    wave: 2,
    tiers: [
      { at: 3,  rewardPoints: 28,  roman: "I",   goal: "3 overtakes" },
      { at: 10, rewardPoints: 60,  roman: "II",  goal: "10 overtakes" },
      { at: 25, rewardPoints: 120, roman: "III", goal: "25 overtakes" },
      { at: 50, rewardPoints: 240, roman: "IV",  goal: "50 overtakes" },
    ],
  },
  {
    key: "executioner",
    displayName: "Executioner",
    family: "rivalry",
    emoji: "⚔️",
    description: "Different people you've overtaken at least once.",
    wave: 2,
    tiers: [
      { at: 2,  rewardPoints: 22,  roman: "I",   goal: "2 unique victims" },
      { at: 5,  rewardPoints: 50,  roman: "II",  goal: "5 unique victims" },
      { at: 12, rewardPoints: 100, roman: "III", goal: "12 unique victims" },
    ],
  },
  {
    key: "nemesis",
    displayName: "Nemesis",
    family: "rivalry",
    emoji: "😈",
    description: "Biggest point lead over 2nd while you're #1.",
    wave: 2,
    tiers: [
      { at: 250,  rewardPoints: 45,  roman: "I",   goal: "250 pt lead while #1" },
      { at: 500,  rewardPoints: 100, roman: "II",  goal: "500 pt lead" },
      { at: 1000, rewardPoints: 220, roman: "III", goal: "1000 pt lead" },
      { at: 2500, rewardPoints: 480, roman: "IV",  goal: "2500 pt lead" },
    ],
  },
  {
    key: "uno_reverse",
    displayName: "Uno Reverse",
    family: "rivalry",
    emoji: "🔄",
    description: "Someone overtook you, then you overtook them back.",
    wave: 2,
    tiers: [
      { at: 1,  rewardPoints: 28, roman: "I",   goal: "1 revenge overtake" },
      { at: 5,  rewardPoints: 70, roman: "II",  goal: "5 revenge overtakes" },
      { at: 15, rewardPoints: 140, roman: "III", goal: "15 revenge overtakes" },
    ],
  },
  {
    key: "tyrant",
    displayName: "Tyrant",
    family: "rivalry",
    emoji: "🏛️",
    description: "Lead by a large margin while ranked #1.",
    wave: 2,
    tiers: [
      { at: 100, rewardPoints: 55,  roman: "I",   goal: "100 pt lead while #1" },
      { at: 200, rewardPoints: 130, roman: "II",  goal: "200 pt lead" },
      { at: 400, rewardPoints: 240, roman: "III", goal: "400 pt lead" },
    ],
  },
  {
    key: "last_to_first",
    displayName: "Last to First",
    family: "comeback",
    emoji: "🔥",
    description: "Jump from last place to #1 in one log.",
    wave: 2,
    tiers: [
      { at: 1,  rewardPoints: 55,  roman: "I",   goal: "Do it once" },
      { at: 3,  rewardPoints: 130, roman: "II",  goal: "3 times" },
      { at: 5,  rewardPoints: 220, roman: "III", goal: "5 times" },
      { at: 10, rewardPoints: 450, roman: "IV",  goal: "10 times" },
    ],
  },
  {
    key: "from_the_dead",
    displayName: "From the Dead",
    family: "comeback",
    emoji: "🧟",
    description: "Climb from the bottom quarter of the board into the top 3.",
    wave: 2,
    tiers: [
      { at: 1, rewardPoints: 40, roman: "I",  goal: "One qualifying climb" },
      { at: 5, rewardPoints: 90, roman: "II", goal: "5 climbs" },
    ],
  },
  {
    key: "clutch",
    displayName: "Clutch",
    family: "comeback",
    emoji: "🎬",
    description: "Big points (40+) from deep in the pack while rising.",
    wave: 2,
    tiers: [
      { at: 1, rewardPoints: 28, roman: "I",  goal: "40+ pts while rank ≥4" },
      { at: 8, rewardPoints: 70, roman: "II", goal: "8 clutch logs" },
    ],
  },
  {
    key: "reclaim_throne",
    displayName: "Reclaim",
    family: "comeback",
    emoji: "👑",
    description: "Take #1 from #2 in one log.",
    wave: 2,
    tiers: [
      { at: 1, rewardPoints: 40, roman: "I",  goal: "Once" },
      { at: 5, rewardPoints: 90, roman: "II", goal: "5 times" },
    ],
  },
  {
    key: "no_contest",
    displayName: "No Contest",
    family: "dominance",
    emoji: "🥱",
    description: "Massive lead while ranked #1.",
    wave: 2,
    tiers: [
      { at: 5000,  rewardPoints: 450, roman: "I",  goal: "5000 pt lead" },
      { at: 10000, rewardPoints: 1000, roman: "II", goal: "10000 pt lead" },
    ],
  },
  {
    key: "monopoly",
    displayName: "Monopoly",
    family: "dominance",
    emoji: "💰",
    description: "Your share of all room points.",
    wave: 2,
    tiers: [
      { at: 25, rewardPoints: 28,  roman: "I",   goal: "25%+ of room pts" },
      { at: 35, rewardPoints: 65,  roman: "II",  goal: "35%+ of room pts" },
      { at: 50, rewardPoints: 140, roman: "III", goal: "50%+ of room pts" },
      { at: 65, rewardPoints: 280, roman: "IV",  goal: "65%+ of room pts" },
    ],
  },
  {
    key: "one_hit_wonder",
    displayName: "Monster",
    family: "behavior",
    emoji: "🎸",
    description: "Best single-log score ever in this room.",
    wave: 2,
    tiers: [
      { at: 100, rewardPoints: 28,  roman: "I",   goal: "Best log ≥ 100 pts" },
      { at: 175, rewardPoints: 65,  roman: "II",  goal: "Best log ≥ 175 pts" },
      { at: 250, rewardPoints: 120, roman: "III", goal: "Best log ≥ 250 pts" },
      { at: 400, rewardPoints: 240, roman: "IV",  goal: "Best log ≥ 400 pts" },
    ],
  },
  {
    key: "late_entry",
    displayName: "Late Entry",
    family: "behavior",
    emoji: "🚪",
    description: "Joined the room within 14 days and hit top 5.",
    wave: 2,
    tiers: [{ at: 1, rewardPoints: 28, roman: "I", goal: "Top 5 within first 14 days" }],
  },
  {
    key: "almost",
    displayName: "Almost",
    family: "behavior",
    emoji: "😬",
    description: "Hold #2 within 10 pts of #1.",
    wave: 2,
    tiers: [{ at: 1, rewardPoints: 15, roman: "I", goal: "#2 within 10 pts of leader" }],
  },
  {
    key: "troll_tiny",
    displayName: "Troll",
    family: "behavior",
    emoji: "🧊",
    description: "Three micro-logs (≤8 pts) within 30 minutes.",
    wave: 2,
    tiers: [{ at: 1, rewardPoints: 15, roman: "I", goal: "3 tiny logs in 30m" }],
  },

  // ── Combo (Wave 3) ────────────────────────────────────────────────
  {
    key: "perfect_storm",
    displayName: "Perfect Storm",
    family: "combo",
    emoji: "🌩️",
    description: "Overtake someone, jump 2+ ranks, PR in your 20m window — same log.",
    wave: 3,
    tiers: [{ at: 1, rewardPoints: 120, roman: "I", goal: "Overtake + 2-rank jump + PR in window" }],
  },
];

export const ACHIEVEMENT_BY_KEY = new Map<string, CatalogEntry>(
  ALL_ACHIEVEMENTS.map((a) => [a.key, a]),
);
