import '../core/league_config.dart';
import '../core/seeded_rng.dart';
import '../models/league.dart';

/// Deterministic AI-league engine. Everything (rosters, form, scores, fixtures,
/// AI-vs-AI results) is a pure function of a seed keyed by
/// (roomId, divisionId, seasonIndex, weekIndex, teamId, playerIndex). Uses only
/// shift/xor arithmetic masked to 32 bits, so it is **bit-identical on web (JS)
/// and native** — every crewmate computes the same league with no backend.
class LeagueSimulator {
  final LeagueConfig cfg;
  LeagueSimulator([LeagueConfig? config]) : cfg = config ?? LeagueConfig.instance;

  static const List<String> _archetypes = [
    'grinder',
    'weekend warrior',
    'streaky',
    'comeback kid',
    'workhorse',
  ];

  /// Build the full league snapshot for a room's current season.
  ///
  /// [yourWeeklyPoints] holds your team's real logged points per matchweek
  /// (index = week-in-season); the entry at [completedWeeks] is the in-progress
  /// week (used for the live fixture). [anchorPerMember] and [yourActiveMembers]
  /// come from the service (trailing average or fallback).
  ///
  /// [yourOutcomes] (siege mode): per completed week, overrides YOUR fixture's
  /// W/L tally — true = won (held the siege), false = lost (stronghold fell),
  /// null = fall back to score comparison. Scores are still tallied for
  /// points-for/against display; AI-vs-AI matches are unaffected.
  LeagueTable build({
    required String roomId,
    required String yourTeamName,
    required LeagueDivision division,
    required int seasonIndex,
    required int completedWeeks,
    required List<int> yourWeeklyPoints,
    required int yourActiveMembers,
    required double anchorPerMember,
    List<bool?>? yourOutcomes,
  }) {
    final matchweeks = cfg.matchweeks;
    final members = yourActiveMembers < 1 ? 1 : yourActiveMembers;
    final rosterSize = members < cfg.ai.rosterMin
        ? cfg.ai.rosterMin
        : (members > cfg.ai.rosterMax ? cfg.ai.rosterMax : members);

    final ai = _aiTeams(roomId, division, seasonIndex, rosterSize);
    final yourAnchorTotal = anchorPerMember * members;
    final nominalTotal = cfg.balance.nominalBaselinePerMember * rosterSize;

    final standings = <String, LeagueTeamStanding>{
      LeagueTable.youId: LeagueTeamStanding(
          teamId: LeagueTable.youId, name: yourTeamName, isYou: true),
      for (final t in ai)
        t.id: LeagueTeamStanding(teamId: t.id, name: t.name, isYou: false),
    };
    final aiById = {for (final t in ai) t.id: t};

    final done = completedWeeks < 0
        ? 0
        : (completedWeeks > matchweeks ? matchweeks : completedWeeks);

    if (cfg.mode == LeagueMode.fixtures) {
      final ids = [LeagueTable.youId, ...ai.map((t) => t.id)];
      final rounds = _schedule(ids);
      for (var w = 0; w < done && w < rounds.length; w++) {
        for (final fx in rounds[w]) {
          final scores = _resolveFixture(
            fx: fx,
            week: w,
            ai: aiById,
            division: division,
            roomId: roomId,
            seasonIndex: seasonIndex,
            yourWeeklyPoints: yourWeeklyPoints,
            yourAnchorTotal: yourAnchorTotal,
            nominalTotal: nominalTotal,
          );
          final aIsYou = fx.teamAId == LeagueTable.youId;
          final bIsYou = fx.teamBId == LeagueTable.youId;
          final override = (aIsYou || bIsYou) &&
                  yourOutcomes != null &&
                  w < yourOutcomes.length
              ? yourOutcomes[w]
              : null;
          if (override != null) {
            _applyOverride(standings[fx.teamAId]!, standings[fx.teamBId]!,
                scores.$1, scores.$2, aIsYou ? override : !override);
          } else {
            _applyResult(standings[fx.teamAId]!, standings[fx.teamBId]!,
                scores.$1, scores.$2);
          }
        }
      }
      final list = standings.values.toList()..sort(_cmpFixtures);
      for (var i = 0; i < list.length; i++) {
        list[i].position = i + 1;
      }
      final live = _liveFixture(
        rounds: rounds,
        week: done,
        matchweeks: matchweeks,
        ai: aiById,
        division: division,
        roomId: roomId,
        seasonIndex: seasonIndex,
        yourWeeklyPoints: yourWeeklyPoints,
        yourAnchorTotal: yourAnchorTotal,
      );
      return LeagueTable(
        division: division,
        theme: cfg.theme,
        seasonIndex: seasonIndex,
        matchweeks: matchweeks,
        completedWeeks: done,
        standings: list,
        aiTeams: ai,
        live: live,
        promoteCount: cfg.promoteCount,
        relegateCount: cfg.relegateCount,
      );
    }

    // ── table mode: rank by total points scored (AI calibrated to you) ─────────
    for (var w = 0; w < done; w++) {
      final you = standings[LeagueTable.youId]!;
      you.played++;
      you.pointsFor += (w < yourWeeklyPoints.length) ? yourWeeklyPoints[w] : 0;
      for (final t in ai) {
        final s = _teamScore(yourAnchorTotal, division, t,
            _teamSeed(roomId, division, seasonIndex, t.id), w);
        final row = standings[t.id]!;
        row.played++;
        row.pointsFor += s;
      }
    }
    final list = standings.values.toList()
      ..sort((a, b) => b.pointsFor.compareTo(a.pointsFor));
    for (var i = 0; i < list.length; i++) {
      list[i].position = i + 1;
    }
    return LeagueTable(
      division: division,
      theme: cfg.theme,
      seasonIndex: seasonIndex,
      matchweeks: matchweeks,
      completedWeeks: done,
      standings: list,
      aiTeams: ai,
      live: null,
      promoteCount: cfg.promoteCount,
      relegateCount: cfg.relegateCount,
    );
  }

  /// Your fixture (opponent + final scores) for a specific matchweek — used to
  /// announce a resolved week. Null in table mode or for out-of-range weeks.
  LiveFixture? matchForWeek({
    required String roomId,
    required LeagueDivision division,
    required int seasonIndex,
    required int week,
    required List<int> yourWeeklyPoints,
    required int yourActiveMembers,
    required double anchorPerMember,
  }) {
    if (cfg.mode != LeagueMode.fixtures) return null;
    final members = yourActiveMembers < 1 ? 1 : yourActiveMembers;
    final rosterSize = members < cfg.ai.rosterMin
        ? cfg.ai.rosterMin
        : (members > cfg.ai.rosterMax ? cfg.ai.rosterMax : members);
    final ai = _aiTeams(roomId, division, seasonIndex, rosterSize);
    final aiById = {for (final t in ai) t.id: t};
    final ids = [LeagueTable.youId, ...ai.map((t) => t.id)];
    final rounds = _schedule(ids);
    return _liveFixture(
      rounds: rounds,
      week: week,
      matchweeks: cfg.matchweeks,
      ai: aiById,
      division: division,
      roomId: roomId,
      seasonIndex: seasonIndex,
      yourWeeklyPoints: yourWeeklyPoints,
      yourAnchorTotal: anchorPerMember * members,
    );
  }

  // ── fixture resolution ──────────────────────────────────────────────────────
  (int, int) _resolveFixture({
    required Fixture fx,
    required int week,
    required Map<String, AiTeam> ai,
    required LeagueDivision division,
    required String roomId,
    required int seasonIndex,
    required List<int> yourWeeklyPoints,
    required double yourAnchorTotal,
    required double nominalTotal,
  }) {
    final aIsYou = fx.teamAId == LeagueTable.youId;
    final bIsYou = fx.teamBId == LeagueTable.youId;
    if (aIsYou || bIsYou) {
      final yourScore =
          (week < yourWeeklyPoints.length) ? yourWeeklyPoints[week] : 0;
      final opp = ai[aIsYou ? fx.teamBId : fx.teamAId]!;
      final oppScore = _teamScore(yourAnchorTotal, division, opp,
          _teamSeed(roomId, division, seasonIndex, opp.id), week);
      return aIsYou ? (yourScore, oppScore) : (oppScore, yourScore);
    }
    final ta = ai[fx.teamAId]!;
    final tb = ai[fx.teamBId]!;
    final sa = _teamScore(nominalTotal, division, ta,
        _teamSeed(roomId, division, seasonIndex, ta.id), week);
    final sb = _teamScore(nominalTotal, division, tb,
        _teamSeed(roomId, division, seasonIndex, tb.id), week);
    return (sa, sb);
  }

  LiveFixture? _liveFixture({
    required List<List<Fixture>> rounds,
    required int week,
    required int matchweeks,
    required Map<String, AiTeam> ai,
    required LeagueDivision division,
    required String roomId,
    required int seasonIndex,
    required List<int> yourWeeklyPoints,
    required double yourAnchorTotal,
  }) {
    if (week >= matchweeks || week >= rounds.length) return null;
    Fixture? mine;
    for (final fx in rounds[week]) {
      if (fx.teamAId == LeagueTable.youId || fx.teamBId == LeagueTable.youId) {
        mine = fx;
        break;
      }
    }
    if (mine == null) return null;
    final oppId =
        mine.teamAId == LeagueTable.youId ? mine.teamBId : mine.teamAId;
    final opp = ai[oppId]!;
    final oppSeed = _teamSeed(roomId, division, seasonIndex, opp.id);
    final oppScore = _teamScore(yourAnchorTotal, division, opp, oppSeed, week);
    final yourSoFar =
        (week < yourWeeklyPoints.length) ? yourWeeklyPoints[week] : 0;
    return LiveFixture(
      week: week,
      opponent: _teamWithWeekOutputs(opp, oppSeed, week),
      yourScore: yourSoFar,
      opponentScore: oppScore,
    );
  }

  void _applyResult(
      LeagueTeamStanding a, LeagueTeamStanding b, int sa, int sb) {
    a.played++;
    b.played++;
    a.pointsFor += sa;
    a.pointsAgainst += sb;
    b.pointsFor += sb;
    b.pointsAgainst += sa;
    if (sa > sb) {
      a.wins++;
      b.losses++;
      a.leaguePoints += cfg.scoring.win;
      b.leaguePoints += cfg.scoring.loss;
    } else if (sa < sb) {
      b.wins++;
      a.losses++;
      b.leaguePoints += cfg.scoring.win;
      a.leaguePoints += cfg.scoring.loss;
    } else {
      a.draws++;
      b.draws++;
      a.leaguePoints += cfg.scoring.draw;
      b.leaguePoints += cfg.scoring.draw;
    }
  }

  /// Siege override: [aWon] decides the W/L tally regardless of scores (no
  /// draws in siege); scores still feed points-for/against for display.
  void _applyOverride(LeagueTeamStanding a, LeagueTeamStanding b, int sa,
      int sb, bool aWon) {
    a.played++;
    b.played++;
    a.pointsFor += sa;
    a.pointsAgainst += sb;
    b.pointsFor += sb;
    b.pointsAgainst += sa;
    if (aWon) {
      a.wins++;
      b.losses++;
      a.leaguePoints += cfg.scoring.win;
      b.leaguePoints += cfg.scoring.loss;
    } else {
      b.wins++;
      a.losses++;
      b.leaguePoints += cfg.scoring.win;
      a.leaguePoints += cfg.scoring.loss;
    }
  }

  int _cmpFixtures(LeagueTeamStanding a, LeagueTeamStanding b) {
    if (b.leaguePoints != a.leaguePoints) {
      return b.leaguePoints.compareTo(a.leaguePoints);
    }
    if (b.diff != a.diff) return b.diff.compareTo(a.diff);
    if (b.pointsFor != a.pointsFor) return b.pointsFor.compareTo(a.pointsFor);
    return a.name.compareTo(b.name); // stable tiebreak
  }

  // ── team / player simulation ────────────────────────────────────────────────
  int _teamSeed(String roomId, LeagueDivision d, int season, String teamId) =>
      seedFromParts([roomId, d.id, season, teamId]);

  List<AiTeam> _aiTeams(
      String roomId, LeagueDivision div, int season, int rosterSize) {
    final count = cfg.teamsPerLeague - 1; // your team fills the last slot
    final rng = SeededRng(seedFromParts([roomId, div.id, season, 'roster']));
    final names = List<String>.from(cfg.ai.teamNames);
    _shuffle(names, rng);
    final teams = <AiTeam>[];
    for (var i = 0; i < count; i++) {
      final teamId = 'ai_$i';
      final tSeed = _teamSeed(roomId, div, season, teamId);
      final tr = SeededRng(tSeed);
      final strength = tr.range(0.85, 1.15);
      final pNames = List<String>.from(cfg.ai.playerNames);
      _shuffle(pNames, SeededRng(seedFromParts([tSeed, 'pnames'])));
      final roster = <AiPlayer>[];
      for (var p = 0; p < rosterSize; p++) {
        final pr = SeededRng(seedFromParts([tSeed, 'p', p]));
        roster.add(AiPlayer(
          name: pNames[p % pNames.length],
          ability: pr.range(div.aiAbilityMin, div.aiAbilityMax),
          archetype: _archetypes[pr.intRange(0, _archetypes.length)],
        ));
      }
      teams.add(AiTeam(
          id: teamId,
          name: names[i % names.length],
          strength: strength,
          roster: roster));
    }
    return teams;
  }

  /// AR(1) mean-reverting form (→ 1.0) with seeded weekly noise → heaters/slumps.
  double _form(int teamSeed, int p, int week) {
    var f = 1.0;
    for (var w = 0; w <= week; w++) {
      final rng = SeededRng(seedFromParts([teamSeed, 'form', p, w]));
      final noise = rng.range(-cfg.ai.weeklyNoise, cfg.ai.weeklyNoise);
      f = 1.0 + cfg.ai.formInertia * (f - 1.0) + noise;
      if (f < 0.3) f = 0.3;
      if (f > 1.9) f = 1.9;
    }
    return f;
  }

  bool _missed(int teamSeed, int p, int week) {
    final rng = SeededRng(seedFromParts([teamSeed, 'miss', p, week]));
    return rng.unit() < cfg.ai.missWeekChance;
  }

  /// (rawTeam, expectedRawTeam) for a team's week — see plan's anchoring formula.
  (double, double) _rawAndExpected(AiTeam team, int teamSeed, int week) {
    var raw = 0.0;
    var expected = 0.0;
    // Bake availability into the expectation so misses/heaters/slumps make the
    // form factor swing *around* 1.0 rather than biasing opponents weak.
    final availability = 1.0 - cfg.ai.missWeekChance;
    for (var p = 0; p < team.roster.length; p++) {
      final ability = team.roster[p].ability;
      expected += ability * availability;
      if (_missed(teamSeed, p, week)) continue;
      raw += ability * _form(teamSeed, p, week);
    }
    return (raw, expected);
  }

  int _teamScore(double anchorTotal, LeagueDivision div, AiTeam team,
      int teamSeed, int week) {
    final (raw, expected) = _rawAndExpected(team, teamSeed, week);
    final f = expected > 0 ? raw / expected : 1.0; // form factor, centered ~1.0
    final sRng = SeededRng(seedFromParts([teamSeed, 'spread', week]));
    final s = 1.0 + sRng.range(-cfg.balance.opponentSpread, cfg.balance.opponentSpread);
    final score = anchorTotal * div.difficulty * s * f * team.strength;
    final r = score.round();
    return r < 0 ? 0 : r;
  }

  AiTeam _teamWithWeekOutputs(AiTeam team, int teamSeed, int week) {
    final players = <AiPlayer>[];
    for (var p = 0; p < team.roster.length; p++) {
      final base = team.roster[p];
      final missed = _missed(teamSeed, p, week);
      players.add(AiPlayer(
        name: base.name,
        ability: base.ability,
        archetype: base.archetype,
        missedWeek: missed,
        weekOutput: missed ? 0 : base.ability * _form(teamSeed, p, week),
      ));
    }
    return AiTeam(
        id: team.id, name: team.name, strength: team.strength, roster: players);
  }

  /// Test hook: the deterministic round-robin schedule for [ids].
  List<List<Fixture>> debugFixtures(List<String> ids) => _schedule(ids);

  // ── round-robin (circle method): complete, no byes when teams is even ────────
  List<List<Fixture>> _schedule(List<String> ids) {
    final n = ids.length;
    final rounds = <List<Fixture>>[];
    final fixed = ids[0];
    var rot = ids.sublist(1);
    final numRounds = cfg.matchweeks; // = n-1 (or n-2 if incompleteSchedule)
    for (var r = 0; r < numRounds; r++) {
      final row = [fixed, ...rot];
      final fixtures = <Fixture>[];
      for (var i = 0; i < n ~/ 2; i++) {
        fixtures.add(
            Fixture(week: r, teamAId: row[i], teamBId: row[n - 1 - i]));
      }
      rounds.add(fixtures);
      rot = [rot.last, ...rot.sublist(0, rot.length - 1)];
    }
    return rounds;
  }

  void _shuffle(List<String> list, SeededRng rng) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = rng.intRange(0, i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}

