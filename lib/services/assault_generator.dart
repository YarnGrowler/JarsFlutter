import '../core/seeded_rng.dart';
import '../core/siege_config.dart';
import '../models/siege.dart';

/// Turns the league's calibrated opponent weekly total (`W_assault`) into a
/// scoutable siege plan: distributed over days (tempo) and fronts (shape),
/// with an optional signature spike. Pure + seeded — every device computes
/// the identical assault, and the crew can scout it in advance (§2.3).
///
/// Seeding:
/// - identity seed (roomId, divisionId, seasonIndex, opponentId): the
///   opponent's *personality* — tempo profile, signature/soft front, spike
///   days. Stable all season so scouting an opponent means something.
/// - week seed (identity + weekIndex): day-to-day magnitude wobble.
class AssaultGenerator {
  final SiegeConfig cfg;
  AssaultGenerator([SiegeConfig? config]) : cfg = config ?? SiegeConfig.instance;

  AssaultPlan generate({
    required String roomId,
    required String divisionId,
    required int seasonIndex,
    required int weekIndex,
    required String opponentId,
    required String opponentName,
    required double totalAssault,
  }) {
    final days = cfg.days;
    final fronts = cfg.frontCount;

    final idRng = SeededRng(seedFromParts(
        [roomId, divisionId, seasonIndex, opponentId, 'siege-identity']));
    final tempo = cfg.tempoProfiles[idRng.intRange(0, cfg.tempoProfiles.length)];
    final signatureFront = idRng.intRange(0, fronts);
    final softFront = fronts > 1
        ? (signatureFront + 1 + idRng.intRange(0, fronts - 1)) % fronts
        : signatureFront;

    final signatureDays = <int>[];
    if (cfg.signatureEnabled && cfg.maxSignatureDays > 0 && days >= 4) {
      final count = 1 + idRng.intRange(0, cfg.maxSignatureDays);
      // Spikes land mid-to-late week (days 2..days-1): scoutable drama.
      while (signatureDays.length < count) {
        final d = 2 + idRng.intRange(0, days - 2);
        if (!signatureDays.contains(d)) signatureDays.add(d);
      }
      signatureDays.sort();
    }

    final weekRng = SeededRng(seedFromParts(
        [roomId, divisionId, seasonIndex, opponentId, weekIndex, 'siege-week']));

    // 1. Day tempo curve (normalized).
    final dayW = List<double>.filled(days, 0);
    for (var d = 0; d < days; d++) {
      final t = days <= 1 ? 0.0 : d / (days - 1);
      double base;
      switch (tempo) {
        case 'lateSurge':
          base = 0.6 + 0.8 * t;
          break;
        case 'frontload':
          base = 1.4 - 0.8 * t;
          break;
        default: // steady
          base = 1.0;
      }
      dayW[d] = base * (1 + weekRng.range(-0.15, 0.15));
    }

    // 2. Front shape per day (normalized across fronts).
    final attack = List.generate(days, (_) => List<double>.filled(fronts, 0));
    for (var d = 0; d < days; d++) {
      final fw = List<double>.filled(fronts, 0);
      for (var f = 0; f < fronts; f++) {
        double base = 1.0;
        if (f == signatureFront) base = 1.35;
        if (f == softFront && softFront != signatureFront) base = 0.55;
        fw[f] = base * (1 + weekRng.range(-0.25, 0.25));
      }
      final fSum = fw.reduce((a, b) => a + b);
      for (var f = 0; f < fronts; f++) {
        attack[d][f] = dayW[d] * (fw[f] / fSum);
      }
    }

    // 3. Signature spike, then renormalize the WHOLE matrix to totalAssault.
    //    (The spec applies the spike without renormalizing, which would inflate
    //    the week total above the calibrated W_assault and break the ~50%
    //    balance guarantee. Renormalizing keeps the spike's relative shape AND
    //    the fairness calibration.)
    for (final d in signatureDays) {
      attack[d][signatureFront] *= cfg.signatureMultiplier;
    }
    var sum = 0.0;
    for (var d = 0; d < days; d++) {
      for (var f = 0; f < fronts; f++) {
        sum += attack[d][f];
      }
    }
    if (sum > 0) {
      final scale = totalAssault / sum;
      for (var d = 0; d < days; d++) {
        for (var f = 0; f < fronts; f++) {
          attack[d][f] *= scale;
        }
      }
    }

    return AssaultPlan(
      opponentId: opponentId,
      opponentName: opponentName,
      weekIndex: weekIndex,
      totalAssault: totalAssault,
      attack: attack,
      tempoProfile: tempo,
      signatureFront: signatureFront,
      softFront: softFront,
      signatureDays: signatureDays,
    );
  }

  /// Fuzzed scouting band for a cell, relative to the week's average cell.
  static ThreatBand band(AssaultPlan plan, int day, int front) {
    final cells = plan.attack.length * plan.attack[0].length;
    final avg = cells > 0 ? plan.totalAssault / cells : 0.0;
    final v = plan.attack[day][front];
    if (avg <= 0) return ThreatBand.medium;
    if (v < 0.6 * avg) return ThreatBand.light;
    if (v > 1.5 * avg) return ThreatBand.heavy;
    return ThreatBand.medium;
  }
}
