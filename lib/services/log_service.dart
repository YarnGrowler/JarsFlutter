import 'package:timezone/timezone.dart' as tz;

import '../core/jars_timezone.dart';
import 'supabase_service.dart';
import '../models/exercise_log.dart';

class LogService {
  static final _db = SupabaseService.client;

  static Future<ExerciseLog> insertLog({
    required String roomId,
    required String exerciseId,
    required String exerciseName,
    required int count,
    required double weight,
    required double pointsEarned,
  }) async {
    final userId = SupabaseService.currentUserId!;
    final data = await _db.from('exercise_logs').insert({
      'room_id': roomId,
      'user_id': userId,
      'exercise_id': exerciseId,
      'exercise_name': exerciseName,
      'count': count,
      'weight': weight,
      'points_earned': pointsEarned,
    }).select('*, profiles(username)').single();

    return ExerciseLog.fromJson(data);
  }

  /// Server may insert idle "__WAKE__" feed rows (see [ensureIdleWakeCards]).
  /// Pass [actorUserId] after a successful log so the server never marks *you* idle
  /// on the same run (avoids races with feed refresh).
  static Future<void> ensureIdleWakeCards(
    String roomId, {
    String? actorUserId,
  }) async {
    try {
      final params = <String, dynamic>{'p_room_id': roomId};
      if (actorUserId != null) {
        params['p_actor_user_id'] = actorUserId;
      }
      await _db.rpc('ensure_idle_wake_cards', params: params);
    } catch (_) {}
  }

  /// Max 2 pings per member per wake card (enforced by [send_wake_nudge] RPC).
  static Future<void> sendWakeNudge(String logId) async {
    await _db.rpc('send_wake_nudge', params: {'p_log_id': logId});
  }

  /// Room admin: insert a wake card for [targetUserId] (cooldown in SQL).
  static Future<void> adminPostWakeReminder({
    required String roomId,
    required String targetUserId,
  }) async {
    await _db.rpc(
      'admin_post_wake_reminder',
      params: {
        'p_room_id': roomId,
        'p_target_user_id': targetUserId,
      },
    );
  }

  static Future<List<ExerciseLog>> getRoomFeed(String roomId, {int limit = 50}) async {
    final rows = await _db
        .from('exercise_logs')
        .select('*, profiles(username)')
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(limit);

    return rows
        .map((r) => ExerciseLog.fromJson(r))
        .toList();
  }

  static Future<List<ExerciseLog>> getUserLogs(String roomId, String userId, {int limit = 100}) async {
    final rows = await _db
        .from('exercise_logs')
        .select()
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .not('exercise_name', 'match', r'^__')
        .order('created_at', ascending: false)
        .limit(limit);

    return rows
        .map((r) => ExerciseLog.fromJson(r))
        .toList();
  }

  static Future<void> deleteLog(String logId) async {
    await _db.from('exercise_logs').delete().eq('id', logId);
  }

  static Future<void> updateLog(
    String logId, {
    required int count,
    required double weight,
    required double pointsEarned,
  }) async {
    await _db.from('exercise_logs').update({
      'count': count,
      'weight': weight,
      'points_earned': pointsEarned,
    }).eq('id', logId);
  }

  /// Fetch paginated user logs across all rooms (or a specific room).
  static Future<List<ExerciseLog>> getUserLogsPaged({
    required String userId,
    String? roomId,
    required int page,
    int pageSize = 30,
  }) async {
    // LIKE treats '_' as wildcard — __RANKUP__ rows leaked into history. Use regex.
    var query = _db
        .from('exercise_logs')
        .select('*, profiles(username)')
        .eq('user_id', userId)
        .not('exercise_name', 'match', r'^__')
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);

    if (roomId != null) {
      query = _db
          .from('exercise_logs')
          .select('*, profiles(username)')
          .eq('user_id', userId)
          .eq('room_id', roomId)
          .not('exercise_name', 'match', r'^__')
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
    }

    final rows = await query;
    return rows.map((r) => ExerciseLog.fromJson(r)).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamRoomFeed(String roomId) {
    return _db
        .from('exercise_logs')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(50);
  }

  /// Returns a map of UTC-midnight [DateTime] → sum of points for that day.
  static Future<Map<DateTime, double>> getDailyPoints(
      String roomId, String userId) async {
    final rows = await _db
        .from('exercise_logs')
        .select('points_earned, created_at, exercise_name')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .order('created_at', ascending: true);

    final map = <DateTime, double>{};
    JarsTimezone.ensureInitialized();
    final chicago = tz.getLocation(JarsTimezone.locationName);
    for (final row in rows) {
      final name = row['exercise_name'] as String? ?? '';
      if (name.startsWith('__')) continue;
      final pts = (row['points_earned'] as num?)?.toDouble() ?? 0.0;
      final raw = row['created_at'] as String?;
      if (raw == null) continue;
      final utc = DateTime.parse(raw).toUtc();
      final local = tz.TZDateTime.from(utc, chicago);
      final day = DateTime(local.year, local.month, local.day);
      map[day] = (map[day] ?? 0) + pts;
    }
    return map;
  }

  /// Room feed row so others see a rank-up taunt (no points, no exercise).
  static Future<void> insertRankUpBroadcast({
    required String roomId,
    required String rankTitle,
  }) async {
    final userId = SupabaseService.currentUserId!;
    await _db.from('exercise_logs').insert({
      'room_id': roomId,
      'user_id': userId,
      'exercise_id': null,
      'exercise_name': '${ExerciseLog.kRankUpPrefix}$rankTitle',
      'count': 0,
      'weight': 0,
      'points_earned': 0,
    });
  }
}
