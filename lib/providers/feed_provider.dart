import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exercise_log.dart';
import '../services/log_service.dart';
import 'active_room_provider.dart';

final roomFeedProvider =
    FutureProvider<List<ExerciseLog>>((ref) async {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return [];
  return LogService.getRoomFeed(room.id);
});

final feedStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return const Stream.empty();
  return LogService.streamRoomFeed(room.id);
});
