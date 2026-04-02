class Exercise {
  final String id;
  final String roomId;
  final String name;
  final double points;
  final String icon;
  final String category;
  final bool supportsWeight;
  final double? weightThreshold;
  final double? weightMultiplier;
  final String createdBy;
  final DateTime createdAt;

  const Exercise({
    required this.id,
    required this.roomId,
    required this.name,
    required this.points,
    required this.icon,
    required this.category,
    this.supportsWeight = false,
    this.weightThreshold,
    this.weightMultiplier,
    required this.createdBy,
    required this.createdAt,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      name: json['name'] as String,
      points: (json['points'] as num).toDouble(),
      icon: json['icon'] as String,
      category: json['category'] as String,
      supportsWeight: json['supports_weight'] as bool? ?? false,
      weightThreshold: (json['weight_threshold'] as num?)?.toDouble(),
      weightMultiplier: (json['weight_multiplier'] as num?)?.toDouble(),
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'name': name,
        'points': points,
        'icon': icon,
        'category': category,
        'supports_weight': supportsWeight,
        'weight_threshold': weightThreshold,
        'weight_multiplier': weightMultiplier,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  double calculatePoints(int count, double? weight) {
    double base = points;
    if (weight != null && supportsWeight && weightThreshold != null) {
      final bonus =
          (weight / weightThreshold!).floor() * (weightMultiplier ?? 1.0);
      base += bonus;
    }
    return base * count;
  }
}
