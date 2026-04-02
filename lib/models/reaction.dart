class Reaction {
  final String id;
  final String logId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  const Reaction({
    required this.id,
    required this.logId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      id: json['id'] as String,
      logId: json['log_id'] as String,
      userId: json['user_id'] as String,
      emoji: json['emoji'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'log_id': logId,
        'user_id': userId,
        'emoji': emoji,
      };
}

const kReactionEmojis = ['🔥', '💀', '😤'];
