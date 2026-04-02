class ExerciseLog {
  final String id;
  final String roomId;
  final String userId;
  final String exerciseId;
  final String exerciseName;
  final int count;
  final double weight;
  final double pointsEarned;
  final DateTime createdAt;

  // Joined fields (not stored in DB)
  final String? username;

  const ExerciseLog({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.exerciseId,
    required this.exerciseName,
    required this.count,
    this.weight = 0,
    required this.pointsEarned,
    required this.createdAt,
    this.username,
  });

  factory ExerciseLog.fromJson(Map<String, dynamic> json) {
    String? username;
    if (json['profiles'] != null && json['profiles'] is Map) {
      username = (json['profiles'] as Map)['username'] as String?;
    }

    return ExerciseLog(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      exerciseId: json['exercise_id'] as String,
      exerciseName: json['exercise_name'] as String,
      count: json['count'] as int,
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
      pointsEarned: (json['points_earned'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      username: username,
    );
  }

  Map<String, dynamic> toJson() => {
        'room_id': roomId,
        'user_id': userId,
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'count': count,
        'weight': weight,
        'points_earned': pointsEarned,
      };
}
