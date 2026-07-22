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

  /// How much real time one simulated war-hour costs. A war day is 24 sim-hours,
  /// so at 2 minutes/hour a whole war unfolds over ~48 real minutes. Bump this
  /// to 3600 for a Clash-style "one war per real day" cadence.
  static const int realSecondsPerSimHour = 120;

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
          ai: AiLevel.seasoned));
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
          ai: enemyDifficulty));
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
      return; // same crew, already seated
    }
    roomId = realRoomId;
    players.clear();
    players.add(WarPlayer(
        id: myUserId,
        name: myUsername,
        emoji: '🦁',
        colorValue: 0xFF2E6BE6,
        side: WarSide.you,
        ai: AiLevel.master,
        isYou: true));
    for (final m in members) {
      players.add(WarPlayer(
          id: m.id,
          name: m.name,
          emoji: _emojiFor(m.id),
          colorValue: _colorFor(m.id),
          side: WarSide.you,
          ai: AiLevel.seasoned));
    }
    final n = youClan.length;
    for (var i = 0; i < n; i++) {
      final c = _enemyChars[i % _enemyChars.length];
      final wave = i ~/ _enemyChars.length;
      final name = wave == 0 ? c[1] as String : '${c[1]} ${_romanNumeral(wave + 1)}';
      players.add(WarPlayer(
          id: 'foe_$i',
          name: name,
          emoji: c[2] as String,
          colorValue: c[3] as int,
          side: WarSide.enemy,
          ai: enemyDifficulty));
    }
    activePlayerId = myUserId;
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
    const clanNames = [
      'Iron Wolves', 'Bone Legion', 'The Red Banners', 'Storm Callers',
      'Ash Walkers', 'The Broken Tusk', 'Night Ravens', 'Granite Sons',
      'The Ember Guard', 'Salt Fang', 'Hollow Kings', 'The Briar Pact',
    ];
    enemyClanName = clanNames[warSeed % clanNames.length];
    if (players.isEmpty) _buildRosters();
    youBase = Base(WarSide.you, warSeed);
    enemyBase = Base(WarSide.enemy, warSeed);
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
      // difficulty bites: sharper enemy clans bring a bigger war chest
      // (rookie ~262 → master ~375); your clan always builds at par
      p.resources = p.side == WarSide.enemy
          ? WarCosts.prepBudgetFor(p.skill)
          : WarCosts.prepBudget;
      p.ready = false;
      p.resetWarTallies();
    }
    // AI builds: the whole enemy base, and your AI crewmates' share of yours.
    WarAi.designBase(
        enemyBase, enemyClan, SeededRng(seedFromParts([warSeed, 'enemyDesign'])));
    final aiCrew = youClan.where((p) => !p.isYou).toList();
    WarAi.designBase(
        youBase, aiCrew, SeededRng(seedFromParts([warSeed, 'crewDesign'])));
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
    final cost = kDefSpecs[type]!.cost;
    if (active.resources < cost) return 'Need $cost points.';
    if (!youBase.canPlace(r, c)) return 'Can\'t build there.';
    youBase.place(r, c, type, active.id);
    active.resources -= cost;
    _save();
    notifyListeners();
    return null;
  }

  void removeStructure(int r, int c) {
    if (phase != WarPhase.prep) return;
    final s = youBase.structAt(r, c);
    if (s == null || s.isCastle) return; // castles are sacred
    // co-op base: anyone can re-plan it — the refund goes to the OWNER
    final owner = players.firstWhere((p) => p.id == s.ownerId,
        orElse: () => active);
    owner.resources += youBase.removeAt(r, c);
    _save();
    notifyListeners();
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
  bool get youHaveCastle => youBase.castles.containsKey('you');

  // ── WAR ─────────────────────────────────────────────────────────────────────
  void startWar() {
    // ensure every player has a castle
    for (final p in youClan) {
      if (!youBase.castles.containsKey(p.id)) {
        final spot = _fallbackCastle(youBase, youBase.castles.length);
        if (spot != null) youBase.placeCastle(p.id, spot.r, spot.c);
      }
    }
    phase = WarPhase.war;
    clock.simMinutes = 0;
    warStartedAtMs = nowMs(); // the wall clock starts ticking now
    for (final p in players) {
      // hard enemies march to war RICH — their raids come big and often
      p.resources = p.side == WarSide.enemy
          ? WarCosts.warStartResources * (0.75 + p.skill)
          : WarCosts.warStartResources;
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

  Cell? _fallbackCastle(Base base, int i) {
    for (var r = 1; r < Base.rows - 1; r++) {
      for (var c = 1; c < Base.cols - 1; c++) {
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
    final cost = kTroopSpecs[type]!.cost.toDouble();
    if (active.resources < cost) {
      return 'Need ${cost.round()} ⚡ — log a workout to earn more.';
    }
    active.resources -= cost;
    if (phase == WarPhase.war) active.resourcesSpent += cost;
    active.army[type] = (active.army[type] ?? 0) + 1;
    _save();
    notifyListeners();
    return null;
  }

  /// Deploy a trained troop from the active player's army (no ⚡ charge — it
  /// was paid at the Training Grounds). Returns null if blocked or untrained.
  Troop? deployTrained(AttackState st, TroopType type, int r, int c) {
    if (knockedOut(active)) return null; // the fallen only spectate
    if ((active.army[type] ?? 0) <= 0) return null;
    final t = st.spawn(type, active.id, r, c, prepaid: true);
    if (t != null) {
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
    final elapsedSec = (nowMs() - warStartedAtMs) / 1000.0;
    if (elapsedSec <= 0) return; // clock skew / just started
    final targetMin = math.min(WarClock.dayMinutes,
        (elapsedSec / realSecondsPerSimHour * 60).floor());
    final delta = (targetMin ~/ 60) - clock.hour;
    if (delta > 0) _runHours(delta);
  }

  /// Manual fast-forward (sandbox / testing). Also winds the wall-clock anchor
  /// back so a hand-skipped war stays consistent with real-time sync.
  void advanceHours(int hours) {
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
    for (var r = 0; r < Base.rows; r++) {
      for (var c = 0; c < Base.cols; c++) {
        final st = b.structAt(r, c);
        if (st == null || st.isCastle) continue;
        structs.add([r, c, st.type.index, st.level, st.ownerId]);
      }
    }
    final j = {
      'v': 1,
      'seed': b.seed,
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
      final fresh = Base(WarSide.you, (j['seed'] as num).toInt());
      for (final v in (j['cleared'] as List? ?? const [])) {
        final k = (v as num).toInt();
        final r = k ~/ Base.cols, c = k % Base.cols;
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
      intel: {for (var k = 0; k < Base.rows * Base.cols; k++) k},
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
  int _drillWaveSeq = 0;
  void summonDrillWave(int difficulty) {
    final st = practiceState;
    if (st == null) return;
    final drops = st.base.dropCells.toList();
    if (drops.isEmpty) return;
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
    var i = 0;
    var dropIdx = 0;
    while (i < cap && dropIdx < drops.length) {
      final drop = drops[dropIdx];
      final t = st.spawn(WarAi.waveTroop(i, skill, rng), 'drill', drop.r, drop.c);
      if (t == null) {
        dropIdx++;
        continue;
      }
      if (skill >= 0.9) {
        t.gainXp(Xp.perLevel * (skill >= 1.3 ? 2.0 : 1.0) + 1);
      }
      dropIdx++;
      i++;
    }
    notifyListeners();
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
    _save();
    notifyListeners();
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
    difficulty = d.clamp(1, 100);
    final s = skillFor(difficulty);
    enemyDifficulty = s >= 0.9
        ? AiLevel.master
        : s >= 0.65
            ? AiLevel.elite
            : s >= 0.4
                ? AiLevel.seasoned
                : AiLevel.rookie;
    for (final p in enemyClan) {
      p.ai = enemyDifficulty;
      p.skillMul = s / AiData.skill(enemyDifficulty);
    }
    _save();
    notifyListeners();
  }

  Future<void> resetSeason() async {
    seasonIndex = 0;
    warIndex = 0;
    divisionIndex = 0;
    seasonResults = [];
    worldGen++; // fresh terrain, fresh strongholds — never the same rerun
    _buildRosters();
    startPrep();
  }

  /// Workout hook — fuels the player you're controlling (one live pool, so it
  /// works mid-raid too).
  void earn(double points) {
    if (points <= 0) return;
    active.resources += points;
    _save();
    notifyListeners();
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
          WarPlayer.fromJson(pj as Map<String, dynamic>)
      ]);
    if (players.isEmpty) _buildRosters();
    seasonResults = [
      for (final v in (j['results'] as List? ?? const [])) v as bool?
    ];
    youBase = j['youBase'] != null
        ? Base.fromJson(j['youBase'] as Map<String, dynamic>)
        : Base(WarSide.you, warSeed);
    enemyBase = j['enemyBase'] != null
        ? Base.fromJson(j['enemyBase'] as Map<String, dynamic>)
        : Base(WarSide.enemy, warSeed);
    youIntel = {
      for (final v in (j['youIntel'] as List? ?? const [])) (v as num).toInt()
    };
    enemyIntel = {
      for (final v in (j['enemyIntel'] as List? ?? const [])) (v as num).toInt()
    };
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
