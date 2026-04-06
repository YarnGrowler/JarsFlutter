import '../core/jars_timezone.dart';

class Score {
  final String roomId;
  final String userId;
  final double totalScore;
  final double dailyPoints;
  final DateTime? lastDailyReset;
  final int streakCurrent;
  final int streakHighest;
  final DateTime? streakLastWorkout;
  final DateTime updatedAt;

  // Joined fields
  final String? username;

  /// True when [lastDailyReset] is before **today in America/Chicago** (CST/CDT).
  static bool isDailyResetStale(DateTime? lastDailyReset) {
    if (lastDailyReset == null) return false;
    final today = JarsTimezone.todayChicago();
    final last = DateTime(
      lastDailyReset.year,
      lastDailyReset.month,
      lastDailyReset.day,
    );
    return last.isBefore(today);
  }

  bool get isDailyStale => Score.isDailyResetStale(lastDailyReset);

  /// Points toward today's goal; 0 when the stored row is from a prior calendar day.
  double get displayDailyPoints =>
      isDailyStale ? 0.0 : dailyPoints;

  const Score({
    required this.roomId,
    required this.userId,
    this.totalScore = 0,
    this.dailyPoints = 0,
    this.lastDailyReset,
    this.streakCurrent = 0,
    this.streakHighest = 0,
    this.streakLastWorkout,
    required this.updatedAt,
    this.username,
  });

  factory Score.fromJson(Map<String, dynamic> json) {
    String? username;
    if (json['profiles'] != null && json['profiles'] is Map) {
      username = (json['profiles'] as Map)['username'] as String?;
    }

    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.round();
      return int.tryParse(v.toString()) ?? 0;
    }

    DateTime? parseDay(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      return DateTime.tryParse(s) ?? DateTime.tryParse('${s}T00:00:00.000Z');
    }

    final updatedRaw = json['updated_at'];
    if (updatedRaw == null) {
      throw FormatException('Score JSON missing updated_at');
    }

    return Score(
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      totalScore: (json['total_score'] as num?)?.toDouble() ?? 0,
      dailyPoints: (json['daily_points'] as num?)?.toDouble() ?? 0,
      lastDailyReset: parseDay(json['last_daily_reset']),
      streakCurrent: asInt(json['streak_current']),
      streakHighest: asInt(json['streak_highest']),
      streakLastWorkout: parseDay(json['streak_last_workout']),
      updatedAt: DateTime.parse(updatedRaw.toString()),
      username: username,
    );
  }

  Map<String, dynamic> toJson() => {
        'room_id': roomId,
        'user_id': userId,
        'total_score': totalScore,
        'daily_points': dailyPoints,
        'last_daily_reset': lastDailyReset?.toIso8601String(),
        'streak_current': streakCurrent,
        'streak_highest': streakHighest,
        'streak_last_workout': streakLastWorkout?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
