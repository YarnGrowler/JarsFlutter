import 'package:timezone/timezone.dart' as tz;

import '../core/jars_timezone.dart';
import 'supabase_service.dart';
import '../core/count_unit.dart';
import '../models/exercise_log.dart';
import '../models/room_exercise_records.dart';

class LogService {
  static final _db = SupabaseService.client;

  /// Most recent (non-broadcast) log for a user+exercise in a room.
  static Future<ExerciseLog?> getLastUserLogForExercise({
    required String roomId,
    required String userId,
    required String exerciseId,
  }) async {
    final rows = await _db
        .from('exercise_logs')
        .select('*, profiles(username)')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .eq('exercise_id', exerciseId)
        .or(
          'exercise_name.not.match.^__,exercise_name.match.^__STIMULUS__\\|',
        )
        .order('created_at', ascending: false)
        .limit(1);

    if (rows is! List || rows.isEmpty) return null;
    final first = rows.first;
    if (first is! Map) return null;
    return ExerciseLog.fromJson(Map<String, dynamic>.from(first));
  }

  static Future<ExerciseLog> insertLog({
    required String roomId,
    required String exerciseId,
    required String exerciseName,
    required int count,
    required double weight,
    required double pointsEarned,
    required CountUnit countUnit,
  }) async {
    final userId = SupabaseService.currentUserId!;
    final data = await _db.from('exercise_logs').insert({
      'room_id': roomId,
      'user_id': userId,
      'exercise_id': exerciseId,
      'exercise_name': exerciseName,
      'count': count,
      'weight': weight,
      'points_earned': pointsEarned,
      'count_unit': countUnit.name,
    }).select('*, profiles(username)').single();

    return ExerciseLog.fromJson(data);
  }

  /// Server may insert idle "__WAKE__" feed rows (see [ensureIdleWakeCards]).
  /// Pass [actorUserId] after a successful log so the server never marks *you* idle
  /// on the same run (avoids races with feed refresh).
  static Future<void> ensureIdleWakeCards(
    String roomId, {
    String? actorUserId,
  }) async {
    try {
      final params = <String, dynamic>{'p_room_id': roomId};
      if (actorUserId != null) {
        params['p_actor_user_id'] = actorUserId;
      }
      await _db.rpc('ensure_idle_wake_cards', params: params);
    } catch (_) {}
  }

  /// Max 2 pings per member per wake card (enforced by [send_wake_nudge] RPC).
  static Future<void> sendWakeNudge(String logId) async {
    await _db.rpc('send_wake_nudge', params: {'p_log_id': logId});
  }

  /// Room admin: insert a wake card for [targetUserId] (cooldown in SQL).
  static Future<void> adminPostWakeReminder({
    required String roomId,
    required String targetUserId,
  }) async {
    await _db.rpc(
      'admin_post_wake_reminder',
      params: {
        'p_room_id': roomId,
        'p_target_user_id': targetUserId,
      },
    );
  }

  static Future<List<ExerciseLog>> getRoomFeed(String roomId, {int limit = 100}) async {
    final rows = await _db
        .from('exercise_logs')
        .select('*, profiles(username)')
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(limit);

    final flat = rows
        .map((r) => ExerciseLog.fromJson(r))
        .where((l) => !l.isRoomStimulus)
        .toList();
    return _groupAiReplies(flat);
  }

  /// Re-sort the flat feed so each AI reply card sits immediately after
  /// the parent log it responded to. Non-reply items keep created_at DESC order.
  static List<ExerciseLog> _groupAiReplies(List<ExerciseLog> flat) {
    final replies = <ExerciseLog>[];
    final base = <ExerciseLog>[];

    for (final log in flat) {
      if (log.isAiThreadedUnderLog) {
        replies.add(log);
      } else {
        base.add(log);
      }
    }

    if (replies.isEmpty) return flat;

    final result = List<ExerciseLog>.from(base);

    // Walk backwards so earlier insertions don't shift un-processed indices.
    for (var i = result.length - 1; i >= 0; i--) {
      final myReplies = replies
          .where((r) => r.replyToLogId == result[i].id)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (myReplies.isNotEmpty) {
        result.insertAll(i + 1, myReplies);
      }
    }

    // Orphaned replies (parent not in the current page) go at the top.
    final inResult = result.map((l) => l.id).toSet();
    final orphans = replies.where((r) => !inResult.contains(r.id)).toList();
    result.insertAll(0, orphans);

    return result;
  }

  static Future<List<ExerciseLog>> getUserLogs(String roomId, String userId, {int limit = 100}) async {
    final rows = await _db
        .from('exercise_logs')
        .select()
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .or(
          'exercise_name.not.match.^__,exercise_name.match.^__STIMULUS__\\|',
        )
        .order('created_at', ascending: false)
        .limit(limit);

    return rows
        .map((r) => ExerciseLog.fromJson(r))
        .toList();
  }

  static Future<void> deleteLog(String logId) async {
    await _db.from('exercise_logs').delete().eq('id', logId);
  }

  static Future<void> updateLog(
    String logId, {
    required int count,
    required double weight,
    required double pointsEarned,
  }) async {
    await _db.from('exercise_logs').update({
      'count': count,
      'weight': weight,
      'points_earned': pointsEarned,
    }).eq('id', logId);
  }

  /// Fetch paginated user logs across all rooms (or a specific room).
  static Future<List<ExerciseLog>> getUserLogsPaged({
    required String userId,
    String? roomId,
    required int page,
    int pageSize = 30,
  }) async {
    // LIKE treats '_' as wildcard — __RANKUP__ rows leaked into history. Use regex.
    var query = _db
        .from('exercise_logs')
        .select('*, profiles(username)')
        .eq('user_id', userId)
        .or(
          'exercise_name.not.match.^__,exercise_name.match.^__STIMULUS__\\|',
        )
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);

    if (roomId != null) {
      query = _db
          .from('exercise_logs')
          .select('*, profiles(username)')
          .eq('user_id', userId)
          .eq('room_id', roomId)
          .or(
            'exercise_name.not.match.^__,exercise_name.match.^__STIMULUS__\\|',
          )
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
    }

    final rows = await query;
    return rows.map((r) => ExerciseLog.fromJson(r)).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamRoomFeed(String roomId) {
    return _db
        .from('exercise_logs')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(100);
  }

  /// Returns a map of UTC-midnight [DateTime] → sum of points for that day.
  static Future<Map<DateTime, double>> getDailyPoints(
      String roomId, String userId) async {
    final rows = await _db
        .from('exercise_logs')
        .select('points_earned, created_at, exercise_name')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .order('created_at', ascending: true);

    final map = <DateTime, double>{};
    JarsTimezone.ensureInitialized();
    final chicago = tz.getLocation(JarsTimezone.locationName);
    for (final row in rows) {
      final name = row['exercise_name'] as String? ?? '';
      if (name.startsWith('__') &&
          !name.startsWith(ExerciseLog.kStimulusPrefix)) {
        continue;
      }
      final pts = (row['points_earned'] as num?)?.toDouble() ?? 0.0;
      final raw = row['created_at'] as String?;
      if (raw == null) continue;
      final utc = DateTime.parse(raw).toUtc();
      final local = tz.TZDateTime.from(utc, chicago);
      final day = DateTime(local.year, local.month, local.day);
      map[day] = (map[day] ?? 0) + pts;
    }
    return map;
  }

  /// Aggregates non-broadcast logs in [roomId]: exercises sorted by total room points,
  /// each with up to [topUsersPerExercise] users by points on that exercise.
  /// Uses the most recent [maxLogs] rows (newest first) for performance.
  static Future<List<ExerciseRoomStats>> getRoomExerciseRecords({
    required String roomId,
    int topUsersPerExercise = 3,
    int maxLogs = 4000,
  }) async {
    final rows = await _db
        .from('exercise_logs')
        .select('user_id, exercise_name, points_earned, profiles(username)')
        .eq('room_id', roomId)
        .not('exercise_name', 'match', r'^__')
        .order('created_at', ascending: false)
        .limit(maxLogs);

    // exerciseName -> userId -> sum points
    final agg = <String, Map<String, double>>{};
    final usernames = <String, String>{};

    final list = rows is List ? rows as List<dynamic> : <dynamic>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final name = m['exercise_name'] as String? ?? '';
      if (name.isEmpty) continue;
      final uid = m['user_id'] as String? ?? '';
      if (uid.isEmpty) continue;
      final pts = (m['points_earned'] as num?)?.toDouble() ?? 0;
      final prof = m['profiles'];
      String uname = '?';
      if (prof is Map) {
        final u = prof['username'];
        if (u is String && u.isNotEmpty) uname = u;
      }
      usernames[uid] = uname;
      agg.putIfAbsent(name, () => {});
      final map = agg[name]!;
      map[uid] = (map[uid] ?? 0) + pts;
    }

    final out = <ExerciseRoomStats>[];
    for (final entry in agg.entries) {
      final exerciseName = entry.key;
      final byUser = entry.value;
      var total = 0.0;
      for (final v in byUser.values) {
        total += v;
      }
      final users = byUser.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = <ExerciseUserPoints>[];
      for (var i = 0; i < users.length && i < topUsersPerExercise; i++) {
        final e = users[i];
        top.add(ExerciseUserPoints(
          userId: e.key,
          username: usernames[e.key] ?? '?',
          points: e.value,
        ));
      }
      out.add(ExerciseRoomStats(
        exerciseName: exerciseName,
        totalRoomPoints: total,
        topUsers: top,
      ));
    }
    out.sort((a, b) => b.totalRoomPoints.compareTo(a.totalRoomPoints));
    return out;
  }

  /// Room feed row so others see a rank-up taunt (no points, no exercise).
  static Future<void> insertRankUpBroadcast({
    required String roomId,
    required String rankTitle,
  }) async {
    final userId = SupabaseService.currentUserId!;
    await _db.from('exercise_logs').insert({
      'room_id': roomId,
      'user_id': userId,
      'exercise_id': null,
      'exercise_name': '${ExerciseLog.kRankUpPrefix}$rankTitle',
      'count': 0,
      'weight': 0,
      'points_earned': 0,
    });
  }
}
