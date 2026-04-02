import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exercise.dart';
import '../services/exercise_service.dart';
import 'active_room_provider.dart';

final roomExercisesProvider =
    FutureProvider<List<Exercise>>((ref) async {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return [];
  return ExerciseService.getRoomExercises(room.id);
});
