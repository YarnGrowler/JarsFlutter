class GroupGoal {
  final String id;
  final String roomId;
  final int targetPoints;
  final int durationDays;
  final String? description;
  final DateTime startDate;
  final DateTime createdAt;

  const GroupGoal({
    required this.id,
    required this.roomId,
    required this.targetPoints,
    required this.durationDays,
    this.description,
    required this.startDate,
    required this.createdAt,
  });

  factory GroupGoal.fromJson(Map<String, dynamic> json) {
    return GroupGoal(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      targetPoints: json['target_points'] as int,
      durationDays: json['duration_days'] as int,
      description: json['description'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'room_id': roomId,
        'target_points': targetPoints,
        'duration_days': durationDays,
        'description': description,
        'start_date': startDate.toIso8601String(),
      };

  bool get isActive {
    final endDate = startDate.add(Duration(days: durationDays));
    return DateTime.now().isBefore(endDate);
  }

  int get daysRemaining {
    final endDate = startDate.add(Duration(days: durationDays));
    final remaining = endDate.difference(DateTime.now()).inDays;
    return remaining.clamp(0, durationDays);
  }
}
