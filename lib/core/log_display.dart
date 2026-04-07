import 'count_unit.dart';
import '../models/exercise_log.dart';

/// Human-readable quantity for a log row (feed, history, chips).
/// Uses [ExerciseLog.countUnit] when set; otherwise infers from exercise name.
String formatExerciseLogQuantityLine(ExerciseLog log) {
  final unit = log.effectiveCountUnit;
  final name = log.exerciseName;
  final c = log.count;
  final w = log.weight;

  String qty;
  switch (unit) {
    case CountUnit.reps:
      qty = '$c $name';
    case CountUnit.seconds:
      qty = '${formatSecondsAsHuman(c)} $name';
    case CountUnit.minutes:
      qty = '$c min $name';
  }

  if (w > 0) {
    qty += ' · ${w % 1 == 0 ? w.toInt() : w} lbs';
  }
  return qty;
}

/// Seconds → "45s", "2 min", or "2m 15s" (no misleading "121 plank").
String formatSecondsAsHuman(int totalSeconds) {
  if (totalSeconds < 60) return '${totalSeconds}s';
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  if (s == 0) return '$m min';
  return '${m}m ${s}s';
}

/// Subline when the exercise name is shown separately (e.g. log history list).
String formatExerciseLogDetailSubtitle(ExerciseLog log) {
  final unit = log.effectiveCountUnit;
  final c = log.count;
  final w = log.weight;
  String q;
  switch (unit) {
    case CountUnit.reps:
      q = '$c reps';
    case CountUnit.seconds:
      q = formatSecondsAsHuman(c);
    case CountUnit.minutes:
      q = '$c min';
  }
  if (w > 0) {
    q += ' · ${w % 1 == 0 ? w.toInt() : w} lbs';
  }
  return q;
}
