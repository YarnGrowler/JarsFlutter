class AppBadge {
  final String id;
  final String userId;
  final String roomId;
  final String type;
  final DateTime awardedAt;
  final Map<String, dynamic>? metadata;

  const AppBadge({
    required this.id,
    required this.userId,
    required this.roomId,
    required this.type,
    required this.awardedAt,
    this.metadata,
  });

  factory AppBadge.fromJson(Map<String, dynamic> json) {
    return AppBadge(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      roomId: json['room_id'] as String,
      type: json['type'] as String,
      awardedAt: DateTime.parse(json['awarded_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'room_id': roomId,
        'type': type,
        'metadata': metadata,
      };

  String get displayEmoji {
    switch (type) {
      case 'gold_medal':   return '🥇';
      case 'silver_medal': return '🥈';
      case 'bronze_medal': return '🥉';
      case 'streak_7':     return '🔥';
      case 'streak_30':    return '🏆';
      case 'first_log':    return '⚡';
      default:             return '🎖️';
    }
  }

  String get displayLabel {
    switch (type) {
      case 'gold_medal':   return 'Gold Medal';
      case 'silver_medal': return 'Silver Medal';
      case 'bronze_medal': return 'Bronze Medal';
      case 'streak_7':     return '7-Day Streak';
      case 'streak_30':    return '30-Day Streak';
      case 'first_log':    return 'First Log';
      default:             return type;
    }
  }

  String? get displayRoom => metadata?['room_name'] as String?;
  int?    get displayRank  => metadata?['rank'] as int?;
}
