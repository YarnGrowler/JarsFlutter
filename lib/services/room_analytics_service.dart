import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../core/jars_timezone.dart';
import '../models/exercise_log.dart';
import 'score_service.dart';
import 'supabase_service.dart';

/// Cumulative total-score series for one room member over [rangeDays] Chicago days.
/// [cumulativePoints[i]] = total score at end of day i (workouts + achievement bonuses
/// on that day; baseline is score before the first day in the window).
class MemberDailySeries {
  final String userId;
  final String username;
  /// Parallel to the range — cumulative total score at end of each day.
  final List<double> cumulativePoints;

  const MemberDailySeries({
    required this.userId,
    required this.username,
    required this.cumulativePoints,
  });
}

/// Aggregated analytics for a room.
class RoomAnalyticsSnapshot {
  final int rangeDays;
  final DateTime startDay;
  /// Per-member cumulative series (max 6 members, current user first).
  final List<MemberDailySeries> memberSeries;

  const RoomAnalyticsSnapshot({
    required this.rangeDays,
    required this.startDay,
    required this.memberSeries,
  });

  bool get hasData => memberSeries.isNotEmpty;
}

class RoomAnalyticsService {
  static final _db = SupabaseService.client;

  static const _pageSize = 1000;

  static DateTime _chicagoDateOnly(DateTime utc) {
    JarsTimezone.ensureInitialized();
    final loc = tz.getLocation(JarsTimezone.locationName);
    final t = tz.TZDateTime.from(utc.toUtc(), loc);
    return DateTime(t.year, t.month, t.day);
  }

  /// Fetches all exercise_logs in [startUtc, endUtc) with pagination.
  static Future<List<dynamic>> _fetchLogsInUtcRange({
    required String roomId,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final all = <dynamic>[];
    var offset = 0;
    while (true) {
      final batch = await _db
          .from('exercise_logs')
          .select(
            'user_id, exercise_name, points_earned, created_at, profiles(username)',
          )
          .eq('room_id', roomId)
          .gte('created_at', startUtc.toIso8601String())
          .lt('created_at', endUtc.toIso8601String())
          .order('created_at', ascending: true)
          .range(offset, offset + _pageSize - 1);
      final list = List<dynamic>.from(batch);
      if (list.isEmpty) break;
      all.addAll(list);
      if (list.length < _pageSize) break;
      offset += _pageSize;
    }
    return all;
  }

  /// Per-day points: workouts from [points_earned], achievements from [__ACH__] JSON
  /// ([unlocks].[points] per user on the feed row's [created_at] day).
  ///
  /// Baseline = live [scores.total_score] − sum(per-day points in window), so the last
  /// day matches the leaderboard and achievements bump the line on the day they unlocked.
  static Future<RoomAnalyticsSnapshot> load({
    required String roomId,
    required String userId,
    int rangeDays = 30,
  }) async {
    final today = JarsTimezone.todayChicago();
    final startDay = today.subtract(Duration(days: rangeDays - 1));
    final startUtc = JarsTimezone.startOfChicagoDayUtc(startDay);
    final endUtc = JarsTimezone.startOfChicagoDayUtc(today.add(const Duration(days: 1)));

    final scores = await ScoreService.getRoomScores(roomId);
    final scoreMap = <String, double>{};
    final nameMap = <String, String>{};
    for (final s in scores) {
      scoreMap[s.userId] = s.totalScore;
      if (s.username != null) nameMap[s.userId] = s.username!;
    }

    final list = await _fetchLogsInUtcRange(
      roomId: roomId,
      startUtc: startUtc,
      endUtc: endUtc,
    );

    for (final raw in list) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final uid = m['user_id'] as String? ?? '';
      if (uid.isEmpty || nameMap.containsKey(uid)) continue;
      final prof = m['profiles'];
      if (prof is Map) {
        final u = prof['username'];
        if (u is String && u.isNotEmpty) nameMap[uid] = u;
      }
    }

    // memberDayPts[uid][dayIndex] = workout + achievement points that day (in window).
    final memberDayPts = <String, List<double>>{};

    void addPts(String uid, int dayIndex, double pts) {
      if (pts <= 0) return;
      if (!scoreMap.containsKey(uid)) return;
      if (dayIndex < 0 || dayIndex >= rangeDays) return;
      final bucket = memberDayPts.putIfAbsent(uid, () => List.filled(rangeDays, 0.0));
      bucket[dayIndex] += pts;
    }

    for (final raw in list) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final exerciseName = m['exercise_name'] as String? ?? '';
      if (exerciseName.isEmpty) continue;

      final created = DateTime.tryParse(m['created_at'] as String? ?? '');
      if (created == null) continue;
      final day = _chicagoDateOnly(created);
      final dayIndex = day.difference(startDay).inDays;
      if (dayIndex < 0 || dayIndex >= rangeDays) continue;

      if (exerciseName.startsWith(ExerciseLog.kAchPrefix)) {
        final jsonStr = exerciseName.substring(ExerciseLog.kAchPrefix.length);
        Map<String, dynamic>? payload;
        try {
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map<String, dynamic>) payload = decoded;
        } catch (_) {}
        final unlocks = payload?['unlocks'];
        if (unlocks is! List) continue;
        for (final u in unlocks) {
          if (u is! Map) continue;
          final uid = u['user_id'] as String?;
          final pts = (u['points'] as num?)?.toDouble() ?? 0;
          if (uid == null || uid.isEmpty) continue;
          addPts(uid, dayIndex, pts);
        }
        continue;
      }

      if (exerciseName.startsWith(ExerciseLog.kStimulusPrefix)) {
        final uid = m['user_id'] as String? ?? '';
        final pts = (m['points_earned'] as num?)?.toDouble() ?? 0;
        addPts(uid, dayIndex, pts);
        continue;
      }

      if (exerciseName.startsWith('__')) continue;

      final uid = m['user_id'] as String? ?? '';
      final pts = (m['points_earned'] as num?)?.toDouble() ?? 0;
      addPts(uid, dayIndex, pts);
    }

    final allUids = scoreMap.keys.toList()
      ..sort((a, b) {
        if (a == userId) return -1;
        if (b == userId) return 1;
        return (scoreMap[b] ?? 0).compareTo(scoreMap[a] ?? 0);
      });
    final topUids = allUids.take(6).toList();

    final memberSeries = <MemberDailySeries>[];
    for (final uid in topUids) {
      final currentTotal = scoreMap[uid] ?? 0;
      final dayPts = memberDayPts[uid] ?? List.filled(rangeDays, 0.0);
      final inWindow = dayPts.fold(0.0, (s, v) => s + v);
      final baseline = (currentTotal - inWindow).clamp(0.0, double.infinity);

      final cumulative = List<double>.filled(rangeDays, 0.0);
      var running = baseline;
      for (var i = 0; i < rangeDays; i++) {
        running += dayPts[i];
        cumulative[i] = running;
      }

      memberSeries.add(MemberDailySeries(
        userId: uid,
        username: nameMap[uid] ?? uid.substring(0, uid.length.clamp(0, 6)),
        cumulativePoints: cumulative,
      ));
    }

    return RoomAnalyticsSnapshot(
      rangeDays: rangeDays,
      startDay: startDay,
      memberSeries: memberSeries,
    );
  }
}
