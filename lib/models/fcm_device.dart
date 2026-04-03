/// Row from [user_fcm_tokens] for the signed-in user.
class FcmDevice {
  final String id;
  final String platform;
  final DateTime? lastSeenAt;
  final String token;

  const FcmDevice({
    required this.id,
    required this.platform,
    required this.lastSeenAt,
    required this.token,
  });

  String get shortToken =>
      token.length <= 14 ? token : '${token.substring(0, 6)}…${token.substring(token.length - 6)}';

  factory FcmDevice.fromJson(Map<String, dynamic> json) {
    final seen = json['last_seen_at'];
    return FcmDevice(
      id: json['id'] as String,
      platform: (json['platform'] as String?) ?? 'unknown',
      lastSeenAt: seen is String ? DateTime.tryParse(seen) : null,
      token: json['token'] as String,
    );
  }
}
