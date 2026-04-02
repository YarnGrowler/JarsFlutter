import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group_goal.dart';
import '../services/goal_service.dart';
import 'active_room_provider.dart';

final groupGoalProvider =
    FutureProvider<GroupGoal?>((ref) async {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return null;
  return GoalService.getRoomGoal(room.id);
});
