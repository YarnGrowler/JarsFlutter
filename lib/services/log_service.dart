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
    var query = _db
        .from('exercise_logs')
        .select('*, profiles(username)')
        .eq('user_id', userId)
        .not('exercise_name', 'like', '${ExerciseLog.kRankUpPrefix}%')
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);

    if (roomId != null) {
      query = _db
          .from('exercise_logs')
          .select('*, profiles(username)')
          .eq('user_id', userId)
          .eq('room_id', roomId)
          .not('exercise_name', 'like', '${ExerciseLog.kRankUpPrefix}%')
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
        .select('points_earned, created_at')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .order('created_at', ascending: true);

    final map = <DateTime, double>{};
    for (final row in rows) {
      final pts = (row['points_earned'] as num?)?.toDouble() ?? 0.0;
      final raw = row['created_at'] as String?;
      if (raw == null) continue;
      final dt = DateTime.parse(raw).toLocal();
      final day = DateTime(dt.year, dt.month, dt.day);
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
