import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import 'score_service.dart';
import '../models/badge.dart';

class BadgeService {
  static final _db = SupabaseService.client;
  static const _kLastBadgeCheckKey = 'jars_last_badge_check_month';

  /// Fetch all badges for the current user.
  static Future<List<AppBadge>> getMyBadges() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return [];

    final rows = await _db
        .from('badges')
        .select()
        .eq('user_id', userId)
        .order('awarded_at', ascending: false);

    return rows.map((r) => AppBadge.fromJson(r)).toList();
  }

  /// Award a badge if the user doesn't already have it for this room+type this month.
  static Future<void> _award({
    required String userId,
    required String roomId,
    required String type,
    Map<String, dynamic>? metadata,
  }) async {
    // Check for duplicate
    final existing = await _db
        .from('badges')
        .select('id')
        .eq('user_id', userId)
        .eq('room_id', roomId)
        .eq('type', type)
        .maybeSingle();

    if (existing != null) return;

    await _db.from('badges').insert({
      'user_id': userId,
      'room_id': roomId,
      'type': type,
      'metadata': metadata,
    });
  }

  /// Called on app open. If it's the 1st of the month and we haven't checked
  /// this month yet, award medals to top 3 players for the previous month.
  static Future<void> checkAndAwardMonthlyBadges(String roomId) async {
    final now = DateTime.now();
    // Check on the 1st of the month
    if (now.day != 1) return;

    final prefs = await SharedPreferences.getInstance();
    final monthKey = '${now.year}-${now.month}';
    final lastCheck = prefs.getString(_kLastBadgeCheckKey);
    if (lastCheck == monthKey) return; // Already checked this month

    try {
      final scores = await ScoreService.getRoomScores(roomId);
      scores.sort((a, b) => b.totalScore.compareTo(a.totalScore));

      const medalTypes = ['gold_medal', 'silver_medal', 'bronze_medal'];
      for (int i = 0; i < scores.length && i < 3; i++) {
        await _award(
          userId: scores[i].userId,
          roomId: roomId,
          type: medalTypes[i],
          metadata: {
            'rank': i + 1,
            'month': '${now.year}-${(now.month == 1 ? 12 : now.month - 1).toString().padLeft(2, '0')}',
            'score': scores[i].totalScore,
          },
        );
      }

      await prefs.setString(_kLastBadgeCheckKey, monthKey);
    } catch (_) {
      // Don't fail silently — badge award is best-effort
    }
  }
}
