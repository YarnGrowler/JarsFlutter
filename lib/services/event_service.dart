import 'dart:developer' as developer;

import 'supabase_service.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'score_service.dart';
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
    required double pointsBefore,
    required double pointsAfter,
    required int streakBefore,
    required int streakAfter,
  }) async {
    try {
      await Future.wait([
        _checkOvertake(roomId, userId, username, pointsBefore, pointsAfter),
        _checkPersonalRecord(roomId, userId, username, exerciseName, repCount),
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
        // Notify the person who got overtaken
        await NotificationService.sendNotification(
          targetUserId: score.userId,
          body: '$username just passed you. You\'re losing ground.',
        );
        break; // one card per log is enough
      }
    }
  }

  // ── Personal Record ────────────────────────────────────────────────────────

  static Future<void> _checkPersonalRecord(
    String roomId,
    String userId,
    String username,
    String exerciseName,
    int repCount,
  ) async {
    final logs = await LogService.getUserLogs(roomId, userId, limit: 500);
    int prevBest = 0;
    for (final log in logs) {
      if (log.exerciseName == exerciseName && !log.isAnyBroadcast) {
        if (log.count > prevBest) prevBest = log.count;
      }
    }
    // The current log is the latest so prevBest includes this one.
    // Only broadcast if it's strictly greater than ALL previous.
    // We already included the current log in getUserLogs, so compare > prevBest
    // means the current log exceeds all history → that would always be true on
    // the first log. Filter: only broadcast if prevBest exists (sessions > 1).
    final previousSessions = logs
        .where((l) => l.exerciseName == exerciseName && !l.isAnyBroadcast)
        .length;
    if (previousSessions <= 1) return; // first ever session — skip
    if (repCount >= prevBest) {
      await _insertBroadcast(
        roomId: roomId,
        userId: userId,
        prefix: ExerciseLog.kPrPrefix,
        payload:
            '💥 $username set a new record · $repCount $exerciseName (was ${prevBest - 1})',
      );
    }
  }

  // ── First Log of Day ───────────────────────────────────────────────────────

  static Future<void> _checkFirstLogOfDay(
    String roomId,
    String userId,
    String username,
  ) async {
    final todayStart = DateTime.now().toUtc().copyWith(
          hour: 0,
          minute: 0,
          second: 0,
          millisecond: 0,
          microsecond: 0,
        );

    // Count non-broadcast logs from this user today
    final rows = await _db
        .from('exercise_logs')
        .select('id')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .gte('created_at', todayStart.toIso8601String())
        .not('exercise_name', 'like', '%__|%'); // exclude broadcasts

    if (rows.length == 1) {
      // This is the first log of the day for this user
      final hour = DateTime.now().hour;
      final minute = DateTime.now().minute;
      final timeStr =
          '${hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)}:${minute.toString().padLeft(2, '0')}${hour >= 12 ? 'pm' : 'am'}';
      await _insertBroadcast(
        roomId: roomId,
        userId: userId,
        prefix: ExerciseLog.kFirstLogPrefix,
        payload: '⚡ $username just woke up · $timeStr',
      );
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
}

