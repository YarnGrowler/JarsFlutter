import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exercise_log.dart';
import '../models/reaction.dart';
import '../services/log_service.dart';
import '../services/reaction_service.dart';
import 'active_room_provider.dart';

final roomFeedProvider =
    FutureProvider<List<ExerciseLog>>((ref) async {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return [];
  await LogService.ensureIdleWakeCards(room.id);
  return LogService.getRoomFeed(room.id);
});

/// Feed logs paired with full [Reaction] objects per log (for [FeedCard]).
/// Using full Reaction objects lets [ReactionRow] identify which emojis
/// the current user has already added (to show them highlighted).
final roomFeedWithReactionsProvider =
    FutureProvider<List<({ExerciseLog log, List<Reaction> reactions})>>(
        (ref) async {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return [];
  await LogService.ensureIdleWakeCards(room.id);
  final logs = await LogService.getRoomFeed(room.id);
  if (logs.isEmpty) return [];
  final ids = logs.map((l) => l.id).toList();
  final rmap = await ReactionService.getReactionsForLogs(ids);
  return logs
      .map((l) => (
            log: l,
            reactions: rmap[l.id] ?? <Reaction>[],
          ))
      .toList();
});

final feedStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return const Stream.empty();
  return LogService.streamRoomFeed(room.id);
});
