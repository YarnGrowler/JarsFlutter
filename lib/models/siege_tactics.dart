import '../core/seeded_rng.dart';

/// The three things that come at your walls. The whole point of the redesign:
/// one defense can't answer all three, so raw supply never auto-wins.
enum AttackType { infantry, ram, archer }

extension AttackTypeMeta on AttackType {
  String get icon {
    switch (this) {
      case AttackType.infantry:
        return '🗡';
      case AttackType.ram:
        return '🐏';
      case AttackType.archer:
        return '🏹';
    }
  }

  String get label {
    switch (this) {
      case AttackType.infantry:
        return 'Infantry';
      case AttackType.ram:
        return 'Rams';
      case AttackType.archer:
        return 'Archers';
    }
  }

  /// One-line "how do I stop this" for the scouting UI.
  String get counter {
    switch (this) {
      case AttackType.infantry:
        return 'Walls stop them — reinforce this front.';
      case AttackType.ram:
        return 'Walls barely slow them — pour Boiling Oil.';
      case AttackType.archer:
        return 'They shoot over walls — need a Roof (Fortify) or a Volley.';
    }
  }
}

/// Incoming stacks on one front for one night.
class FrontIncoming {
  final double infantry;
  final double ram;
  final double archer;
  const FrontIncoming(this.infantry, this.ram, this.archer);

  double get total => infantry + ram + archer;
  double byType(AttackType t) {
    switch (t) {
      case AttackType.infantry:
        return infantry;
      case AttackType.ram:
        return ram;
      case AttackType.archer:
        return archer;
    }
  }

  /// The dominant threat, for at-a-glance scouting.
  AttackType get dominant {
    if (ram >= infantry && ram >= archer) return AttackType.ram;
    if (archer >= infantry && archer >= ram) return AttackType.archer;
    return AttackType.infantry;
  }
}

/// The tactical cards. A limited number can be played per night (command
/// slots), each costs supply — so you answer the night's composition, you don't
/// brute-force it.
enum TacticKind { oil, volley, shieldwall, rally, repair }

extension TacticMeta on TacticKind {
  String get icon {
    switch (this) {
      case TacticKind.oil:
        return '🛢';
      case TacticKind.volley:
        return '🏹';
      case TacticKind.shieldwall:
        return '🛡';
      case TacticKind.rally:
        return '🚩';
      case TacticKind.repair:
        return '🔧';
    }
  }

  String get name {
    switch (this) {
      case TacticKind.oil:
        return 'Boiling Oil';
      case TacticKind.volley:
        return 'Archer Volley';
      case TacticKind.shieldwall:
        return 'Shieldwall';
      case TacticKind.rally:
        return 'Rally';
      case TacticKind.repair:
        return 'Repair';
    }
  }

  String get blurb {
    switch (this) {
      case TacticKind.oil:
        return 'Negates ALL rams on one front tonight.';
      case TacticKind.volley:
        return 'Chips every incoming stack on every front — the archer answer.';
      case TacticKind.shieldwall:
        return 'Flat defense to all three fronts.';
      case TacticKind.rally:
        return 'Your reinforcements count +50% tonight.';
      case TacticKind.repair:
        return 'Rebuilds cracked walls and patches the keep (+8 integrity).';
    }
  }

  /// True if the tactic needs a target front (oil).
  bool get needsFront => this == TacticKind.oil;
}

/// What the player has committed for tonight.
class NightPlan {
  final List<double> reinforce; // supply placed on each front tonight
  final List<double> fortifyWall; // persistent wall bonus per front
  final List<double> fortifyRoof; // persistent archer cover per front
  final List<bool> wallDamaged; // fronts breached earlier (weakened)
  final List<TacticKind> tactics; // played tonight
  final int? oilFront; // oil target, if oil played
  final int morale; // 0..5

  const NightPlan({
    required this.reinforce,
    required this.fortifyWall,
    required this.fortifyRoof,
    required this.wallDamaged,
    required this.tactics,
    required this.oilFront,
    required this.morale,
  });

  bool has(TacticKind t) => tactics.contains(t);
}

/// Per-front breakdown after resolution.
class FrontResolve {
  final int front;
  final double incoming;
  final double stopped;
  final double breach;
  final double infantryBreach;
  final double ramBreach;
  final double archerBreach;
  const FrontResolve({
    required this.front,
    required this.incoming,
    required this.stopped,
    required this.breach,
    required this.infantryBreach,
    required this.ramBreach,
    required this.archerBreach,
  });
  bool get held => breach <= 0.000001;
}

class NightResolve {
  final List<FrontResolve> fronts;
  const NightResolve(this.fronts);
  double get totalBreach =>
      fronts.fold(0.0, (a, f) => a + f.breach);
  double get totalIncoming =>
      fronts.fold(0.0, (a, f) => a + f.incoming);
  bool get flawless => fronts.every((f) => f.held);
}

/// Pure night resolver — the heart of the redesign. No state, fully testable.
///
/// Each front resolves per attack type against the matching defense:
///   • Infantry ← wall defense (reinforce + fortify wall), morale/rally scaled
///   • Rams     ← wall defense × 0.35 only, UNLESS Boiling Oil (then negated)
///   • Archers  ← roof (fortify) + volley only; walls do nothing
/// A Volley chips a flat amount off every stack first; Shieldwall adds flat
/// defense everywhere; a damaged wall is 25% weaker until Repaired.
class SiegeTactics {
  static const double ramWallFactor = 0.35; // walls vs rams, sans oil
  static const double reinforceRoof = 0.0; // manning walls ≠ stopping arrows
  static const double moralePerPoint = 0.08; // +8% troop effectiveness / morale
  static const double damagedWallPenalty = 0.25;

  static NightResolve resolveNight(
    List<FrontIncoming> incoming,
    NightPlan plan, {
    double volleyValue = 0,
    double shieldwallValue = 0,
  }) {
    final fronts = incoming.length;
    final moraleMult = 1 + moralePerPoint * plan.morale;
    final rallyMult = plan.has(TacticKind.rally) ? 1.5 : 1.0;
    final volley = plan.has(TacticKind.volley) ? volleyValue : 0.0;
    final shield = plan.has(TacticKind.shieldwall) ? shieldwallValue : 0.0;

    final results = <FrontResolve>[];
    for (var f = 0; f < fronts; f++) {
      final inc = incoming[f];
      final damaged = f < plan.wallDamaged.length && plan.wallDamaged[f];
      final damageMult = damaged ? (1 - damagedWallPenalty) : 1.0;

      // Wall pool (vs infantry & partially rams): troops + fortification.
      final wall = ((plan.reinforce[f] * rallyMult + plan.fortifyWall[f]) *
                  moraleMult +
              shield) *
          damageMult;
      // Roof pool (vs archers): structural only + shieldwall half + volley.
      final roof = plan.fortifyRoof[f] + shield * 0.5;
      final oilHere = plan.oilFront == f && plan.has(TacticKind.oil);

      // Volley chips each stack first (flat, per front).
      final inf = (inc.infantry - volley).clamp(0.0, double.infinity);
      final ram = (inc.ram - volley).clamp(0.0, double.infinity);
      final arc = (inc.archer - volley).clamp(0.0, double.infinity);

      // Infantry & rams draw from the same wall pool; infantry first.
      var pool = wall;
      final infBreach = (inf - pool).clamp(0.0, double.infinity);
      pool = (pool - inf).clamp(0.0, double.infinity);

      final double ramBreach;
      if (oilHere) {
        ramBreach = 0; // oil obliterates rams on this front
      } else {
        // Only a fraction of remaining wall bites into rams.
        final ramDef = pool * ramWallFactor;
        ramBreach = (ram - ramDef).clamp(0.0, double.infinity);
      }

      final archBreach = (arc - roof).clamp(0.0, double.infinity);

      final breach = infBreach + ramBreach + archBreach;
      results.add(FrontResolve(
        front: f,
        incoming: inc.total,
        stopped: (inc.total - breach).clamp(0.0, double.infinity),
        breach: breach,
        infantryBreach: infBreach,
        ramBreach: ramBreach,
        archerBreach: archBreach,
      ));
    }
    return NightResolve(results);
  }

  /// Deterministic composition for a front on a night: splits the calibrated
  /// attack total into infantry/ram/archer, escalating toward heavier siege
  /// weapons late and on the signature front.
  static FrontIncoming composition({
    required double total,
    required int night,
    required int totalNights,
    required int front,
    required bool signatureFront,
    required bool signatureDay,
    required bool softFront,
    required List<Object> seedParts,
  }) {
    if (total <= 0) return const FrontIncoming(0, 0, 0);
    final t = totalNights > 1 ? night / (totalNights - 1) : 0.5;
    var infW = 0.66 - 0.28 * t;
    var ramW = 0.17 + 0.23 * t;
    var arcW = 0.17 + 0.23 * t;

    if (signatureDay && signatureFront) ramW += 0.45; // the ram to the gate
    if (softFront) infW += 0.5; // barely-touched front stays simple

    final rng = SeededRng(seedFromParts(seedParts));
    infW *= 0.85 + rng.unit() * 0.3;
    ramW *= 0.85 + rng.unit() * 0.3;
    arcW *= 0.85 + rng.unit() * 0.3;

    final sum = infW + ramW + arcW;
    final inf = total * infW / sum;
    final ram = total * ramW / sum;
    final arc = total * arcW / sum;
    return FrontIncoming(
        inf.roundToDouble(), ram.roundToDouble(), arc.roundToDouble());
  }
}
