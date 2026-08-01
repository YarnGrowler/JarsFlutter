import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/league.dart';

class ScoringConfig {
  final int win;
  final int draw;
  final int loss;
  const ScoringConfig({this.win = 3, this.draw = 1, this.loss = 0});
}

class AiConfig {
  final List<String> teamNames;
  final List<String> playerNames;
  final int rosterMin;
  final int rosterMax;
  final double missWeekChance;
  final double formInertia; // AR(1) mean-reversion weight
  final double weeklyNoise;
  const AiConfig({
    required this.teamNames,
    required this.playerNames,
    this.rosterMin = 2,
    this.rosterMax = 8,
    this.missWeekChance = 0.12,
    this.formInertia = 0.6,
    this.weeklyNoise = 0.18,
  });
}

class BalanceConfig {
  final int anchorTrailingWeeks;
  final double? fallbackPerMember; // null → 7 × room.streakMinimum
  final double nominalBaselinePerMember; // for AI-vs-AI matches
  final double opponentSpread;
  const BalanceConfig({
    this.anchorTrailingWeeks = 3,
    this.fallbackPerMember,
    this.nominalBaselinePerMember = 60,
    this.opponentSpread = 0.2,
  });
}

/// Parsed `assets/leagues.json`. All league tuning lives here. Loaded once at
/// startup; if the asset is missing/invalid, a safe built-in [_fallback] is used
/// so the app never breaks on a bad config.
class LeagueConfig {
  final LeagueMode mode;
  final int teamsPerLeague; // even
  final bool incompleteSchedule;
  final int promoteCount;
  final int relegateCount;
  final ScoringConfig scoring;
  final DivisionTheme theme;
  final List<LeagueDivision> divisions; // ascending difficulty
  final AiConfig ai;
  final BalanceConfig balance;

  const LeagueConfig({
    required this.mode,
    required this.teamsPerLeague,
    required this.incompleteSchedule,
    required this.promoteCount,
    required this.relegateCount,
    required this.scoring,
    required this.theme,
    required this.divisions,
    required this.ai,
    required this.balance,
  });

  /// Matchweeks in a season = a complete single round-robin (no byes).
  int get matchweeks =>
      incompleteSchedule ? (teamsPerLeague - 2) : (teamsPerLeague - 1);

  LeagueDivision divisionByIndex(int index) =>
      divisions[index.clamp(0, divisions.length - 1)];

  LeagueDivision? divisionById(String id) {
    for (final d in divisions) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// All troop unlock names available at [divisionIndex] (cumulative).
  Set<String> unlockedTroopsThrough(int divisionIndex) {
    final out = <String>{};
    final hi = divisionIndex.clamp(0, divisions.length - 1);
    for (var i = 0; i <= hi; i++) {
      out.addAll(divisions[i].unlockTroops);
    }
    return out;
  }

  /// All new-def unlock names available at [divisionIndex] (cumulative).
  Set<String> unlockedDefsThrough(int divisionIndex) {
    final out = <String>{};
    final hi = divisionIndex.clamp(0, divisions.length - 1);
    for (var i = 0; i <= hi; i++) {
      out.addAll(divisions[i].unlockDefs);
    }
    return out;
  }

  // ── Loading ────────────────────────────────────────────────────────────────
  static LeagueConfig _instance = _fallback;
  static LeagueConfig get instance => _instance;

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('assets/leagues.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = _fromJson(map);
      _validate(parsed); // throws on bad config
      _instance = parsed;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LeagueConfig: using fallback ($e)');
      }
      _instance = _fallback;
    }
  }

  static LeagueConfig _fromJson(Map<String, dynamic> j) {
    List<String> strList(dynamic v) =>
        (v as List?)?.map((e) => e.toString()).toList() ?? const [];
    double dbl(dynamic v, double d) => (v is num) ? v.toDouble() : d;
    int intOf(dynamic v, int d) => (v is num) ? v.toInt() : d;

    final divsJson = (j['divisions'] as List?) ?? const [];
    final divisions = <LeagueDivision>[];
    for (var i = 0; i < divsJson.length; i++) {
      final d = divsJson[i] as Map<String, dynamic>;
      final ability = (d['aiAbility'] as List?) ?? const [0.7, 1.0];
      final water = (d['water'] as Map<String, dynamic>?) ?? const {};
      divisions.add(LeagueDivision(
        index: i,
        id: (d['id'] ?? 'div$i').toString(),
        metalName: (d['metal'] ?? 'Division $i').toString(),
        footballName: (d['football'] ?? 'Division $i').toString(),
        color: _parseColor(d['color']?.toString()),
        icon: (d['icon'] ?? '🏆').toString(),
        difficulty: dbl(d['difficulty'], 1.0),
        aiAbilityMin: dbl(ability.isNotEmpty ? ability[0] : 0.7, 0.7),
        aiAbilityMax: dbl(ability.length > 1 ? ability[1] : 1.0, 1.0),
        mapSize: intOf(d['mapSize'], 40 + i * 2).clamp(40, 80),
        biome: (d['biome'] ?? 'meadow').toString(),
        unlockTroops: strList(d['unlockTroops']),
        unlockDefs: strList(d['unlockDefs']),
        wards: intOf(d['wards'], 1).clamp(1, 4),
        mountainFrac: dbl(d['mountainFrac'], 0.11),
        forestFrac: dbl(d['forestFrac'], 0.16),
        waterDry: dbl(water['dry'], 0.25),
        waterLight: dbl(water['light'], 0.50),
        waterWet: dbl(water['wet'], 0.25),
      ));
    }

    final aiJson = (j['ai'] as Map<String, dynamic>?) ?? const {};
    final balJson = (j['balance'] as Map<String, dynamic>?) ?? const {};
    final scoreJson = (j['scoring'] as Map<String, dynamic>?) ?? const {};

    return LeagueConfig(
      mode: leagueModeFromString(j['mode']?.toString()),
      teamsPerLeague: intOf(j['teamsPerLeague'], 8),
      incompleteSchedule: j['incompleteSchedule'] == true,
      promoteCount: intOf(j['promoteCount'], 2),
      relegateCount: intOf(j['relegateCount'], 2),
      scoring: ScoringConfig(
        win: intOf(scoreJson['win'], 3),
        draw: intOf(scoreJson['draw'], 1),
        loss: intOf(scoreJson['loss'], 0),
      ),
      theme: divisionThemeFromString(j['theme']?.toString()),
      divisions: divisions.isEmpty ? _fallback.divisions : divisions,
      ai: AiConfig(
        teamNames: strList(aiJson['teamNames']).isEmpty
            ? _fallback.ai.teamNames
            : strList(aiJson['teamNames']),
        playerNames: strList(aiJson['playerNames']).isEmpty
            ? _fallback.ai.playerNames
            : strList(aiJson['playerNames']),
        rosterMin: intOf(aiJson['rosterMin'], 2),
        rosterMax: intOf(aiJson['rosterMax'], 8),
        missWeekChance: dbl(aiJson['missWeekChance'], 0.12),
        formInertia: dbl(aiJson['formInertia'], 0.6),
        weeklyNoise: dbl(aiJson['weeklyNoise'], 0.18),
      ),
      balance: BalanceConfig(
        anchorTrailingWeeks: intOf(balJson['anchorTrailingWeeks'], 3),
        fallbackPerMember: (balJson['fallbackPerMember'] is num)
            ? (balJson['fallbackPerMember'] as num).toDouble()
            : null,
        nominalBaselinePerMember: dbl(balJson['nominalBaselinePerMember'], 60),
        opponentSpread: dbl(balJson['opponentSpread'], 0.2),
      ),
    );
  }

  /// Fail-fast validation so a fat-fingered config can't produce a broken season.
  static void _validate(LeagueConfig c) {
    if (c.teamsPerLeague < 4 || c.teamsPerLeague.isOdd) {
      throw StateError('teamsPerLeague must be even and >= 4');
    }
    if (c.promoteCount + c.relegateCount >= c.teamsPerLeague) {
      throw StateError('promoteCount + relegateCount must be < teamsPerLeague');
    }
    if (c.divisions.isEmpty) throw StateError('divisions must be non-empty');
    for (var i = 1; i < c.divisions.length; i++) {
      if (c.divisions[i].difficulty < c.divisions[i - 1].difficulty) {
        throw StateError('divisions must ascend in difficulty');
      }
      if (c.divisions[i].mapSize < c.divisions[i - 1].mapSize) {
        throw StateError('divisions must ascend (or hold) in mapSize');
      }
    }
    if (c.ai.rosterMin > c.ai.rosterMax || c.ai.rosterMin < 1) {
      throw StateError('invalid roster bounds');
    }
    if (c.scoring.win < c.scoring.draw || c.scoring.draw < c.scoring.loss) {
      throw StateError('scoring must satisfy win >= draw >= loss');
    }
  }

  static Color _parseColor(String? hex) {
    if (hex == null) return const Color(0xFF7C6BF0);
    var h = hex.replaceFirst('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFF7C6BF0) : Color(v);
  }

  /// Safe built-in config (used if the asset is missing/invalid).
  static const LeagueConfig _fallback = LeagueConfig(
    mode: LeagueMode.fixtures,
    teamsPerLeague: 8,
    incompleteSchedule: false,
    promoteCount: 2,
    relegateCount: 2,
    scoring: ScoringConfig(),
    theme: DivisionTheme.metal,
    divisions: [
      LeagueDivision(
          index: 0,
          id: 'bronze',
          metalName: 'Bronze League',
          footballName: 'Division Four',
          color: Color(0xFFCD7F32),
          icon: '🥉',
          difficulty: 0.80,
          aiAbilityMin: 0.7,
          aiAbilityMax: 1.0,
          mapSize: 40,
          biome: 'meadow'),
      LeagueDivision(
          index: 1,
          id: 'silver',
          metalName: 'Silver League',
          footballName: 'Division Three',
          color: Color(0xFFB8C0CC),
          icon: '🥈',
          difficulty: 0.90,
          aiAbilityMin: 0.8,
          aiAbilityMax: 1.1,
          mapSize: 42,
          biome: 'autumn',
          unlockTroops: ['healer']),
      LeagueDivision(
          index: 2,
          id: 'gold',
          metalName: 'Gold League',
          footballName: 'Division Two',
          color: Color(0xFFE8B923),
          icon: '🥇',
          difficulty: 1.00,
          aiAbilityMin: 0.9,
          aiAbilityMax: 1.2,
          mapSize: 44,
          biome: 'sunscrub',
          unlockTroops: ['javelin'],
          unlockDefs: ['tributeChest', 'commandTent']),
      LeagueDivision(
          index: 3,
          id: 'platinum',
          metalName: 'Platinum League',
          footballName: 'Division One',
          color: Color(0xFF6EE7D6),
          icon: '💠',
          difficulty: 1.12,
          aiAbilityMin: 1.0,
          aiAbilityMax: 1.3,
          mapSize: 48,
          biome: 'coast',
          unlockTroops: ['fogger'],
          unlockDefs: ['pitchPot'],
          wards: 2),
      LeagueDivision(
          index: 4,
          id: 'diamond',
          metalName: 'Diamond League',
          footballName: 'Championship',
          color: Color(0xFF67C7FF),
          icon: '💎',
          difficulty: 1.25,
          aiAbilityMin: 1.1,
          aiAbilityMax: 1.45,
          mapSize: 52,
          biome: 'tundra',
          unlockTroops: ['elephant'],
          wards: 2),
      LeagueDivision(
          index: 5,
          id: 'champion',
          metalName: 'Champion League',
          footballName: 'Premier',
          color: Color(0xFFB06BF0),
          icon: '👑',
          difficulty: 1.40,
          aiAbilityMin: 1.25,
          aiAbilityMax: 1.6,
          mapSize: 56,
          biome: 'nightglass',
          wards: 3),
      LeagueDivision(
          index: 6,
          id: 'radiant',
          metalName: 'Radiant League',
          footballName: 'Elite',
          color: Color(0xFFFF7DB0),
          icon: '🌟',
          difficulty: 1.55,
          aiAbilityMin: 1.4,
          aiAbilityMax: 1.8,
          mapSize: 60,
          biome: 'ashfall',
          unlockDefs: ['citadelCore'],
          wards: 3),
    ],
    ai: AiConfig(
      teamNames: [
        'Iron Wolves',
        'Night Owls',
        'Gym Rats',
        'Barbell Club',
        'Chalk Dust',
        'Rep Machine',
        'Sweat Equity',
        'The Grinders',
        'Lactic Acid',
        'Peak Hour',
        'Failure Sets',
        'Warm Bloods',
      ],
      playerNames: [
        'Diesel', 'Ace', 'Tank', 'Cardio Carl', 'Bolt', 'Rhino', 'Nova',
        'Quads', 'Blitz', 'Sarge', 'Titan', 'Echo', 'Piston', 'Maverick',
        'Bruno', 'Vega', 'Hammer', 'Ziggy', 'Onyx', 'Rocco',
      ],
    ),
    balance: BalanceConfig(),
  );
}
