import 'achievement_catalog.dart';

/// Sums reward points for all tiers unlocked according to [tier_reached] rows.
int sumUnlockedAchievementRewardPoints(List<Map<String, dynamic>> progressRows) {
  var sum = 0;
  int tierReachedOf(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  for (final r in progressRows) {
    final key = r['achievement_key'] as String?;
    if (key == null || key.isEmpty) continue;
    final tierReached = tierReachedOf(r['tier_reached']);
    if (tierReached < 1) continue;
    AchievementCatalogEntry? entry;
    for (final e in kAchievementCatalog) {
      if (e.key == key) {
        entry = e;
        break;
      }
    }
    if (entry == null) continue;
    for (var i = 0; i < tierReached && i < entry.tiers.length; i++) {
      sum += entry.tiers[i].rewardPoints;
    }
  }
  return sum;
}
