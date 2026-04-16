import 'dart:developer' as developer;

import 'package:timezone/timezone.dart' as tz;

import 'supabase_service.dart';
import '../core/jars_timezone.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'score_service.dart';
import '../core/count_unit.dart';
import '../core/log_display.dart';
import '../core/member_feed_quips.dart';
import '../models/exercise_log.dart';
import '../models/score.dart';

/// Generates special broadcast feed rows (Overtake, PR, First Log, Close Gap,
/// Streak Milestone, Dead Streak) after a user logs an exercise.
///
/// Call [checkAndBroadcast] right after [ScoreService.addPoints] resolves.
class EventService {
  static final _db = SupabaseService.client;

  static Future<void> checkAndBroadcast({
    required String roomId,
    required String userId,
    required String username,
    required String exerciseName,
    required int repCount,
    double logWeight = 0,
    CountUnit countUnit = CountUnit.reps,
    required double pointsBefore,
    required double pointsAfter,
    required int streakBefore,
    required int streakAfter,
    required String currentLogId,
  }) async {
    try {
      await Future.wait([
        _checkOvertake(roomId, userId, username, pointsBefore, pointsAfter),
        _checkPersonalRecord(
          roomId,
          userId,
          username,
          exerciseName,
          repCount,
          logWeight,
          countUnit,
          currentLogId,
        ),
        _checkFirstLogOfDay(roomId, userId, username),
        _checkStreakMilestone(roomId, userId, username, streakBefore, streakAfter),
        _checkDeadStreak(roomId, userId, username, streakBefore, streakAfter),
        _checkCloseGap(roomId, userId, pointsAfter),
      ]);
    } catch (e, st) {
      developer.log('EventService: $e', name: 'Jars', error: e, stackTrace: st);
    }
  }

  // ── Overtake ───────────────────────────────────────────────────────────────

  static Future<void> _checkOvertake(
    String roomId,
    String userId,
    String username,
    double pointsBefore,
    double pointsAfter,
  ) async {
    final scores = await ScoreService.getRoomScores(roomId);
    // Find users who had more points than me before, but now I have >= them
    for (final score in scores) {
      if (score.userId == userId) continue;
      if (score.totalScore > pointsBefore && score.totalScore <= pointsAfter) {
        final overtakenName = score.username ?? 'someone';
        final gap = (pointsAfter - score.totalScore).toInt();
        await _insertBroadcast(
          roomId: roomId,
          userId: userId,
          prefix: ExerciseLog.kOvertakePrefix,
          payload:
              '⚔️ $username overtook $overtakenName · now $gap pts ahead',
        );
        // Victim gets a targeted push; everyone else gets the routine
        // "workout logged" push from [log_sheet] (avoid duplicate room-wide lines).
        await NotificationService.sendNotification(
          targetUserId: score.userId,
          body: '$username just passed you. You\'re losing ground.',
        );
        break; // one card per log is enough
      }
    }
  }

  // ── Personal Record ────────────────────────────────────────────────────────

  static String _prVolumePhrase(int value, CountUnit u) {
    switch (u) {
      case CountUnit.reps:
        return '$value';
      case CountUnit.seconds:
        return formatSecondsAsHuman(value);
      case CountUnit.minutes:
        return '$value min';
    }
  }

  static Future<void> _checkPersonalRecord(
    String roomId,
    String userId,
    String username,
    String exerciseName,
    int repCount,
    double logWeight,
    CountUnit countUnit,
    String currentLogId,
  ) async {
    final logs = await LogService.getUserLogs(roomId, userId, limit: 500);
    final prior = logs
        .where(
          (l) =>
              l.exerciseName == exerciseName &&
              !l.isAnyBroadcast &&
              l.id != currentLogId,
        )
        .toList();

    var prevBestReps = 0;
    var prevBestWeight = 0.0;
    for (final log in prior) {
      if (log.count > prevBestReps) prevBestReps = log.count;
      if (log.weight > prevBestWeight) prevBestWeight = log.weight;
    }

    final w = logWeight > 0 ? logWeight : 0.0;
    final repPr = prior.isNotEmpty && repCount > prevBestReps;
    final weightPr = w > 0 && w > prevBestWeight;

    if (!repPr && !weightPr) return;

    final vol = _prVolumePhrase(repCount, countUnit);
    final prevVol = _prVolumePhrase(prevBestReps, countUnit);

    final String payload;
    if (repPr && weightPr) {
      final wStr = _formatWeight(w);
      final pwStr = prevBestWeight > 0 ? _formatWeight(prevBestWeight) : 'none';
      payload =
          '💥 $username set a new record · $vol $exerciseName @ $wStr '
          '(previous best $prevVol · $pwStr max weight)';
    } else if (repPr) {
      final wasLabel = switch (countUnit) {
        CountUnit.reps => 'was $prevBestReps reps',
        CountUnit.seconds => 'was $prevVol',
        CountUnit.minutes => 'was $prevBestReps min',
      };
      payload =
          '💥 $username set a new record · $vol $exerciseName ($wasLabel)';
    } else {
      final wStr = _formatWeight(w);
      final pwStr = prevBestWeight > 0 ? _formatWeight(prevBestWeight) : 'none';
      payload =
          '💥 $username new weight PR · $exerciseName @ $wStr (was $pwStr)';
    }

    await _insertBroadcast(
      roomId: roomId,
      userId: userId,
      prefix: ExerciseLog.kPrPrefix,
      payload: payload,
    );
    // Push: roommates already get per-log activity from [log_sheet]; feed card is the PR highlight.
  }

  static String _formatWeight(double lb) {
    if (lb % 1 == 0) return '${lb.toInt()} lb';
    return '${lb.toStringAsFixed(1)} lb';
  }

  // ── First Log of Day ───────────────────────────────────────────────────────

  static Future<void> _checkFirstLogOfDay(
    String roomId,
    String userId,
    String username,
  ) async {
    final todayStart = JarsTimezone.startOfTodayChicagoUtc();

    // Count non-broadcast logs from this user today (Chicago calendar day)
    final rows = await _db
        .from('exercise_logs')
        .select('id')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .gte('created_at', todayStart.toIso8601String())
        .not('exercise_name', 'match', r'^__'); // exclude feed broadcast rows

    if (rows.length == 1) {
      // First real log of the Chicago calendar day (same window as [todayStart]).
      JarsTimezone.ensureInitialized();
      final nowChi =
          tz.TZDateTime.now(tz.getLocation(JarsTimezone.locationName));
      final hour = nowChi.hour;
      final minute = nowChi.minute;
      final timeStr =
          '${hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)}:${minute.toString().padLeft(2, '0')}${hour >= 12 ? 'pm' : 'am'}';
      await _insertBroadcast(
        roomId: roomId,
        userId: userId,
        prefix: ExerciseLog.kFirstLogPrefix,
        payload: '⚡ $username first log today · $timeStr',
      );
      // Push: covered by per-log activity in [log_sheet].
    }
  }

  // ── Streak Milestone ───────────────────────────────────────────────────────

  static Future<void> _checkStreakMilestone(
    String roomId,
    String userId,
    String username,
    int streakBefore,
    int streakAfter,
  ) async {
    const milestones = [3, 7, 14, 30, 60, 100];
    for (final m in milestones) {
      if (streakBefore < m && streakAfter >= m) {
        await _insertBroadcast(
          roomId: roomId,
          userId: userId,
          prefix: ExerciseLog.kStreakPrefix,
          payload: '🔥 $username is on a $m-day streak',
        );
        // Push: covered by per-log activity in [log_sheet].
        break;
      }
    }
  }

  // ── Dead Streak ────────────────────────────────────────────────────────────

  static Future<void> _checkDeadStreak(
    String roomId,
    String userId,
    String username,
    int streakBefore,
    int streakAfter,
  ) async {
    // If streak reset (went to 1 from something bigger ≥ 3), it died
    if (streakBefore >= 3 && streakAfter == 1) {
      await _insertBroadcast(
        roomId: roomId,
        userId: userId,
        prefix: ExerciseLog.kDeadPrefix,
        payload: "💀 $username's $streakBefore-day streak just ended",
      );
      // Push: covered by per-log activity in [log_sheet].
    }
  }

  // ── Close Gap ──────────────────────────────────────────────────────────────

  static Future<void> _checkCloseGap(
    String roomId,
    String userId,
    double myNewScore,
  ) async {
    final scores = await ScoreService.getRoomScores(roomId);
    // Find the person directly ahead of me
    Score? ahead;
    for (final s in scores) {
      if (s.userId == userId) continue;
      if (s.totalScore > myNewScore) {
        if (ahead == null || s.totalScore < ahead.totalScore) {
          ahead = s;
        }
      }
    }
    if (ahead == null) return;

    final gap = (ahead.totalScore - myNewScore).toInt();
    if (gap <= 50) {
      // Insert a close-gap card visible only to the person being chased
      await _insertBroadcastForUser(
        roomId: roomId,
        userId: ahead.userId,
        prefix: ExerciseLog.kCloseGapPrefix,
        payload: '👀 You are $gap pts ahead · someone is closing in fast',
      );
      // Also push-notify them
      await NotificationService.sendNotification(
        targetUserId: ahead.userId,
        body: 'Watch out — someone is only $gap pts behind you.',
      );
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static Future<void> _insertBroadcast({
    required String roomId,
    required String userId,
    required String prefix,
    required String payload,
  }) async {
    await _db.from('exercise_logs').insert({
      'room_id': roomId,
      'user_id': userId,
      'exercise_id': null,
      'exercise_name': '$prefix$payload',
      'count': 0,
      'weight': 0,
      'points_earned': 0,
    });
  }

  static Future<void> _insertBroadcastForUser({
    required String roomId,
    required String userId,
    required String prefix,
    required String payload,
  }) async {
    await _db.from('exercise_logs').insert({
      'room_id': roomId,
      'user_id': userId,
      'exercise_id': null,
      'exercise_name': '$prefix$payload',
      'count': 0,
      'weight': 0,
      'points_earned': 0,
    });
  }

  /// Feed + push when someone joins via room code.
  static Future<void> roomMemberJoined({
    required String roomId,
    required String userId,
    required String username,
    required String roomName,
  }) async {
    try {
      final pick =
          (userId.hashCode ^ roomId.hashCode).abs() % 8;
      await _insertBroadcast(
        roomId: roomId,
        userId: userId,
        prefix: ExerciseLog.kMemberJoinPrefix,
        payload: MemberFeedQuips.joinFeedLine(username, pick),
      );
      await NotificationService.notifyRoomMembersExcept(
        roomId: roomId,
        excludeUserId: userId,
        body: '$username joined $roomName',
      );
    } catch (e, st) {
      developer.log('EventService.roomMemberJoined: $e',
          name: 'Jars', error: e, stackTrace: st);
    }
  }

  /// Feed + push when a member is removed (admin kick).
  static Future<void> roomMemberKicked({
    required String roomId,
    required String removedUserId,
    required String removedUsername,
    required String roomName,
  }) async {
    try {
      final actorId = SupabaseService.currentUserId;
      if (actorId == null) return;

      final pick =
          (removedUserId.hashCode ^ roomId.hashCode).abs() % 8;
      await _insertBroadcast(
        roomId: roomId,
        userId: actorId,
        prefix: ExerciseLog.kMemberKickPrefix,
        payload: MemberFeedQuips.kickFeedLine(removedUsername, pick),
      );
      await NotificationService.notifyRoomMembersExceptIds(
        roomId: roomId,
        excludeUserIds: {removedUserId},
        body: '$removedUsername was removed from $roomName',
      );
      await NotificationService.sendNotification(
        targetUserId: removedUserId,
        body: 'You were removed from $roomName.',
      );
    } catch (e, st) {
      developer.log('EventService.roomMemberKicked: $e',
          name: 'Jars', error: e, stackTrace: st);
    }
  }
}

