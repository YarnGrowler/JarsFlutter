import 'supabase_service.dart';
import '../models/score.dart';
import '../core/jars_timezone.dart';

/// Preview-only: mirrors streak day logic in [addPoints] when only [basePoints]
/// are applied toward daily (used to pick streak multiplier before bonus is added).
int previewStreakDaysForBonus({
  required Score score,
  required double basePoints,
  required int streakMinimum,
}) {
  final today = JarsTimezone.todayChicago();
  double dailyPoints = score.dailyPoints;
  if (Score.isDailyResetStale(score.lastDailyReset)) {
    dailyPoints = 0;
  }
  dailyPoints += basePoints;
  if (dailyPoints < streakMinimum) return 0;

  int streakCurrent = score.streakCurrent;
  final streakLastWorkout = score.streakLastWorkout;

  DateTime? lastDay;
  if (streakLastWorkout != null) {
    lastDay = DateTime(
      streakLastWorkout.year,
      streakLastWorkout.month,
      streakLastWorkout.day,
    );
  }
  if (streakLastWorkout == null) {
    return 1;
  }
  if (lastDay == today) {
    return streakCurrent;
  }
  if (lastDay == today.subtract(const Duration(days: 1))) {
    return streakCurrent + 1;
  }
  return 1;
}

class ScoreService {
  static final _db = SupabaseService.client;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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

    final today = JarsTimezone.todayChicago();
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
      DateTime? lastDay;
      final prevStreak = streakLastWorkout;
      if (prevStreak != null) {
        lastDay = DateTime(prevStreak.year, prevStreak.month, prevStreak.day);
      }
      if (streakLastWorkout == null) {
        streakCurrent = 1;
      } else if (lastDay == today) {
        // Same Chicago calendar day, no streak change
      } else if (lastDay ==
          today.subtract(const Duration(days: 1))) {
        streakCurrent += 1;
      } else {
        streakCurrent = 1;
      }
      streakLastWorkout = today;
      if (streakCurrent > streakHighest) {
        streakHighest = streakCurrent;
      }
    }

    final streakDayOut = streakLastWorkout;

    await _db.from('scores').update({
      'total_score': newTotal,
      'daily_points': dailyPoints,
      'last_daily_reset': _ymd(today),
      'streak_current': streakCurrent,
      'streak_highest': streakHighest,
      'streak_last_workout':
          streakDayOut == null ? null : _ymd(streakDayOut),
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
      final today = JarsTimezone.todayChicago();
      await _db.from('scores').update({
        'daily_points': 0,
        'last_daily_reset':
            '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
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
