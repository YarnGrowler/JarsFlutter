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

  static Stream<List<Map<String, dynamic>>> streamRoomFeed(String roomId) {
    return _db
        .from('exercise_logs')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(50);
  }
}
