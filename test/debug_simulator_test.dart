import 'package:flutter_test/flutter_test.dart';
import 'package:jars/core/league_config.dart';
import 'package:jars/models/siege.dart';
import 'package:jars/services/debug_simulator.dart';

void main() {
  final lcfg = LeagueConfig.instance;

  DebugSimulator makeSim(int seed) => DebugSimulator(
        seed: seed,
        bots: BotMember.presets,
        autoAllocate: true,
      );

  test('full season simulates in under a second with valid results', () {
    final sim = makeSim(42);
    final sw = Stopwatch()..start();
    final summary = sim.simulateFullSeason();
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1000),
        reason: 'season took ${sw.elapsedMilliseconds}ms');
    expect(summary.weeks.length, lcfg.matchweeks);
    expect(summary.finalStandings.length, lcfg.teamsPerLeague);
    expect(summary.promoted.length, lcfg.promoteCount);
    expect(summary.relegated.length, lcfg.relegateCount);
    for (final s in summary.finalStandings) {
      expect(s.played, lcfg.matchweeks);
    }
    expect(summary.yourPosition, inInclusiveRange(1, lcfg.teamsPerLeague));
    // Season rolled over cleanly.
    expect(sim.seasonIndex, 1);
    expect(sim.week, 0);
  });

  test('same seed + same bots → identical season outcome', () {
    final a = makeSim(1234).simulateFullSeason();
    final b = makeSim(1234).simulateFullSeason();
    expect(a.yourPosition, b.yourPosition);
    expect(a.nextDivisionName, b.nextDivisionName);
    for (var w = 0; w < a.weeks.length; w++) {
      expect(a.weeks[w].won, b.weeks[w].won);
      expect(a.weeks[w].integrityRemaining, b.weeks[w].integrityRemaining);
      expect(a.weeks[w].supplyEarned, b.weeks[w].supplyEarned);
    }
    for (var i = 0; i < a.finalStandings.length; i++) {
      expect(a.finalStandings[i].teamId, b.finalStandings[i].teamId);
      expect(a.finalStandings[i].leaguePoints, b.finalStandings[i].leaguePoints);
    }
  });

  test('advanceDay steps a single wave; end-of-week rolls the matchweek', () {
    final sim = makeSim(7);
    sim.advanceDay();
    expect(sim.day, 1);
    expect(sim.current, isNotNull);
    expect(sim.current!.waves.length, 1);
    sim.advanceToEndOfWeek();
    expect(sim.week, 1);
    expect(sim.day, 0);
    expect(sim.outcomes.length, 1);
  });

  test('jumpToWeek and reset are deterministic', () {
    final sim = makeSim(99);
    sim.jumpToWeek(3);
    expect(sim.week, 3);
    final tableA = sim.buildTable().yourRow!.leaguePoints;
    sim.jumpToWeek(3);
    expect(sim.buildTable().yourRow!.leaguePoints, tableA);
    sim.reset();
    expect(sim.week, 0);
    expect(sim.seasonIndex, 0);
    expect(sim.outcomes, isEmpty);
  });

  test('multi-season run promotes/relegates and changes division', () {
    final sim = makeSim(5);
    final divisions = <String>{};
    for (var s = 0; s < 4; s++) {
      final summary = sim.simulateFullSeason();
      divisions.add(summary.divisionName);
      expect(summary.promoted.length, lcfg.promoteCount);
      expect(summary.relegated.length, lcfg.relegateCount);
    }
    expect(sim.seasonIndex, 4);
  });
}
