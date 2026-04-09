import 'package:flutter/foundation.dart';

@immutable
class AchievementTierDef {
  final int at;
  final int rewardPoints;
  final String roman;
  final String goal;

  const AchievementTierDef({
    required this.at,
    required this.rewardPoints,
    required this.roman,
    required this.goal,
  });
}

@immutable
class AchievementCatalogEntry {
  final String key;
  final String displayName;
  final String family;
  final String emoji;
  final String description;
  final int wave;
  final List<AchievementTierDef> tiers;

  const AchievementCatalogEntry({
    required this.key,
    required this.displayName,
    required this.family,
    required this.emoji,
    required this.description,
    required this.wave,
    required this.tiers,
  });
}

const List<AchievementCatalogEntry> kAchievementCatalog = [
  // ── Wave 1 ────────────────────────────────────────────────────────
  AchievementCatalogEntry(
    key: 'night_creature',
    displayName: 'Night Creature',
    family: 'habit',
    emoji: '🦉',
    description: 'Log workouts between 11pm–5am.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 3,  rewardPoints: 15, roman: 'I',   goal: '3 late-night logs'),
      AchievementTierDef(at: 7,  rewardPoints: 35, roman: 'II',  goal: '7 late-night logs'),
      AchievementTierDef(at: 15, rewardPoints: 70, roman: 'III', goal: '15 late-night logs'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'spam_demon',
    displayName: 'Spam Demon',
    family: 'volume',
    emoji: '👹',
    description: 'Many real logs within 5 minutes.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 3, rewardPoints: 12, roman: 'I',   goal: '3+ logs in 5m'),
      AchievementTierDef(at: 5, rewardPoints: 28, roman: 'II',  goal: '5+ logs in 5m'),
      AchievementTierDef(at: 8, rewardPoints: 50, roman: 'III', goal: '8+ logs in 5m'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'breaker',
    displayName: 'Breaker',
    family: 'prs',
    emoji: '💥',
    description: 'PR broadcast cards in this room.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 1,  rewardPoints: 12, roman: 'I',   goal: '1 PR card'),
      AchievementTierDef(at: 5,  rewardPoints: 30, roman: 'II',  goal: '5 PR cards'),
      AchievementTierDef(at: 15, rewardPoints: 60, roman: 'III', goal: '15 PR cards'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'exploded',
    displayName: 'Exploded',
    family: 'session',
    emoji: '🧨',
    description: 'Session points inside a 20-minute window.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 100,  rewardPoints: 20,  roman: 'I',   goal: '100+ pts in 20m'),
      AchievementTierDef(at: 250,  rewardPoints: 50,  roman: 'II',  goal: '250+ pts in 20m'),
      AchievementTierDef(at: 500,  rewardPoints: 120, roman: 'III', goal: '500+ pts in 20m'),
      AchievementTierDef(at: 1000, rewardPoints: 280, roman: 'IV',  goal: '1000+ pts in 20m'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'engine',
    displayName: 'Engine',
    family: 'streak',
    emoji: '⚙️',
    description: 'Current streak length.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 3,  rewardPoints: 18, roman: 'I',   goal: '3-day streak'),
      AchievementTierDef(at: 7,  rewardPoints: 40, roman: 'II',  goal: '7-day streak'),
      AchievementTierDef(at: 30, rewardPoints: 90, roman: 'III', goal: '30-day streak'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'machine',
    displayName: 'Machine',
    family: 'streak',
    emoji: '🤖',
    description: 'Long streak milestones.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 100, rewardPoints: 140, roman: 'I',   goal: '100-day streak'),
      AchievementTierDef(at: 200, rewardPoints: 280, roman: 'II',  goal: '200-day streak'),
      AchievementTierDef(at: 365, rewardPoints: 550, roman: 'III', goal: '365-day streak'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'warmup',
    displayName: 'Warmup',
    family: 'comeback',
    emoji: '🌅',
    description: 'Yesterday only 1–5 pts; today you showed up.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 18, roman: 'I', goal: 'Micro-day yesterday, log today'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'witness',
    displayName: 'Witness',
    family: 'room',
    emoji: '👁️',
    description: 'Break a long stretch of room silence.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 18, roman: 'I',  goal: 'Break 8+ hours of silence'),
      AchievementTierDef(at: 1, rewardPoints: 45, roman: 'II', goal: 'Break 24+ hours of silence'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'ghost',
    displayName: 'Ghost',
    family: 'idle',
    emoji: '👻',
    description: 'Stayed quiet while others logged.',
    wave: 1,
    tiers: [
      AchievementTierDef(at: 3, rewardPoints: 18, roman: 'I',  goal: '3+ days without logging'),
      AchievementTierDef(at: 7, rewardPoints: 45, roman: 'II', goal: '7+ days without logging'),
    ],
  ),

  // ── Wave 2 ────────────────────────────────────────────────────────
  AchievementCatalogEntry(
    key: 'head_hunter',
    displayName: 'Head Hunter',
    family: 'rivalry',
    emoji: '🎯',
    description: 'Times you passed someone on the leaderboard.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 3,  rewardPoints: 28,  roman: 'I',   goal: '3 overtakes'),
      AchievementTierDef(at: 10, rewardPoints: 60,  roman: 'II',  goal: '10 overtakes'),
      AchievementTierDef(at: 25, rewardPoints: 120, roman: 'III', goal: '25 overtakes'),
      AchievementTierDef(at: 50, rewardPoints: 240, roman: 'IV',  goal: '50 overtakes'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'executioner',
    displayName: 'Executioner',
    family: 'rivalry',
    emoji: '⚔️',
    description: 'Different people you\'ve overtaken at least once.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 2,  rewardPoints: 22,  roman: 'I',   goal: '2 unique victims'),
      AchievementTierDef(at: 5,  rewardPoints: 50,  roman: 'II',  goal: '5 unique victims'),
      AchievementTierDef(at: 12, rewardPoints: 100, roman: 'III', goal: '12 unique victims'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'nemesis',
    displayName: 'Nemesis',
    family: 'rivalry',
    emoji: '😈',
    description: 'Biggest point lead over 2nd while you\'re #1.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 250,  rewardPoints: 45,  roman: 'I',   goal: '250 pt lead while #1'),
      AchievementTierDef(at: 500,  rewardPoints: 100, roman: 'II',  goal: '500 pt lead'),
      AchievementTierDef(at: 1000, rewardPoints: 220, roman: 'III', goal: '1000 pt lead'),
      AchievementTierDef(at: 2500, rewardPoints: 480, roman: 'IV',  goal: '2500 pt lead'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'uno_reverse',
    displayName: 'Uno Reverse',
    family: 'rivalry',
    emoji: '🔄',
    description: 'Someone overtook you, then you overtook them back.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 1,  rewardPoints: 28, roman: 'I',   goal: '1 revenge overtake'),
      AchievementTierDef(at: 5,  rewardPoints: 70, roman: 'II',  goal: '5 revenge overtakes'),
      AchievementTierDef(at: 15, rewardPoints: 140, roman: 'III', goal: '15 revenge overtakes'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'tyrant',
    displayName: 'Tyrant',
    family: 'rivalry',
    emoji: '🏛️',
    description: 'Lead by a large margin while ranked #1.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 100, rewardPoints: 55,  roman: 'I',   goal: '100 pt lead while #1'),
      AchievementTierDef(at: 200, rewardPoints: 130, roman: 'II',  goal: '200 pt lead'),
      AchievementTierDef(at: 400, rewardPoints: 240, roman: 'III', goal: '400 pt lead'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'last_to_first',
    displayName: 'Last to First',
    family: 'comeback',
    emoji: '🔥',
    description: 'Jump from last place to #1 in one log.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 1,  rewardPoints: 55,  roman: 'I',   goal: 'Do it once'),
      AchievementTierDef(at: 3,  rewardPoints: 130, roman: 'II',  goal: '3 times'),
      AchievementTierDef(at: 5,  rewardPoints: 220, roman: 'III', goal: '5 times'),
      AchievementTierDef(at: 10, rewardPoints: 450, roman: 'IV',  goal: '10 times'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'from_the_dead',
    displayName: 'From the Dead',
    family: 'comeback',
    emoji: '🧟',
    description: 'Climb from the bottom quarter into the top 3.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 40, roman: 'I',  goal: 'One qualifying climb'),
      AchievementTierDef(at: 5, rewardPoints: 90, roman: 'II', goal: '5 climbs'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'clutch',
    displayName: 'Clutch',
    family: 'comeback',
    emoji: '🎬',
    description: 'Big points (40+) from deep in the pack while rising.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 28, roman: 'I',  goal: '40+ pts while rank ≥4'),
      AchievementTierDef(at: 8, rewardPoints: 70, roman: 'II', goal: '8 clutch logs'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'reclaim_throne',
    displayName: 'Reclaim',
    family: 'comeback',
    emoji: '👑',
    description: 'Take #1 from #2 in one log.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 40, roman: 'I',  goal: 'Once'),
      AchievementTierDef(at: 5, rewardPoints: 90, roman: 'II', goal: '5 times'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'no_contest',
    displayName: 'No Contest',
    family: 'dominance',
    emoji: '🥱',
    description: 'Massive lead while ranked #1.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 5000,  rewardPoints: 450, roman: 'I',  goal: '5000 pt lead'),
      AchievementTierDef(at: 10000, rewardPoints: 1000, roman: 'II', goal: '10000 pt lead'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'monopoly',
    displayName: 'Monopoly',
    family: 'dominance',
    emoji: '💰',
    description: 'Your share of all room points.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 25, rewardPoints: 28,  roman: 'I',   goal: '25%+ of room pts'),
      AchievementTierDef(at: 35, rewardPoints: 65,  roman: 'II',  goal: '35%+ of room pts'),
      AchievementTierDef(at: 50, rewardPoints: 140, roman: 'III', goal: '50%+ of room pts'),
      AchievementTierDef(at: 65, rewardPoints: 280, roman: 'IV',  goal: '65%+ of room pts'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'one_hit_wonder',
    displayName: 'Monster',
    family: 'behavior',
    emoji: '🎸',
    description: 'Best single-log score ever in this room.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 100, rewardPoints: 28,  roman: 'I',   goal: 'Best log ≥ 100 pts'),
      AchievementTierDef(at: 175, rewardPoints: 65,  roman: 'II',  goal: 'Best log ≥ 175 pts'),
      AchievementTierDef(at: 250, rewardPoints: 120, roman: 'III', goal: 'Best log ≥ 250 pts'),
      AchievementTierDef(at: 400, rewardPoints: 240, roman: 'IV',  goal: 'Best log ≥ 400 pts'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'late_entry',
    displayName: 'Late Entry',
    family: 'behavior',
    emoji: '🚪',
    description: 'Joined within 14 days and hit top 5.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 28, roman: 'I', goal: 'Top 5 within first 14 days'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'almost',
    displayName: 'Almost',
    family: 'behavior',
    emoji: '😬',
    description: 'Hold #2 within 10 pts of #1.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 15, roman: 'I', goal: '#2 within 10 pts of leader'),
    ],
  ),
  AchievementCatalogEntry(
    key: 'troll_tiny',
    displayName: 'Troll',
    family: 'behavior',
    emoji: '🧊',
    description: 'Three micro-logs (≤8 pts) within 30 minutes.',
    wave: 2,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 15, roman: 'I', goal: '3 tiny logs in 30m'),
    ],
  ),

  // ── Wave 3 ────────────────────────────────────────────────────────
  AchievementCatalogEntry(
    key: 'perfect_storm',
    displayName: 'Perfect Storm',
    family: 'combo',
    emoji: '🌩️',
    description: 'Overtake + 2-rank jump + PR in window — same log.',
    wave: 3,
    tiers: [
      AchievementTierDef(at: 1, rewardPoints: 120, roman: 'I', goal: 'Overtake + 2-rank jump + PR in window'),
    ],
  ),
];

AchievementCatalogEntry? kAchievementByKey(String key) {
  for (final e in kAchievementCatalog) {
    if (e.key == key) return e;
  }
  return null;
}
