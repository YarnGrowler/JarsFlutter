import '../core/count_unit.dart';

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

  /// How [points] × count is interpreted (reps vs time).
  final CountUnit countUnit;

  /// For [CountUnit.seconds] only: per-second vs per-minute scoring. Null → [inferTimePointsMode].
  final TimePointsMode? timePointsMode;

  /// From DB `uses_time`: logging counts time (seconds/minutes), not reps.
  final bool usesTime;

  /// From DB `timer_ui`: stopwatch tap UI (plank-style).
  final bool timerUiPreferred;

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
    this.countUnit = CountUnit.reps,
    this.timePointsMode,
    this.usesTime = false,
    this.timerUiPreferred = false,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final cat = json['category'] as String? ?? '';
    final inferred = inferCountUnitFromExerciseName(name, category: cat);
    final raw = json['count_unit'];
    final CountUnit unit;
    if (raw == null || raw.toString().trim().isEmpty) {
      unit = inferred;
    } else {
      // Trust persisted `count_unit` when present (backfill + admin corrections).
      unit = countUnitFromJson(raw);
    }
    final tpmRaw = json['time_points_mode'];
    // Only seconds exercises use time_points_mode; ignore stray DB values on minutes/reps.
    final TimePointsMode? tpm = unit == CountUnit.seconds
        ? (tpmRaw != null
            ? timePointsModeFromJson(tpmRaw)
            : inferTimePointsMode(name, countUnit: unit))
        : null;
    final usesTimeJson = json['uses_time'];
    final usesTime = usesTimeJson is bool
        ? usesTimeJson
        : (unit == CountUnit.seconds || unit == CountUnit.minutes);
    final timerJson = json['timer_ui'];
    final timerUi = timerJson is bool ? timerJson : false;
    return Exercise(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      name: name,
      points: (json['points'] as num).toDouble(),
      icon: json['icon'] as String,
      category: json['category'] as String,
      supportsWeight: json['supports_weight'] as bool? ?? false,
      weightThreshold: (json['weight_threshold'] as num?)?.toDouble(),
      weightMultiplier: (json['weight_multiplier'] as num?)?.toDouble(),
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      countUnit: unit,
      timePointsMode: tpm,
      usesTime: usesTime,
      timerUiPreferred: timerUi,
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
        'count_unit': countUnit.name,
        if (countUnit == CountUnit.seconds && timePointsMode != null)
          'time_points_mode': timePointsModeToJson(timePointsMode!),
        'uses_time': usesTime,
        'timer_ui': timerUiPreferred,
      };

  /// Stopwatch UI: DB flag first, then name heuristic ([exerciseUsesTimerUi]).
  bool get effectiveTimerUi =>
      timerUiPreferred || exerciseUsesTimerUi(name, countUnit);

  TimePointsMode get _effectiveTimePointsMode =>
      timePointsMode ??
      inferTimePointsMode(name, countUnit: countUnit);

  /// e.g. `1 pts/min` for timed court sports; `1 pts/sec` for planks.
  String get pointsPerUnitLabel {
    final p =
        points % 1 == 0 ? points.toStringAsFixed(0) : points.toStringAsFixed(1);
    switch (countUnit) {
      case CountUnit.reps:
        return '$p pts/rep';
      case CountUnit.minutes:
        return '$p pts/min';
      case CountUnit.seconds:
        switch (_effectiveTimePointsMode) {
          case TimePointsMode.perSecond:
            return '$p pts/sec';
          case TimePointsMode.perMinute:
            return '$p pts/min';
        }
    }
  }

  double calculatePoints(int count, double? weight) {
    double base = points;
    if (weight != null && supportsWeight && weightThreshold != null) {
      final bonus =
          (weight / weightThreshold!).floor() * (weightMultiplier ?? 1.0);
      base += bonus;
    }
    switch (countUnit) {
      case CountUnit.reps:
      case CountUnit.minutes:
        return base * count;
      case CountUnit.seconds:
        switch (_effectiveTimePointsMode) {
          case TimePointsMode.perSecond:
            return base * count;
          case TimePointsMode.perMinute:
            return base * (count / 60.0);
        }
    }
  }
}
