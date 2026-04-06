/// How [Exercise.count] is interpreted for display and the rep/time picker.
enum CountUnit {
  reps,
  seconds,
  minutes,
}

extension CountUnitX on CountUnit {
  /// Short label for UI ("reps", "sec", "min").
  String get shortLabel {
    switch (this) {
      case CountUnit.reps:
        return 'reps';
      case CountUnit.seconds:
        return 'sec';
      case CountUnit.minutes:
        return 'min';
    }
  }

  String get pickerHint {
    switch (this) {
      case CountUnit.reps:
        return 'reps';
      case CountUnit.seconds:
        return 'seconds';
      case CountUnit.minutes:
        return 'minutes';
    }
  }
}

CountUnit countUnitFromJson(dynamic v) {
  if (v == null) return CountUnit.reps;
  final s = v.toString().toLowerCase().trim();
  switch (s) {
    case 'seconds':
    case 'sec':
    case 's':
      return CountUnit.seconds;
    case 'minutes':
    case 'min':
    case 'm':
      return CountUnit.minutes;
    default:
      return CountUnit.reps;
  }
}

/// Heuristic when DB has no column yet.
CountUnit inferCountUnitFromExerciseName(String name, {String category = ''}) {
  final n = name.toLowerCase();
  // Short holds — log seconds (plank UI when name matches [exerciseUsesTimerUi]).
  if (n.contains('plank') ||
      n.contains('l-sit') ||
      n.contains('wall sit') ||
      n.contains('dead hang') ||
      (n.contains('hold') && n.contains('sec'))) {
    return CountUnit.seconds;
  }
  // Block cardio / sports named "(5 min)" — log whole minutes (pts × minutes).
  if (n.contains('(5 min)') ||
      n.contains('(5min)') ||
      (n.contains('5 min') && !n.contains('mile'))) {
    return CountUnit.minutes;
  }
  final c = category.toLowerCase().trim();
  if (c == 'sports' || c.contains('sport')) {
    return CountUnit.minutes;
  }
  if (n.contains('marathon')) {
    return CountUnit.minutes;
  }
  if ((n.contains('run') || n.contains('jog')) && n.contains('minute')) {
    return CountUnit.minutes;
  }
  if (n.contains('minute') && !n.contains('rep')) {
    return CountUnit.minutes;
  }
  return CountUnit.reps;
}

/// How [Exercise.points] applies when [CountUnit.seconds] (per-second vs per-minute of time).
enum TimePointsMode {
  /// `points` is multiplied by whole seconds logged.
  perSecond,
  /// `points` is multiplied by (seconds / 60), i.e. points are "per minute of time".
  perMinute,
}

TimePointsMode timePointsModeFromJson(dynamic v) {
  if (v == null) return TimePointsMode.perMinute;
  final s = v.toString().toLowerCase().trim();
  if (s == 'per_second' || s == 'second' || s == 'sec' || s == 's') {
    return TimePointsMode.perSecond;
  }
  return TimePointsMode.perMinute;
}

String timePointsModeToJson(TimePointsMode m) {
  switch (m) {
    case TimePointsMode.perSecond:
      return 'per_second';
    case TimePointsMode.perMinute:
      return 'per_minute';
  }
}

/// When DB has no `time_points_mode`, infer from name + unit (e.g. plank → per sec, volleyball → per min).
TimePointsMode inferTimePointsMode(
  String name, {
  required CountUnit countUnit,
}) {
  if (countUnit != CountUnit.seconds) {
    return TimePointsMode.perMinute;
  }
  final n = name.toLowerCase();
  if (n.contains('plank') ||
      n.contains('l-sit') ||
      n.contains('wall sit') ||
      n.contains('dead hang')) {
    return TimePointsMode.perSecond;
  }
  return TimePointsMode.perMinute;
}

/// Plank-style stopwatch UI (tap = start/pause), not tap-to-add-seconds.
bool exerciseUsesTimerUi(String name, CountUnit countUnit) {
  if (countUnit != CountUnit.seconds) return false;
  final n = name.toLowerCase();
  return n.contains('plank') ||
      n.contains('l-sit') ||
      n.contains('wall sit') ||
      n.contains('dead hang') ||
      (n.contains('hold') && n.contains('sec'));
}
