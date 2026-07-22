import 'package:flutter_test/flutter_test.dart';
import 'package:jars/core/league_config.dart';
import 'package:jars/core/siege_config.dart';
import 'package:jars/models/league.dart';
import 'package:jars/models/siege.dart';
import 'package:jars/services/assault_generator.dart';
import 'package:jars/services/league_simulator.dart';
import 'package:jars/services/siege_engine.dart';

void main() {
  final scfg = SiegeConfig.fallback;
  final lcfg = LeagueConfig.instance;
  final gen = AssaultGenerator(scfg);
  final engine = SiegeEngine(scfg);
  final lsim = LeagueSimulator(lcfg);
  final gold = lcfg.divisionById('gold')!;

  const members = 4;
  const anchorPerMember = 300.0;
  const weeklySupply = anchorPerMember * members; // "average logging"

  /// The real calibrated opponent total for a seeded room/week.
  double assaultFor(String roomId, LeagueDivision div, int week) {
    final live = lsim.matchForWeek(
      roomId: roomId,
      division: div,
      seasonIndex: 0,
      week: week,
      yourWeeklyPoints: List<int>.filled(lcfg.matchweeks, weeklySupply.round()),
      yourActiveMembers: members,
      anchorPerMember: anchorPerMember,
    );
    return (live?.opponentScore ?? weeklySupply).toDouble();
  }

  AssaultPlan planFor(String roomId, LeagueDivision div, {int week = 0}) {
    return gen.generate(
      roomId: roomId,
      divisionId: div.id,
      seasonIndex: 0,
      weekIndex: week,
      opponentId: 'ai_2',
      opponentName: 'Test FC',
      totalAssault: assaultFor(roomId, div, week),
    );
  }

  /// Equal supply each day, at day-start timestamps.
  List<SupplyEvent> equalSupply({double total = weeklySupply}) => [
        for (var d = 0; d < scfg.days; d++)
          SupplyEvent(
            userId: 'u1',
            amount: total / scfg.days,
            dayIndex: d,
            at: DateTime.utc(2030, 1, 1).add(Duration(days: d)),
          ),
      ];

  /// Daily allocation strategy: each day, spend the available bank on today's
  /// wave using [weightFor] to split across fronts.
  List<SiegeAllocation> dailyStrategy(
    AssaultPlan plan,
    List<SupplyEvent> supply,
    double Function(int day, int front) weightFor,
  ) {
    final allocs = <SiegeAllocation>[];
    for (var d = 0; d < scfg.days; d++) {
      final state = engine.resolveWeek(
          plan: plan, supply: supply, allocations: allocs, daysResolved: d);
      var bank = state.bankRemaining;
      // Only supply earned by day d is actually usable for day d commits —
      // the engine enforces this via timestamps, so mirror it here.
      var earned = 0.0;
      for (final s in supply) {
        if (s.dayIndex <= d) earned += s.amount;
      }
      final usable =
          (earned - state.allocatedSupply).clamp(0.0, bank);
      var want = 0.0;
      final w = List<double>.generate(
          scfg.frontCount, (f) => weightFor(d, f));
      for (final v in w) {
        want += v;
      }
      if (usable <= 0 || want <= 0) continue;
      final scale = usable >= want ? 1.0 : usable / want;
      for (var f = 0; f < scfg.frontCount; f++) {
        final amt = w[f] * scale;
        if (amt <= 0) continue;
        allocs.add(SiegeAllocation(
          userId: 'u1',
          day: d,
          front: f,
          amount: amt,
          createdDayIndex: d,
          at: DateTime.utc(2030, 1, 1)
              .add(Duration(days: d, minutes: 30 + f)),
          id: 'a-$d-$f',
        ));
      }
    }
    return allocs;
  }

  SiegeWeekState runWeek(AssaultPlan plan, List<SupplyEvent> supply,
          List<SiegeAllocation> allocs) =>
      engine.resolveWeek(
          plan: plan,
          supply: supply,
          allocations: allocs,
          daysResolved: scfg.days);

  test('assault generation is deterministic and sums to W_assault', () {
    final a = planFor('room-det', gold);
    final b = planFor('room-det', gold);
    var sumA = 0.0;
    for (var d = 0; d < scfg.days; d++) {
      for (var f = 0; f < scfg.frontCount; f++) {
        expect(a.attack[d][f], b.attack[d][f]);
        sumA += a.attack[d][f];
      }
    }
    expect(a.tempoProfile, b.tempoProfile);
    expect(a.signatureFront, b.signatureFront);
    expect(a.signatureDays, b.signatureDays);
    expect((sumA - a.totalAssault).abs() / a.totalAssault, lessThan(1e-9));
  });

  test('week resolution is deterministic for identical inputs', () {
    final plan = planFor('room-det2', gold);
    final supply = equalSupply();
    final allocs =
        dailyStrategy(plan, supply, (d, f) => plan.attack[d][f]);
    final r1 = runWeek(plan, supply, allocs);
    final r2 = runWeek(plan, supply, allocs);
    expect(r1.integrity, r2.integrity);
    expect(r1.result?.won, r2.result?.won);
    expect(r1.allocatedSupply, r2.allocatedSupply);
  });

  test('calibration: decent logging + smart defense usually holds', () {
    // Co-op design: a crew that logs at its expected level and defends the
    // scouted shape should HOLD most weeks (losing only the toughest draws) —
    // not a coin flip. A single undefended day must never one-shot the week.
    var holds = 0;
    const n = 300;
    for (var r = 0; r < n; r++) {
      final plan = planFor('cal-$r', gold, week: r % lcfg.matchweeks);
      final supply = equalSupply();
      final allocs =
          dailyStrategy(plan, supply, (d, f) => plan.attack[d][f]);
      if (runWeek(plan, supply, allocs).result!.won) holds++;
    }
    final rate = holds / n;
    expect(rate, greaterThan(0.55), reason: 'too punishing: hold rate $rate');
    expect(rate, lessThan(0.95), reason: 'too trivial: hold rate $rate');
  });

  test('higher division = more integrity lost for the same effort', () {
    final radiant = lcfg.divisionById('radiant')!;
    double avgIntegrity(LeagueDivision div) {
      var total = 0.0;
      const n = 150;
      for (var r = 0; r < n; r++) {
        final plan = planFor('div-$r', div);
        final supply = equalSupply();
        final allocs =
            dailyStrategy(plan, supply, (d, f) => plan.attack[d][f]);
        total += runWeek(plan, supply, allocs).integrity;
      }
      return total / n;
    }

    expect(avgIntegrity(radiant), lessThan(avgIntegrity(gold)));
  });

  test('stacking every point on one front loses the week', () {
    var falls = 0;
    const n = 100;
    for (var r = 0; r < n; r++) {
      final plan = planFor('stack-$r', gold);
      final supply = equalSupply();
      final allocs =
          dailyStrategy(plan, supply, (d, f) => f == 0 ? 1.0 : 0.0);
      if (!runWeek(plan, supply, allocs).result!.won) falls++;
    }
    expect(falls / n, greaterThan(0.8),
        reason: 'one-front stacking should almost always fall');
  });

  test('resolution stops at the fall — no phantom post-fall waves', () {
    // No supply at all → the stronghold falls early; the wave list must end
    // exactly at the breach day (no contradictory "held" days after it).
    final plan = planFor('fall-stop', gold);
    final state = runWeek(plan, const [], const []);
    final res = state.result!;
    expect(res.won, isFalse);
    expect(res.breachDay, isNotNull);
    expect(state.waves.length, res.breachDay! + 1);
    expect(state.waves.last.integrityAfter, 0);
    for (final w in state.waves.take(state.waves.length - 1)) {
      expect(w.integrityAfter, greaterThan(0));
    }
  });

  test('forecast-aware allocation beats uniform allocation', () {
    var smartHolds = 0, uniformHolds = 0;
    const n = 200;
    for (var r = 0; r < n; r++) {
      final plan = planFor('strat-$r', gold);
      final supply = equalSupply();
      final smart =
          dailyStrategy(plan, supply, (d, f) => plan.attack[d][f]);
      final uniform = dailyStrategy(plan, supply, (d, f) => 1.0);
      if (runWeek(plan, supply, smart).result!.won) smartHolds++;
      if (runWeek(plan, supply, uniform).result!.won) uniformHolds++;
    }
    expect(smartHolds, greaterThan(uniformHolds),
        reason: 'strategy must beat spam (smart $smartHolds vs uniform $uniformHolds)');
  });

  test('unallocated supply banks across days (a missed day wastes nothing)',
      () {
    final plan = planFor('bank-1', gold);
    final supply = equalSupply(total: 700); // 100/day
    // Nothing allocated days 0–2; on day 3 commit 250 (needs banked supply:
    // only 400 earned by day 3 — 250 must be fully accepted).
    final allocs = [
      SiegeAllocation(
        userId: 'u1',
        day: 3,
        front: plan.signatureFront,
        amount: 250,
        createdDayIndex: 3,
        at: DateTime.utc(2030, 1, 1).add(const Duration(days: 3, hours: 1)),
        id: 'bank-alloc',
      ),
    ];
    final state = runWeek(plan, supply, allocs);
    expect(state.allocatedSupply, 250);
    expect(state.defense[3][plan.signatureFront], 250);
    expect(state.bankRemaining, 700 - 250);
  });

  test('allocations cannot defend the past and are clamped to the bank', () {
    final plan = planFor('bank-2', gold);
    final supply = equalSupply(total: 700);
    final allocs = [
      // Targets day 1 but committed on day 4 → ignored.
      SiegeAllocation(
          userId: 'u1',
          day: 1,
          front: 0,
          amount: 100,
          createdDayIndex: 4,
          at: DateTime.utc(2030, 1, 5),
          id: 'past'),
      // Requests 10,000 on day 5 with only ~600 earned → clamped.
      SiegeAllocation(
          userId: 'u1',
          day: 5,
          front: 0,
          amount: 10000,
          createdDayIndex: 5,
          at: DateTime.utc(2030, 1, 6, 1),
          id: 'greedy'),
    ];
    final state = runWeek(plan, supply, allocs);
    expect(state.defense[1][0], 0);
    expect(state.defense[5][0], 600); // supply earned through day 5
  });
}
