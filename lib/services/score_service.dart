import 'supabase_service.dart';
import '../models/score.dart';
import '../core/extensions.dart';

class ScoreService {
  static final _db = SupabaseService.client;

  static Future<Score?> getUserScore(String roomId, String userId) async {
    final rows = await _db
        .from('scores')
        .select('*, profiles(username)')
        .eq('room_id', roomId)
        .eq('user_id', userId);

    if (rows.isEmpty) return null;
    return Score.fromJson(rows.first);
  }

  static Future<List<Score>> getRoomScores(String roomId) async {
    final rows = await _db
        .from('scores')
        .select('*, profiles(username)')
        .eq('room_id', roomId)
        .order('total_score', ascending: false);

    return rows
        .map((r) => Score.fromJson(r))
        .toList();
  }

  static Future<void> addPoints({
    required String roomId,
    required double points,
    required int streakMinimum,
  }) async {
    final userId = SupabaseService.currentUserId!;

    final current = await getUserScore(roomId, userId);
    if (current == null) return;

    final today = DateTime.now().startOfDay;
    double dailyPoints = current.dailyPoints;

    if (Score.isDailyResetStale(current.lastDailyReset)) {
      dailyPoints = 0;
    }

    dailyPoints += points;
    final newTotal = current.totalScore + points;

    int streakCurrent = current.streakCurrent;
    int streakHighest = current.streakHighest;
    DateTime? streakLastWorkout = current.streakLastWorkout;

    if (dailyPoints >= streakMinimum) {
      if (streakLastWorkout == null) {
        streakCurrent = 1;
      } else if (streakLastWorkout.startOfDay == today) {
        // Same day, no streak change
      } else if (streakLastWorkout.startOfDay ==
          today.subtract(const Duration(days: 1))) {
        streakCurrent += 1;
      } else {
        streakCurrent = 1;
      }
      streakLastWorkout = DateTime.now();
      if (streakCurrent > streakHighest) {
        streakHighest = streakCurrent;
      }
    }

    await _db.from('scores').update({
      'total_score': newTotal,
      'daily_points': dailyPoints,
      'last_daily_reset': today.toIso8601String().split('T')[0],
      'streak_current': streakCurrent,
      'streak_highest': streakHighest,
      'streak_last_workout':
          streakLastWorkout?.toIso8601String().split('T')[0],
    }).eq('room_id', roomId).eq('user_id', userId);
  }

  static Future<void> subtractPoints({
    required String roomId,
    required double points,
  }) async {
    final userId = SupabaseService.currentUserId!;
    final current = await getUserScore(roomId, userId);
    if (current == null) return;

    final dpBase = current.isDailyStale ? 0.0 : current.dailyPoints;

    await _db.from('scores').update({
      'total_score': (current.totalScore - points).clamp(0, double.infinity),
      'daily_points': (dpBase - points).clamp(0, double.infinity),
    }).eq('room_id', roomId).eq('user_id', userId);
  }

  static Future<void> checkDailyReset(String roomId) async {
    final userId = SupabaseService.currentUserId!;
    final current = await getUserScore(roomId, userId);
    if (current == null) return;

    if (current.isDailyStale) {
      final today = DateTime.now().startOfDay;
      await _db.from('scores').update({
        'daily_points': 0,
        'last_daily_reset': today.toIso8601String().split('T')[0],
      }).eq('room_id', roomId).eq('user_id', userId);
    }
  }

  static Stream<List<Map<String, dynamic>>> streamRoomScores(String roomId) {
    return _db
        .from('scores')
        .stream(primaryKey: ['room_id', 'user_id'])
        .eq('room_id', roomId)
        .order('total_score', ascending: false);
  }
}
