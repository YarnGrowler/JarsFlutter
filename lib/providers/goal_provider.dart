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

/// Active group goal plus room points earned since the goal started; null if none or expired.
final groupGoalProgressProvider =
    FutureProvider<GroupGoalProgress?>((ref) async {
  final goal = await ref.watch(groupGoalProvider.future);
  if (goal == null || !goal.isActive) return null;
  final earned =
      await GoalService.getRoomPointsEarnedSince(goal.roomId, goal.startDate);
  return GroupGoalProgress(goal: goal, earnedPoints: earned);
});
