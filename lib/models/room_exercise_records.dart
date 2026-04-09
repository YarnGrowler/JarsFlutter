/// Per-user points on one exercise in a room (aggregated from logs).
class ExerciseUserPoints {
  final String userId;
  final String username;
  final double points;

  const ExerciseUserPoints({
    required this.userId,
    required this.username,
    required this.points,
  });
}

/// One exercise, total room points, and top contributors.
class ExerciseRoomStats {
  final String exerciseName;
  final double totalRoomPoints;
  final List<ExerciseUserPoints> topUsers;

  const ExerciseRoomStats({
    required this.exerciseName,
    required this.totalRoomPoints,
    required this.topUsers,
  });
}
