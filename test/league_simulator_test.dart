import 'package:flutter_test/flutter_test.dart';
import 'package:jars/core/league_config.dart';
import 'package:jars/models/league.dart';
import 'package:jars/services/league_simulator.dart';

void main() {
  // Tests use LeagueConfig's built-in fallback (no asset load in the test host):
  // 8 teams → 7 matchweeks, gold = even difficulty (1.0).
  final cfg = LeagueConfig.instance;
  final sim = LeagueSimulator(cfg);
  final gold = cfg.divisionById('gold')!;

  LeagueTable buildFor(String roomId,
      {int completed = 7, double anchorPerMember = 300, int members = 4}) {
    final weekly =
        List<int>.filled(cfg.matchweeks, (anchorPerMember * members).round());
    return sim.build(
      roomId: roomId,
      yourTeamName: 'Your Crew',
      division: gold,
      seasonIndex: 0,
      completedWeeks: completed,
      yourWeeklyPoints: weekly,
      yourActiveMembers: members,
      anchorPerMember: anchorPerMember,
    );
  }

  test('is fully deterministic for the same inputs', () {
    final a = buildFor('room-abc');
    final b = buildFor('room-abc');
    expect(a.standings.length, b.standings.length);
    for (var i = 0; i < a.standings.length; i++) {
      expect(a.standings[i].teamId, b.standings[i].teamId);
      expect(a.standings[i].leaguePoints, b.standings[i].leaguePoints);
      expect(a.standings[i].pointsFor, b.standings[i].pointsFor);
      expect(a.standings[i].position, b.standings[i].position);
    }
  });

  test('fixtures are a complete round-robin (each pair once, no byes)', () {
    final ids = [LeagueTable.youId, for (var i = 0; i < 7; i++) 'ai_$i'];
    final rounds = sim.debugFixtures(ids);
    expect(rounds.length, cfg.matchweeks); // 7
    final pairs = <String>{};
    for (final round in rounds) {
      expect(round.length, ids.length ~/ 2); // 4 fixtures, everyone plays (no bye)
      final seenThisWeek = <String>{};
      for (final fx in round) {
        expect(fx.teamAId, isNot(fx.teamBId)); // no self-match
        expect(seenThisWeek.contains(fx.teamAId), isFalse);
        expect(seenThisWeek.contains(fx.teamBId), isFalse);
        seenThisWeek.add(fx.teamAId);
        seenThisWeek.add(fx.teamBId);
        final key = ([fx.teamAId, fx.teamBId]..sort()).join('-');
        expect(pairs.contains(key), isFalse, reason: 'duplicate pairing $key');
        pairs.add(key);
      }
    }
    // C(8,2) = 28 unique pairings across the season.
    expect(pairs.length, 28);
  });

  test('everyone plays every matchweek after a full season', () {
    final t = buildFor('room-xyz');
    for (final s in t.standings) {
      expect(s.played, cfg.matchweeks);
    }
  });

  test('win rate is competitive (~50%) when you perform at your anchor', () {
    var wins = 0, played = 0;
    for (var r = 0; r < 300; r++) {
      final t = buildFor('room-$r');
      final you = t.yourRow!;
      wins += you.wins;
      played += you.played;
    }
    final rate = wins / played;
    expect(rate, greaterThan(0.35), reason: 'too hard: $rate');
    expect(rate, lessThan(0.65), reason: 'too easy: $rate');
  });

  test('higher divisions are harder at the same effort', () {
    final radiant = cfg.divisionById('radiant')!;
    int winsIn(LeagueDivision d) {
      var w = 0;
      for (var r = 0; r < 200; r++) {
        final weekly = List<int>.filled(cfg.matchweeks, 1200);
        final t = sim.build(
          roomId: 'r-$r',
          yourTeamName: 'You',
          division: d,
          seasonIndex: 0,
          completedWeeks: cfg.matchweeks,
          yourWeeklyPoints: weekly,
          yourActiveMembers: 4,
          anchorPerMember: 300,
        );
        w += t.yourRow!.wins;
      }
      return w;
    }

    expect(winsIn(radiant), lessThan(winsIn(gold)),
        reason: 'radiant should yield fewer wins than gold at equal effort');
  });
}
