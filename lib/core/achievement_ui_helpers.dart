import 'achievement_catalog.dart';

/// Single goal line for the **next** tier only (shown in purple).
String achievementNextTierConditionLine({
  required AchievementCatalogEntry def,
  required int tierReached,
}) {
  if (def.tiers.isEmpty || tierReached >= def.tiers.length) return '';
  return def.tiers[tierReached].goal;
}

/// Progress text for the right side of the tier row, e.g. "7 / 10 overtakes".
/// Falls back to the goal string if no numeric progress is available.
String achievementTierProgressText({
  required AchievementCatalogEntry def,
  required int tierReached,
  required Map<String, dynamic>? progressJson,
}) {
  if (def.tiers.isEmpty || tierReached >= def.tiers.length) return '';
  final next = def.tiers[tierReached];

  if (progressJson == null) return next.goal;

  final p = progressJson;
  int n(dynamic v) => (v is num) ? v.toInt() : 0;

  switch (def.key) {
    case 'night_creature':
      return '${n(p['night_count'])} / ${next.at}';
    case 'head_hunter':
      return '${n(p['overtake_total'])} / ${next.at}';
    case 'executioner':
      final ids = p['victim_ids'];
      final c = (ids is List) ? ids.length : 0;
      return '$c / ${next.at}';
    case 'nemesis':
      return '${n(p['max_lead_gap'])} / ${next.at} pts';
    case 'tyrant':
      return '${n(p['tyrant_max_lead'])} / ${next.at} pts';
    case 'uno_reverse':
      return '${n(p['reverse_count'])} / ${next.at}';
    case 'last_to_first':
      return '${n(p['ltf_count'])} / ${next.at}';
    case 'from_the_dead':
      return '${n(p['ftd_count'])} / ${next.at}';
    case 'clutch':
      return '${n(p['clutch_count'])} / ${next.at}';
    case 'reclaim_throne':
      return '${n(p['reclaim_count'])} / ${next.at}';
    case 'one_hit_wonder':
      return '${n(p['best_single_log'])} / ${next.at} pts';
    default:
      return next.goal;
  }
}
