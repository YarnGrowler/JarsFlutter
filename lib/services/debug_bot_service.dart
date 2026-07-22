import 'supabase_service.dart';

/// Thin wrappers over the `47_debug_bots.sql` RPCs. Debug-only. Each throws if
/// the patch isn't applied — callers surface a "run patch 47" message.
class DebugBotService {
  static final _db = SupabaseService.client;

  /// Add the 3 fixed bots to [roomId] as real members + score rows.
  static Future<void> addBotsToRoom(String roomId) async {
    await _db.rpc('debug_add_bots_to_room', params: {'p_room_id': roomId});
  }

  /// Wipe the bots' members/scores/logs from [roomId].
  static Future<void> removeBots(String roomId) async {
    await _db.rpc('debug_remove_bots', params: {'p_room_id': roomId});
  }

  /// Log a real workout for a bot (feed shows the bot as the actor; supply +
  /// leaderboard update). [createdAt] lets the caller back-date to a sim day.
  static Future<void> botLog({
    required String roomId,
    required String botUuid,
    required String exerciseName,
    required int count,
    required double points,
    required DateTime createdAt,
  }) async {
    await _db.rpc('debug_bot_log', params: {
      'p_room_id': roomId,
      'p_bot_id': botUuid,
      'p_exercise_name': exerciseName,
      'p_count': count,
      'p_points': points,
      'p_created_at': createdAt.toUtc().toIso8601String(),
    });
  }
}
