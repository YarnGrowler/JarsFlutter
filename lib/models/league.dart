import 'package:flutter/material.dart';

import 'siege.dart';

/// How a matchweek turns into standing.
enum LeagueMode { fixtures, table }

/// Which name set to display for divisions.
enum DivisionTheme { metal, football }

LeagueMode leagueModeFromString(String? s) =>
    (s == 'table') ? LeagueMode.table : LeagueMode.fixtures;

DivisionTheme divisionThemeFromString(String? s) =>
    (s == 'football') ? DivisionTheme.football : DivisionTheme.metal;

/// One rung of the league ladder (group tier). Mirrors [Level] for individuals.
class LeagueDivision {
  final int index; // 0 = lowest division
  final String id;
  final String metalName;
  final String footballName;
  final Color color;
  final String icon;
  final double difficulty; // multiplier on opponent scores; ascends with index
  final double aiAbilityMin;
  final double aiAbilityMax;

  /// Battlefield side length for this rung (square). Peak map size never shrinks.
  final int mapSize;

  /// Biome id string (see [WarBiomeId] / war_biome.dart).
  final String biome;

  /// Troop type names unlocked AT this rung (cumulative with lower rungs).
  final List<String> unlockTroops;

  /// Defense type names unlocked AT this rung (cumulative; current palette always free).
  final List<String> unlockDefs;

  /// Target AI ward/citadel count for enemy base design.
  final int wards;

  final double mountainFrac;
  final double forestFrac;

  /// dry / light / wet weights (should roughly sum to 1).
  final double waterDry;
  final double waterLight;
  final double waterWet;

  const LeagueDivision({
    required this.index,
    required this.id,
    required this.metalName,
    required this.footballName,
    required this.color,
    required this.icon,
    required this.difficulty,
    required this.aiAbilityMin,
    required this.aiAbilityMax,
    this.mapSize = 40,
    this.biome = 'meadow',
    this.unlockTroops = const [],
    this.unlockDefs = const [],
    this.wards = 1,
    this.mountainFrac = 0.11,
    this.forestFrac = 0.16,
    this.waterDry = 0.25,
    this.waterLight = 0.50,
    this.waterWet = 0.25,
  });

  String displayName(DivisionTheme theme) =>
      theme == DivisionTheme.football ? footballName : metalName;
}

/// A simulated opponent player (for roster flavor: heaters, slumps, missed weeks).
class AiPlayer {
  final String name;
  final double ability;
  final String archetype;
  final double weekOutput; // this week's raw output (0 if missed)
  final bool missedWeek;

  const AiPlayer({
    required this.name,
    required this.ability,
    required this.archetype,
    this.weekOutput = 0,
    this.missedWeek = false,
  });
}

/// A simulated opponent team with a roster and a season-long strength.
class AiTeam {
  final String id;
  final String name;
  final double strength; // persistent within a season (~0.85..1.15)
  final List<AiPlayer> roster;

  const AiTeam({
    required this.id,
    required this.name,
    required this.strength,
    required this.roster,
  });
}

/// A scheduled pairing in a matchweek.
class Fixture {
  final int week; // 0-based matchweek within the season
  final String teamAId;
  final String teamBId;

  const Fixture({
    required this.week,
    required this.teamAId,
    required this.teamBId,
  });
}

/// A resolved match with both teams' workout-point scores.
class MatchResult {
  final int week;
  final String teamAId;
  final String teamBId;
  final int scoreA;
  final int scoreB;

  const MatchResult({
    required this.week,
    required this.teamAId,
    required this.teamBId,
    required this.scoreA,
    required this.scoreB,
  });
}

/// One row of the league table. Mutable — accumulated as weeks resolve.
class LeagueTeamStanding {
  final String teamId;
  final String name;
  final bool isYou;
  int position; // 1-based, assigned after sorting
  int played;
  int wins;
  int draws;
  int losses;
  int pointsFor; // total workout points scored
  int pointsAgainst;
  int leaguePoints; // 3/1/0-style table points

  LeagueTeamStanding({
    required this.teamId,
    required this.name,
    required this.isYou,
    this.position = 0,
    this.played = 0,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
    this.pointsFor = 0,
    this.pointsAgainst = 0,
    this.leaguePoints = 0,
  });

  int get diff => pointsFor - pointsAgainst;
}

/// The current-week fixture involving your team, with live/partial scores.
class LiveFixture {
  final int week; // 0-based matchweek
  final AiTeam opponent;
  final int yourScore; // your real points so far this week
  final int opponentScore; // opponent's projected/final points this week

  const LiveFixture({
    required this.week,
    required this.opponent,
    required this.yourScore,
    required this.opponentScore,
  });
}

/// The full computed league snapshot for a room's current season.
class LeagueTable {
  final LeagueDivision division;
  final DivisionTheme theme;
  final int seasonIndex;
  final int matchweeks;
  final int completedWeeks;
  final List<LeagueTeamStanding> standings; // sorted, positions assigned
  final List<AiTeam> aiTeams;
  final LiveFixture? live;
  final int promoteCount;
  final int relegateCount;

  /// Siege mode: the current week's stronghold state (null when siege is off
  /// or no week is in progress). Attached by LeagueService after the build.
  final SiegeWeekState? siege;

  /// Preparation phase: the room was created mid-week — its first matchweek
  /// starts next Monday (room-anchored campaign, no inherited losses).
  final bool preseason;

  /// Days until the first matchweek starts (only meaningful in [preseason]).
  final int daysUntilStart;

  const LeagueTable({
    required this.division,
    required this.theme,
    required this.seasonIndex,
    required this.matchweeks,
    required this.completedWeeks,
    required this.standings,
    required this.aiTeams,
    required this.live,
    required this.promoteCount,
    required this.relegateCount,
    this.siege,
    this.preseason = false,
    this.daysUntilStart = 0,
  });

  LeagueTable withSiege(SiegeWeekState? state) => LeagueTable(
        division: division,
        theme: theme,
        seasonIndex: seasonIndex,
        matchweeks: matchweeks,
        completedWeeks: completedWeeks,
        standings: standings,
        aiTeams: aiTeams,
        live: live,
        promoteCount: promoteCount,
        relegateCount: relegateCount,
        siege: state,
        preseason: preseason,
        daysUntilStart: daysUntilStart,
      );

  LeagueTable asPreseason(int daysUntil) => LeagueTable(
        division: division,
        theme: theme,
        seasonIndex: seasonIndex,
        matchweeks: matchweeks,
        completedWeeks: completedWeeks,
        standings: standings,
        aiTeams: aiTeams,
        live: live,
        promoteCount: promoteCount,
        relegateCount: relegateCount,
        siege: null,
        preseason: true,
        daysUntilStart: daysUntil,
      );

  static const String youId = '__you__';

  LeagueTeamStanding? get yourRow {
    for (final s in standings) {
      if (s.isYou) return s;
    }
    return null;
  }

  bool get seasonComplete => completedWeeks >= matchweeks;
}
