import 'dart:math' as math;

import 'war_types.dart';

/// An attacking unit on a base. Owned by the player who spawned it (actions cost
/// that player's resources). Gains XP from damage/kills/structures → levels up
/// → hits harder and lives longer.
class Troop {
  final String id;
  final String ownerId;
  final WarSide side;
  final TroopType type;
  int r, c;
  int hp;
  double xp;
  bool hasMoved = false;
  bool done = false; // acted this activation
  // garrison patrol anchor: defenders leash to their post and return to it
  int? homeR, homeC;
  // sticky AI objective (transient): commit to a target instead of circling
  int? objectiveKey;
  int objectiveAge = 0;
  // fractional movement accumulator (transient): speed without tile-skipping.
  // Starts charged so a fresh troop moves on its first activation.
  double movePoints = 1;

  Troop({
    required this.id,
    required this.ownerId,
    required this.side,
    required this.type,
    required this.r,
    required this.c,
    this.xp = 0,
    this.homeR,
    this.homeC,
  }) : hp = (kTroopSpecs[type]!.hp).toInt();

  /// Beats of clinging pitch left — burns 3/beat and SLOWS while it lasts.
  int burnRounds = 0;

  /// Beats of tar slow left (from Pitch Pot) — halves move, no burn damage.
  int tarRounds = 0;

  /// Fogger: one smoke drop per life.
  bool smokeUsed = false;

  TroopSpec get spec => kTroopSpecs[type]!;
  int get level => Xp.levelForXp(xp);
  int get maxHp => (spec.hp * Xp.bonus(level)).round();
  int get atk => (spec.atk * Xp.bonus(level)).round();
  int get moveBudget {
    var m = spec.moveBudget;
    if (burnRounds > 0 || tarRounds > 0) m = math.max(1, (m * 0.5).round());
    return m;
  }
  bool get alive => hp > 0;

  void gainXp(double amount) {
    final beforeLevel = level;
    xp += amount;
    if (level > beforeLevel) {
      // a promotion patches you up a bit — it does NOT make you immortal
      hp = (hp + (maxHp * 0.25).round()).clamp(0, maxHp);
    } else if (hp > maxHp) {
      hp = maxHp;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'o': ownerId,
        's': side.index,
        't': type.index,
        'r': r,
        'c': c,
        'hp': hp,
        'xp': xp,
        'hr': homeR,
        'hc': homeC,
        'bu': burnRounds,
        'tar': tarRounds,
        'sm': smokeUsed,
      };

  factory Troop.fromJson(Map<String, dynamic> j) {
    final t = Troop(
      id: j['id'] as String,
      ownerId: j['o'] as String,
      side: WarSide.values[(j['s'] as num).toInt()],
      type: TroopType.values[(j['t'] as num).toInt()],
      r: (j['r'] as num).toInt(),
      c: (j['c'] as num).toInt(),
      xp: (j['xp'] as num?)?.toDouble() ?? 0,
      homeR: (j['hr'] as num?)?.toInt(),
      homeC: (j['hc'] as num?)?.toInt(),
    );
    t.hp = (j['hp'] as num?)?.toInt() ?? t.maxHp;
    t.burnRounds = (j['bu'] as num?)?.toInt() ?? 0;
    t.tarRounds = (j['tar'] as num?)?.toInt() ?? 0;
    t.smokeUsed = j['sm'] == true;
    return t;
  }
}
