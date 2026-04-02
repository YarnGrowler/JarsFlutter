class Profile {
  final String id;
  final String username;
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.username,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'created_at': createdAt.toIso8601String(),
      };
}
