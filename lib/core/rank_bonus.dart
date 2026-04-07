/// Rank multiplier for the current room leaderboard position.
///
/// This is applied **on top of** base points (and streak bonus, if any) at log time.
double rankBonusFraction(int rank) {
  switch (rank) {
    case 1:
      return 0.05;
    case 2:
      return 0.03;
    case 3:
      return 0.01;
    default:
      return 0.0;
  }
}

/// Whole points added from the rank bonus (rounded).
int rankBonusPointsRounded({
  required int pointsSoFar,
  required int rank,
}) {
  if (pointsSoFar <= 0) return 0;
  final f = rankBonusFraction(rank);
  if (f <= 0) return 0;
  return (pointsSoFar * f).round();
}

