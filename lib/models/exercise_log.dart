import 'dart:convert';

import '../core/count_unit.dart';

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

  /// Set on AI-generated reply cards; references the log that triggered the event.
  final String? replyToLogId;

  /// `reps` | `seconds` | `minutes` — how [count] is interpreted (matches exercise).
  final String? countUnitRaw;

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
    this.replyToLogId,
    this.countUnitRaw,
  });

  /// How to interpret [count] for display (DB column, else name heuristic).
  CountUnit get effectiveCountUnit {
    final raw = countUnitRaw?.trim();
    if (raw != null && raw.isNotEmpty) return countUnitFromJson(raw);
    return inferCountUnitFromExerciseName(exerciseName);
  }

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
  /// AI narrator card (JSON payload after prefix).
  static const kAiPrefix = '__AI__|';
  /// Achievement batch card (JSON payload after prefix).
  static const kAchPrefix = '__ACH__|';

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
  bool get isAiBroadcast       => exerciseName.startsWith(kAiPrefix);
  bool get isAchievementBroadcast => exerciseName.startsWith(kAchPrefix);

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
      isMemberKick ||
      isAiBroadcast ||
      isAchievementBroadcast;

  String? get rankUpTitle {
    if (!isRankUpBroadcast) return null;
    return exerciseName.substring(kRankUpPrefix.length);
  }

  /// Parsed JSON for [isAiBroadcast] rows.
  Map<String, dynamic>? get aiPayload {
    if (!isAiBroadcast) return null;
    try {
      final raw = exerciseName.length > kAiPrefix.length
          ? exerciseName.substring(kAiPrefix.length)
          : '';
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  String? get aiText {
    final m = aiPayload;
    final t = m?['text'];
    return t is String ? t : null;
  }

  /// True when this AI row is threaded under a parent log (grouping + indent), including `mode: post`.
  bool get isAiThreadedUnderLog => isAiBroadcast && replyToLogId != null;

  /// True for [_AiReplyCard] layout (`reply` / `react` / legacy rows). `mode: post` uses [_AiPostCard] but stays threaded.
  bool get isAiReply =>
      isAiThreadedUnderLog &&
      (aiPayload == null ||
          aiPayload!['mode'] == null ||
          aiPayload!['mode'] == 'reply' ||
          aiPayload!['mode'] == 'react');

  /// The persona label stored in the AI payload (e.g. "Analyst", "Hype Man").
  String? get aiPersona {
    final m = aiPayload;
    final p = m?['persona'];
    return p is String && p.isNotEmpty ? p : null;
  }

  /// For reply cards: the username of the person whose log triggered this AI card.
  String? get aiReplyToUsername {
    final m = aiPayload;
    final v = m?['replyToUsername'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// For reply cards: the exercise name that triggered this AI card.
  String? get aiReplyToExercise {
    final m = aiPayload;
    final v = m?['replyToExercise'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// For reply cards: the rep count on the triggering log.
  int? get aiReplyToReps {
    final m = aiPayload;
    final v = m?['replyToReps'];
    return v is num ? v.toInt() : null;
  }

  /// Preformatted "2 min", "45s", "12 reps" for AI reply chip when present.
  String? get aiReplyToVolumeHuman {
    final m = aiPayload;
    final v = m?['replyToVolumeHuman'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// Emoji the AI decided to react with (may be set with or without text).
  String? get aiEmoji {
    final m = aiPayload;
    final v = m?['aiEmoji'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// True when the card is emoji-only (no text reply, just a reaction).
  bool get isAiReactOnly {
    if (!isAiBroadcast) return false;
    final m = aiPayload;
    final mode = m?['mode'];
    return mode == 'react';
  }

  Map<String, dynamic>? get achPayload {
    if (!isAchievementBroadcast) return null;
    try {
      final raw = exerciseName.length > kAchPrefix.length
          ? exerciseName.substring(kAchPrefix.length)
          : '';
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  String? get achTitle {
    final m = achPayload;
    final t = m?['title'];
    return t is String && t.isNotEmpty ? t : null;
  }

  List<Map<String, dynamic>> get achUnlockLines {
    final m = achPayload;
    final u = m?['unlocks'];
    if (u is! List) return const [];
    return u
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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
      replyToLogId: json['reply_to_log_id'] as String?,
      countUnitRaw: json['count_unit'] as String?,
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

