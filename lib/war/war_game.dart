import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/league_config.dart';
import '../core/seeded_rng.dart';
import '../models/league.dart';
import '../services/league_simulator.dart';
import 'war_ai.dart';
import 'war_base.dart';
import 'war_biome.dart';
import 'war_clock.dart';
import 'war_engine.dart';
import 'war_player.dart';
import 'war_scoring.dart';
import 'war_sim.dart';
import 'war_troop.dart';
import 'war_types.dart';

/// A real room member, stripped down to what the war cares about. Built by
/// the app layer from Supabase data — keeps `lib/war/` free of any Supabase
/// dependency, same as every other pure-Dart file in this package.
class RosterMember {
  final String id;
  final String name;
  const RosterMember(this.id, this.name);
}

/// Live view over the players' pools — the ONE source of truth for money.
/// Prep, raids, defense, and income all read/write the same numbers, so
/// nothing desyncs and nothing is lost on navigation.
class PlayerPools implements WarPools {
  final WarGame g;
  PlayerPools(this.g);
  WarPlayer? _find(String id) {
    for (final p in g.players) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  double of(String id) => _find(id)?.resources ?? 0;
  @override
  bool spend(String id, double amt) {
    final p = _find(id);
    if (p == null || p.resources < amt) return false;
    p.resources -= amt;
    return true;
  }

  @override
  void add(String id, double amt) => _find(id)?.resources += amt;
}

/// The Clan War master. One shared base per clan, per-player resource pools,
/// a simulated war day you fast-forward through, hands-on raids for the player
/// you're controlling, and a season leaderboard (reusing [LeagueSimulator]).
class WarGame extends ChangeNotifier {
  WarGame._();
  static WarGame? _i;
  static WarGame get instance => _i ??= WarGame._();
  @visibleForTesting
  static set instance(WarGame g) => _i = g;
  @visibleForTesting
  factory WarGame.fresh() => WarGame._();

  // v12: the content war — new units/defenses, hills, L3s, knockout stakes
  static const _prefsKey = 'war_game_v12';
  static const String seedKey = 'jars-clanwar';
  static const String clanName = 'Your Crew';

  // ── persistent state ────────────────────────────────────────────────────────
  int warSeed = 1;
  WarPhase phase = WarPhase.prep;
  int seasonIndex = 0;
  int warIndex = 0; // war number within the season
  int worldGen = 0; // bumped on season reset → a brand-new WORLD, not a rerun
  int divisionIndex = 0;

  /// Peak battlefield side length. Never shrinks on relegation; grows on promote.
  int mapSize = Base.defaultSize;

  /// Sim-minutes already paid out by War Generators (wall-clock catch-up cursor).
  int lastGeneratorAccrueMin = 0;

  AiLevel enemyDifficulty = AiLevel.seasoned;

  /// The 1..100 war dial. 50 ~ old Master; past it the enemy grows crueler
  /// than any preset tier (skill up to 1.5).
  int difficulty = 50;
  String enemyClanName = 'The Enemy';

  /// slider → effective enemy skill (0.3 .. 1.5)
  static double skillFor(int difficulty) =>
      (0.3 + (difficulty.clamp(1, 100) / 100) * 1.2);
  final WarClock clock = WarClock();
  final List<WarPlayer> players = [];
  String activePlayerId = 'you';
  late Base youBase;
  late Base enemyBase;

  // ── the wall clock: the war runs on REAL time, not a button ─────────────────
  /// Real epoch-ms when the current war began. 0 = no war anchored. Whenever
  /// the app opens, [syncToWallClock] replays every enemy raid that "should"
  /// have happened since — the crew comes home to a war that kept raging.
  int warStartedAtMs = 0;

  /// How much real time one simulated war-hour costs. A war day is
  /// [WarClock.dayMinutes] sim-hours (16), so at 3600 seconds (1 real hour)
  /// per sim-hour a whole war unfolds over 16 real hours — Clash-style raid
  /// windows, not a compressed demo.
  static const int realSecondsPerSimHour = 3600;

  /// Wall-clock source, seam-injected so tests can time-travel. This drives ONLY
  /// how many hours have elapsed — each raid is still seeded, so catch-up is
  /// deterministic.
  static int Function() nowMs = () => DateTime.now().millisecondsSinceEpoch;

  int enemyBaseFellAt = -1, youBaseFellAt = -1;
  final List<WarLogEntry> feed = [];
  List<bool?> seasonResults = [];
  WarVerdict? lastVerdict;

  /// The in-progress hands-on raid. Persists across navigation, fast-forward,
  /// and app restarts; only END RAID (or the war ending) banks it.
  AttackState? liveAttack;

  /// The most recent enemy raid on YOUR base, watchable on the defense board.
  List<RaidFrame>? lastEnemyReplay;
  String lastEnemyRaider = '';

  /// Shared clan fog: everything YOUR clan has scouted on the enemy base, and
  /// everything THEIR clan has scouted on yours. Persists across raids.
  Set<int> youIntel = {};
  Set<int> enemyIntel = {};

  late final PlayerPools pools = PlayerPools(this);
  final LeagueSimulator _sim = LeagueSimulator();
  LeagueConfig get _lcfg => LeagueConfig.instance;
  int get warsPerSeason => _lcfg.matchweeks;

  LeagueDivision get currentDivision => _lcfg.divisionByIndex(divisionIndex);

  WarBiome get currentBiome =>
      WarBiome.of(warBiomeFromString(currentDivision.biome));

  TerrainConfig _terrainForDivision([LeagueDivision? d]) {
    final div = d ?? currentDivision;
    return TerrainConfig(
      mountainFrac: div.mountainFrac,
      forestFrac: div.forestFrac,
      waterDry: div.waterDry,
      waterLight: div.waterLight,
      waterWet: div.waterWet,
    );
  }

  /// Sync peak [mapSize] up to the current division (never shrinks).
  void _syncMapSize() {
    final want = currentDivision.mapSize;
    if (want > mapSize) mapSize = want;
    if (mapSize < Base.defaultSize) mapSize = Base.defaultSize;
  }

  bool troopUnlocked(TroopType t) {
    if (!kLeagueGatedTroops.contains(t)) return true;
    return _lcfg
        .unlockedTroopsThrough(divisionIndex)
        .contains(troopUnlockKey(t));
  }

  bool defUnlocked(DefType t) {
    if (!kLeagueGatedDefs.contains(t)) return true;
    return _lcfg.unlockedDefsThrough(divisionIndex).contains(defUnlockKey(t));
  }

  /// Lowest division index that unlocks [t], or -1 if always free.
  int troopUnlockDivision(TroopType t) {
    if (!kLeagueGatedTroops.contains(t)) return -1;
    final key = troopUnlockKey(t);
    for (final d in _lcfg.divisions) {
      if (d.unlockTroops.contains(key)) return d.index;
    }
    return _lcfg.divisions.length - 1;
  }

  int defUnlockDivision(DefType t) {
    if (!kLeagueGatedDefs.contains(t)) return -1;
    final key = defUnlockKey(t);
    for (final d in _lcfg.divisions) {
      if (d.unlockDefs.contains(key)) return d.index;
    }
    return _lcfg.divisions.length - 1;
  }

  /// Gated defenses unlocked through the current rung (for AI builders).
  Set<DefType> get unlockedDefsNow {
    final keys = _lcfg.unlockedDefsThrough(divisionIndex);
    return {
      for (final t in kLeagueGatedDefs)
        if (keys.contains(defUnlockKey(t))) t,
    };
  }

  /// Gated troops unlocked through the current rung (for AI waves).
  Set<TroopType> get unlockedTroopsNow {
    final keys = _lcfg.unlockedTroopsThrough(divisionIndex);
    return {
      for (final t in kLeagueGatedTroops)
        if (keys.contains(troopUnlockKey(t))) t,
    };
  }

  /// Max permanent troop doctrine level purchasable at the current rung.
  /// Bronze → L2, Silver → L3, … Diamond+ → L6.
  int get troopDoctrineCap =>
      (2 + divisionIndex).clamp(2, Xp.maxLevel);

  int troopDoctrineCapFor(int divIndex) =>
      (2 + divIndex).clamp(2, Xp.maxLevel);

  // ── rosters ─────────────────────────────────────────────────────────────────
  // The solo/offline fallback crew — used only when no real room is wired in
  // (fresh installs before onboarding, the practice sandbox, and every
  // existing test). The moment [applyRoomRoster] runs, these never appear.
  static const List<List<Object>> _crewChars = [
    ['casey', 'Casey', '🐐', 0xFF35D0BA],
    ['wade', 'Wade', '🐻', 0xFFFF8A3D],
    ['finn', 'Finn', '🦊', 0xFF9B6BFF],
  ];
  static const List<List<Object>> _enemyChars = [
    ['grik', 'Grik', '💀', 0xFFE6483F],
    ['mara', 'Mara', '👺', 0xFFD24357],
    ['vorn', 'Vorn', '👹', 0xFFC0424F],
    ['zyla', 'Zyla', '🐗', 0xFFE05A47],
    ['skarr', 'Skarr', '🐍', 0xFFB8443C],
    ['nyx', 'Nyx', '🦂', 0xFF8B3A62],
    ['thorne', 'Thorne', '🐗', 0xFF6B4E2E],
    ['ravok', 'Ravok', '🦇', 0xFF4A3A5C],
    ['grendel', 'Grendel', '🐊', 0xFF3E6B4E],
    ['ash', 'Ash', '👻', 0xFF7A7A8C],
    ['korth', 'Korth', '🦍', 0xFF5C4A3A],
    ['viper', 'Viper', '🐲', 0xFF2E7D5C],
  ];

  // Real teammates keep their own username, so no name palette is needed —
  // just something visual to tell them apart on the crew strip.
  static const List<String> _rosterEmoji = [
    '🦊', '🐻', '🐺', '🦉', '🐸', '🐢', '🦅', '🐝',
    '🦁', '🐯', '🐼', '🐨', '🦝', '🐿', '🦔', '🐙',
  ];
  static const List<int> _rosterColors = [
    0xFF35D0BA, 0xFFFF8A3D, 0xFF9B6BFF, 0xFF4ADE80,
    0xFFFF6B9D, 0xFF60A5FA, 0xFFFBBF24, 0xFFA78BFA,
    0xFF2DD4BF, 0xFFF97316, 0xFF818CF8, 0xFF34D399,
  ];
  static String _emojiFor(String id) =>
      _rosterEmoji[id.hashCode.abs() % _rosterEmoji.length];
  static int _colorFor(String id) =>
      _rosterColors[(id.hashCode.abs() ~/ 7) % _rosterColors.length];

  /// The real Supabase room this war belongs to, once wired in via
  /// [applyRoomRoster]. Null = solo/offline mode (tests, practice sandbox,
  /// pre-onboarding) — every existing local-only behavior is unchanged.
  String? roomId;

  /// The last version of the room's war row we KNOW we're in sync with —
  /// every save is a compare-and-swap against this (see `onRoomSave`). Not
  /// part of [toJson]: it's a sync-layer bookkeeping number, not game state.
  int roomVersion = 0;

  /// Bumped whenever a teammate's save beat ours to the server and we had to
  /// reload their version instead of ours. The war hub watches this to show
  /// a brief "a teammate just updated the base" notice.
  int syncConflicts = 0;

  /// Whether THIS device's signed-in user runs the room (`Room.adminId`).
  /// Solo/offline play defaults true — you're always the admin of your own
  /// local game. Set by the app layer (see `warRoomSyncProvider`); not
  /// persisted — it's re-derived from the real room every session, never
  /// trusted from a shared blob (same principle as `activePlayerId`).
  bool isRoomAdmin = true;

  /// Workout ⚡ logged before [roomId] was seated to that room (War sync still
  /// catching up). Flushed in [applyRoomRoster] so a wall-sit right after
  /// opening the app never silently evaporates.
  final Map<String, double> _pendingWorkoutEarn = {};

  /// ⚡ credited locally but not yet confirmed on the room war row. A sync
  /// conflict must put these back on [ _unsyncedEarnPlayerId ] after reload.
  double _unsyncedEarn = 0;
  String? _unsyncedEarnPlayerId;

  /// War-wide controls (who's fighting whom, how hard, when the day starts)
  /// are the room admin's call in a real room — nobody wants a teammate's
  /// stray tap resetting the season or cranking the difficulty for
  /// everyone. Per-player actions (building, training, raiding, readying up)
  /// are never gated here; they only ever touch the acting player's own
  /// resources and are already scoped correctly.
  bool get canControlWar => roomId == null || isRoomAdmin;

  List<WarPlayer> get youClan =>
      players.where((p) => p.side == WarSide.you).toList();
  List<WarPlayer> get enemyClan =>
      players.where((p) => p.side == WarSide.enemy).toList();
  WarPlayer get active =>
      players.firstWhere((p) => p.id == activePlayerId, orElse: () => players.first);

  /// A fighter whose own castle is RAZED is out of the war — spectator only.
  bool knockedOut(WarPlayer p) {
    final ownBase = p.side == WarSide.you ? youBase : enemyBase;
    final cell = ownBase.castles[p.id];
    if (cell == null) return false;
    final s = ownBase.structAt(cell.r, cell.c);
    return s == null || s.hp <= 0;
  }

  double get youDestruction => enemyBase.destructionPercent; // your clan dealt
  double get enemyDestruction => youBase.destructionPercent; // enemy clan dealt

  /// ⚡ currently sitting in the stronghold under [p]'s name (place + upgrades).
  /// Castles are free. Sold pieces drop out of the total automatically.
  double defenseSpentOf(WarPlayer p) {
    final base = p.side == WarSide.you ? youBase : enemyBase;
    var total = 0.0;
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s == null || !s.alive || s.ownerId != p.id) continue;
        total += s.investedCost;
      }
    }
    return total;
  }

  /// ⚡ poured into the attack this war (training + raid costs).
  double offenseSpentOf(WarPlayer p) => p.resourcesSpent;

  double clanOffense(List<WarPlayer> clan) =>
      clan.fold(0.0, (a, p) => a + offenseSpentOf(p));

  double clanDefense(List<WarPlayer> clan) =>
      clan.fold(0.0, (a, p) => a + defenseSpentOf(p));

  /// Offense / defense leaders for the spenders sheet, highest first.
  List<WarPlayer> biggestOffenseSpenders({int limit = 5}) {
    final all = [...youClan, ...enemyClan]
      ..sort((a, b) => offenseSpentOf(b).compareTo(offenseSpentOf(a)));
    return all.where((p) => offenseSpentOf(p) > 0).take(limit).toList();
  }

  List<WarPlayer> biggestDefenseSpenders({int limit = 5}) {
    final all = [...youClan, ...enemyClan]
      ..sort((a, b) => defenseSpentOf(b).compareTo(defenseSpentOf(a)));
    return all.where((p) => defenseSpentOf(p) > 0).take(limit).toList();
  }

  double resourcesOf(String id) => pools.of(id);

  /// Widgets kick the game from initState/dispose (start a clash, bank a
  /// raid, log a workout mid-build) — notifying during the build phase trips
  /// Riverpod's modify-while-building assertion. Any notification that lands
  /// inside a frame's build/layout/paint is deferred to the frame's end.
  bool _notifyQueued = false;
  @override
  void notifyListeners() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks ||
        binding.schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
      if (_notifyQueued) return;
      _notifyQueued = true;
      binding.addPostFrameCallback((_) {
        _notifyQueued = false;
        super.notifyListeners();
      });
    } else {
      super.notifyListeners();
    }
  }

  void _buildRosters() {
    players.clear();
    players.add(WarPlayer(
        id: 'you',
        name: 'You',
        emoji: '🦁',
        colorValue: 0xFF2E6BE6,
        side: WarSide.you,
        ai: AiLevel.master,
        isYou: true));
    for (final c in _crewChars) {
      players.add(WarPlayer(
          id: c[0] as String,
          name: c[1] as String,
          emoji: c[2] as String,
          colorValue: c[3] as int,
          side: WarSide.you,
          ai: AiLevel.seasoned,
          isBot: true));
    }
    final n = youClan.length;
    for (var i = 0; i < n; i++) {
      final c = _enemyChars[i % _enemyChars.length];
      players.add(WarPlayer(
          id: 'foe_$i',
          name: c[1] as String,
          emoji: c[2] as String,
          colorValue: c[3] as int,
          side: WarSide.enemy,
          ai: enemyDifficulty,
          isBot: true));
    }
    activePlayerId = 'you';
  }

  /// Seat the REAL crew: your side becomes exactly [members] — no fake AI
  /// teammates — and the enemy clan is generated to match that headcount, one
  /// foe per real friend. Call once you have the room's member list (from
  /// `RoomService.getRoomMembers`); re-wiring the same room with an unchanged
  /// roster is a cheap no-op so callers can invoke it freely on every rebuild.
  ///
  /// [members] must NOT include yourself — you're added separately as the
  /// human always known as "you" on your own device.
  void applyRoomRoster({
    required String realRoomId,
    required String myUserId,
    required String myUsername,
    required List<RosterMember> members,
  }) {
    final want = {myUserId, ...members.map((m) => m.id)};
    final have = players.where((p) => p.side == WarSide.you).map((p) => p.id);
    if (roomId == realRoomId && want.length == have.length && want.containsAll(have)) {
      // Same crew, already seated — BUT a remote sync (a teammate's save,
      // or the initial load) may have just overwritten `activePlayerId`
      // with WHOEVER last saved from THEIR device. This device is never
      // controlled by anyone but its own signed-in user — full stop. This
      // is the exact bug that let one player's building silently spend a
      // teammate's resources: `activePlayerId` is per-device identity, it
      // must NEVER be trusted from a shared blob.
      var dirty = false;
      if (activePlayerId != myUserId) {
        activePlayerId = myUserId;
        dirty = true;
      }
      final pending = _pendingWorkoutEarn[realRoomId] ?? 0;
      _flushPendingWorkoutEarn();
      if (pending > 0) dirty = true;
      if (dirty) {
        _save();
        notifyListeners();
      }
      return;
    }
    roomId = realRoomId;
    // A stale crew's castles (the solo/offline bot crew's auto-built ones,
    // or a friend who's since left) must never linger once the roster no
    // longer includes them — otherwise "how many castles are down" reads
    // wrong forever and orphaned structures clutter the base.
    youBase.pruneCastlesNotIn(want);
    // A roster reconciliation (a teammate joins/leaves, or a device just
    // catches up) must never wipe anyone's earned progress — carry every
    // still-present player's pool/army/tallies forward by id instead of
    // rebuilding them from scratch.
    final prior = {for (final p in players) p.id: p};
    WarPlayer seat(WarPlayer fresh) {
      final old = prior[fresh.id];
      if (old == null) return fresh;
      fresh.resources = old.resources;
      fresh.army = old.army;
      fresh.troopDoctrine = old.troopDoctrine;
      fresh.ready = old.ready;
      fresh.troopsLost = old.troopsLost;
      fresh.resourcesSpent = old.resourcesSpent;
      fresh.destructionDealt = old.destructionDealt;
      fresh.prepEarned = old.prepEarned;
      return fresh;
    }
    players.clear();
    players.add(seat(WarPlayer(
        id: myUserId,
        name: myUsername,
        emoji: '🦁',
        colorValue: 0xFF2E6BE6,
        side: WarSide.you,
        ai: AiLevel.master,
        isYou: true)));
    for (final m in members) {
      // Real teammates, never bots — they design and place their own base
      // sector (see startPrep's aiCrew filter).
      players.add(seat(WarPlayer(
          id: m.id,
          name: m.name,
          emoji: _emojiFor(m.id),
          colorValue: _colorFor(m.id),
          side: WarSide.you,
          ai: AiLevel.seasoned)));
    }
    final n = youClan.length;
    for (var i = 0; i < n; i++) {
      final c = _enemyChars[i % _enemyChars.length];
      final wave = i ~/ _enemyChars.length;
      final name = wave == 0 ? c[1] as String : '${c[1]} ${_romanNumeral(wave + 1)}';
      players.add(seat(WarPlayer(
          id: 'foe_$i',
          name: name,
          emoji: c[2] as String,
          colorValue: c[3] as int,
          side: WarSide.enemy,
          ai: enemyDifficulty,
          isBot: true)));
    }
    activePlayerId = myUserId;
    _flushPendingWorkoutEarn();
    _save();
    notifyListeners();
  }

  static String _romanNumeral(int n) {
    const table = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];
    return n >= 1 && n <= table.length ? table[n - 1] : '$n';
  }

  // ── PREP ────────────────────────────────────────────────────────────────────
  void startPrep() {
    phase = WarPhase.prep;
    warSeed = seedFromParts([seedKey, worldGen, seasonIndex, warIndex]).abs();
    _syncMapSize();
    const clanNames = [
      'Iron Wolves', 'Bone Legion', 'The Red Banners', 'Storm Callers',
      'Ash Walkers', 'The Broken Tusk', 'Night Ravens', 'Granite Sons',
      'The Ember Guard', 'Salt Fang', 'Hollow Kings', 'The Briar Pact',
    ];
    enemyClanName = clanNames[warSeed % clanNames.length];
    if (players.isEmpty) _buildRosters();
    final terr = _terrainForDivision();
    youBase = Base(WarSide.you, warSeed, config: terr, size: mapSize);
    enemyBase = Base(WarSide.enemy, warSeed, config: terr, size: mapSize);
    clock.simMinutes = 0;
    enemyBaseFellAt = -1;
    youBaseFellAt = -1;
    feed.clear();
    lastVerdict = null;
    liveAttack = null;
    clashState = null;
    lastEnemyReplay = null;
    lastEnemyRaider = '';
    youIntel = {};
    enemyIntel = {};
    for (final p in players) {
      p.ready = false;
      p.resetWarTallies(); // zeroes prepEarned — fresh ledger for THIS prep
      // Real players KEEP leftover ⚡ from the last war and get a small
      // prep stipend on top. Bots still get a flat build chest. Enemies
      // get nothing until startWar sizes their fort budget.
      if (p.side == WarSide.enemy) {
        p.resources = 0;
      } else if (p.isBot) {
        p.resources = WarCosts.prepBudget;
      } else {
        p.resources += WarCosts.realPlayerPrepStipend;
        p.prepEarned = WarCosts.realPlayerPrepStipend;
      }
    }
    // Your BOT crewmates' share of the base builds immediately (solo/offline
    // only) — real teammates (isBot == false) place their own castle and
    // structures, never auto-built. The ENEMY base is deliberately NOT built
    // here anymore — see startWar().
    final aiCrew = youClan.where((p) => p.isBot).toList();
    if (aiCrew.isNotEmpty) {
      WarAi.designBase(
          youBase, aiCrew, SeededRng(seedFromParts([warSeed, 'crewDesign'])));
    }
    _save();
    notifyListeners();
  }

  // editor actions (as the active human, on your base)
  String? placeCastle(int r, int c) {
    if (phase != WarPhase.prep) return null;
    if (!youBase.canPlace(r, c)) return 'Blocked ground.';
    // moving an existing castle refunds nothing (free), just relocate
    youBase.placeCastle(active.id, r, c);
    _save();
    notifyListeners();
    return null;
  }

  String? placeStructure(int r, int c, DefType type) {
    if (phase != WarPhase.prep) return 'Prep is over.';
    if (!defUnlocked(type)) {
      final div = _lcfg.divisionByIndex(defUnlockDivision(type));
      return '${kDefSpecs[type]!.name} unlocks in ${div.metalName}.';
    }
    if (type == DefType.commandTent) {
      for (var rr = 0; rr < youBase.rows; rr++) {
        for (var cc = 0; cc < youBase.cols; cc++) {
          final s = youBase.structAt(rr, cc);
          if (s != null &&
              s.type == DefType.commandTent &&
              s.ownerId == active.id) {
            return 'You already have a Command Tent.';
          }
        }
      }
    }
    if (type == DefType.citadelCore) {
      for (var rr = 0; rr < youBase.rows; rr++) {
        for (var cc = 0; cc < youBase.cols; cc++) {
          final s = youBase.structAt(rr, cc);
          if (s != null && s.type == DefType.citadelCore) {
            return 'The crew already has a Citadel Core.';
          }
        }
      }
    }
    final cost = kDefSpecs[type]!.cost;
    if (active.resources < cost) return 'Need $cost points.';
    if (!youBase.canPlace(r, c)) return 'Can\'t build there.';
    youBase.place(r, c, type, active.id);
    active.resources -= cost;
    _save();
    notifyListeners();
    return null;
  }

  /// Display name of whoever paid for the piece at (r, c), or null when the
  /// tile is empty or its owner has left the room.
  String? structureOwnerName(int r, int c) {
    final s = youBase.structAt(r, c);
    if (s == null) return null;
    final i = players.indexWhere((p) => p.id == s.ownerId);
    return i == -1 ? null : players[i].name;
  }

  /// The base is shared, but a real teammate's build is *theirs* — you can't
  /// bulldoze what someone else paid for. AI crewmates (solo/offline) and
  /// players who have left the room have nobody to object, so their leftovers
  /// stay clearable.
  bool canRemoveStructure(int r, int c) {
    final s = youBase.structAt(r, c);
    if (s == null || s.isCastle) return false; // castles are sacred
    if (s.ownerId == active.id) return true;
    final i = players.indexWhere((p) => p.id == s.ownerId);
    return i == -1 || players[i].isBot;
  }

  String? removeStructure(int r, int c) {
    if (phase != WarPhase.prep) return 'Prep is over.';
    final s = youBase.structAt(r, c);
    if (s == null) return null;
    if (s.isCastle) return 'Castles are sacred.';
    if (!canRemoveStructure(r, c)) {
      final who = structureOwnerName(r, c) ?? 'A crewmate';
      return '$who built that — only they can sell it.';
    }
    // The refund goes to the OWNER. If the owner has since left the room,
    // nobody gets a free refund for materials they didn't pay for (mirrors
    // pruneCastlesNotIn: a departed player's stuff is gone, not up for grabs).
    final ownerIndex = players.indexWhere((p) => p.id == s.ownerId);
    final refund = youBase.removeAt(r, c);
    if (ownerIndex != -1) players[ownerIndex].resources += refund;
    _save();
    notifyListeners();
    return null;
  }

  /// Upgrade any upgradable defense: +30% hp, +25% damage, gilded look
  /// (tents get +2 patrol and the pavilion instead).
  String? upgradeStructure(int r, int c) {
    if (phase != WarPhase.prep) return 'Upgrades are a prep-day job.';
    final s = youBase.structAt(r, c);
    if (s == null || s.spec.upgradeCost <= 0) {
      return 'That piece cannot be upgraded.';
    }
    if (s.isCastle) return 'Castles are beyond upgrading.';
    if (s.level >= s.spec.maxLevel) return 'Fully upgraded.';
    final cost = s.spec.upgradeCost * s.level; // L2→L3 costs double
    if (active.resources < cost) {
      return 'Need $cost ⚡ to upgrade.';
    }
    active.resources -= cost.toDouble();
    s.level++;
    s.hp = s.maxHp; // fresh reinforcement
    _save();
    notifyListeners();
    return null;
  }

  void readyUp() {
    active.ready = true;
    _save();
    notifyListeners();
  }

  bool get allReady => youClan.every((p) => p.ready);

  /// Has the player CURRENTLY at the controls placed their own castle yet
  /// (the builder's "place your castle first" hint). Per-player — everyone
  /// on the crew has their own answer to this.
  bool get activeHasCastle => youBase.castles.containsKey(active.id);

  /// Has ANYONE on the crew placed a castle — not everyone has to. The
  /// admin can start the war the moment a single castle is down.
  bool get anyCastlePlaced => youBase.castles.isNotEmpty;

  /// Crew who actually showed up for prep (placed their own castle). Idle
  /// roommates stay on the roster and still get an auto-castle at war start,
  /// but they must NOT inflate the enemy's headcount or build chest.
  ///
  /// Real rooms: only humans who placed (solo bot crewmates are ignored).
  /// Solo/offline: whoever on your side already has a castle.
  List<WarPlayer> get warParticipants {
    final placed = [
      for (final p in youClan)
        if (youBase.castles.containsKey(p.id)) p
    ];
    if (roomId != null) {
      return [for (final p in placed) if (!p.isBot) p];
    }
    return placed;
  }

  /// How many enemy castles / raid bots this war fields — one per participant,
  /// never one per idle roster seat.
  int get enemyWarSlots {
    final n = warParticipants.length;
    return n > 0 ? n : 1;
  }

  /// slider → effective enemy skill (0.3 .. 1.5), FLOORED by how far your
  /// clan has climbed the league — Bronze asks nothing extra, Radiant floors
  /// you into citadel territory even if nobody's touched the difficulty
  /// dial. Whichever is HIGHER (dial or league) wins.
  double _effectiveEnemySkill() {
    final divCount = math.max(1, _lcfg.divisions.length - 1);
    final leagueFloor = 0.3 + (divisionIndex / divCount) * 0.8;
    return math.max(skillFor(difficulty), leagueFloor);
  }

  double get _enemyForgeMultiplier {
    final areaMul = (mapSize * mapSize) /
        (Base.defaultSize * Base.defaultSize).toDouble();
    return mapSize >= 60
        ? areaMul * 2.6
        : mapSize >= 52
            ? areaMul * 1.7
            : areaMul;
  }

  /// Estimated total build chest the enemy team receives when war starts.
  /// Matches [startWar]: participant prep × mirror + skill budget × fighter
  /// slots (idle roster seats do not count).
  double get estimatedEnemyWarChest {
    if (enemyClan.isEmpty) return 0;
    final fighters = warParticipants;
    // Real rooms: only castle-placers fund the floor (idle seats don't).
    // Solo/offline: the human's prep always counts for the preview.
    // Before anyone places, fall back to every real crewmate's prep so the
    // difficulty dial still moves the estimate.
    final List<WarPlayer> prepSource;
    if (roomId == null) {
      prepSource = youClan.where((p) => !p.isBot).toList();
    } else if (fighters.isNotEmpty) {
      prepSource = fighters;
    } else {
      prepSource = youClan.where((p) => !p.isBot).toList();
    }
    final crewFloor =
        prepSource.fold(0.0, (sum, p) => sum + p.prepEarned) *
            WarCosts.enemyPrepMirror;
    final slots = enemyWarSlots;
    final basePerFoe =
        WarCosts.prepBudgetFor(_effectiveEnemySkill()) * _enemyForgeMultiplier;
    return crewFloor + basePerFoe * slots;
  }

  double get estimatedEnemyWarChestPerFoe =>
      enemyClan.isEmpty ? 0 : estimatedEnemyWarChest / enemyWarSlots;

  static AiLevel _tierForSkill(double s) => s >= 0.9
      ? AiLevel.master
      : s >= 0.65
          ? AiLevel.elite
          : s >= 0.4
              ? AiLevel.seasoned
              : AiLevel.rookie;

  // ── WAR ─────────────────────────────────────────────────────────────────────
  void startWar() {
    if (!canControlWar) return; // only the room admin starts the war

    // Snapshot who actually prepped BEFORE we auto-castle the idle seats —
    // those fighters alone size the enemy and fund its build chest.
    final fighters = warParticipants.isNotEmpty
        ? List<WarPlayer>.of(warParticipants)
        : youClan.where((p) => !p.isBot).toList();
    _trimEnemyClan(math.max(1, fighters.length));

    // Idle crewmates still get a castle so the base isn't soft-locked, but
    // they already lost their vote on enemy strength above.
    for (final p in youClan) {
      if (!youBase.castles.containsKey(p.id)) {
        final spot = _fallbackCastle(youBase, youBase.castles.length);
        if (spot != null) youBase.placeCastle(p.id, spot.r, spot.c);
      }
    }

    // ── the build phase just ended — THIS is when the enemy's stronghold
    // is sized and built. Chest = participant prep × mirror + skill budget
    // per FIGHTING foe (not per idle roommate). ──
    final crewTotal =
        fighters.fold(0.0, (sum, p) => sum + p.prepEarned) *
            WarCosts.enemyPrepMirror;
    final foes = enemyClan;
    if (foes.isNotEmpty) {
      final effSkill = _effectiveEnemySkill();
      final tier = _tierForSkill(effSkill);
      enemyDifficulty = tier;
      final perFoeFloor = crewTotal / foes.length;
      // A bigger board needs a bigger war chest or the fortress spreads thin
      // and every promotion feels like a WEAKER enemy. Radiant-band boards
      // get an extra forge budget so L4/L5 steel actually gets paid for.
      final forgeMul = _enemyForgeMultiplier;
      for (final p in foes) {
        p.ai = tier;
        p.skillMul = effSkill / AiData.skill(tier);
        p.resources = perFoeFloor + WarCosts.prepBudgetFor(p.skill) * forgeMul;
      }
      // Wards raise the FLOOR under the citadel plan — they never cap it, or
      // climbing the ladder would shrink the enemy's city.
      final wards = currentDivision.wards;
      WarAi.designBase(
        enemyBase,
        foes,
        SeededRng(seedFromParts([warSeed, 'enemyDesign'])),
        style: StrongholdStyle(
          minRooms: wards >= 2 ? 8 + wards * 6 : null,
          unlockDefs: unlockedDefsNow,
        ),
      );
    }

    phase = WarPhase.war;
    clock.simMinutes = 0;
    lastGeneratorAccrueMin = 0;
    warStartedAtMs = nowMs(); // the wall clock starts ticking now
    for (final p in players) {
      // Enemies and bots get a fresh war-day raid chest. Real players KEEP
      // whatever they didn't spend in prep and receive a small war stipend
      // on top — leftover ⚡ is never wiped at the phase change.
      if (p.side == WarSide.enemy) {
        p.resources = WarCosts.warStartResources * (0.75 + p.skill);
      } else if (p.isBot) {
        p.resources = WarCosts.warStartResources;
      } else {
        p.resources += WarCosts.realPlayerWarStipend;
      }
      p.resetWarTallies();
    }
    feed.clear();
    liveAttack = null;
    clashState = null;
    lastEnemyReplay = null;
    lastEnemyRaider = '';
    youIntel = {};
    enemyIntel = {};
    enemyBaseFellAt = -1;
    youBaseFellAt = -1;
    _save();
    notifyListeners();
  }

  /// Drop surplus enemy bots so the war mirrors [keep] fighters — not the
  /// full room roster. Call before [WarAi.designBase] so idle seats never
  /// buy the enemy extra castles or hourly raid rolls.
  void _trimEnemyClan(int keep) {
    final foes = enemyClan;
    if (foes.length <= keep) return;
    final drop = {for (final p in foes.skip(keep)) p.id};
    players.removeWhere((p) => drop.contains(p.id));
    enemyBase.pruneCastlesNotIn({for (final p in enemyClan) p.id});
  }

  Cell? _fallbackCastle(Base base, int i) {
    for (var r = 1; r < base.rows - 1; r++) {
      for (var c = 1; c < base.cols - 1; c++) {
        if (base.canPlace(r, c)) return Cell(r, c);
      }
    }
    return null;
  }

  // ── Training Grounds (armies are trained, then deployed for free) ──────────
  /// Train one [type] for the active player. Instant. Returns an error or null.
  String? trainTroop(TroopType type) {
    if (phase == WarPhase.war && knockedOut(active)) {
      return 'Your castle has fallen — you fight no more this war.';
    }
    if (type == TroopType.general) {
      return 'Generals are fielded by Command Tents — not trained.';
    }
    if (!troopUnlocked(type)) {
      final div = _lcfg.divisionByIndex(troopUnlockDivision(type));
      return '${kTroopSpecs[type]!.name} unlocks in ${div.metalName}.';
    }
    final cost = kTroopSpecs[type]!.cost.toDouble();
    if (active.resources < cost) {
      return 'Need ${cost.round()} ⚡ — log a workout to earn more.';
    }
    active.resources -= cost;
    active.resourcesSpent += cost; // offense ledger: training counts in prep too
    active.army[type] = (active.army[type] ?? 0) + 1;
    _save();
    notifyListeners();
    return null;
  }

  /// Buy the next permanent doctrine level for [type] (one-time, personal).
  /// League caps how high you can go (Bronze max L2, … Diamond+ max L6).
  String? upgradeTroopDoctrine(TroopType type) {
    if (type == TroopType.general) {
      return 'Generals aren\'t trained — Command Tents field them.';
    }
    if (!troopUnlocked(type)) {
      final div = _lcfg.divisionByIndex(troopUnlockDivision(type));
      return '${kTroopSpecs[type]!.name} unlocks in ${div.metalName}.';
    }
    final cur = active.doctrineLevel(type);
    final cap = troopDoctrineCap;
    if (cur >= cap) {
      if (cur >= Xp.maxLevel) {
        return '${kTroopSpecs[type]!.name} is already maxed (L$cur).';
      }
      final nextDiv = _lcfg.divisions
          .where((d) => troopDoctrineCapFor(d.index) > cur)
          .toList();
      final name = nextDiv.isEmpty
          ? 'a higher league'
          : nextDiv.first.metalName;
      return 'L${cur + 1} needs $name.';
    }
    final next = cur + 1;
    final cost = WarCosts.troopDoctrineCost(type, next);
    if (active.resources < cost) {
      return 'Need ${cost.round()} ⚡ to unlock L$next.';
    }
    active.resources -= cost;
    // Doctrine is a permanent unlock, not a war-day offense/defense tally.
    active.troopDoctrine[type] = next;
    _save();
    notifyListeners();
    return null;
  }

  /// Deploy a trained troop from the active player's army (no ⚡ charge — it
  /// was paid at the Training Grounds). Lands at the player's doctrine level.
  /// [allowStack] is for Free Move raids where tiles aren't exclusive slots.
  Troop? deployTrained(AttackState st, TroopType type, int r, int c,
      {bool allowStack = false}) {
    if (knockedOut(active)) return null; // the fallen only spectate
    if ((active.army[type] ?? 0) <= 0) return null;
    final t =
        st.spawn(type, active.id, r, c, prepaid: true, allowStack: allowStack);
    if (t != null) {
      final doctrine = active.doctrineLevel(type);
      if (doctrine > 1) {
        t.gainXp(Xp.perLevel * (doctrine - 1) + 1.0);
      }
      active.army[type] = active.army[type]! - 1;
      _save();
      notifyListeners();
    }
    return t;
  }

  /// 🪓 Prep-phase forest clearing (permanent, costs ⚡).
  String? clearForestAt(int r, int c) {
    if (phase != WarPhase.prep) return 'Clearing is a prep-day job.';
    if (youBase.at(r, c)?.terrain == Terrain.mountain) {
      return 'Mountains cannot be cleared.';
    }
    if (youBase.at(r, c)?.terrain != Terrain.forest) return 'Nothing to clear there.';
    if (active.resources < WarCosts.clearForest) {
      return 'Need ${WarCosts.clearForest.round()} ⚡ to clear.';
    }
    if (!youBase.clearForest(r, c)) return 'Can\'t clear that tile.';
    active.resources -= WarCosts.clearForest;
    _save();
    notifyListeners();
    return null;
  }

  /// Catch the war up to real time: replay every enemy raid that should have
  /// fired since the war began. Called on app launch and whenever the war hub
  /// is open — a player who's been away comes home to a war that kept going.
  void syncToWallClock() {
    if (phase != WarPhase.war || warStartedAtMs == 0) return;
    // Generators drip on minute granularity — every room login / hub open.
    _accrueWarGenerators();
    final elapsedSec = (nowMs() - warStartedAtMs) / 1000.0;
    if (elapsedSec <= 0) return; // clock skew / just started
    final targetMin = math.min(WarClock.dayMinutes,
        (elapsedSec / realSecondsPerSimHour * 60).floor());
    final delta = (targetMin ~/ 60) - clock.hour;
    if (delta > 0) _runHours(delta);
  }

  /// Pay out War Generators for sim-time since [lastGeneratorAccrueMin].
  /// L1 = 6⚡/hr (1 per 10 min); L2 = 15⚡/hr. Credits each pump's owner.
  /// Stops at day end / when [forceEnd] finalizes an early knockout.
  void _accrueWarGenerators({bool forceEnd = false}) {
    if (warStartedAtMs == 0) return;
    if (phase != WarPhase.war && !forceEnd) return;

    final elapsedSec = math.max(0.0, (nowMs() - warStartedAtMs) / 1000.0);
    var targetMin = math.min(WarClock.dayMinutes,
        (elapsedSec / realSecondsPerSimHour * 60).floor());
    // Admin fast-forward advances [clock] ahead of wall time — honor that too.
    targetMin = math.max(targetMin, clock.simMinutes);
    if (forceEnd) targetMin = math.max(targetMin, clock.simMinutes);
    targetMin = targetMin.clamp(0, WarClock.dayMinutes);

    final last = lastGeneratorAccrueMin.clamp(0, WarClock.dayMinutes);
    if (targetMin <= last) return;
    final hours = (targetMin - last) / 60.0;
    lastGeneratorAccrueMin = targetMin;

    for (var r = 0; r < youBase.rows; r++) {
      for (var c = 0; c < youBase.cols; c++) {
        final s = youBase.structAt(r, c);
        if (s == null || !s.alive || s.type != DefType.warGenerator) continue;
        final pay = warGeneratorRatePerHour(s.level) * hours;
        if (pay <= 0) continue;
        final i = players.indexWhere((p) => p.id == s.ownerId);
        if (i == -1) continue;
        players[i].resources += pay;
      }
    }
  }

  /// Manual fast-forward (sandbox / testing). Also winds the wall-clock anchor
  /// back so a hand-skipped war stays consistent with real-time sync. Room
  /// admin only — it rewinds the SHARED wall clock, so a teammate skipping
  /// ahead would desync the whole crew's war.
  void advanceHours(int hours) {
    if (!canControlWar) return;
    if (phase != WarPhase.war || hours <= 0) return;
    warStartedAtMs -= hours * realSecondsPerSimHour * 1000;
    _runHours(hours);
  }

  void advanceToEndOfDay() => advanceHours(24);

  /// Run [hours] whole sim-hours of the AI timeline, banking raids into the
  /// feed. Ends the war at day's end or a double knockout. The player's own
  /// in-progress raid is untouched.
  void _runHours(int hours) {
    if (phase != WarPhase.war) return;
    for (var h = 0; h < hours && !clock.dayOver; h++) {
      clock.advance(60);
      final entries = WarSim.runHour(
        hour: clock.hour,
        minute: clock.simMinutes,
        youBase: youBase,
        enemyBase: enemyBase,
        players: players,
        pools: pools,
        warSeed: warSeed,
        activePlayerId: activePlayerId,
        youIntel: youIntel,
        enemyIntel: enemyIntel,
        unlockTroops: unlockedTroopsNow,
        // dial 29 → 29% per bot per hour (never a free guaranteed smash)
        raidChance: difficulty / 100.0,
      );
      feed.addAll(entries);
      for (final e in entries) {
        if (e.attackerSide == WarSide.enemy &&
            e.replay != null &&
            e.replay!.isNotEmpty) {
          lastEnemyReplay = e.replay;
          lastEnemyRaider = e.attackerName;
        }
      }
      _trimFeed();
      _noteFalls();
      if (enemyBase.allCastlesRazed && youBase.allCastlesRazed) break;
    }
    // Keep pumps current with the sim clock (admin skip / catch-up hours).
    _accrueWarGenerators();
    if (clock.dayOver || (enemyBase.allCastlesRazed && youBase.allCastlesRazed)) {
      endWar();
    } else {
      _save();
      notifyListeners();
    }
  }

  /// Real time until the next sim-hour ticks (and its raids may land). Zero
  /// when there's no live war or the day is already over.
  Duration get untilNextWarHour {
    if (phase != WarPhase.war || warStartedAtMs == 0 || clock.dayOver) {
      return Duration.zero;
    }
    final nextHourAtMs =
        warStartedAtMs + (clock.hour + 1) * realSecondsPerSimHour * 1000;
    final ms = nextHourAtMs - nowMs();
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  /// Real time until the war day closes and the verdict is struck.
  Duration get untilWarEnds {
    if (phase != WarPhase.war || warStartedAtMs == 0) return Duration.zero;
    final endAtMs = warStartedAtMs +
        WarClock.dayMinutes ~/ 60 * realSecondsPerSimHour * 1000;
    final ms = endAtMs - nowMs();
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  void _noteFalls() {
    if (enemyBase.allCastlesRazed && enemyBaseFellAt < 0) {
      enemyBaseFellAt = clock.simMinutes;
    }
    if (youBase.allCastlesRazed && youBaseFellAt < 0) {
      youBaseFellAt = clock.simMinutes;
    }
  }

  // ── hands-on raid (active player attacks the enemy base) ────────────────────
  /// Starts a raid — or RESUMES the one already in progress. Nothing is lost by
  /// leaving the battle screen or fast-forwarding.
  AttackState beginLiveAttack() {
    liveAttack ??= AttackState(
      base: enemyBase,
      attacker: WarSide.you,
      attackerName: active.name,
      pools: pools,
      defenderIq: skillFor(difficulty), // their defense fights smart
      intel: youIntel, // the clan's scouting carries over
    );
    notifyListeners();
    return liveAttack!;
  }

  /// Cap the feed — every raid KEEPS its replay until the war ends.
  void _trimFeed() {
    if (feed.length > 40) feed.removeRange(0, feed.length - 40);
  }

  /// Fold the live raid's tallies into the war (END RAID / war end).
  void _absorbLiveAttack() {
    final la = liveAttack;
    if (la == null) return;
    la.snapshot('Raid banked');
    youIntel.addAll(la.revealed); // scouting is forever (this war)
    active.destructionDealt =
        (active.destructionDealt + la.gained).clamp(0.0, 100.0);
    active.troopsLost += la.troopsLost;
    active.resourcesSpent += la.resourcesSpent;
    _recallSurvivors(la, active);
    if (la.gained >= 0.5) {
      feed.add(WarLogEntry(
        minute: clock.simMinutes,
        attackerSide: WarSide.you,
        attackerName: active.name,
        gained: la.gained,
        defenderDestruction: enemyBase.destructionPercent,
        troopsLost: la.troopsLost,
        resourcesSpent: la.resourcesSpent,
        razed: enemyBase.allCastlesRazed,
        replay: List.of(la.frames),
      ));
      _trimFeed();
    }
    liveAttack = null;
  }

  /// Living prepaid raiders march home into [owner]'s army. Dead stay dead;
  /// ⚡ was paid at the Training Grounds, so survivors refill the camp — not a
  /// cash refund. Called on END RAID, timer/razed bank, and war end.
  void _recallSurvivors(AttackState st, WarPlayer owner) {
    for (final t in st.troops) {
      if (!t.alive) continue;
      if (t.side != st.attacker) continue;
      if (t.ownerId != owner.id) continue;
      owner.army[t.type] = (owner.army[t.type] ?? 0) + 1;
    }
  }

  // ── Clash-style auto-battle (session-scoped, freeActions economy) ───────────
  AttackState? clashState;

  AttackState startClashBattle() {
    clashState = AttackState(
      base: enemyBase,
      attacker: WarSide.you,
      attackerName: active.name,
      pools: pools,
      freeActions: true,
      defenderIq: skillFor(difficulty), // their defense fights smart
      intel: youIntel, // the clan's scouting carries over
    );
    notifyListeners();
    return clashState!;
  }

  // ── base codes: your fortress as a string — survives version wipes ──────────
  /// Everything that IS the build: the terrain seed, chopped forests, castles,
  /// and every placed piece with its level. Scars are not the build.
  String exportBaseCode() {
    final b = youBase;
    final structs = <List<dynamic>>[];
    for (var r = 0; r < b.rows; r++) {
      for (var c = 0; c < b.cols; c++) {
        final st = b.structAt(r, c);
        if (st == null || st.isCastle) continue;
        structs.add([r, c, st.type.index, st.level, st.ownerId]);
      }
    }
    final j = {
      'v': 1,
      'seed': b.seed,
      'size': b.rows,
      'cleared': b.cleared.toList(),
      'castles': {
        for (final e in b.castles.entries) e.key: [e.value.r, e.value.c]
      },
      'structs': structs,
    };
    return 'JARS1.${base64UrlEncode(utf8.encode(jsonEncode(j)))}';
  }

  /// Rebuild YOUR base from a code — same seed → same terrain, same walls,
  /// same everything. Free (it's a restore, not a purchase). Prep only.
  String? importBaseCode(String code) {
    if (phase != WarPhase.prep) return 'Importing is a prep-day job.';
    try {
      var payload = code.trim();
      if (payload.startsWith('JARS1.')) payload = payload.substring(6);
      final j = jsonDecode(utf8.decode(base64Url.decode(payload)))
          as Map<String, dynamic>;
      final fresh = Base(
        WarSide.you,
        (j['seed'] as num).toInt(),
        size: (j['size'] as num?)?.toInt() ?? mapSize,
      );
      for (final v in (j['cleared'] as List? ?? const [])) {
        final k = (v as num).toInt();
        final r = k ~/ fresh.cols, c = k % fresh.cols;
        if (fresh.inBounds(r, c) &&
            fresh.grid[r][c].terrain == Terrain.forest) {
          fresh.grid[r][c].terrain = Terrain.plains;
        }
        fresh.cleared.add(k);
      }
      (j['castles'] as Map<String, dynamic>? ?? const {})
          .forEach((id, rc) {
        fresh.placeCastle(
            id, (rc[0] as num).toInt(), (rc[1] as num).toInt());
      });
      for (final e in (j['structs'] as List? ?? const [])) {
        final r = (e[0] as num).toInt(), c = (e[1] as num).toInt();
        final tIdx = (e[2] as num).toInt();
        if (!fresh.inBounds(r, c) || tIdx >= DefType.values.length) continue;
        if (fresh.structAt(r, c) != null) continue;
        final st = Structure(DefType.values[tIdx], e[4] as String)
          ..level = (e[3] as num).toInt();
        st.hp = st.maxHp;
        fresh.grid[r][c].structure = st;
      }
      youBase = fresh;
      _save();
      notifyListeners();
      return null;
    } catch (_) {
      return 'That code didn\'t take — check you pasted the whole thing.';
    }
  }

  // ── practice drills: raid a CLONE of your own base — nothing is real ────────
  AttackState? practiceState;

  /// Unlimited troops against your own walls. The battle runs on a deep copy,
  /// so no scars, no losses, no war effect — pure rehearsal. [clean] sweeps
  /// the clone's graves and craters for a pristine sandbox.
  AttackState startPracticeBattle({bool clean = false}) {
    final clone = Base.fromJson(youBase.toJson());
    if (clean) {
      clone.graves.clear();
      clone.scorch.clear();
    }
    practiceState = AttackState(
      base: clone,
      attacker: WarSide.enemy, // the red team drills against your design
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      defenderIq: skillFor(difficulty),
      // it's YOUR base — you know every stone of it
      intel: {for (var k = 0; k < clone.rows * clone.cols; k++) k},
    );
    notifyListeners();
    return practiceState!;
  }

  void endPractice() {
    practiceState = null;
    notifyListeners();
  }

  /// Sandbox: hurl an AI wave at the drill base at the chosen difficulty —
  /// same doctrine the real enemy uses (comp, veterans, one anchor flank).
  /// Returns the troops that actually landed (so Free Move can seat them).
  int _drillWaveSeq = 0;
  List<Troop> summonDrillWave(int difficulty) {
    final st = practiceState;
    if (st == null) return const [];
    final drops = st.base.dropCells.toList();
    if (drops.isEmpty) return const [];
    final skill = skillFor(difficulty);
    final rng =
        SeededRng(seedFromParts([warSeed, 'drillwave', _drillWaveSeq++]));
    final anchor = drops[rng.intRange(0, drops.length)];
    drops.sort((a, b) {
      final da = (a.r - anchor.r).abs() + (a.c - anchor.c).abs();
      final db = (b.r - anchor.r).abs() + (b.c - anchor.c).abs();
      return da.compareTo(db);
    });
    final cap = 3 + (skill * 7).round();
    final spawned = <Troop>[];
    var i = 0;
    var dropIdx = 0;
    while (i < cap && dropIdx < drops.length) {
      final drop = drops[dropIdx];
      final t = st.spawn(
          WarAi.waveTroop(i, skill, rng, unlockTroops: unlockedTroopsNow),
          'drill',
          drop.r,
          drop.c,
          allowStack: true);
      if (t == null) {
        dropIdx++;
        continue;
      }
      if (skill >= 0.9) {
        t.gainXp(Xp.perLevel * (skill >= 1.3 ? 2.0 : 1.0) + 1);
        t.hp = t.maxHp;
      }
      spawned.add(t);
      dropIdx++;
      i++;
    }
    notifyListeners();
    return spawned;
  }

  void _absorbClash() {
    final st = clashState;
    if (st == null) return;
    st.snapshot('Battle over');
    youIntel.addAll(st.revealed); // scouting is forever (this war)
    active.destructionDealt =
        (active.destructionDealt + st.gained).clamp(0.0, 100.0);
    active.troopsLost += st.troopsLost;
    active.resourcesSpent += st.resourcesSpent;
    _recallSurvivors(st, active);
    if (st.gained >= 0.5 || st.troopsLost > 0) {
      feed.add(WarLogEntry(
        minute: clock.simMinutes,
        attackerSide: WarSide.you,
        attackerName: active.name,
        gained: st.gained,
        defenderDestruction: enemyBase.destructionPercent,
        troopsLost: st.troopsLost,
        resourcesSpent: st.resourcesSpent,
        razed: enemyBase.allCastlesRazed,
        replay: List.of(st.frames),
      ));
      _trimFeed();
    }
    clashState = null;
  }

  /// Bank a finished (or abandoned) clash battle into the war.
  void bankClashBattle() {
    if (clashState == null) return;
    _absorbClash();
    _noteFalls();
    if (phase == WarPhase.war && enemyBase.allCastlesRazed) {
      endWar();
    } else {
      _save();
      notifyListeners();
    }
  }

  void commitLiveAttack() {
    _absorbLiveAttack();
    _noteFalls();
    if (phase == WarPhase.war && enemyBase.allCastlesRazed) {
      endWar();
    } else {
      _save();
      notifyListeners();
    }
  }

  /// Persist mid-raid progress (called by the battle screen after actions).
  void raidChanged() {
    liveAttack?.snapshot(); // record a replay frame per action
    _noteFalls();
    if (phase == WarPhase.war && enemyBase.allCastlesRazed) {
      commitLiveAttack();
    } else {
      _save();
      notifyListeners();
    }
  }

  // ── results ─────────────────────────────────────────────────────────────────
  void endWar() {
    _absorbLiveAttack(); // bank any open raid first
    _absorbClash();
    // Final generator drip through knockout / day-end, then freeze.
    _accrueWarGenerators(forceEnd: true);
    phase = WarPhase.results;
    final you = ClanTally(WarSide.you,
        destructionDealt: enemyBase.destructionPercent,
        razedEnemy: enemyBase.allCastlesRazed,
        enemyFellAtMin: enemyBaseFellAt,
        troopsLost: youClan.fold(0, (a, p) => a + p.troopsLost),
        resourcesSpent: youClan.fold(0.0, (a, p) => a + p.resourcesSpent));
    final foe = ClanTally(WarSide.enemy,
        destructionDealt: youBase.destructionPercent,
        razedEnemy: youBase.allCastlesRazed,
        enemyFellAtMin: youBaseFellAt,
        troopsLost: enemyClan.fold(0, (a, p) => a + p.troopsLost),
        resourcesSpent: enemyClan.fold(0.0, (a, p) => a + p.resourcesSpent));
    lastVerdict = WarScoring.decide(you, foe);
    _payoutTributeChests();
    _save();
    notifyListeners();
  }

  /// Surviving Tribute Chests pay 2× cost, split evenly across real crewmates.
  void _payoutTributeChests() {
    var chests = 0;
    for (var r = 0; r < youBase.rows; r++) {
      for (var c = 0; c < youBase.cols; c++) {
        final s = youBase.structAt(r, c);
        if (s != null && s.alive && s.type == DefType.tributeChest) chests++;
      }
    }
    if (chests <= 0) return;
    final real = youClan.where((p) => !p.isBot).toList();
    if (real.isEmpty) return;
    final total = chests * 200.0;
    final share = total / real.length;
    for (final p in real) {
      p.resources += share;
    }
  }

  void nextWar() {
    final won = lastVerdict?.winner == WarSide.you;
    seasonResults = [...seasonResults, won];
    warIndex++;
    if (warIndex >= _lcfg.matchweeks) {
      _rollSeason();
    }
    startPrep();
  }

  void _rollSeason() {
    final table = buildTable();
    final pos = table.yourRow?.position ?? _lcfg.teamsPerLeague;
    if (pos <= _lcfg.promoteCount &&
        divisionIndex < _lcfg.divisions.length - 1) {
      divisionIndex++;
    } else if (pos > _lcfg.teamsPerLeague - _lcfg.relegateCount &&
        divisionIndex > 0) {
      divisionIndex--;
    }
    // Peak map size never shrinks — pad the living fortress if we grew.
    final before = mapSize;
    _syncMapSize();
    if (mapSize > before && youBase.rows < mapSize) {
      youBase = youBase.expandTo(mapSize, rimConfig: _terrainForDivision());
    }
    seasonIndex++;
    warIndex = 0;
    seasonResults = [];
  }

  // ── controls (sim affordances) ──────────────────────────────────────────────
  /// Swap who you're playing as. In a REAL room this is locked to yourself —
  /// your friends are real people on their own devices; you can't step into
  /// their shoes any more than you could in real life. The switcher only
  /// exists for solo/offline play (testing the whole crew from one phone).
  void switchActive(String id) {
    if (roomId != null) return;
    if (players.any((p) => p.id == id && p.side == WarSide.you)) {
      activePlayerId = id;
      notifyListeners();
    }
  }

  void setEnemyDifficulty(AiLevel level) {
    enemyDifficulty = level;
    for (final p in enemyClan) {
      p.ai = level;
    }
    notifyListeners();
  }

  /// The war dial (1..100): sets the tier for plan depth AND a continuous
  /// skill multiplier so the top half of the dial goes BEYOND master.
  void setDifficulty(int d) {
    if (!canControlWar) return; // only the room admin sets the difficulty
    difficulty = d.clamp(1, 100);
    final s = skillFor(difficulty);
    enemyDifficulty = _tierForSkill(s);
    for (final p in enemyClan) {
      p.ai = enemyDifficulty;
      p.skillMul = s / AiData.skill(enemyDifficulty);
    }
    _save();
    notifyListeners();
  }

  Future<void> resetSeason() async {
    if (!canControlWar) return; // only the room admin resets the season
    seasonIndex = 0;
    warIndex = 0;
    divisionIndex = 0;
    seasonResults = [];
    worldGen++; // fresh terrain, fresh strongholds — never the same rerun
    // Solo/offline only: a real room's roster (seated via applyRoomRoster)
    // must survive a reset untouched — swapping it for the fake bot crew
    // here was auto-building a full stronghold for every real teammate the
    // instant the season reset, same bug as startPrep used to have.
    if (roomId == null) _buildRosters();
    startPrep();
  }

  /// Workout hook — fuels the player you're controlling (one live pool, so it
  /// works mid-raid too).
  void earn(double points) {
    if (points <= 0) return;
    _creditEarn(points, activePlayerId);
    _save();
    notifyListeners();
  }

  /// Credit a real log to Clan War ⚡ for [forRoomId].
  ///
  /// Returns `true` when it lands on the live pool immediately. Returns
  /// `false` when War sync hasn't seated this room yet — the points are
  /// queued and flush the moment [applyRoomRoster] binds that room (the
  /// exact silent-drop that ate BossmanFat's wall-sit).
  bool earnFromWorkout(String forRoomId, double points) {
    if (points <= 0) return false;
    if (roomId == forRoomId) {
      _creditEarn(points, activePlayerId);
      _save();
      notifyListeners();
      return true;
    }
    _pendingWorkoutEarn[forRoomId] =
        (_pendingWorkoutEarn[forRoomId] ?? 0) + points;
    return false;
  }

  /// Admin-only manual credit — compensation for a bug, a correction, a
  /// judgment call, whatever the room's admin decides. Unlike a peer
  /// donation (which moves ⚡ OUT of the giver's own pool), this creates it,
  /// so it isn't capped by anyone's current balance.
  void grantPoints(String playerId, double amount) {
    if (!canControlWar) return;
    if (amount <= 0) return;
    _creditEarn(amount, playerId);
    _save();
    notifyListeners();
  }

  void _creditEarn(double points, String playerId) {
    WarPlayer? p;
    for (final pl in players) {
      if (pl.id == playerId) {
        p = pl;
        break;
      }
    }
    p ??= active;
    p.resources += points;
    // track real prep-day effort — this is what floors the enemy's war
    // chest at startWar(), so it has to be everything you had, not just
    // whatever's left unspent by the time the day ends.
    if (phase == WarPhase.prep) p.prepEarned += points;
    _unsyncedEarn += points;
    _unsyncedEarnPlayerId = p.id;
  }

  void _flushPendingWorkoutEarn() {
    final id = roomId;
    if (id == null) return;
    final pending = _pendingWorkoutEarn.remove(id);
    if (pending == null || pending <= 0) return;
    _creditEarn(pending, activePlayerId);
  }

  /// Put workout ⚡ back after a sync conflict reloaded a blob that never
  /// saw them. Safe to call repeatedly — only the still-unsynced delta is
  /// re-applied, and [clearUnsyncedEarn] runs on a successful room push.
  void reapplyUnsyncedEarn() {
    final amt = _unsyncedEarn;
    final id = _unsyncedEarnPlayerId;
    if (amt <= 0 || id == null || players.isEmpty) return;
    WarPlayer? p;
    for (final pl in players) {
      if (pl.id == id) {
        p = pl;
        break;
      }
    }
    if (p == null) return;
    p.resources += amt;
    if (phase == WarPhase.prep) p.prepEarned += amt;
  }

  void clearUnsyncedEarn() {
    _unsyncedEarn = 0;
    _unsyncedEarnPlayerId = null;
  }

  /// Gift live ⚡ from the player you're controlling to a teammate.
  /// Does NOT rewrite [WarPlayer.prepEarned] either way — workout effort
  /// already counted for the enemy floor, and donated coin shouldn't inflate
  /// (or erase) that ledger. Returns an error string, or null on success.
  String? donateResources(String toId, double amount) {
    final amt = amount.floorToDouble();
    if (amt < 1) return 'Pick at least 1⚡.';
    final from = active;
    if (from.id == toId) return 'Can\'t donate to yourself.';
    WarPlayer? to;
    for (final p in youClan) {
      if (p.id == toId) {
        to = p;
        break;
      }
    }
    if (to == null) return 'Teammate not found.';
    if (knockedOut(from)) return 'You\'re knocked out — no ⚡ left to give.';
    if (from.resources < amt) {
      return 'Only ${from.resources.floor()}⚡ on hand.';
    }
    from.resources -= amt;
    to.resources += amt;
    _save();
    notifyListeners();
    return null;
  }

  // ── leaderboard (reuse LeagueSimulator) ─────────────────────────────────────
  static const double _leagueAnchorPerMember = 60.0;

  /// Your weekly ladder points, on the SAME scale as the AI opponents (whose
  /// scores orbit `anchorPerMember × members × division.difficulty`). The war
  /// verdict already forces the W/L via `yourOutcomes`; these numbers exist so
  /// pointsFor / against / goal-difference read honestly — a won war beats a
  /// typical opponent, a lost war falls short, and the live week tracks how
  /// the raid is actually going.
  List<int> get _yourWarScores {
    final base = _leagueAnchorPerMember * youClan.length; // ≈ opponent midpoint
    return [
      for (var i = 0; i < seasonResults.length; i++)
        (seasonResults[i] == true ? base * 1.18 : base * 0.62).round(),
      // live week: 0% razed ≈ a heavy loss, 100% razed ≈ a commanding win
      (base * (0.62 + youDestruction / 100 * 0.62)).round(),
    ];
  }

  LeagueTable buildTable() {
    final division = _lcfg.divisionByIndex(divisionIndex);
    final members = youClan.length;
    final anchor = _leagueAnchorPerMember;
    return _sim.build(
      roomId: seedKey,
      yourTeamName: clanName,
      division: division,
      seasonIndex: seasonIndex,
      completedWeeks: warIndex,
      yourWeeklyPoints: _yourWarScores,
      yourActiveMembers: members,
      anchorPerMember: anchor,
      yourOutcomes: seasonResults,
    );
  }

  // ── persistence ─────────────────────────────────────────────────────────────
  // The whole game — every player, both bases, the timeline — as one blob.
  // Local play writes this to SharedPreferences; a real room writes the SAME
  // shape to a Supabase row instead (see WarSyncService). One serialization,
  // two destinations.
  Map<String, dynamic> toJson() => {
        'seed': warSeed,
        'phase': phase.index,
        'season': seasonIndex,
        'war': warIndex,
        'gen': worldGen,
        'div': divisionIndex,
        'mapSize': mapSize,
        'genAccrue': lastGeneratorAccrueMin,
        'diff': enemyDifficulty.index,
        'diff100': difficulty,
        'eClan': enemyClanName,
        'clock': clock.simMinutes,
        'anchor': warStartedAtMs,
        'room': roomId,
        'active': activePlayerId,
        'eFell': enemyBaseFellAt,
        'yFell': youBaseFellAt,
        'players': [for (final pl in players) pl.toJson()],
        'results': seasonResults,
        'youBase': youBase.toJson(),
        'enemyBase': enemyBase.toJson(),
        'raid': liveAttack?.toJson(),
        'youIntel': youIntel.toList(),
        'enemyIntel': enemyIntel.toList(),
        'feed': [for (final e in feed) e.toJson()],
        'lastEnemyRaider': lastEnemyRaider,
      };

  /// Rehydrate every field from a [toJson] blob — pure deserialization, no
  /// I/O, no wall-clock catch-up (callers run [syncToWallClock] themselves
  /// once they're ready, same as they always have).
  void loadFromJson(Map<String, dynamic> j) {
    warSeed = (j['seed'] as num?)?.toInt() ?? 1;
    phase = WarPhase.values[(j['phase'] as num?)?.toInt() ?? 0];
    seasonIndex = (j['season'] as num?)?.toInt() ?? 0;
    warIndex = (j['war'] as num?)?.toInt() ?? 0;
    worldGen = (j['gen'] as num?)?.toInt() ?? 0;
    divisionIndex = (j['div'] as num?)?.toInt() ?? 0;
    mapSize = (j['mapSize'] as num?)?.toInt() ?? Base.defaultSize;
    _syncMapSize(); // division may demand larger than a legacy save
    lastGeneratorAccrueMin = (j['genAccrue'] as num?)?.toInt() ?? 0;
    enemyDifficulty = AiLevel.values[(j['diff'] as num?)?.toInt() ?? 1];
    difficulty = (j['diff100'] as num?)?.toInt() ?? 50;
    enemyClanName = j['eClan'] as String? ?? 'The Enemy';
    clock.simMinutes = (j['clock'] as num?)?.toInt() ?? 0;
    warStartedAtMs = (j['anchor'] as num?)?.toInt() ?? 0;
    roomId = j['room'] as String?;
    activePlayerId = j['active'] as String? ?? 'you';
    enemyBaseFellAt = (j['eFell'] as num?)?.toInt() ?? -1;
    youBaseFellAt = (j['yFell'] as num?)?.toInt() ?? -1;
    players
      ..clear()
      ..addAll([
        for (final pj in (j['players'] as List? ?? const []))
          WarPlayer.fromJson(pj as Map<String, dynamic>, roomSeated: roomId != null)
      ]);
    if (players.isEmpty) _buildRosters();
    seasonResults = [
      for (final v in (j['results'] as List? ?? const [])) v as bool?
    ];
    youBase = j['youBase'] != null
        ? Base.fromJson(j['youBase'] as Map<String, dynamic>)
        : Base(WarSide.you, warSeed, size: mapSize, config: _terrainForDivision());
    if (youBase.rows < mapSize) {
      youBase = youBase.expandTo(mapSize, rimConfig: _terrainForDivision());
    }
    enemyBase = j['enemyBase'] != null
        ? Base.fromJson(j['enemyBase'] as Map<String, dynamic>)
        : Base(WarSide.enemy, warSeed,
            size: mapSize, config: _terrainForDivision());
    if (enemyBase.rows < mapSize && phase == WarPhase.prep) {
      enemyBase =
          enemyBase.expandTo(mapSize, rimConfig: _terrainForDivision());
    }
    youIntel = {
      for (final v in (j['youIntel'] as List? ?? const [])) (v as num).toInt()
    };
    enemyIntel = {
      for (final v in (j['enemyIntel'] as List? ?? const [])) (v as num).toInt()
    };
    // Raid history + replays — without this, an app reload (or a mobile
    // browser reclaiming a backgrounded tab, the everyday version of that)
    // wiped every raid's watchable replay while leaving the DAMAGE it dealt
    // behind (that part always lived on youBase/enemyBase, which WAS
    // serialized) — "I can see the damage but there's no replay."
    feed
      ..clear()
      ..addAll([
        for (final ej in (j['feed'] as List? ?? const []))
          WarLogEntry.fromJson(ej as Map<String, dynamic>)
      ]);
    lastEnemyReplay = null;
    lastEnemyRaider = j['lastEnemyRaider'] as String? ?? '';
    for (final e in feed) {
      if (e.attackerSide == WarSide.enemy &&
          e.replay != null &&
          e.replay!.isNotEmpty) {
        lastEnemyReplay = e.replay;
      }
    }
    // resume an in-progress raid — nothing the player built up is lost
    if (j['raid'] != null && phase == WarPhase.war) {
      liveAttack = AttackState.restore(
        base: enemyBase,
        attacker: WarSide.you,
        pools: pools,
        j: j['raid'] as Map<String, dynamic>,
      );
    }
  }

  /// Solo/offline local play (tests, practice sandbox, pre-onboarding): the
  /// device's own SharedPreferences is the whole world. A real room instead
  /// goes through [WarSyncService] — see [WarGame.loadFromJson]/[toJson].
  static Future<void> load() async {
    final g = instance;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        g._buildRosters();
        g.startPrep();
        return;
      }
      g.loadFromJson(jsonDecode(raw) as Map<String, dynamic>);
      // welcome back: replay every raid that fired while you were away
      g.syncToWallClock();
    } catch (e) {
      if (kDebugMode) debugPrint('WarGame: fresh ($e)');
      g._buildRosters();
      g.startPrep();
    }
  }

  /// Set by the app layer when a real room is active — pushes the same
  /// [toJson] blob to Supabase (compare-and-swap against [roomVersion]) so
  /// every teammate sees it. Kept out of `lib/war/` proper (no Supabase
  /// import here); see `WarSyncService`. Local save always still happens too
  /// (below) — an offline mirror that keeps solo play, tests, and "no
  /// network right now" all working exactly as before.
  static void Function(WarGame game)? onRoomSave;

  /// Call on SIGN-OUT. Nothing else clears `WarGame.instance` between
  /// sessions — if a different real user signs in on the same device
  /// without a full app restart (two friends testing on one laptop is
  /// exactly this), they must NEVER inherit the outgoing user's room,
  /// identity, or roster, even for the one frame before the next screen's
  /// sync gets a chance to run.
  void resetForSignOut() {
    roomId = null;
    roomVersion = 0;
    syncConflicts = 0;
    isRoomAdmin = true;
    players.clear();
    activePlayerId = 'you';
    onRoomSave = null;
    _pendingWorkoutEarn.clear();
    clearUnsyncedEarn();
  }

  // A bare `SharedPreferences.getInstance().then(...)` per call races: two
  // independent Future chains resolving out of order can let an OLDER save
  // land LAST, silently reverting a newer one (confirmed — rapid-fire calls
  // do NOT preserve write order). Chaining every write onto the same Future
  // forces strict FIFO: call order is always completion order.
  Future<void> _writeChain = Future.value();

  void _save() {
    final json = toJson();
    _writeChain = _writeChain.then((_) async {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode(json));
    });
    if (roomId != null) onRoomSave?.call(this);
  }
}
