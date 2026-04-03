import 'supabase_service.dart';
import '../models/reaction.dart';

class ReactionService {
  static final _db = SupabaseService.client;

  static Future<List<Reaction>> getReactionsForLog(String logId) async {
    final rows = await _db
        .from('reactions')
        .select()
        .eq('log_id', logId);

    return rows
        .map((r) => Reaction.fromJson(r))
        .toList();
  }

  static Future<Map<String, List<Reaction>>> getReactionsForLogs(
      List<String> logIds) async {
    if (logIds.isEmpty) return {};

    final rows = await _db
        .from('reactions')
        .select()
        .inFilter('log_id', logIds);

    final map = <String, List<Reaction>>{};
    for (final row in rows) {
      final reaction = Reaction.fromJson(row);
      map.putIfAbsent(reaction.logId, () => []).add(reaction);
    }
    return map;
  }

  /// Toggle a specific emoji reaction on a log.
  /// - Same emoji already exists for this user → remove (toggle off).
  /// - Emoji not present → insert new row.
  /// Multiple distinct emojis per user per log are allowed.
  static Future<Reaction?> addReaction({
    required String logId,
    required String emoji,
  }) async {
    final userId = SupabaseService.currentUserId!;

    // Check if this user already has this exact emoji on this log
    final existing = await _db
        .from('reactions')
        .select('id, emoji')
        .eq('log_id', logId)
        .eq('user_id', userId)
        .eq('emoji', emoji)
        .maybeSingle();

    if (existing != null) {
      // Same emoji → toggle off
      final rowId = existing['id'].toString();
      await _db.from('reactions').delete().eq('id', rowId);
      return null;
    }

    // No matching emoji → insert new row (allows multiple emojis per user)
    final data = await _db.from('reactions').insert({
      'log_id': logId,
      'user_id': userId,
      'emoji': emoji,
    }).select().single();

    return Reaction.fromJson(data);
  }

  static Future<void> removeReaction(String reactionId) async {
    await _db.from('reactions').delete().eq('id', reactionId);
  }

  /// Reactions on **your** logs from **other** users, since [since] (for celebration UI).
  static Future<List<String>> getNewReactionEmojisOnMyLogsSince(
      DateTime since) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return [];

    final logs = await _db
        .from('exercise_logs')
        .select('id')
        .eq('user_id', userId);

    if (logs.isEmpty) return [];

    final ids = logs.map((r) => r['id'].toString()).toList();
    final sinceStr = since.toUtc().toIso8601String();

    final rows = await _db
        .from('reactions')
        .select('emoji')
        .inFilter('log_id', ids)
        .neq('user_id', userId)
        .gt('created_at', sinceStr);

    final emojis = <String>[];
    for (final row in rows) {
      final e = row['emoji'] as String?;
      if (e != null && e.isNotEmpty) emojis.add(e);
    }
    return emojis;
  }
}
