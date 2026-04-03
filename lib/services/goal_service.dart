import 'supabase_service.dart';
import '../models/group_goal.dart';

class GoalService {
  static final _db = SupabaseService.client;

  static Future<GroupGoal?> getRoomGoal(String roomId) async {
    final rows = await _db
        .from('group_goals')
        .select()
        .eq('room_id', roomId);

    if (rows.isEmpty) return null;
    return GroupGoal.fromJson(rows.first);
  }

  static Future<GroupGoal> createGoal({
    required String roomId,
    required int targetPoints,
    required int durationDays,
    String? description,
  }) async {
    final data = await _db.from('group_goals').upsert({
      'room_id': roomId,
      'target_points': targetPoints,
      'duration_days': durationDays,
      'description': description,
      'start_date': DateTime.now().toIso8601String(),
    }).select().single();

    return GroupGoal.fromJson(data);
  }

  static Future<void> deleteGoal(String goalId) async {
    await _db.from('group_goals').delete().eq('id', goalId);
  }

  /// Sum of [points_earned] for the room on or after [since] (typically goal start).
  static Future<double> getRoomPointsEarnedSince(
    String roomId,
    DateTime since,
  ) async {
    final rows = await _db
        .from('exercise_logs')
        .select('points_earned')
        .eq('room_id', roomId)
        .gte('created_at', since.toUtc().toIso8601String());
    var sum = 0.0;
    for (final r in rows) {
      final v = r['points_earned'];
      if (v is num) sum += v.toDouble();
    }
    return sum;
  }
}
