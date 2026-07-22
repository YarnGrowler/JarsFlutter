import 'war_types.dart';

/// One clan's aggregate war performance (fed into the verdict + battle report).
class ClanTally {
  final WarSide side;
  double destructionDealt; // 0..100 on the OTHER clan's base
  bool razedEnemy; // fully razed the enemy base
  int enemyFellAtMin; // sim-minute the enemy base fully fell (-1 if it didn't)
  int troopsLost;
  double resourcesSpent;
  ClanTally(this.side,
      {this.destructionDealt = 0,
      this.razedEnemy = false,
      this.enemyFellAtMin = -1,
      this.troopsLost = 0,
      this.resourcesSpent = 0});
}

class WarVerdict {
  final WarSide? winner; // null = genuine draw
  final bool knockout;
  final String headline;
  final List<String> reasons;
  const WarVerdict(this.winner, this.knockout, this.headline, this.reasons);
}

/// Decides the war. Primary: destruction %. A full raze is a knockout. Ties
/// break on who razed faster → fewer troops lost → fewer resources spent — the
/// multi-factor "who was better tactically" the user asked for.
class WarScoring {
  static WarVerdict decide(ClanTally you, ClanTally foe) {
    final youKO = you.razedEnemy;
    final foeKO = foe.razedEnemy;

    if (youKO && !foeKO) {
      return WarVerdict(WarSide.you, true, 'FLAWLESS VICTORY',
          ['You razed the enemy stronghold; they never finished yours.']);
    }
    if (foeKO && !youKO) {
      return WarVerdict(WarSide.enemy, true, 'DEFEAT',
          ['They razed your stronghold; you never finished theirs.']);
    }

    final reasons = <String>[];
    // 1) destruction %
    if ((you.destructionDealt - foe.destructionDealt).abs() > 0.5) {
      final win = you.destructionDealt > foe.destructionDealt;
      reasons.add(
          'Destruction: you ${you.destructionDealt.round()}% vs ${foe.destructionDealt.round()}%.');
      return WarVerdict(win ? WarSide.you : WarSide.enemy, youKO && foeKO,
          win ? 'VICTORY' : 'DEFEAT', reasons);
    }
    reasons.add('Destruction level (~${you.destructionDealt.round()}%).');

    // 2) who razed faster (if both KO'd)
    if (youKO && foeKO && you.enemyFellAtMin != foe.enemyFellAtMin) {
      final win = you.enemyFellAtMin < foe.enemyFellAtMin;
      reasons.add(
          'Speed: you finished them at ${_hm(you.enemyFellAtMin)} vs ${_hm(foe.enemyFellAtMin)}.');
      return WarVerdict(win ? WarSide.you : WarSide.enemy, true,
          win ? 'VICTORY ON SPEED' : 'DEFEAT ON SPEED', reasons);
    }

    // 3) fewer troops lost
    if (you.troopsLost != foe.troopsLost) {
      final win = you.troopsLost < foe.troopsLost;
      reasons.add('Losses: you lost ${you.troopsLost} vs ${foe.troopsLost}.');
      return WarVerdict(win ? WarSide.you : WarSide.enemy, false,
          win ? 'VICTORY ON LOSSES' : 'DEFEAT ON LOSSES', reasons);
    }

    // 4) fewer resources spent (efficiency)
    if ((you.resourcesSpent - foe.resourcesSpent).abs() > 0.5) {
      final win = you.resourcesSpent < foe.resourcesSpent;
      reasons.add(
          'Efficiency: you spent ${you.resourcesSpent.round()} vs ${foe.resourcesSpent.round()}.');
      return WarVerdict(win ? WarSide.you : WarSide.enemy, false,
          win ? 'VICTORY ON EFFICIENCY' : 'DEFEAT ON EFFICIENCY', reasons);
    }

    reasons.add('Dead even on every measure.');
    return WarVerdict(null, false, 'STALEMATE', reasons);
  }

  static String _hm(int mins) {
    if (mins < 0) return '—';
    final h = mins ~/ 60, m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
