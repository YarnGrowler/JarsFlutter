import 'dart:math' as math;

/// Streak multiplier curve (asymptotic max 25%): \(y = 0.25(1 - e^{-x/10})\).
/// [streakDays] is current streak length (days) after a qualifying log.
double streakBonusFraction(int streakDays) {
  if (streakDays < 1) return 0;
  return 0.25 * (1 - math.exp(-streakDays / 10));
}

/// Whole points added from the streak bonus (rounded).
int streakBonusPointsRounded({
  required double basePoints,
  required int streakDaysForBonus,
}) {
  if (basePoints <= 0 || streakDaysForBonus < 1) return 0;
  return (basePoints * streakBonusFraction(streakDaysForBonus)).round();
}
