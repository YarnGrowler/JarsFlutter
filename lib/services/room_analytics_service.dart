import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../core/jars_timezone.dart';
import '../models/exercise_log.dart';
import 'score_service.dart';
import 'supabase_service.dart';

/// Cumulative score series for one room member over [rangeDays] Chicago days.
///
/// Window modes (7/30/90): [cumulativePoints] starts at 0 and only counts points
/// earned inside the range. All-time: same, from the room's earliest log day.
class MemberDailySeries {
  final String userId;
  final String username;
  /// Parallel to the range — cumulative points from the start of the window.
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
  /// True when the series spans all-time (not a fixed 7/30/90 window).
  final bool isAllTime;
  /// Per-member cumulative series (max 6 members, current user first).
  final List<MemberDailySeries> memberSeries;

  const RoomAnalyticsSnapshot({
    required this.rangeDays,
    required this.startDay,
    required this.memberSeries,
    this.isAllTime = false,
  });

  bool get hasData => memberSeries.isNotEmpty;
}

class RoomAnalyticsService {
  static final _db = SupabaseService.client;

  static const _pageSize = 1000;
  /// Cap all-time charts so we don't pull unbounded history.
  static const _maxAllTimeDays = 730;

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

  static Future<DateTime?> _earliestLogDay(String roomId) async {
    final row = await _db
        .from('exercise_logs')
        .select('created_at')
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final raw = row['created_at'] as String?;
    if (raw == null) return null;
    final created = DateTime.tryParse(raw);
    if (created == null) return null;
    return _chicagoDateOnly(created);
  }

  /// Per-day points: workouts from [points_earned], achievements from [__ACH__] JSON.
  ///
  /// [rangeDays] 7/30/90 = fixed window ending today. Pass `0` for all-time
  /// (from earliest room log, capped at [_maxAllTimeDays]).
  /// Series always start at **zero** — only points earned in the window.
  static Future<RoomAnalyticsSnapshot> load({
    required String roomId,
    required String userId,
    int rangeDays = 30,
  }) async {
    final today = JarsTimezone.todayChicago();
    final isAllTime = rangeDays <= 0;

    late final DateTime startDay;
    late final int days;
    if (isAllTime) {
      final earliest = await _earliestLogDay(roomId);
      final rawStart = earliest ?? today;
      final span = today.difference(rawStart).inDays + 1;
      days = span.clamp(1, _maxAllTimeDays);
      startDay = today.subtract(Duration(days: days - 1));
    } else {
      days = rangeDays;
      startDay = today.subtract(Duration(days: days - 1));
    }

    final startUtc = JarsTimezone.startOfChicagoDayUtc(startDay);
    final endUtc =
        JarsTimezone.startOfChicagoDayUtc(today.add(const Duration(days: 1)));

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

    // memberDayPts[uid][dayIndex] = workout + achievement points that day.
    final memberDayPts = <String, List<double>>{};

    void addPts(String uid, int dayIndex, double pts) {
      if (pts <= 0) return;
      if (!scoreMap.containsKey(uid)) return;
      if (dayIndex < 0 || dayIndex >= days) return;
      final bucket =
          memberDayPts.putIfAbsent(uid, () => List.filled(days, 0.0));
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
      if (dayIndex < 0 || dayIndex >= days) continue;

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

    // Rank by points earned IN this window so the race highlights who's
    // grinding now — all-time still uses career total for the top 6.
    final windowTotals = <String, double>{
      for (final uid in scoreMap.keys)
        uid: (memberDayPts[uid] ?? const <double>[])
            .fold(0.0, (s, v) => s + v),
    };

    final allUids = scoreMap.keys.toList()
      ..sort((a, b) {
        if (a == userId) return -1;
        if (b == userId) return 1;
        if (isAllTime) {
          return (scoreMap[b] ?? 0).compareTo(scoreMap[a] ?? 0);
        }
        final cmp = (windowTotals[b] ?? 0).compareTo(windowTotals[a] ?? 0);
        if (cmp != 0) return cmp;
        return (scoreMap[b] ?? 0).compareTo(scoreMap[a] ?? 0);
      });
    final topUids = allUids.take(6).toList();

    final memberSeries = <MemberDailySeries>[];
    for (final uid in topUids) {
      final dayPts = memberDayPts[uid] ?? List.filled(days, 0.0);
      // Always from zero — only what was earned in this window.
      final cumulative = List<double>.filled(days, 0.0);
      var running = 0.0;
      for (var i = 0; i < days; i++) {
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
      rangeDays: days,
      startDay: startDay,
      memberSeries: memberSeries,
      isAllTime: isAllTime,
    );
  }
}
