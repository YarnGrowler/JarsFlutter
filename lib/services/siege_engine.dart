import '../core/siege_config.dart';
import '../models/siege.dart';

/// Pure siege resolver (§2.4). No clock, no I/O, no randomness — everything is
/// a function of (assault plan, supply events, allocation events, resolved-day
/// count), so every device and the DebugSimulator agree bit-for-bit.
///
/// Bank model: supply accrues from logs; allocations are processed in
/// (createdAt, id) order and each is clamped to the bank available at its
/// commit moment. Allocations targeting an already-resolved day (created
/// after the target day) are ignored. Unspent supply stays banked — a missed
/// day never wastes anyone's points.
///
/// Damage model (relative — see SiegeConfig docs):
///   integrityLoss(day) = breach(day) / totalAssault × 100 × damageFactor
class SiegeEngine {
  final SiegeConfig cfg;
  SiegeEngine([SiegeConfig? config]) : cfg = config ?? SiegeConfig.instance;

  SiegeWeekState resolveWeek({
    required AssaultPlan plan,
    required List<SupplyEvent> supply,
    required List<SiegeAllocation> allocations,
    required int daysResolved,
  }) {
    final days = cfg.days;
    final fronts = cfg.frontCount;
    final resolved = daysResolved.clamp(0, days);

    // ── bank pass: accept allocations in commit order, clamped to the bank ──
    final supplySorted = List<SupplyEvent>.from(supply)
      ..sort((a, b) {
        final c = a.at.compareTo(b.at);
        return c != 0 ? c : a.userId.compareTo(b.userId);
      });
    final allocSorted = List<SiegeAllocation>.from(allocations)
      ..sort((a, b) {
        final c = a.at.compareTo(b.at);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

    var totalSupply = 0.0;
    for (final s in supplySorted) {
      totalSupply += s.amount;
    }

    final defense = List.generate(days, (_) => List<double>.filled(fronts, 0));
    var accepted = 0.0;
    var supplyIdx = 0;
    var earnedSoFar = 0.0;
    for (final a in allocSorted) {
      // supply earned up to (and including) this allocation's moment
      while (supplyIdx < supplySorted.length &&
          !supplySorted[supplyIdx].at.isAfter(a.at)) {
        earnedSoFar += supplySorted[supplyIdx].amount;
        supplyIdx++;
      }
      if (a.day < 0 || a.day >= days) continue;
      if (a.front < 0 || a.front >= fronts) continue;
      if (a.day < a.createdDayIndex) continue; // can't defend the past
      final bank = earnedSoFar - accepted;
      if (bank <= 0) continue;
      final take = a.amount < bank ? a.amount : bank;
      if (take <= 0) continue;
      defense[a.day][a.front] += take;
      accepted += take;
    }

    // ── wave resolution ─────────────────────────────────────────────────────
    var integrity = cfg.integrityStart.toDouble();
    int? breachDay;
    final waves = <WaveResult>[];
    for (var d = 0; d < resolved; d++) {
      final before = integrity;
      final frontResults = <WaveFrontResult>[];
      var breachTotal = 0.0;
      for (var f = 0; f < fronts; f++) {
        final atk = plan.attack[d][f];
        final def = defense[d][f];
        final breach = (atk - def) > 0 ? (atk - def) : 0.0;
        breachTotal += breach;
        frontResults.add(WaveFrontResult(
            front: f, attack: atk, defense: def, breach: breach));
      }
      if (plan.totalAssault > 0) {
        integrity -=
            breachTotal / plan.totalAssault * 100.0 * cfg.damageFactor;
      }
      if (integrity < 0) integrity = 0;
      if (integrity == 0 && breachDay == null && breachTotal > 0) {
        breachDay = d;
      }
      waves.add(WaveResult(
        day: d,
        fronts: frontResults,
        integrityBefore: before,
        integrityAfter: integrity,
      ));
      // The siege ends the moment the stronghold falls — resolving further
      // days would produce phantom "held" waves against a 0-integrity clamp.
      if (breachDay != null) break;
    }

    SiegeResult? result;
    if (breachDay != null) {
      result = SiegeResult(won: false, integrityRemaining: 0, breachDay: breachDay);
    } else if (resolved >= days) {
      result = SiegeResult(won: integrity > 0, integrityRemaining: integrity);
    }

    return SiegeWeekState(
      plan: plan,
      integrity: integrity,
      daysResolved: resolved,
      waves: waves,
      totalSupply: totalSupply,
      allocatedSupply: accepted,
      bankRemaining: totalSupply - accepted,
      defense: defense,
      result: result,
    );
  }
}
