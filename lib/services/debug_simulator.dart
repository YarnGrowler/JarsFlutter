import 'dart:math' as math;

import '../core/league_config.dart';
import '../core/seeded_rng.dart';
import '../core/siege_config.dart';
import '../models/league.dart';
import '../models/siege.dart';
import 'assault_generator.dart';
import 'league_simulator.dart';
import 'siege_engine.dart';

/// One matchweek's outcome in a simulated run.
class SimWeekRecord {
  final int week;
  final String opponentName;
  final bool won;
  final double integrityRemaining;
  final int? breachDay;
  final double supplyEarned;
  const SimWeekRecord({
    required this.week,
    required this.opponentName,
    required this.won,
    required this.integrityRemaining,
    required this.breachDay,
    required this.supplyEarned,
  });
}

/// Season summary produced when a simulated season completes.
class SimSeasonSummary {
  final int seasonIndex;
  final String divisionName;
  final List<LeagueTeamStanding> finalStandings;
  final List<String> promoted;
  final List<String> relegated;
  final int yourPosition;
  final String nextDivisionName;
  final List<SimWeekRecord> weeks;
  const SimSeasonSummary({
    required this.seasonIndex,
    required this.divisionName,
    required this.finalStandings,
    required this.promoted,
    required this.relegated,
    required this.yourPosition,
    required this.nextDivisionName,
    required this.weeks,
  });
}

/// Fully in-memory, deterministic season runner (§4.2): AI teammate bots log
/// workouts day by day, supply feeds the siege engine, results feed the league
/// table, seasons promote/relegate — all with zero Supabase and zero waiting.
/// Same seed + same bot config → identical outcome, every run.
class DebugSimulator {
  final LeagueConfig lcfg;
  final SiegeConfig scfg;
  final int seed;
  final List<BotMember> bots;
  bool autoAllocate;

  late final AssaultGenerator _gen = AssaultGenerator(scfg);
  late final SiegeEngine _engine = SiegeEngine(scfg);
  late final LeagueSimulator _lsim = LeagueSimulator(lcfg);

  // Season/room state
  late String roomId;
  int divisionIndex = 0;
  int seasonIndex = 0;
  int week = 0; // week-in-season
  int day = 0; // next unresolved day in the current week

  // Current-week state
  final List<SupplyEvent> supply = [];
  final List<SiegeAllocation> allocations = [];
  SiegeWeekState? current;
  AssaultPlan? plan;

  // Season history
  final List<double> weeklyTotals = []; // completed weeks' supply
  final List<bool?> outcomes = [];
  final List<SimWeekRecord> records = [];
  SimSeasonSummary? lastSeasonSummary;

  DebugSimulator({
    required this.seed,
    required this.bots,
    this.autoAllocate = true,
    LeagueConfig? leagueConfig,
    SiegeConfig? siegeConfig,
    int startDivisionIndex = 0,
  })  : lcfg = leagueConfig ?? LeagueConfig.instance,
        scfg = siegeConfig ?? SiegeConfig.fallback {
    divisionIndex = startDivisionIndex;
    roomId = 'sim-room-$seed';
  }

  LeagueDivision get division => lcfg.divisionByIndex(divisionIndex);
  int get activeMembers => bots.isEmpty ? 1 : bots.length;

  /// Trailing per-member anchor over the last ≤3 non-zero completed weeks;
  /// falls back to the jar-baseline default (7 × 10) with no history.
  double anchorPerMember() {
    final vals = <double>[];
    for (var i = weeklyTotals.length - 1;
        i >= 0 && vals.length < 3;
        i--) {
      if (weeklyTotals[i] > 0) vals.add(weeklyTotals[i]);
    }
    if (vals.isEmpty) return 70;
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return avg / activeMembers;
  }

  List<int> _yourWeeklyPointsWithCurrent() => <int>[
        for (final t in weeklyTotals) t.round(),
        _currentSupplyTotal().round(),
      ];

  double _currentSupplyTotal() {
    var t = 0.0;
    for (final s in supply) {
      t += s.amount;
    }
    return t;
  }

  void _ensurePlan() {
    if (plan != null) return;
    final live = _lsim.matchForWeek(
      roomId: roomId,
      division: division,
      seasonIndex: seasonIndex,
      week: week,
      yourWeeklyPoints: _yourWeeklyPointsWithCurrent(),
      yourActiveMembers: activeMembers,
      anchorPerMember: anchorPerMember(),
    );
    final oppId = live?.opponent.id ?? 'ai_0';
    final oppName = live?.opponent.name ?? 'Unknown';
    final total = (live?.opponentScore ?? (anchorPerMember() * activeMembers))
        .toDouble();
    plan = _gen.generate(
      roomId: roomId,
      divisionId: division.id,
      seasonIndex: seasonIndex,
      weekIndex: week,
      opponentId: oppId,
      opponentName: oppName,
      totalAssault: total <= 0 ? 1 : total,
    );
  }

  /// Deterministic normal(0,1) via Box-Muller on the seeded RNG.
  double _gauss(SeededRng rng) {
    var u1 = rng.unit();
    if (u1 < 1e-9) u1 = 1e-9;
    final u2 = rng.unit();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  DateTime _syntheticTime(int d, int slot) =>
      DateTime.utc(2030, 1, 1).add(Duration(days: d, minutes: slot));

  /// Advance exactly one day: bots log → (auto-)allocate → the wave resolves.
  /// Rolls into the next week/season automatically at boundaries.
  void advanceDay() {
    _ensurePlan();

    // 1. Bot logs for this day.
    for (var b = 0; b < bots.length; b++) {
      final bot = bots[b];
      final rng = SeededRng(
          seedFromParts([seed, seasonIndex, week, day, bot.id, 'log']));
      if (rng.unit() >= bot.activeProbability) continue;
      var pts = bot.meanDailyPoints + _gauss(rng) * bot.variance;
      if (pts < 0) pts = 0;
      if (pts == 0) continue;
      supply.add(SupplyEvent(
        userId: bot.id,
        amount: pts.roundToDouble() * scfg.supplyPerPoint,
        dayIndex: day,
        at: _syntheticTime(day, b),
      ));
    }

    // 2. Auto-allocation: spend today's available bank on today's wave,
    //    proportional to the (scouted) attack shape.
    if (autoAllocate) {
      final state = _engine.resolveWeek(
        plan: plan!,
        supply: supply,
        allocations: allocations,
        daysResolved: day,
      );
      var bank = state.bankRemaining;
      final atk = plan!.attack[day];
      var want = 0.0;
      for (final a in atk) {
        want += a;
      }
      if (bank > 0 && want > 0) {
        final scale = bank >= want ? 1.0 : bank / want;
        for (var f = 0; f < atk.length; f++) {
          final amt = atk[f] * scale;
          if (amt <= 0) continue;
          allocations.add(SiegeAllocation(
            userId: 'auto',
            day: day,
            front: f,
            amount: amt,
            createdDayIndex: day,
            at: _syntheticTime(day, 1000 + f),
            id: 'auto-$seasonIndex-$week-$day-$f',
          ));
          bank -= amt;
        }
      }
    }

    // 3. Resolve through today.
    current = _engine.resolveWeek(
      plan: plan!,
      supply: supply,
      allocations: allocations,
      daysResolved: day + 1,
    );
    day++;

    if (day >= scfg.days) _finishWeek();
  }

  void _finishWeek() {
    final res = current?.result ??
        const SiegeResult(won: false, integrityRemaining: 0);
    records.add(SimWeekRecord(
      week: week,
      opponentName: plan?.opponentName ?? '?',
      won: res.won,
      integrityRemaining: res.integrityRemaining,
      breachDay: res.breachDay,
      supplyEarned: _currentSupplyTotal(),
    ));
    weeklyTotals.add(_currentSupplyTotal());
    outcomes.add(res.won);

    supply.clear();
    allocations.clear();
    plan = null;
    current = null;
    day = 0;
    week++;

    if (week >= lcfg.matchweeks) _finishSeason();
  }

  void _finishSeason() {
    final table = buildTable();
    final pos = table.yourRow?.position ?? lcfg.teamsPerLeague;
    final promoted = table.standings
        .take(lcfg.promoteCount)
        .map((s) => s.name)
        .toList();
    final relegated = table.standings
        .skip(table.standings.length - lcfg.relegateCount)
        .map((s) => s.name)
        .toList();

    var newDiv = divisionIndex;
    if (pos <= lcfg.promoteCount && divisionIndex < lcfg.divisions.length - 1) {
      newDiv = divisionIndex + 1;
    } else if (pos > lcfg.teamsPerLeague - lcfg.relegateCount &&
        divisionIndex > 0) {
      newDiv = divisionIndex - 1;
    }

    lastSeasonSummary = SimSeasonSummary(
      seasonIndex: seasonIndex,
      divisionName: division.displayName(lcfg.theme),
      finalStandings: table.standings,
      promoted: promoted,
      relegated: relegated,
      yourPosition: pos,
      nextDivisionName:
          lcfg.divisionByIndex(newDiv).displayName(lcfg.theme),
      weeks: List<SimWeekRecord>.from(records),
    );

    divisionIndex = newDiv;
    seasonIndex++;
    week = 0;
    weeklyTotals.clear();
    outcomes.clear();
    records.clear();
  }

  /// League table at the current point of the season (siege outcomes applied).
  LeagueTable buildTable() {
    return _lsim.build(
      roomId: roomId,
      yourTeamName: 'Your Crew',
      division: division,
      seasonIndex: seasonIndex,
      completedWeeks: week,
      yourWeeklyPoints: _yourWeeklyPointsWithCurrent(),
      yourActiveMembers: activeMembers,
      anchorPerMember: anchorPerMember(),
      yourOutcomes: List<bool?>.from(outcomes),
    );
  }

  void advanceToEndOfWeek() {
    final w = week, s = seasonIndex;
    while (week == w && seasonIndex == s) {
      advanceDay();
    }
  }

  /// Runs the remainder of the current season. Returns its summary.
  SimSeasonSummary simulateFullSeason() {
    final s = seasonIndex;
    while (seasonIndex == s) {
      advanceDay();
    }
    return lastSeasonSummary!;
  }

  /// Deterministic jump: reset, then replay whole weeks up to [n].
  void jumpToWeek(int n) {
    reset();
    final target = n.clamp(0, lcfg.matchweeks - 1);
    while (week < target && seasonIndex == 0) {
      advanceToEndOfWeek();
    }
  }

  void reset({int? startDivisionIndex}) {
    divisionIndex = startDivisionIndex ?? 0;
    seasonIndex = 0;
    week = 0;
    day = 0;
    supply.clear();
    allocations.clear();
    weeklyTotals.clear();
    outcomes.clear();
    records.clear();
    plan = null;
    current = null;
    lastSeasonSummary = null;
  }
}
