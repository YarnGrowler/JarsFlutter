import 'supabase_service.dart';

class AchievementService {
  static final _db = SupabaseService.client;

  /// PostgREST may return [int], [double], or occasionally a string; normalize for UI.
  static int normalizeTierReached(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static Future<void> markAchievementsOpened({
    required String roomId,
    required String userId,
  }) async {
    await _db.from('user_room_achievement_read_state').upsert({
      'user_id': userId,
      'room_id': roomId,
      'last_opened_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// True when the user has unlocks newer than the last time they opened the achievements sheet.
  static Future<bool> hasUnreadAchievements({
    required String roomId,
    required String userId,
  }) async {
    final readRows = await _db
        .from('user_room_achievement_read_state')
        .select('last_opened_at')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .maybeSingle();

    DateTime? lastOpened;
    final lo = readRows?['last_opened_at'];
    if (lo is String && lo.isNotEmpty) {
      lastOpened = DateTime.tryParse(lo);
    }

    final progRows = await _db
        .from('room_achievement_progress')
        .select('last_unlock_at')
        .eq('room_id', roomId)
        .eq('user_id', userId);

    DateTime? latest;
    for (final r in progRows as List<dynamic>) {
      final m = r as Map<String, dynamic>;
      final u = m['last_unlock_at'];
      if (u is! String || u.isEmpty) continue;
      final t = DateTime.tryParse(u);
      if (t == null) continue;
      if (latest == null || t.isAfter(latest)) latest = t;
    }

    if (latest == null) return false;
    if (lastOpened == null) return true;
    return latest.isAfter(lastOpened);
  }

  static Future<List<Map<String, dynamic>>> getMyProgress(
    String roomId,
    String userId,
  ) async {
    final rows = await _db
        .from('room_achievement_progress')
        .select()
        .eq('room_id', roomId)
        .eq('user_id', userId);
    final list = List<Map<String, dynamic>>.from(rows as List<dynamic>);
    for (final r in list) {
      final t = r['tier_reached'];
      r['tier_reached'] = normalizeTierReached(t);
    }
    return list;
  }
}
