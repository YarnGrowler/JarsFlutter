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

  static Future<Reaction> addReaction({
    required String logId,
    required String emoji,
  }) async {
    final userId = SupabaseService.currentUserId!;
    final data = await _db.from('reactions').upsert({
      'log_id': logId,
      'user_id': userId,
      'emoji': emoji,
    }).select().single();

    return Reaction.fromJson(data);
  }

  static Future<void> removeReaction(String reactionId) async {
    await _db.from('reactions').delete().eq('id', reactionId);
  }
}
