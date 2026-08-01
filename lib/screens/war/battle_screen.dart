import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/war_providers.dart';
import '../../war/live_battle.dart';
import '../../war/war_engine.dart';
import '../../war/war_game.dart';
import '../../war/war_troop.dart';
import '../../war/war_types.dart';
import 'battle_fx.dart';
import 'war_board.dart';
import 'war_board_view.dart';
import 'war_info_cards.dart';
import 'war_replay_viewer.dart';

/// The war's boards.
/// - DEFENSE: your base — fast-forward, watch enemy raid replays.
/// - COMMANDER: hands-on persistent raid (select, move, strike — full control).
/// - CLASH: Clash-style auto-battle — drop troops, they fight, you watch the
///   cannonballs fly.
class BattleScreen extends ConsumerStatefulWidget {
  final String mode; // 'attack' | 'defense' | 'practice'
  const BattleScreen({super.key, required this.mode});

  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  String _mode = 'defense'; // 'defense' | 'attack' | 'clash' | 'practice'

  final FxLayer _fx = FxLayer();
  final WarBoardController _cam = WarBoardController();

  /// FX enter through here so mortar hits can RATTLE the camera — but a
  /// battery firing nonstop must not turn the screen into a paint shaker:
  /// one kick, then a breather.
  double _sinceKick = 9;
  void _ingest(List<FxEvent> evs) {
    for (final e in evs) {
      if (e.defType == DefType.mortar &&
          (e.kind == FxKind.shot || e.kind == FxKind.trap) &&
          _sinceKick > 0.6) {
        _sinceKick = 0;
        _cam.kick(e.kind == FxKind.trap ? 6 : 3);
      }
    }
    _fx.ingest(evs);
  }

  // commander state
  TroopType? _deploy = TroopType.soldier;
  Troop? _selected;
  Map<int, ReachInfo> _reachInfo = {};
  List<Cell> _targets = [];

  // clash state
  LiveBattle? _battle;
  int _drillDiff = 50; // difficulty of SUMMONED sandbox waves
  bool _freeFlowDrill = false;
  bool _clashBanked = false;
  double _uiThrottle = 0;

  // smooth troop glide: animated display positions in cell-space (x=col, y=row)
  final Map<String, Offset> _animPos = {};

  /// Open a full-screen replay list for [side]'s raids.
  void _openRaidList(WarSide side) {
    final g = WarGame.instance;
    final raids = g.feed
        .where((e) => e.attackerSide == side && e.replay != null)
        .toList();
    if (raids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(side == WarSide.you
              ? 'No clan raids recorded yet — go raid!'
              : 'No enemy raids yet — fast-forward the war.')));
      return;
    }
    final base = side == WarSide.you ? g.enemyBase : g.youBase;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: JarsColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  side == WarSide.you
                      ? 'YOUR CLAN\'S RAIDS'
                      : 'ENEMY RAIDS ON YOUR BASE',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: JarsColors.textTertiary)),
              const SizedBox(height: 8),
              for (final e in raids.reversed.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Text(side == WarSide.you ? '🔵' : '🔴',
                      style: const TextStyle(fontSize: 16)),
                  title: Text(e.line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: JarsColors.textPrimary)),
                  trailing: Text('▶',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: side == WarSide.you
                              ? JarsColors.gold
                              : JarsColors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    WarReplayViewer.show(context,
                        base: base,
                        frames: e.replay!,
                        // clan raids honor YOUR intel — no free base scouting;
                        // enemy raids hit your own base, which you fully know
                        fog: side == WarSide.you ? g.youIntel : null,
                        biome: g.currentBiome,
                        title:
                            '${side == WarSide.you ? '🔵' : '🔴'} ${e.attackerName}\'s raid',
                        summary:
                            '⚔ ${e.troopsSent} sent · 💀 ${e.troopsLost} lost · ⏱ ${_fmtDur(e.replay!.length * 0.55)}');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    if (widget.mode == 'defense') {
      _mode = 'defense';
    } else if (widget.mode == 'practice') {
      // a DRILL on a clone of your own base — unlimited troops, zero stakes
      final st = WarGame.instance.startPracticeBattle();
      _mode = 'practice';
      _battle = _newDrillBattle(st);
      _clashBanked = false;
      _deploy = TroopType.soldier;
    } else {
      final g = WarGame.instance;
      if (g.liveAttack != null) {
        _mode = 'attack'; // resume a persistent commander raid (legacy save)
      } else {
        // WAR MACHINE is the way — no dialogs, straight into the fight
        final st = g.startClashBattle();
        _mode = 'clash';
        _battle = LiveBattle(st,
            canDeploy: () => WarGame.instance.active.armyTotal > 0);
        _clashBanked = false;
        _deploy = TroopType.soldier;
      }
    }
  }

  @override
  void dispose() {
    if (_mode == 'practice') {
      // drills evaporate — nothing to bank, nothing was real
      WarGame.instance.endPractice();
      super.dispose();
      return;
    }
    // never lose a clash battle — resolve and bank it
    if (_battle != null && !_clashBanked) {
      _battle!.fastResolve();
      WarGame.instance.bankClashBattle();
    }
    super.dispose();
  }


  // ── shared helpers ──────────────────────────────────────────────────────────
  AttackState? get _atk => switch (_mode) {
        'clash' => WarGame.instance.clashState,
        'practice' => WarGame.instance.practiceState,
        _ => WarGame.instance.liveAttack,
      };

  Map<String, String> get _badges =>
      {for (final p in WarGame.instance.players) p.id: p.emoji};

  LiveBattle _newDrillBattle(AttackState st) => LiveBattle(st,
      canDeploy: () => true,
      // Preserve the proven combat cadence. Free Flow changes presentation,
      // formation spacing, and interpolation without multiplying expensive
      // 64² objective scans.
      roundPeriod: LiveBattle.stepPeriod,
      defenseEveryRounds: 1);

  void _resetDrill(WarGame g, {bool clean = true}) {
    final st = g.startPracticeBattle(clean: clean);
    _battle = _newDrillBattle(st);
    _animPos.clear();
    _fx.clear();
    _drillOverShown = false;
    _selected = null;
    _reachInfo = {};
    _targets = [];
  }

  Offset _freeFlowOffset(String id) {
    // Deterministic sub-cell formation: quarter-size units spread instead of
    // stacking visually at cell centers. No per-frame allocation/cache.
    final h = id.hashCode & 0x7fffffff;
    final x = (((h & 0xff) / 255.0) - 0.5) * 0.58;
    final y = ((((h >> 8) & 0xff) / 255.0) - 0.5) * 0.58;
    return Offset(x, y);
  }

  void _refreshSel() {
    final t = _selected;
    final atk = _atk;
    if (t == null || !t.alive || atk == null) {
      _selected = null;
      _reachInfo = {};
      _targets = [];
      return;
    }
    _reachInfo = atk.reachable(t);
    _targets = atk.attackTargets(t);
  }

  /// Glide each troop's display position toward its true tile (~5.5 cells/s).
  void _tickGlide(double dt) {
    final atk = _atk;
    if (atk == null) {
      _animPos.clear();
      return;
    }
    final liveIds = <String>{};
    for (final tr in [...atk.troops, ...atk.garrison]) {
      if (!tr.alive) continue;
      liveIds.add(tr.id);
      final target = Offset(tr.c.toDouble(), tr.r.toDouble()) +
          (_mode == 'practice' && _freeFlowDrill
              ? _freeFlowOffset(tr.id)
              : Offset.zero);
      final cur = _animPos[tr.id];
      if (cur == null) {
        _animPos[tr.id] = target;
        continue;
      }
      final delta = target - cur;
      final dist = delta.distance;
      if (dist < 0.01) {
        _animPos[tr.id] = target;
      } else {
        // Deliberately slower than the classic snap-glide, so each route reads
        // as continuous travel between combat decisions.
        final speed = _mode == 'practice' && _freeFlowDrill ? 2.4 : 5.5;
        final step = (speed * dt).clamp(0.0, dist);
        _animPos[tr.id] = cur + delta / dist * step;
      }
    }
    _animPos.removeWhere((id, _) => !liveIds.contains(id));
  }

  void _onTick(double dt) {
    _fx.tick(dt);
    _tickGlide(dt);
    _sinceKick += dt;
    final battle = _battle;
    if ((_mode == 'clash' || _mode == 'practice') &&
        battle != null &&
        !_clashBanked) {
      battle.tick(dt);
      final st = _atk;
      if (st != null) _ingest(st.takeFx());
      _uiThrottle += dt;
      if (_uiThrottle > 0.2) {
        _uiThrottle = 0;
        if (mounted) setState(() {});
      }
      if (battle.over) {
        if (_mode == 'clash') {
          _onClashOver();
        } else if (_mode == 'practice') {
          _onDrillOver();
        }
      }
    }
  }

  // ── clash flow ──────────────────────────────────────────────────────────────
  void _onClashOver() {
    if (_clashBanked) return;
    _clashBanked = true;
    final st = WarGame.instance.clashState;
    final gained = st?.gained ?? 0;
    final lost = st?.troopsLost ?? 0;
    final sent = st?.troopsSent ?? 0;
    final spent = st?.resourcesSpent ?? 0;
    final dur = _battle?.elapsed ?? 0;
    WarGame.instance.bankClashBattle();
    if (!mounted) return;
    setState(() {});
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(gained >= 30 ? '🔥' : (gained >= 5 ? '⚔️' : '💨'),
                style: const TextStyle(fontSize: 42)),
            const SizedBox(height: 6),
            Text('BATTLE OVER',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: JarsColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              '+${gained.round()}% destruction · ⚔ $sent sent · 💀 $lost lost'
              ' · ⏱ ${_fmtDur(dur)} · ${spent.round()}⚡ spent',
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
              final g = WarGame.instance;
              if (g.phase == WarPhase.results) {
                context.go('/war/report');
              } else {
                context.go('/war');
              }
            },
            child: const Text('DONE'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dCtx);
              final g = ref.read(warGameProvider);
              if (g.phase != WarPhase.war) {
                context.go('/war/report');
                return;
              }
              final st = g.startClashBattle();
              setState(() {
                _battle = LiveBattle(st,
                    canDeploy: () => WarGame.instance.active.armyTotal > 0);
                _clashBanked = false;
              });
            },
            child: Text('ANOTHER WAVE',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  String _fmtDur(double secs) {
    final s = secs.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _clockSuffix() {
    final b = _battle;
    if (b == null || !b.clockRunning) return '';
    final s = b.timeLeft.ceil();
    return ' · ⏱ ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  bool _drillOverShown = false;
  void _onDrillOver() {
    if (_drillOverShown) return;
    _drillOverShown = true;
    final st = WarGame.instance.practiceState;
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
              ' · ⚔ ${st?.troopsSent ?? 0} sent · 💀 ${st?.troopsLost ?? 0} lost'
              ' · ⏱ ${_fmtDur(_battle?.elapsed ?? 0)}',
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
              setState(() {
                _resetDrill(WarGame.instance);
              });
            },
            child: const Text('🧹 RESET'),
          ),
          if (!razed)
            FilledButton(
              onPressed: () {
                Navigator.pop(dCtx);
                setState(() {
                  _battle?.extend();
                  _drillOverShown = false;
                });
              },
              child: Text('KEEP GOING',
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }

  void _onPracticeTap(Cell cell) {
    final g = WarGame.instance;
    final st = g.practiceState;
    final battle = _battle;
    if (st == null || battle == null) return;
    final type = _deploy;
    if (type == null) return;
    if (!st.base.isRing(cell.r, cell.c)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Deploy on the golden landing ring — any of the four sides.'),
          duration: Duration(milliseconds: 1100)));
      return;
    }
    Troop? t = st.spawn(type, 'drill', cell.r, cell.c);
    // Free-flow units are tiny, so make rapid formation deployment forgiving:
    // if the tapped ring cell is occupied, use the nearest open ring slot.
    if (t == null && _freeFlowDrill) {
      for (var radius = 1; radius <= 4 && t == null; radius++) {
        for (var dr = -radius; dr <= radius && t == null; dr++) {
          for (var dc = -radius; dc <= radius && t == null; dc++) {
            if (dr.abs() != radius && dc.abs() != radius) continue;
            final rr = cell.r + dr, cc = cell.c + dc;
            if (!st.base.inBounds(rr, cc) || !st.base.isRing(rr, cc)) {
              continue;
            }
            t = st.spawn(type, 'drill', rr, cc);
          }
        }
      }
    }
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That landing spot is blocked.')));
    } else {
      HapticFeedback.selectionClick();
      if (battle.over) battle.extend(); // the sandbox never says no
      _drillOverShown = false;
      battle.notifyDeploy();
      _ingest(st.takeFx());
      setState(() {});
    }
  }

  void _onClashTap(Cell cell) {
    final g = WarGame.instance;
    final st = g.clashState;
    final battle = _battle;
    if (st == null || battle == null || _clashBanked) return;
    final type = _deploy;
    if (type == null) return;
    if (!g.enemyBase.isRing(cell.r, cell.c)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Deploy on the golden landing ring — any of the four sides.'),
          duration: Duration(milliseconds: 1100)));
      return;
    }
    if (g.active.armyCount(type) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'No trained ${kTroopSpecs[type]!.name}s — hit 🎖 TRAIN to muster more.')));
      return;
    }
    final t = g.deployTrained(st, type, cell.r, cell.c);
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(g.knockedOut(g.active)
              ? '💀 Your castle has fallen — you can only spectate.'
              : 'That landing spot is blocked.')));
    } else {
      HapticFeedback.selectionClick();
      battle.notifyDeploy();
      _ingest(st.takeFx());
      setState(() {});
    }
  }

  // ── commander flow ──────────────────────────────────────────────────────────
  void _onCommanderTap(Cell cell, WarGame g) {
    final atk = _atk;
    if (atk == null) return;
    // deploy on the landing ring (only when a chip is armed)
    if (g.enemyBase.isRing(cell.r, cell.c) &&
        _deploy != null &&
        atk.troopAt(cell.r, cell.c) == null) {
      if (g.active.armyCount(_deploy!) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'No trained ${kTroopSpecs[_deploy!]!.name}s — hit 🎖 TRAIN to muster more.')));
        return;
      }
      final t = g.deployTrained(atk, _deploy!, cell.r, cell.c);
      if (t == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(g.knockedOut(g.active)
                ? '💀 Your castle has fallen — you can only spectate.'
                : 'That landing spot is blocked.')));
      } else {
        HapticFeedback.selectionClick();
        atk.defendersReact();
        _ingest(atk.takeFx());
        g.raidChanged();
      }
      _refreshSel();
      setState(() {});
      return;
    }
    final onCell = atk.troopAt(cell.r, cell.c);
    final sel = _selected;
    if (onCell != null && onCell.side == WarSide.you) {
      _selected = onCell;
      _deploy = null; // selecting a troop disarms the shop — no accidental drops
      _refreshSel();
      HapticFeedback.selectionClick();
      setState(() {});
      return;
    }
    if (sel != null) {
      if (_targets.any((t) => t.r == cell.r && t.c == cell.c)) {
        atk.attackCell(sel, cell.r, cell.c);
        atk.defendersReact();
        _ingest(atk.takeFx());
        HapticFeedback.mediumImpact();
        g.raidChanged();
        if (WarGame.instance.phase == WarPhase.results) {
          context.go('/war/report');
          return;
        }
        _refreshSel();
        setState(() {});
        return;
      }
      if (_reachInfo.containsKey(cell.r * atk.base.cols + cell.c)) {
        atk.moveTroop(sel, cell.r, cell.c);
        atk.defendersReact();
        _ingest(atk.takeFx());
        g.raidChanged();
        _refreshSel();
        setState(() {});
        return;
      }
    }
    _selected = null;
    _reachInfo = {};
    _targets = [];
    setState(() {});
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // same reasoning as base_builder_screen: reachable via a direct
    // deep-link/reload, so it must trigger its own sync, not rely on the hub.
    ref.watch(warRoomSyncProvider);
    final g = ref.watch(warGameProvider);
    final base = _mode == 'defense'
        ? g.youBase
        : _mode == 'practice'
            ? (g.practiceState?.base ?? g.youBase)
            : g.enemyBase;

    return Scaffold(
      backgroundColor: const Color(0xFF090B12),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(g),
            Expanded(
              child: WarBoardView(
                key: ValueKey('board-$_mode'),
                base: base,
                controller: _cam,
                startFitted: _mode != 'attack',
                startFocus: _mode == 'attack'
                    ? Cell(base.rows - 1, base.cols ~/ 2)
                    : null,
                // Smooth enough to read movement, capped hard so 64² drills
                // never repaint at an unnecessary 60 fps.
                animationFps: _mode == 'practice' && _freeFlowDrill
                    ? (base.rows >= 52 ? 16 : 24)
                    : null,
                onTick: _onTick,
                onCellTap: switch (_mode) {
                  'attack' => (cell) => _onCommanderTap(cell, g),
                  'clash' => _onClashTap,
                  'practice' => _onPracticeTap,
                  _ => null,
                },
                painterBuilder: (tile, gx, gy, t) => WarBoardPainter(
                  base: base,
                  tile: tile,
                  gx: gx,
                  gy: gy,
                  t: t,
                  ownBase: _mode == 'defense',
                  showDropLane: _mode != 'defense',
                  // never flash the whole base before the raid exists
                  fog: _mode == 'defense'
                      ? null
                      : (_atk?.revealed ?? const <int>{}),
                  troops: _mode == 'defense' || _atk == null
                      ? const []
                      : [..._atk!.troops, ..._atk!.garrison],
                  graves: _mode == 'defense' || _atk == null
                      ? const []
                      : _atk!.graves,
                  reachable: _mode == 'attack' ? _reachInfo.keys.toSet() : const {},
                  reachCosts: _mode == 'attack'
                      ? {for (final e in _reachInfo.entries) e.key: e.value.energyCost}
                      : const {},
                  targets: _mode == 'attack' ? _targets : const [],
                  selected:
                      _selected == null ? null : Cell(_selected!.r, _selected!.c),
                  ownerBadges: _mode == 'defense' ? const {} : _badges,
                  troopPositions: _mode == 'defense' ? const {} : _animPos,
                  troopScale:
                      _mode == 'practice' && _freeFlowDrill ? 0.45 : 1,
                  // on defense, show where the ENEMY has eyes (their scouting),
                  // not the marched trail; on attack the fog is the signal
                  showTerritory: _mode == 'defense',
                  enemyEyes:
                      _mode == 'defense' ? g.enemyIntel : const <int>{},
                  biome: g.currentBiome,
                  smokeCells: _mode == 'defense' || _atk == null
                      ? const {}
                      : _atk!.smoke.keys.toSet(),
                ),
                overlayBuilder: (tile, gx, gy, t) =>
                    _fx.isEmpty ? null : _fx.painter(tile, gx, gy),
              ),
            ),
            switch (_mode) {
              'attack' => _commanderBar(g),
              'clash' => _clashBar(g),
              'practice' => _practiceBar(g),
              _ => _defenseBar(g),
            },
          ],
        ),
      ),
    );
  }

  // ── top bar ─────────────────────────────────────────────────────────────────
  Widget _topBar(WarGame g) {
    final atk = _atk;
    String status;
    switch (_mode) {
      case 'clash':
        status =
            '💥 ${g.youDestruction.round()}% razed · ${_battle?.troopsAlive ?? 0} troops fighting${_clockSuffix()}';
        break;
      case 'practice':
        status =
            '🎯 ${_freeFlowDrill ? 'FREE FLOW' : 'CLASSIC'} — '
            '${(_atk?.base.destructionPercent ?? 0).round()}% razed${_clockSuffix()}';
        break;
      case 'attack':
        status = 'enemy base ${g.youDestruction.round()}% razed';
        break;
      default:
        status = 'your base ${g.enemyDestruction.round()}% lost · ⏱ ${g.clock.label}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 10, 2),
      child: Column(
        children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              onPressed: () => context.go('/war'),
            ),
            _modeChip('🛡', 'defense'),
            const SizedBox(width: 5),
            _modeChip(_mode == 'clash' ? '🤖' : '🎯', 'attackEntry'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      GoogleFonts.inter(fontSize: 10.5, color: JarsColors.textSecondary)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: JarsColors.gold.withValues(alpha: 0.5)),
              ),
              child: Text('⚡ ${g.resourcesOf(g.activePlayerId).round()}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: JarsColors.textPrimary)),
            ),
          ]),
          // combat ticker: the last hits, so nothing lands invisibly
          if (_mode != 'defense' && atk != null && atk.log.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 4, bottom: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  atk.log.reversed
                      .take(2)
                      .map((e) => e.text)
                      .join('   ·   '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceMono(
                      fontSize: 9.5, color: JarsColors.textTertiary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeChip(String emoji, String target) {
    final isDefense = target == 'defense';
    final on = isDefense ? _mode == 'defense' : _mode != 'defense';
    final col = isDefense ? JarsColors.primary : JarsColors.gold;
    return GestureDetector(
      onTap: () {
        if (isDefense) {
          if (_mode == 'practice') {
            WarGame.instance.endPractice();
            setState(() {
              _mode = 'defense';
              _battle = null;
              _selected = null;
              _reachInfo = {};
              _targets = [];
            });
            return;
          }
          if (_mode == 'clash' && _battle != null && !_clashBanked) {
            _battle!.fastResolve();
            _onClashOver();
            return;
          }
          setState(() {
            _mode = 'defense';
            _selected = null;
            _reachInfo = {};
            _targets = [];
          });
        } else if (_mode == 'defense') {
          final g = WarGame.instance;
          if (g.phase != WarPhase.war) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content:
                    Text('The war hasn\'t started — raid when the horns sound.')));
            return;
          }
          if (g.liveAttack != null) {
            setState(() => _mode = 'attack'); // legacy commander resume
          } else {
            // straight into the WAR MACHINE — no dialogs
            final st = g.startClashBattle();
            setState(() {
              _mode = 'clash';
              _battle = LiveBattle(st,
                  canDeploy: () => WarGame.instance.active.armyTotal > 0);
              _clashBanked = false;
              _deploy = TroopType.soldier;
            });
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? col.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: on ? col : JarsColors.border),
        ),
        child: Text('$emoji ${isDefense ? 'DEFENSE' : 'ATTACK'}',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: JarsColors.textPrimary)),
      ),
    );
  }

  // ── clash bottom bar ────────────────────────────────────────────────────────
  Widget _clashBar(WarGame g) {
    return Container(
      color: Colors.black.withValues(alpha: 0.32),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  '🤖 Drop troops on the golden ring — they fight on their own.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: JarsColors.textSecondary)),
            ),
            _clanRaidsChip(),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 62,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _trainShortcut(),
                    for (final type in TroopType.values) _deployChip(type, g),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (_battle != null && !_clashBanked) {
                  _battle!.fastResolve();
                  _onClashOver();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: JarsColors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('END\nBATTLE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── commander bottom bar ────────────────────────────────────────────────────
  Widget _commanderBar(WarGame g) {
    final sel = _selected;
    return Container(
      color: Colors.black.withValues(alpha: 0.32),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sel != null && sel.alive)
            _selInfo(sel, g)
          else
            Row(children: [
              Expanded(
                child: Text(
                  '👇 Arm a card + tap the ring to deploy · tap a troop to command it',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      GoogleFonts.inter(fontSize: 11, color: JarsColors.textSecondary),
                ),
              ),
              _clanRaidsChip(),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 62,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _trainShortcut(),
                    for (final type in TroopType.values) _deployChip(type, g),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                ref.read(warGameProvider).commitLiveAttack();
                if (WarGame.instance.phase == WarPhase.results) {
                  context.go('/war/report');
                } else {
                  context.go('/war');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: JarsColors.gold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('END\nRAID',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.black)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── practice bottom bar: the FULL sandbox ───────────────────────────────────
  // deploy anything, summon AI waves at any difficulty, hop to the builder,
  // sweep the board clean. Nothing here is real.
  Widget _practiceBar(WarGame g) {
    return Container(
      color: Colors.black.withValues(alpha: 0.32),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  _freeFlowDrill
                      ? 'FREE FLOW PREVIEW — quarter-size troops, smooth formations.'
                      : 'CLASSIC DRILL — original tile combat.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: JarsColors.textSecondary)),
            ),
            _sandChip(
                _freeFlowDrill ? '◉ FREE FLOW' : '▦ CLASSIC',
                _freeFlowDrill ? JarsColors.green : JarsColors.textSecondary,
                () {
              setState(() {
                _freeFlowDrill = !_freeFlowDrill;
                // Never cross engines: switching starts a pristine clone.
                _resetDrill(g);
              });
            }),
            const SizedBox(width: 6),
            // the wave dial: 25 → 50 → 75 → 100, tap to cycle
            _sandChip('💀 $_drillDiff', JarsColors.red, () {
              setState(() =>
                  _drillDiff = _drillDiff >= 100 ? 25 : _drillDiff + 25);
            }),
            const SizedBox(width: 6),
            _sandChip('⚔ AI WAVE', JarsColors.gold, () {
              g.summonDrillWave(_drillDiff);
              if (_battle?.over ?? false) _battle?.extend();
              _drillOverShown = false;
              _battle?.notifyDeploy();
              final st = g.practiceState;
              if (st != null) _ingest(st.takeFx());
              setState(() {});
            }),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 62,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final type in TroopType.values)
                      _deployChip(type, g, practice: true),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _sandSquare('▶', 'REPLAY', () {
              final st = g.practiceState;
              if (st == null || st.frames.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Nothing to replay yet — fight first.')));
                return;
              }
              WarReplayViewer.show(context,
                  base: st.base,
                  frames: List.of(st.frames),
                  fog: null,
                  biome: g.currentBiome,
                  title: '🎯 The drill',
                  summary:
                      '⚔ ${st.troopsSent} sent · 💀 ${st.troopsLost} lost · ⏱ ${_fmtDur(st.frames.length * 0.55)}');
            }),
            const SizedBox(width: 6),
            _sandSquare('🔨', 'BUILD', () => context.go('/war/build')),
            const SizedBox(width: 6),
            _sandSquare('🧹', 'RESET', () {
              // fresh clone, scars swept — a pristine yard to wreck again
              setState(() {
                _resetDrill(g);
              });
            }),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => context.go('/war'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: JarsColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('END\nDRILL',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sandChip(String label, Color col, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: col.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: col.withValues(alpha: 0.65)),
          ),
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: JarsColors.textPrimary)),
        ),
      );

  Widget _sandSquare(String emoji, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 62,
          decoration: BoxDecoration(
            color: JarsColors.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: JarsColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 17)),
              Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: JarsColors.textSecondary)),
            ],
          ),
        ),
      );

  Widget _deployChip(TroopType type, WarGame g, {bool practice = false}) {
    final spec = kTroopSpecs[type]!;
    final on = _deploy == type;
    final count = g.active.armyCount(type);
    return Opacity(
      opacity: practice || count > 0 || on ? 1 : 0.45,
      child: GestureDetector(
        onTap: () => setState(() {
          _deploy = type;
          _selected = null; // arming the shop deselects the board
          _reachInfo = {};
          _targets = [];
        }),
        onLongPress: () => showTroopCard(context, type),
        child: Container(
          width: 74,
          margin: const EdgeInsets.only(right: 7),
          decoration: BoxDecoration(
            color: on ? JarsColors.gold.withValues(alpha: 0.18) : JarsColors.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: on ? JarsColors.gold : JarsColors.border, width: on ? 2 : 1),
          ),
          child: Stack(children: [
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                              fontSize: 8.5, color: JarsColors.textTertiary)),
                    ],
                  ),
                ),
              ),
            ),
            // trained count — the army you brought (drills are bottomless)
            Positioned(
              top: 2,
              left: 4,
              child: Text(practice ? '∞' : '×$count',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: practice || count > 0
                          ? JarsColors.gold
                          : JarsColors.red)),
            ),
            Positioned(
              top: 2,
              right: 4,
              child: GestureDetector(
                onTap: () => showTroopCard(context, type),
                child: Text('ⓘ',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: JarsColors.textTertiary)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _trainShortcut() => GestureDetector(
        onTap: () => context.go('/war/train'),
        child: Container(
          width: 58,
          margin: const EdgeInsets.only(right: 7),
          decoration: BoxDecoration(
            color: JarsColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: JarsColors.primary.withValues(alpha: 0.6)),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  const Text('🎖', style: TextStyle(fontSize: 17)),
                  Text('TRAIN',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: JarsColors.textPrimary)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _selInfo(Troop sel, WarGame g) {
    final atk = _atk;
    if (atk == null) return const SizedBox.shrink();
    final mult = atk.multiplierAt(sel.r, sel.c, WarSide.you);
    final mc =
        mult >= 1.5 ? JarsColors.green : (mult >= 1 ? JarsColors.gold : JarsColors.red);
    final owner = g.players.firstWhere((p) => p.id == sel.ownerId,
        orElse: () => g.active);
    final broke = owner.resources < 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(sel.spec.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                        '${owner.emoji} ${owner.isYou ? 'Your' : "${owner.name}'s"} ${sel.spec.name} · L${sel.level}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: JarsColors.textPrimary)),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: mc.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(color: mc.withValues(alpha: 0.6)),
                    ),
                    child: Text('×${mult.toStringAsFixed(2)}',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 11, fontWeight: FontWeight.w800, color: mc)),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => showTroopCard(context, sel.type),
                    child: Text('ⓘ',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: JarsColors.textTertiary)),
                  ),
                ]),
                Text(
                    'HP ${sel.hp}/${sel.maxHp} · ATK ${sel.atk} · spends ${owner.name}\'s ⚡${owner.resources.round()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 10, color: JarsColors.textTertiary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('XP → L${(sel.level + 1).clamp(1, Xp.maxLevel)}',
                    style:
                        GoogleFonts.inter(fontSize: 8, color: JarsColors.textTertiary)),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: Xp.progress(sel.xp),
                    minHeight: 5,
                    backgroundColor: JarsColors.surface,
                    valueColor: const AlwaysStoppedAnimation<Color>(JarsColors.gold),
                  ),
                ),
              ],
            ),
          ),
        ]),
        if (broke)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '🚫 ${owner.isYou ? 'You are' : '${owner.name} is'} out of ⚡ — this troop can\'t act. Log a workout to refuel.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.red)),
          ),
      ],
    );
  }

  // ── defense bottom bar ──────────────────────────────────────────────────────
  Widget _defenseBar(WarGame g) {
    final raids = g.feed
        .where((e) => e.attackerSide == WarSide.enemy && e.replay != null)
        .toList();
    return Container(
      color: Colors.black.withValues(alpha: 0.32),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fast-forward to see the enemy hit your base, then watch the replays.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, color: JarsColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _ff('+1h', () => g.advanceHours(1))),
            const SizedBox(width: 7),
            Expanded(child: _ff('+6h', () => g.advanceHours(6))),
            const SizedBox(width: 7),
            Expanded(child: _ff('End Day', () => g.advanceToEndOfDay())),
            const SizedBox(width: 7),
            Expanded(
              child: GestureDetector(
                onTap: () => _openRaidList(WarSide.enemy),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: raids.isNotEmpty
                        ? JarsColors.red.withValues(alpha: 0.2)
                        : JarsColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: raids.isNotEmpty ? JarsColors.red : JarsColors.border),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('▶ REPLAYS (${raids.length})',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: JarsColors.textPrimary)),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// Watch your clan's raids on the enemy base (crew AI + your banked raids).
  Widget _clanRaidsChip() => GestureDetector(
        onTap: () => _openRaidList(WarSide.you),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: JarsColors.gold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(color: JarsColors.gold.withValues(alpha: 0.5)),
          ),
          child: Text('▶ CLAN RAIDS',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: JarsColors.textPrimary)),
        ),
      );

  Widget _ff(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: JarsColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: JarsColors.border),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: JarsColors.textPrimary)),
            ),
          ),
        ),
      );
}
