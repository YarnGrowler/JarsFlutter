import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/league_config.dart';
import '../../core/seeded_rng.dart';
import '../../core/theme.dart';
import '../../models/league.dart';
import '../../providers/low_performance_mode_provider.dart';
import '../../war/free_move_battle.dart';
import '../../war/war_ai.dart';
import '../../war/war_base.dart';
import '../../war/war_biome.dart';
import '../../war/war_engine.dart';
import '../../war/war_game.dart';
import '../../war/war_player.dart';
import '../../war/war_types.dart';
import 'battle_fx.dart';
import 'war_board.dart';
import 'war_board_view.dart';
import 'war_info_cards.dart';

/// 🧪 The BASE LAB — sandbox for stronghold + terrain generators.
/// Anyone can browse league presets (size / biome / wards) to preview higher
/// rung enemy maps. Season reset stays admin-only on the war hub.
class BaseLabScreen extends ConsumerStatefulWidget {
  const BaseLabScreen({super.key});

  @override
  ConsumerState<BaseLabScreen> createState() => _BaseLabScreenState();
}

class _BaseLabScreenState extends ConsumerState<BaseLabScreen> {
  /// ⚡ the last generate actually handed EACH defending castle, and the
  /// pooled total across them. Scaling difficulty/league without seeing this
  /// number is guesswork — it's the single input that decides how much
  /// fortress the generator can afford to build.
  double _budgetPerCastle = 0;
  double _budgetPooled = 0;

  double _difficulty = 60; // 1..100
  double _castles = 4; // 1..6
  double _rivers = 1; // 0..3
  double _lakes = 1; // 0..3
  double _forest = 0.16; // 0..0.35
  double _mountain = 0.11; // 0..0.30
  int _mapSize = Base.defaultSize;
  WarBiome _biome = WarBiome.meadow;
  int? _leaguePreset; // division index, or null = free dials
  // stronghold grammar dials (-1 / null = let the algorithm decide)
  int _archetype = -1; // -1 auto, 0 keep, 1 bailey, 2 twins
  double _gates = 0; // 0 = auto, 1..3 forced
  double _pad = 0; // 0 = auto, 2..5 forced
  double _chamfer = -1; // -1 = auto, 0..3 forced
  double _spacing = 0; // 0 = auto, 2..6 forced
  double _layers = -1; // -1 = auto, 0..8 forced ward partitions
  double _rooms = -1; // -1 = auto, 2..40 forced CITADEL room target
  int _minRooms = 0; // league floor under the citadel plan (0 = none)
  int _innerKeep = -1; // -1 auto, 0 off, 1 on
  int _seed = 1337;
  bool _dials = true; // dials drawer open?

  Base? _base;

  // ── battle sandbox over the generated map ──────────────────────────────────
  bool _battling = false;
  AttackState? _raid;
  FreeMoveBattle? _fight;
  TroopType _deploy = TroopType.soldier;
  int _waveDiff = 50;
  int _waveSeq = 0;
  bool _overShown = false;
  double _uiThrottle = 0;
  final FxLayer _fx = FxLayer();
  final Map<String, Offset> _animPos = {};

  /// League-gated troops unlocked through the selected rung (empty = Bronze).
  Set<TroopType> get _unlockTroops {
    final keys =
        LeagueConfig.instance.unlockedTroopsThrough(_leaguePreset ?? 0);
    return {
      for (final t in kLeagueGatedTroops)
        if (keys.contains(troopUnlockKey(t))) t,
    };
  }

  List<TroopType> get _deployable => [
        for (final t in TroopType.values)
          if (t != TroopType.general) t,
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // League maps are a sandbox anyone can browse — season reset stays
      // admin-only on the war hub, not here.
      _generate();
    });
  }

  AiLevel get _ai => _difficulty >= 80
      ? AiLevel.master
      : _difficulty >= 55
          ? AiLevel.elite
          : _difficulty >= 30
              ? AiLevel.seasoned
              : AiLevel.rookie;

  void _applyLeague(int index) {
    final div = LeagueConfig.instance.divisionByIndex(index);
    _leaguePreset = index;
    _mapSize = div.mapSize;
    _biome = WarBiome.of(warBiomeFromString(div.biome));
    _mountain = div.mountainFrac;
    _forest = div.forestFrac;
    // Water weights → forced river/lake dials (preview, not seeded roll).
    if (div.waterWet >= 0.4) {
      _rivers = 2;
      _lakes = 1;
    } else if (div.waterDry >= 0.4) {
      _rivers = 0;
      _lakes = 0;
    } else {
      _rivers = 1;
      _lakes = 1;
    }
    // Match production: wards raise the FLOOR under the citadel plan, they
    // never cap it — the room target itself stays skill/area driven.
    final wards = div.wards;
    _minRooms = wards >= 2 ? 8 + wards * 6 : 0;
    _rooms = -1;
    _layers = -1;
    // Nudge difficulty toward the rung's feel.
    _difficulty = (30 + div.difficulty * 55).clamp(1, 100);
    _generate();
  }

  void _generate({bool reroll = false}) {
    if (reroll) _seed = (_seed * 16807 + 13) & 0x7fffffff;
    final waterMode = _rivers.round() == 0 && _lakes.round() == 0
        ? 0
        : (_rivers.round() + _lakes.round() >= 3 ? 2 : 1);
    final base = Base(
      WarSide.enemy,
      _seed,
      size: _mapSize,
      config: TerrainConfig(
        rivers: _rivers.round(),
        lakes: _lakes.round(),
        forestFrac: _forest,
        mountainFrac: _mountain,
        waterMode: waterMode,
      ),
    );
    // the difficulty dial drives both the WAR CHEST and the plan depth —
    // and the CONTINUOUS skill (past master → citadels), same as a real war
    final s = WarGame.skillFor(_difficulty.round());
    // Same area-scaled war chest the real war hands the enemy, so the
    // preview is honest about how full a big board actually gets.
    final areaMul = (_mapSize * _mapSize) /
        (Base.defaultSize * Base.defaultSize).toDouble();
    final forgeMul = _mapSize >= 60
        ? areaMul * 2.6
        : _mapSize >= 52
            ? areaMul * 1.7
            : areaMul;
    final budget = WarCosts.prepBudgetFor(s) * forgeMul;
    final castleN = _castles.round().clamp(1, 6);
    _budgetPerCastle = budget;
    _budgetPooled = budget * castleN;
    final crew = [
      for (var i = 0; i < castleN; i++)
        WarPlayer(
            id: 'lab$i',
            name: 'Lab $i',
            emoji: '🧪',
            colorValue: 0xFFE6483F,
            side: WarSide.enemy,
            ai: _ai,
            resources: budget)
          ..skillMul = s / AiData.skill(_ai)
    ];
    WarAi.designBase(
        base, crew, SeededRng(seedFromParts([_seed, 'lab', _difficulty.round()])),
        style: StrongholdStyle(
          archetype: _archetype < 0 ? null : _archetype,
          gates: _gates.round() == 0 ? null : _gates.round(),
          pad: _pad.round() == 0 ? null : _pad.round(),
          chamfer: _chamfer.round() < 0 ? null : _chamfer.round(),
          towerSpacing: _spacing.round() == 0 ? null : _spacing.round(),
          innerKeep: _innerKeep < 0 ? null : _innerKeep == 1,
          layers: _layers.round() < 0 ? null : _layers.round(),
          rooms: _rooms.round() < 0 ? null : _rooms.round().clamp(2, 40),
          minRooms: _minRooms > 1 ? _minRooms : null,
          unlockDefs: () {
            final idx = _leaguePreset ?? 0;
            final keys =
                LeagueConfig.instance.unlockedDefsThrough(idx);
            return {
              for (final t in kLeagueGatedDefs)
                if (keys.contains(defUnlockKey(t))) t,
            };
          }(),
        ));
    setState(() => _base = base);
  }

  // ── battle sandbox ──────────────────────────────────────────────────────────
  void _enterBattle() {
    final design = _base;
    if (design == null) return;
    final clone = Base.fromJson(design.toJson());
    clone.graves.clear();
    clone.scorch.clear();
    final st = AttackState(
      base: clone,
      attacker: WarSide.you,
      attackerName: 'Lab Raid',
      pools: MapPools({'lab': 1e9}),
      freeActions: true,
      defenderIq: WarGame.skillFor(_difficulty.round()),
      // you designed it — every stone is known
      intel: {for (var k = 0; k < clone.rows * clone.cols; k++) k},
    );
    setState(() {
      _raid = st;
      _fight = FreeMoveBattle(st, canDeploy: () => true);
      _battling = true;
      _dials = false;
      _animPos.clear();
      _fx.clear();
      _overShown = false;
      _uiThrottle = 0;
      _deploy = TroopType.soldier;
    });
  }

  void _exitBattle() {
    setState(() {
      _battling = false;
      _raid = null;
      _fight = null;
      _animPos.clear();
      _fx.clear();
      _overShown = false;
      _dials = true;
    });
  }

  /// Fresh clone of the same design — scars swept, same walls.
  void _resetBattle() {
    if (_base == null) return;
    _enterBattle();
  }

  void _summonWave() {
    final st = _raid;
    final fight = _fight;
    if (st == null || fight == null) return;
    final drops = st.base.dropCells.toList();
    if (drops.isEmpty) return;
    final skill = WarGame.skillFor(_waveDiff);
    final rng = SeededRng(seedFromParts([_seed, 'labwave', _waveSeq++]));
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
      final type =
          WarAi.waveTroop(i, skill, rng, unlockTroops: _unlockTroops);
      final t = st.spawn(type, 'lab', drop.r, drop.c, allowStack: true);
      if (t == null) {
        dropIdx++;
        continue;
      }
      if (skill >= 0.9) {
        t.gainXp(Xp.perLevel * (skill >= 1.3 ? 2.0 : 1.0) + 1);
        t.hp = t.maxHp;
      }
      // fan the wave around the drop so they don't stack on a pin
      final a = i * 2.399963;
      final rad = 0.18 * math.sqrt((i % 9) + 1);
      fight.placeAt(
          t, drop.c + math.cos(a) * rad, drop.r + math.sin(a) * rad);
      dropIdx++;
      i++;
    }
    if (fight.over) fight.extend();
    _overShown = false;
    fight.notifyDeploy();
    _fx.ingest(st.takeFx());
    setState(() {});
  }

  void _onBattleTap(Cell cell) {
    final st = _raid;
    final fight = _fight;
    if (st == null || fight == null) return;
    if (!st.base.isRing(cell.r, cell.c)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Deploy on the golden landing ring — any of the four sides.'),
          duration: Duration(milliseconds: 1100)));
      return;
    }
    final t = st.spawn(_deploy, 'lab', cell.r, cell.c, allowStack: true);
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That landing spot is blocked.')));
      return;
    }
    final n = st.troopsSent;
    final a = n * 2.399963;
    final rad = 0.16 * math.sqrt(n % 9);
    fight.placeAt(t, cell.c + math.cos(a) * rad, cell.r + math.sin(a) * rad);
    HapticFeedback.selectionClick();
    if (fight.over) fight.extend();
    _overShown = false;
    fight.notifyDeploy();
    _fx.ingest(st.takeFx());
    setState(() {});
  }

  void _onBattleTick(double dt) {
    if (!_battling) return;
    final fight = _fight;
    final st = _raid;
    if (fight == null || st == null) return;
    fight.tick(dt);
    _fx.tick(dt);
    _animPos
      ..clear()
      ..addEntries(fight.positions.entries
          .map((e) => MapEntry(e.key, Offset(e.value.col, e.value.row))));
    _fx.ingest(st.takeFx());
    _uiThrottle += dt;
    if (_uiThrottle > 0.2) {
      _uiThrottle = 0;
      if (mounted) setState(() {});
    }
    if (fight.over && !_overShown) _onBattleOver();
  }

  void _onBattleOver() {
    if (_overShown || !mounted) return;
    _overShown = true;
    final st = _raid;
    final razed = st?.base.allCastlesRazed ?? false;
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(razed ? '🏰🔥' : '⏱', style: const TextStyle(fontSize: 42)),
            const SizedBox(height: 6),
            Text(razed ? 'BASE RAZED' : 'TIME — 5:00 UP',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: JarsColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              '${(st?.base.destructionPercent ?? 0).round()}% razed'
              ' · ⚔ ${st?.troopsSent ?? 0} sent · 💀 ${st?.troopsLost ?? 0} lost',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12.5, color: JarsColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dCtx);
              _resetBattle();
            },
            child: const Text('🧹 RESET'),
          ),
          if (!razed)
            FilledButton(
              onPressed: () {
                Navigator.pop(dCtx);
                setState(() {
                  _fight?.extend();
                  _overShown = false;
                });
              },
              child: Text('KEEP GOING',
                  style:
                      GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800)),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(dCtx);
              _exitBattle();
            },
            child: const Text('EXIT'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = _base;
    final lowPerf = ref.watch(lowPerformanceModeProvider);
    final divisions = LeagueConfig.instance.divisions;
    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                onPressed: () {
                  if (_battling) {
                    _exitBattle();
                  } else {
                    context.go('/war');
                  }
                },
              ),
              Text(_battling ? '⚔️ LAB BATTLE' : '🧪 BASE LAB',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: JarsColors.textPrimary)),
              const Spacer(),
              Flexible(
                child: Text(
                    _battling
                        ? '${(_raid?.base.destructionPercent ?? 0).round()}% razed'
                            ' · ${_fight?.troopsAlive ?? 0} fighting'
                            '${_fight != null && _fight!.clockRunning ? ' · ⏱ ${_fmtClock(_fight!.timeLeft)}' : ''}'
                            '\n⚡${(_raid?.base.investedDestroyed ?? 0).round()}'
                            ' / ⚡${(_raid?.base.investedValue ?? 0).round()} wrecked'
                            ' · army ⚡${(_raid?.troopSpendSent ?? 0).round()}'
                            ' (💀${(_raid?.troopSpendLost ?? 0).round()})'
                            ' · ${_raid?.troopsLost ?? 0} lost'
                        : '${_biome.name} · ${_mapSize}x$_mapSize · seed $_seed · ${AiData.label(_ai)}'
                            '${WarAi.lastBuildStats == null ? '' : ' · ${WarAi.lastBuildStats!.rooms} rooms · ${WarAi.lastBuildStats!.structures} pieces'}'
                            '\n⚡${_budgetPerCastle.round()}/castle'
                            ' · ⚡${_budgetPooled.round()} pooled'
                            ' → ⚡${(_base?.investedValue ?? 0).round()} actually built',
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceMono(
                        fontSize: 10, color: JarsColors.textSecondary)),
              ),
              if (!_battling)
                IconButton(
                  icon: Icon(_dials ? Icons.tune_rounded : Icons.tune_outlined,
                      color: JarsColors.gold),
                  onPressed: () => setState(() => _dials = !_dials),
                ),
              if (_battling)
                TextButton(
                  onPressed: _exitBattle,
                  child: Text('EXIT',
                      style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w800,
                          color: JarsColors.gold)),
                )
              else if (base != null)
                TextButton(
                  onPressed: _enterBattle,
                  child: Text('⚔ BATTLE',
                      style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w800,
                          color: JarsColors.gold)),
                ),
            ]),
            Expanded(
              child: base == null
                  ? const Center(
                      child: CircularProgressIndicator(color: JarsColors.gold))
                  : WarBoardView(
                      key: ValueKey(_battling
                          ? 'fight-${_raid!.base.seed}-${_raid!.hashCode}'
                          : 'lab-${base.seed}-${base.rows}-${base.hashCode}'),
                      base: _battling ? _raid!.base : base,
                      startFitted: true,
                      animationFps: _battling
                          ? ((_raid?.base.rows ?? 40) >= 52 ? 24 : 30)
                          : null,
                      onTick: _battling ? _onBattleTick : null,
                      onCellTap: _battling ? _onBattleTap : null,
                      lowPerformanceMode: lowPerf,
                      painterBuilder: (tile, gx, gy, t) => WarBoardPainter(
                        base: _battling ? _raid!.base : base,
                        tile: tile,
                        gx: gx,
                        gy: gy,
                        t: t,
                        ownBase: !_battling, // hide traps once the fight starts
                        showDropLane: _battling,
                        showTerritory: false,
                        fog: _battling
                            ? (_raid?.revealed ?? const <int>{})
                            : null,
                        troops: _battling && _raid != null
                            ? [..._raid!.troops, ..._raid!.garrison]
                            : const [],
                        graves: _battling ? (_raid?.graves ?? const []) : const [],
                        troopPositions: _battling ? _animPos : const {},
                        troopScale: _battling ? 0.45 : 1,
                        smokeCells: _battling
                            ? (_raid?.smoke.keys.toSet() ?? const {})
                            : const {},
                        biome: _biome,
                        lowPerformanceMode: lowPerf,
                      ),
                      overlayBuilder: (tile, gx, gy, t) =>
                          !_battling || _fx.isEmpty
                              ? null
                              : _fx.painter(tile, gx, gy),
                    ),
            ),
            if (_battling)
              _battleBar()
            else if (_dials)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF10131C),
                  border: Border(top: BorderSide(color: JarsColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('LEAGUE ENEMY PRESET (admin)',
                          style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: JarsColors.textTertiary)),
                    ),
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < divisions.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            _leagueChip(divisions[i], i),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _dial('DIFFICULTY', _difficulty, 1, 100,
                        '${_difficulty.round()}',
                        (v) {
                      _leaguePreset = null;
                      _difficulty = v;
                    }),
                    _dial('MAP SIZE', _mapSize.toDouble(), 40, 64,
                        '${_mapSize}x$_mapSize', (v) {
                      _leaguePreset = null;
                      _mapSize = v.round();
                      if (_mapSize % 2 != 0) _mapSize += 1;
                    }),
                    _dial('CASTLES', _castles, 1, 6, '${_castles.round()}',
                        (v) => _castles = v),
                    Row(children: [
                      Expanded(
                        child: _dial('RIVERS', _rivers, 0, 3,
                            '${_rivers.round()}', (v) {
                          _leaguePreset = null;
                          _rivers = v;
                        }),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial('LAKES', _lakes, 0, 3, '${_lakes.round()}',
                            (v) {
                          _leaguePreset = null;
                          _lakes = v;
                        }),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: _dial('FOREST', _forest, 0, 0.35,
                            '${(_forest * 100).round()}%', (v) {
                          _leaguePreset = null;
                          _forest = v;
                        }),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial(
                            'MOUNTAINS',
                            _mountain,
                            0,
                            0.30,
                            '${(_mountain * 100).round()}%', (v) {
                          _leaguePreset = null;
                          _mountain = v;
                        }),
                      ),
                    ]),
                    // ── stronghold grammar dials ──
                    Row(children: [
                      Expanded(
                        child: _dial('GATES', _gates, 0, 3,
                            _gates.round() == 0 ? 'auto' : '${_gates.round()}',
                            (v) => _gates = v),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial('PADDING', _pad, 0, 14,
                            _pad.round() == 0 ? 'auto' : '${_pad.round()}',
                            (v) => _pad = v < 2 && v > 0 ? 2 : v),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: _dial(
                            'CORNER CUT',
                            _chamfer,
                            -1,
                            3,
                            _chamfer.round() < 0 ? 'auto' : '${_chamfer.round()}',
                            (v) => _chamfer = v),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial(
                            'TOWER GAP',
                            _spacing,
                            0,
                            6,
                            _spacing.round() == 0 ? 'auto' : '${_spacing.round()}',
                            (v) => _spacing = v < 2 && v > 0 ? 2 : v),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: _dial(
                            'WARD LAYERS',
                            _layers,
                            -1,
                            8,
                            _layers.round() < 0 ? 'auto' : '${_layers.round()}',
                            (v) => _layers = v),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial(
                            'ROOMS',
                            _rooms,
                            -1,
                            40,
                            _rooms.round() < 0 ? 'auto' : '${_rooms.round()}',
                            (v) => _rooms = v),
                      ),
                    ]),
                    Row(children: [
                      _chips('SHAPE', const ['AUTO', 'KEEP', 'BAILEY', 'TWINS'],
                          _archetype + 1, (i) {
                        _archetype = i - 1;
                        _generate();
                      }),
                      const SizedBox(width: 12),
                      _chips('INNER KEEP', const ['AUTO', 'OFF', 'ON'],
                          _innerKeep + 1, (i) {
                        _innerKeep = i - 1;
                        _generate();
                      }),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _generate(reroll: true),
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: JarsColors.gold,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('🎲 GENERATE',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _base == null ? null : _enterBattle,
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: JarsColors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('⚔ BATTLE',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── battle bottom bar ───────────────────────────────────────────────────────
  Widget _battleBar() {
    return Container(
      color: Colors.black.withValues(alpha: 0.38),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  'FREE MOVE — tap the ring to drop · league unlocks feed AI waves.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: JarsColors.textSecondary)),
            ),
            _chip('💀 $_waveDiff', JarsColors.red, () {
              setState(() =>
                  _waveDiff = _waveDiff >= 100 ? 25 : _waveDiff + 25);
            }),
            const SizedBox(width: 6),
            _chip('⚔ AI WAVE', JarsColors.gold, _summonWave),
            const SizedBox(width: 6),
            _chip('🧹 RESET', JarsColors.textSecondary, _resetBattle),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 62,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final type in _deployable) _deployChip(type),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color col, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: col.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: col.withValues(alpha: 0.55)),
          ),
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: col)),
        ),
      );

  Widget _deployChip(TroopType type) {
    final spec = kTroopSpecs[type]!;
    final on = _deploy == type;
    final gated = kLeagueGatedTroops.contains(type);
    final unlocked = !gated || _unlockTroops.contains(type);
    return Opacity(
      opacity: unlocked || on ? 1 : 0.4,
      child: GestureDetector(
        onTap: () => setState(() => _deploy = type),
        onLongPress: () => showTroopCard(context, type),
        child: Container(
          width: 74,
          margin: const EdgeInsets.only(right: 7),
          decoration: BoxDecoration(
            color: on
                ? JarsColors.gold.withValues(alpha: 0.18)
                : JarsColors.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: on ? JarsColors.gold : JarsColors.border,
                width: on ? 2 : 1),
          ),
          child: Stack(children: [
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Column(
                    children: [
                      Text(spec.emoji, style: const TextStyle(fontSize: 18)),
                      Text(spec.name,
                          style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: JarsColors.textSecondary)),
                      Text('${spec.hp}❤ ${spec.atk}⚔',
                          style: GoogleFonts.spaceMono(
                              fontSize: 8.5,
                              color: JarsColors.textTertiary)),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2,
              left: 4,
              child: Text(unlocked ? '∞' : '🔒',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: unlocked ? JarsColors.gold : JarsColors.red)),
            ),
          ]),
        ),
      ),
    );
  }

  String _fmtClock(double secs) {
    final s = secs.ceil().clamp(0, 9999);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _leagueChip(LeagueDivision d, int index) {
    final on = _leaguePreset == index;
    return GestureDetector(
      onTap: () => setState(() => _applyLeague(index)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? d.color.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? d.color : JarsColors.border, width: on ? 1.4 : 1),
        ),
        child: Text('${d.icon} ${d.metalName.replaceAll(' League', '')} ${d.mapSize}',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : JarsColors.textSecondary)),
      ),
    );
  }

  Widget _dial(String label, double value, double min, double max, String shown,
      ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(
        width: 88,
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: JarsColors.textTertiary)),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: JarsColors.gold,
            inactiveTrackColor: JarsColors.border,
            thumbColor: JarsColors.gold,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) => setState(() {
              onChanged(v);
            }),
            onChangeEnd: (_) => _generate(),
          ),
        ),
      ),
      SizedBox(
        width: 52,
        child: Text(shown,
            textAlign: TextAlign.right,
            style: GoogleFonts.spaceMono(
                fontSize: 11, color: JarsColors.textSecondary)),
      ),
    ]);
  }

  Widget _chips(String label, List<String> options, int selected,
      ValueChanged<int> onPick) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: JarsColors.textTertiary)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < options.length; i++)
                GestureDetector(
                  onTap: () => setState(() => onPick(i)),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: selected == i
                          ? JarsColors.gold.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selected == i
                              ? JarsColors.gold
                              : JarsColors.border),
                    ),
                    child: Text(options[i],
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: selected == i
                                ? JarsColors.gold
                                : JarsColors.textSecondary)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
