import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/score.dart';
import '../services/score_service.dart';
import '../services/supabase_service.dart';
import 'active_room_provider.dart';

final roomScoresProvider =
    FutureProvider<List<Score>>((ref) async {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return [];
  return ScoreService.getRoomScores(room.id);
});

final myScoreProvider = FutureProvider<Score?>((ref) async {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return null;
  final userId = SupabaseService.currentUserId;
  if (userId == null) return null;
  return ScoreService.getUserScore(room.id, userId);
});

final scoreStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return const Stream.empty();
  return ScoreService.streamRoomScores(room.id);
});
