import 'dart:convert';

class ExerciseLog {
  final String id;
  final String roomId;
  final String userId;
  final String? exerciseId;
  final String exerciseName;
  final int count;
  final double weight;
  final double pointsEarned;
  final DateTime createdAt;

  // Joined fields (not stored in DB)
  final String? username;

  const ExerciseLog({
    required this.id,
    required this.roomId,
    required this.userId,
    this.exerciseId,
    required this.exerciseName,
    required this.count,
    this.weight = 0,
    required this.pointsEarned,
    required this.createdAt,
    this.username,
  });

  // ── Special broadcast row prefixes ───────────────────────────────────────
  static const kRankUpPrefix   = '__RANKUP__|';
  static const kOvertakePrefix = '__OVERTAKE__|';
  static const kStreakPrefix   = '__STREAK__|';
  static const kPrPrefix       = '__PR__|';
  static const kDeadPrefix     = '__DEAD__|';
  static const kFirstLogPrefix = '__FIRSTLOG__|';
  static const kCloseGapPrefix = '__CLOSEGAP__|';
  static const kWakePrefix = '__WAKE__|';
  static const kMemberJoinPrefix = '__JOIN__|';
  static const kMemberKickPrefix = '__KICK__|';

  bool get isRankUpBroadcast    => exerciseName.startsWith(kRankUpPrefix);
  bool get isOvertake           => exerciseName.startsWith(kOvertakePrefix);
  bool get isStreakMilestone    => exerciseName.startsWith(kStreakPrefix);
  bool get isPersonalRecord     => exerciseName.startsWith(kPrPrefix);
  bool get isDeadStreak         => exerciseName.startsWith(kDeadPrefix);
  bool get isFirstLog           => exerciseName.startsWith(kFirstLogPrefix);
  bool get isCloseGap           => exerciseName.startsWith(kCloseGapPrefix);
  bool get isWakeCard           => exerciseName.startsWith(kWakePrefix);
  bool get isMemberJoin        => exerciseName.startsWith(kMemberJoinPrefix);
  bool get isMemberKick        => exerciseName.startsWith(kMemberKickPrefix);

  bool get isAnyBroadcast =>
      isRankUpBroadcast ||
      isOvertake ||
      isStreakMilestone ||
      isPersonalRecord ||
      isDeadStreak ||
      isFirstLog ||
      isCloseGap ||
      isWakeCard ||
      isMemberJoin ||
      isMemberKick;

  String? get rankUpTitle {
    if (!isRankUpBroadcast) return null;
    return exerciseName.substring(kRankUpPrefix.length);
  }

  String? get broadcastPayload {
    for (final prefix in [
      kOvertakePrefix,
      kStreakPrefix,
      kPrPrefix,
      kDeadPrefix,
      kFirstLogPrefix,
      kCloseGapPrefix,
      kMemberJoinPrefix,
      kMemberKickPrefix,
    ]) {
      if (exerciseName.startsWith(prefix)) {
        return exerciseName.substring(prefix.length);
      }
    }
    return null;
  }

  /// Parsed payload for [isWakeCard] rows (JSON after [kWakePrefix]).
  WakeFeedPayload? get wakeFeedPayload {
    if (!isWakeCard) return null;
    final raw = exerciseName.length > kWakePrefix.length
        ? exerciseName.substring(kWakePrefix.length)
        : '';
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return WakeFeedPayload(
        days: (m['days'] as num?)?.toInt() ?? 1,
        rank: (m['rank'] as num?)?.toInt() ?? 0,
        lastSeenIso: m['lastSeen'] as String? ?? '',
        pick: (m['pick'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  factory ExerciseLog.fromJson(Map<String, dynamic> json) {
    String? username;
    if (json['profiles'] != null && json['profiles'] is Map) {
      username = (json['profiles'] as Map)['username'] as String?;
    }

    return ExerciseLog(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      exerciseId: json['exercise_id'] as String?,
      exerciseName: json['exercise_name'] as String,
      count: (json['count'] as num?)?.toInt() ?? 0,
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
      pointsEarned: (json['points_earned'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      username: username,
    );
  }

  Map<String, dynamic> toJson() => {
        'room_id': roomId,
        'user_id': userId,
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'count': count,
        'weight': weight,
        'points_earned': pointsEarned,
      };
}

class WakeFeedPayload {
  final int days;
  final int rank;
  final String lastSeenIso;
  final int pick;

  const WakeFeedPayload({
    required this.days,
    required this.rank,
    required this.lastSeenIso,
    required this.pick,
  });

  DateTime? get lastSeenUtc {
    if (lastSeenIso.isEmpty) return null;
    return DateTime.tryParse(lastSeenIso);
  }
}

