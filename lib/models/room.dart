class Room {
  final String id;
  final String name;
  final String adminId;
  final String roomCode;
  final int maxParticipants;
  final int? dailyGoalPoints;
  final DateTime? dailyGoalSetAt;
  final int streakMinimum;
  final DateTime createdAt;
  /// Hours without a real log before a wake/ghost card. `0` = disabled.
  final int idleNudgeHours;
  /// True when the room requires a password to join (from safe RPC projection).
  final bool requiresJoinPassword;

  const Room({
    required this.id,
    required this.name,
    required this.adminId,
    required this.roomCode,
    this.maxParticipants = 20,
    this.dailyGoalPoints,
    this.dailyGoalSetAt,
    this.streakMinimum = 10,
    required this.createdAt,
    this.idleNudgeHours = 48,
    this.requiresJoinPassword = false,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.round();
      return int.tryParse(v.toString());
    }

    String reqStr(String key) {
      final v = json[key];
      if (v == null || (v is String && v.isEmpty)) {
        throw FormatException('Room JSON missing "$key": $json');
      }
      return v.toString();
    }

    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      return DateTime.tryParse(s) ??
          DateTime.tryParse('${s}T00:00:00.000Z');
    }

    final created = parseTs(json['created_at']);
    if (created == null) {
      throw FormatException('Room JSON missing created_at: $json');
    }

    final idle = asInt(json['idle_nudge_hours']);
    final needsPw = json['join_password_required'] == true ||
        json['requires_join_password'] == true;

    return Room(
      id: reqStr('id'),
      name: reqStr('name'),
      adminId: reqStr('admin_id'),
      roomCode: reqStr('room_code'),
      maxParticipants: asInt(json['max_participants']) ?? 20,
      dailyGoalPoints: asInt(json['daily_goal_points']),
      dailyGoalSetAt: parseTs(json['daily_goal_set_at']),
      streakMinimum: asInt(json['streak_minimum']) ?? 10,
      createdAt: created,
      idleNudgeHours: idle ?? 48,
      requiresJoinPassword: needsPw,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'admin_id': adminId,
        'room_code': roomCode,
        'max_participants': maxParticipants,
        'daily_goal_points': dailyGoalPoints,
        'daily_goal_set_at': dailyGoalSetAt?.toIso8601String(),
        'streak_minimum': streakMinimum,
        'created_at': createdAt.toIso8601String(),
        'idle_nudge_hours': idleNudgeHours,
        'join_password_required': requiresJoinPassword,
      };

  Room copyWith({
    String? name,
    int? maxParticipants,
    int? dailyGoalPoints,
    DateTime? dailyGoalSetAt,
    int? streakMinimum,
    int? idleNudgeHours,
    bool? requiresJoinPassword,
  }) {
    return Room(
      id: id,
      name: name ?? this.name,
      adminId: adminId,
      roomCode: roomCode,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      dailyGoalPoints: dailyGoalPoints ?? this.dailyGoalPoints,
      dailyGoalSetAt: dailyGoalSetAt ?? this.dailyGoalSetAt,
      streakMinimum: streakMinimum ?? this.streakMinimum,
      createdAt: createdAt,
      idleNudgeHours: idleNudgeHours ?? this.idleNudgeHours,
      requiresJoinPassword:
          requiresJoinPassword ?? this.requiresJoinPassword,
    );
  }
}
