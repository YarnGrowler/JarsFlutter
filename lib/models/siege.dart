/// Siege game-mode models. Everything here is plain data — the engine
/// (`services/siege_engine.dart`) and generator (`services/assault_generator.dart`)
/// are pure functions over these, which is what keeps Siege deterministic and
/// simulatable (commit-then-simulate — see docs in the build spec).
library;

/// The AI opponent's committed, scoutable plan for the week.
class AssaultPlan {
  final String opponentId;
  final String opponentName;
  final int weekIndex; // week-in-season
  final double totalAssault; // = the league's calibrated W_assault
  /// attack[day][front] — sums (≈, after rounding) to [totalAssault].
  final List<List<double>> attack;
  final String tempoProfile; // steady | lateSurge | frontload
  final int signatureFront; // the front they hammer
  final int softFront; // the front they barely touch
  final List<int> signatureDays; // days the signature spike lands ([] if off)

  const AssaultPlan({
    required this.opponentId,
    required this.opponentName,
    required this.weekIndex,
    required this.totalAssault,
    required this.attack,
    required this.tempoProfile,
    required this.signatureFront,
    required this.softFront,
    required this.signatureDays,
  });

  double dayTotal(int d) {
    var t = 0.0;
    for (final v in attack[d]) {
      t += v;
    }
    return t;
  }
}

/// Forecast band for fuzzed scouting.
enum ThreatBand { light, medium, heavy }

/// Supply arriving from a real (or bot) workout log.
class SupplyEvent {
  final String userId;
  final double amount; // points × supplyPerPoint
  final int dayIndex; // 0-based day within the siege week
  final DateTime at; // ordering key for the bank

  const SupplyEvent({
    required this.userId,
    required this.amount,
    required this.dayIndex,
    required this.at,
  });
}

/// A crew member committing supply from the bank onto a (day, front) cell.
class SiegeAllocation {
  final String userId;
  final int day;
  final int front;
  final double amount; // requested; engine clamps to the bank at commit time
  final int createdDayIndex; // day the commit happened (can't defend the past)
  final DateTime at; // ordering key
  final String id; // tiebreak for identical timestamps

  const SiegeAllocation({
    required this.userId,
    required this.day,
    required this.front,
    required this.amount,
    required this.createdDayIndex,
    required this.at,
    required this.id,
  });
}

class WaveFrontResult {
  final int front;
  final double attack;
  final double defense;
  final double breach;
  bool get held => breach <= 0.000001;

  const WaveFrontResult({
    required this.front,
    required this.attack,
    required this.defense,
    required this.breach,
  });
}

class WaveResult {
  final int day;
  final List<WaveFrontResult> fronts;
  final double integrityBefore;
  final double integrityAfter;

  const WaveResult({
    required this.day,
    required this.fronts,
    required this.integrityBefore,
    required this.integrityAfter,
  });

  double get totalBreach {
    var t = 0.0;
    for (final f in fronts) {
      t += f.breach;
    }
    return t;
  }

  bool get held => integrityAfter >= integrityBefore - 0.000001;
}

class SiegeResult {
  final bool won;
  final double integrityRemaining;
  final int? breachDay; // day the stronghold fell (null on a hold)

  const SiegeResult({
    required this.won,
    required this.integrityRemaining,
    this.breachDay,
  });
}

/// Full computed state of the current siege week (what the UI renders).
class SiegeWeekState {
  final AssaultPlan plan;
  final double integrity;
  final int daysResolved; // waves 0..daysResolved-1 are final
  final List<WaveResult> waves;
  final double totalSupply; // all supply earned this week (so far)
  final double allocatedSupply; // accepted allocations total
  final double bankRemaining; // totalSupply - allocatedSupply
  /// Accepted (effective) allocation per [day][front].
  final List<List<double>> defense;
  final SiegeResult? result; // non-null once won/lost is decided

  const SiegeWeekState({
    required this.plan,
    required this.integrity,
    required this.daysResolved,
    required this.waves,
    required this.totalSupply,
    required this.allocatedSupply,
    required this.bankRemaining,
    required this.defense,
    this.result,
  });
}

/// Debug-only AI teammate that logs workouts automatically (client-side).
class BotMember {
  final String id;
  final String name;
  final double activeProbability; // chance the bot logs on a given day
  final double meanDailyPoints;
  final double variance; // stddev of the daily roll

  const BotMember({
    required this.id,
    required this.name,
    required this.activeProbability,
    required this.meanDailyPoints,
    required this.variance,
  });

  static const presets = <BotMember>[
    BotMember(
        id: 'bot_casey',
        name: 'Consistent Casey 🤖',
        activeProbability: 0.95,
        meanDailyPoints: 130,
        variance: 20),
    BotMember(
        id: 'bot_wade',
        name: 'Weekend Warrior Wade 🤖',
        activeProbability: 0.45,
        meanDailyPoints: 260,
        variance: 90),
    BotMember(
        id: 'bot_finn',
        name: 'Flaky Finn 🤖',
        activeProbability: 0.55,
        meanDailyPoints: 80,
        variance: 60),
  ];
}
