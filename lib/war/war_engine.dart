import 'dart:collection';
import 'dart:math' as math;

import '../core/seeded_rng.dart';
import 'war_base.dart';
import 'war_troop.dart';
import 'war_types.dart';

/// Per-player resource access. The engine never owns money — it spends through
/// this, so the SAME pool backs prep, raids, and defense (no copies to lose).
abstract class WarPools {
  double of(String id);
  bool spend(String id, double amt);
  void add(String id, double amt);
}

/// Map-backed pools (tests / headless sims).
class MapPools implements WarPools {
  final Map<String, double> map;
  MapPools(this.map);
  @override
  double of(String id) => map[id] ?? 0;
  @override
  bool spend(String id, double amt) {
    if ((map[id] ?? 0) < amt) return false;
    map[id] = (map[id] ?? 0) - amt;
    return true;
  }

  @override
  void add(String id, double amt) => map[id] = (map[id] ?? 0) + amt;
}

/// One line of a battle for the log/report.
class AttackEvent {
  final String text;
  final Cell? at;
  const AttackEvent(this.text, {this.at});
}

/// A combat effect for the UI to animate (cannonball, tesla arc, damage pop…).
class FxEvent {
  final FxKind kind;
  final Cell? from;
  final Cell to;
  final int amount;
  final WarSide bySide;
  final DefType? defType;
  final String? emoji; // who fell (death FX draws the fallen figure)
  const FxEvent(this.kind, this.to,
      {this.from,
      this.amount = 0,
      required this.bySide,
      this.defType,
      this.emoji});
}

/// Where a troop can go this activation: pathing cost + what it'll cost in ⚡.
class ReachInfo {
  final int moveCost;
  final double energyCost;
  const ReachInfo(this.moveCost, this.energyCost);
}

/// A single frame of a recorded raid (for the WATCH RAID playback).
class RaidSprite {
  final String id; // stable troop identity — playback glides MATCH by this
  final String emoji;
  final int r, c;
  final WarSide side;
  final double hpFrac;
  const RaidSprite(this.id, this.emoji, this.r, this.c, this.side, this.hpFrac);
}

/// A structure's state at frame time — so replays show walls standing, taking
/// damage, and falling (not the post-battle rubble the whole time).
class RaidStruct {
  final int r, c;
  final DefType type;
  final double hpFrac;
  const RaidStruct(this.r, this.c, this.type, this.hpFrac);
}

class RaidFrame {
  final List<RaidSprite> sprites;
  final List<RaidStruct> structs;
  final List<Cell> flashes;
  final List<FxEvent> fx; // the shots/zaps/blasts of this beat — replayable
  final String caption;
  final List<List<int>> graves; // [r, c, slot] — the fallen stay fallen
  final List<List<int>> scorch; // [cellKey, count] — craters AS OF this beat
  const RaidFrame(this.sprites, this.structs, this.flashes, this.fx, this.caption,
      {this.graves = const [], this.scorch = const []});
}

/// The result of a completed attack (AI sim + the report).
class AttackResult {
  final WarSide attacker;
  final String attackerName;
  final double destructionPercent;
  final double gained;
  final int troopsLost;
  final int troopsSent;
  final double resourcesSpent;
  final bool castleRazed;
  final List<AttackEvent> log;
  final List<RaidFrame> frames;
  final Set<int> revealed; // scouting to fold into the clan's shared intel
  const AttackResult({
    required this.attacker,
    required this.attackerName,
    required this.destructionPercent,
    required this.gained,
    required this.troopsLost,
    this.troopsSent = 0,
    required this.resourcesSpent,
    required this.castleRazed,
    required this.log,
    required this.frames,
    required this.revealed,
  });
}

class CombatPreview {
  final double attMult;
  final int dmg;
  final int counter;
  final bool destroys;
  const CombatPreview(this.attMult, this.dmg, this.counter, this.destroys);
}

/// A live attack on one base. Pure logic, fully serializable so an in-progress
/// raid SURVIVES navigation, fast-forward, and app restarts.
class AttackState {
  final Base base; // the DEFENDER's base
  final WarSide attacker;
  final String attackerName;
  final WarPools pools;

  /// Clash-mode economy: troops cost ⚡ to DEPLOY, but their moves/captures/
  /// attacks are free (CoC-style). Defense still pays per shot.
  final bool freeActions;

  /// How SMART this base's defense fights (0..1, from the clan's AiLevel):
  /// masters focus-fire the weakest intruder and their garrison spots farther.
  final double defenderIq;
  final List<Troop> troops = []; // attacker troops
  final List<Troop> garrison = []; // live defenders (from Guard Posts)
  final List<List<int>> graves = []; // [r, c, slot 0..3] — tombstones
  final Set<int> revealed = {}; // fog
  final List<AttackEvent> log = [];
  final List<RaidFrame> frames = [];
  final List<Cell> _pendingFlashes = [];
  final List<FxEvent> _fxQueue = [];
  final List<FxEvent> _frameFx = []; // buffered per snapshot for replays

  /// Fogger smoke: cellKey → ticks remaining (forest-style concealment).
  final Map<int, int> smoke = {};

  int troopsLost = 0;
  int troopsSent = 0;
  int garrisonLost = 0;
  double resourcesSpent = 0;
  int _troopSeq = 0;
  late double _startDestruction;

  AttackState({
    required this.base,
    required this.attacker,
    required this.attackerName,
    required this.pools,
    bool spawnGarrison = true,
    this.freeActions = false,
    this.defenderIq = 0.5,
    Set<int>? intel, // everything the clan has ALREADY scouted on this base
  }) {
    _startDestruction = base.destructionPercent;
    // the landing ring (all four sides) starts scouted
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        if (base.isRing(r, c)) revealed.add(_key(r, c));
      }
    }
    if (intel != null) revealed.addAll(intel);
    if (spawnGarrison) {
      _spawnGarrison();
      _spawnGenerals();
    }
  }

  /// Drain pending combat effects (the UI animates them).
  List<FxEvent> takeFx() {
    final out = List<FxEvent>.of(_fxQueue);
    _fxQueue.clear();
    return out;
  }

  void _fx(FxEvent e) {
    _fxQueue.add(e);
    if (_fxQueue.length > 300) _fxQueue.removeRange(0, _fxQueue.length - 300);
    _frameFx.add(e);
    if (_frameFx.length > 120) _frameFx.removeRange(0, _frameFx.length - 120);
  }

  /// How far a garrison defender will chase from its post before returning.
  static const int garrisonLeash = 4;

  /// A standing STOREHOUSE within 3 of the post keeps its watch well-fed.
  bool _provisioned(int r, int c) {
    for (var dr = -3; dr <= 3; dr++) {
      for (var dc = -3; dc <= 3; dc++) {
        final s = base.structAt(r + dr, c + dc);
        if (s != null && s.alive && s.type == DefType.storehouse) return true;
      }
    }
    return false;
  }

  /// Command Tents field one General each (ranged elite defender).
  void _spawnGenerals() {
    var i = 0;
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s == null || !s.alive || s.type != DefType.commandTent) continue;
        // Prefer an adjacent open tile; else sit on the tent.
        var gr = r, gc = c;
        for (final d in _orth) {
          final nr = r + d[0], nc = c + d[1];
          if (base.passable(nr, nc) &&
              troopAt(nr, nc) == null &&
              !base.isRing(nr, nc)) {
            gr = nr;
            gc = nc;
            break;
          }
        }
        if (troopAt(gr, gc) != null) continue;
        final gen = Troop(
          id: 'gen${i++}',
          ownerId: s.ownerId,
          side: base.side,
          type: TroopType.general,
          r: gr,
          c: gc,
          homeR: r,
          homeC: c,
        );
        gen.gainXp(Xp.perLevel * 2 + 1);
        gen.hp = gen.maxHp;
        garrison.add(gen);
      }
    }
  }

  /// Guard Posts field a live defender each raid, anchored to the post.
  void _spawnGarrison() {
    var i = 0;
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s == null || !s.alive || s.type != DefType.guardPost) continue;
        if (troopAt(r, c) != null) continue;
        final guard = Troop(
            id: 'g${i++}',
            ownerId: s.ownerId,
            side: base.side,
            type: TroopType.soldier,
            r: r,
            c: c,
            homeR: r,
            homeC: c);
        // well-fed watch: a storehouse within 3 fields VETERAN guards
        if (_provisioned(r, c)) {
          guard.gainXp(Xp.perLevel + 1.0);
          guard.hp = guard.maxHp;
        }
        garrison.add(guard);
        // HOUSING nearby quarters a second defender for this post
        var housed = false;
        for (var dr = -2; dr <= 2 && !housed; dr++) {
          for (var dc = -2; dc <= 2 && !housed; dc++) {
            final h = base.structAt(r + dr, c + dc);
            housed = h != null && h.alive && h.type == DefType.housing;
          }
        }
        if (housed) {
          for (final d in _orth) {
            final nr = r + d[0], nc = c + d[1];
            if (!base.passable(nr, nc) || troopAt(nr, nc) != null) continue;
            if (base.isRing(nr, nc)) continue;
            final housed2 = Troop(
                id: 'g${i++}',
                ownerId: s.ownerId,
                side: base.side,
                type: TroopType.soldier,
                r: nr,
                c: nc,
                homeR: r,
                homeC: c);
            if (_provisioned(r, c)) {
              housed2.gainXp(Xp.perLevel + 1.0);
              housed2.hp = housed2.maxHp;
            }
            garrison.add(housed2);
            break;
          }
        }
      }
    }
  }

  WarSide get defender => base.side;
  int _key(int r, int c) => r * base.cols + c;
  bool visible(int r, int c) => revealed.contains(_key(r, c));

  /// The landing ring is ONE-WAY: once a unit steps inland it can never walk
  /// back onto the ring (no cheesing around the defenses).
  bool _stepAllowed(int fromR, int fromC, int toR, int toC) {
    if (base.isRing(toR, toC) && !base.isRing(fromR, fromC)) return false;
    return true;
  }

  bool _pay(String id, double amt) {
    final ok = pools.spend(id, amt);
    return ok;
  }

  bool _payAttacker(String id, double amt) {
    if (!_pay(id, amt)) return false;
    resourcesSpent += amt;
    return true;
  }

  /// Attacker ACTION cost (move/capture/strike) — free in clash mode.
  bool _payAction(String id, double amt) {
    if (freeActions) return true;
    return _payAttacker(id, amt);
  }

  Troop? troopAt(int r, int c) {
    for (final t in troops) {
      if (t.alive && t.r == r && t.c == c) return t;
    }
    for (final t in garrison) {
      if (t.alive && t.r == r && t.c == c) return t;
    }
    return null;
  }

  void _reveal(int r, int c, {int radius = 1}) {
    for (var dr = -radius; dr <= radius; dr++) {
      for (var dc = -radius; dc <= radius; dc++) {
        final nr = r + dr, nc = c + dc;
        if (base.inBounds(nr, nc)) revealed.add(_key(nr, nc));
      }
    }
  }

  // ── spawning ────────────────────────────────────────────────────────────────
  /// Deploy on the landing ring. [prepaid] troops come from a trained army —
  /// their ⚡ was spent at the Training Grounds.
  /// [allowStack] lets several units share a tile — only the continuous
  /// free-move simulator, which owns sub-tile positions, may ask for this.
  Troop? spawn(TroopType type, String ownerId, int r, int c,
      {bool prepaid = false, bool allowStack = false}) {
    if ((!allowStack && troopAt(r, c) != null) || !base.passable(r, c)) {
      return null;
    }
    if (!base.isRing(r, c)) return null;
    if (!prepaid) {
      final cost = kTroopSpecs[type]!.cost.toDouble();
      if (!_payAttacker(ownerId, cost)) return null;
    }
    final t = Troop(
        id: 'a${_troopSeq++}',
        ownerId: ownerId,
        side: attacker,
        type: type,
        r: r,
        c: c);
    troops.add(t);
    troopsSent++;
    _reveal(r, c, radius: t.spec.revealRadius);
    _stepEffects(t);
    log.add(AttackEvent('${t.spec.emoji} ${t.spec.name} deployed', at: Cell(r, c)));
    return t;
  }

  /// Budget-free BFS route to (tr,tc) — real paths around rivers and walls.
  /// Friendly troops are IGNORED while planning: a crowd is temporary, and
  /// routing around it made whole convoys oscillate. Troops only care about a
  /// friend when it stands on their very next step (they wait a beat).
  ///
  /// [throughWalls]: plan AS IF blocking structures were passable (terrain
  /// still rules) — the CoC breach plan. The route then includes structure
  /// cells; the first one is what the troop should smash.
  List<List<int>> routeTo(Troop t, int tr, int tc, {bool throughWalls = false}) {
    if (!base.inBounds(tr, tc)) return const [];
    bool open(int r, int c) {
      if (!base.inBounds(r, c)) return false;
      if (!TerrainData.passable(base.grid[r][c].terrain)) return false;
      if (throughWalls) return true; // structures are breachable
      final s = base.grid[r][c].structure;
      return s == null || !s.alive || !s.spec.blocks;
    }

    final prev = <int, List<int>>{};
    final seen = <int>{_key(t.r, t.c)};
    final q = Queue<List<int>>()..add([t.r, t.c]);
    var found = false;
    // each troop breaks path ties its OWN way — columns fan out instead of
    // marching single file down the one canonical shortest path
    final rot = t.id.hashCode & 3;
    while (q.isNotEmpty && !found) {
      final cur = q.removeFirst();
      for (var di = 0; di < 4; di++) {
        final d = _orth[(di + rot) & 3];
        final nr = cur[0] + d[0], nc = cur[1] + d[1];
        if (!open(nr, nc)) continue;
        if (!_stepAllowed(cur[0], cur[1], nr, nc)) continue;
        final k = _key(nr, nc);
        if (seen.contains(k)) continue;
        seen.add(k);
        prev[k] = cur;
        if (nr == tr && nc == tc) {
          found = true;
          break;
        }
        q.add([nr, nc]);
      }
    }
    if (!found) return const [];
    final path = <List<int>>[];
    var k = [tr, tc];
    while (!(k[0] == t.r && k[1] == t.c)) {
      path.insert(0, k);
      k = prev[_key(k[0], k[1])]!;
    }
    return path;
  }

  /// Effective spotting range vs [t]: forests AND fogger smoke conceal troops
  /// from a distance — unless a WATCHTOWER stands within 3 of them.
  int _spotRange(int range, Troop t) {
    final concealed = (base.at(t.r, t.c)!.terrain == Terrain.forest ||
            smoke.containsKey(_key(t.r, t.c))) &&
        !_watchtowerNear(t.r, t.c);
    if (concealed) {
      return range < TerrainData.forestSpotRange
          ? range
          : TerrainData.forestSpotRange;
    }
    return range;
  }

  /// A fogger BLEEDS smoke — it doesn't light one on arrival. The first wound
  /// it takes bursts the cloud, and if something one-shots it the corpse lets
  /// a last, brief puff go. Veterans carry more pitch, so the cloud lingers.
  bool dropSmoke(Troop t, {bool dying = false}) {
    if (t.type != TroopType.fogger || t.smokeUsed) return false;
    if (!dying && !t.alive) return false;
    t.smokeUsed = true;
    // a dying burst is a puff; a wounded fogger lays a proper screen
    final life = dying ? 3 + t.level : 6 + t.level * 2;
    final spread = dying ? 2 : 5; // squared radius
    for (var dr = -2; dr <= 2; dr++) {
      for (var dc = -2; dc <= 2; dc++) {
        if (dr * dr + dc * dc > spread) continue;
        final nr = t.r + dr, nc = t.c + dc;
        if (!base.inBounds(nr, nc)) continue;
        final k = _key(nr, nc);
        smoke[k] = math.max(smoke[k] ?? 0, life);
      }
    }
    log.add(AttackEvent(
        dying ? '🌫️ The fogger bursts as it falls' : '🌫️ Smoke blooms',
        at: Cell(t.r, t.c)));
    _fx(FxEvent(FxKind.trap, Cell(t.r, t.c), bySide: t.side));
    return true;
  }

  /// Every damage path in the engine funnels through [_cull], so this is the
  /// one place that can catch "a fogger just got hurt" no matter what hurt it.
  void _foggersReact() {
    for (final t in troops) {
      if (t.type != TroopType.fogger || t.smokeUsed) continue;
      if (!t.alive) {
        dropSmoke(t, dying: true);
      } else if (t.hp < t.maxHp) {
        dropSmoke(t);
      }
    }
  }

  void _tickSmoke() {
    final next = <int, int>{};
    smoke.forEach((k, v) {
      if (v > 1) next[k] = v - 1;
    });
    smoke
      ..clear()
      ..addAll(next);
  }

  /// Garrison discipline: defenders DON'T climb their own walls anymore —
  /// they march through the GATE like proper soldiers. (Non-blocking pieces
  /// — wire, mines, tents — they walk over freely; it's their yard.)
  bool _garrisonPassable(int r, int c) {
    if (!base.inBounds(r, c)) return false;
    if (!TerrainData.passable(base.grid[r][c].terrain)) return false;
    final s = base.grid[r][c].structure;
    if (s != null && s.alive && s.spec.blocks && s.type != DefType.gate) {
      return false;
    }
    return true;
  }

  /// Fog frontier: unrevealed cells adjacent to revealed passable ground — the
  /// places a scout would push toward.
  List<Cell> fogFrontier() {
    final out = <Cell>[];
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        if (visible(r, c)) continue;
        // TERRAIN passability only — a wall hiding in the fog is still a
        // frontier (the breach system smashes it). Filtering walls out here
        // made the LAST wall-sealed pocket invisible: no frontier, no
        // objective, and the whole army froze mid-raid.
        if (!TerrainData.passable(base.grid[r][c].terrain)) continue;
        var touchesRevealed = false;
        for (final d in _orth) {
          final nr = r + d[0], nc = c + d[1];
          if (base.inBounds(nr, nc) && visible(nr, nc)) {
            touchesRevealed = true;
            break;
          }
        }
        if (touchesRevealed) out.add(Cell(r, c));
      }
    }
    return out;
  }

  // ── movement (Dijkstra over move cost) ──────────────────────────────────────
  static const List<List<int>> _orth = [
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1]
  ];

  /// Tiles [t] can reach this activation, with the ⚡ each destination costs
  /// (1/step + 2 per uncaptured tile). Destinations the OWNER can't afford are
  /// excluded — no more "why won't my brute move" mysteries.
  Map<int, ReachInfo> reachable(Troop t) {
    final dist = <int, int>{_key(t.r, t.c): 0};
    final energy = <int, double>{_key(t.r, t.c): 0};
    final pq = SplayTreeSet<List<int>>((a, b) {
      final d = a[0].compareTo(b[0]);
      return d != 0 ? d : (a[1] * base.cols + a[2]).compareTo(b[1] * base.cols + b[2]);
    });
    pq.add([0, t.r, t.c]);
    while (pq.isNotEmpty) {
      final cur = pq.first;
      pq.remove(cur);
      final cd = cur[0], cr = cur[1], cc = cur[2];
      if (cd > (dist[_key(cr, cc)] ?? 1 << 30)) continue;
      for (final d in _orth) {
        final nr = cr + d[0], nc = cc + d[1];
        if (!base.passable(nr, nc)) continue;
        if (!_stepAllowed(cr, cc, nr, nc)) continue;
        if (troopAt(nr, nc) != null) continue;
        var step = base.moveCost(nr, nc, mover: t.type);
        if (base.at(nr, nc)!.owner != attacker) step += 1;
        final nd = cd + step;
        if (nd > t.moveBudget) continue;
        final k = _key(nr, nc);
        if (nd < (dist[k] ?? 1 << 30)) {
          dist[k] = nd;
          energy[k] = (energy[_key(cr, cc)] ?? 0) +
              WarCosts.move +
              (base.at(nr, nc)!.owner != attacker ? WarCosts.capture : 0);
          pq.add([nd, nr, nc]);
        }
      }
    }
    dist.remove(_key(t.r, t.c));
    final budget = freeActions ? double.infinity : pools.of(t.ownerId);
    final out = <int, ReachInfo>{};
    dist.forEach((k, moveCost) {
      final e = freeActions ? 0.0 : (energy[k] ?? 0);
      if (e <= budget) out[k] = ReachInfo(moveCost, e);
    });
    return out;
  }

  List<List<int>> pathTo(Troop t, int tr, int tc) {
    final prev = <int, List<int>>{};
    final dist = <int, int>{_key(t.r, t.c): 0};
    final pq = SplayTreeSet<List<int>>((a, b) {
      final d = a[0].compareTo(b[0]);
      return d != 0 ? d : (a[1] * base.cols + a[2]).compareTo(b[1] * base.cols + b[2]);
    });
    pq.add([0, t.r, t.c]);
    while (pq.isNotEmpty) {
      final cur = pq.first;
      pq.remove(cur);
      final cd = cur[0], cr = cur[1], cc = cur[2];
      if (cr == tr && cc == tc) break;
      if (cd > (dist[_key(cr, cc)] ?? 1 << 30)) continue;
      for (final d in _orth) {
        final nr = cr + d[0], nc = cc + d[1];
        if (!base.passable(nr, nc)) continue;
        if (!_stepAllowed(cr, cc, nr, nc)) continue;
        if (troopAt(nr, nc) != null) continue;
        var step = base.moveCost(nr, nc, mover: t.type);
        if (base.at(nr, nc)!.owner != attacker) step += 1;
        final nd = cd + step;
        if (nd > t.moveBudget) continue;
        final k = _key(nr, nc);
        if (nd < (dist[k] ?? 1 << 30)) {
          dist[k] = nd;
          prev[k] = [cr, cc];
          pq.add([nd, nr, nc]);
        }
      }
    }
    if (!dist.containsKey(_key(tr, tc))) return const [];
    final path = <List<int>>[];
    var k = [tr, tc];
    while (!(k[0] == t.r && k[1] == t.c)) {
      path.insert(0, k);
      k = prev[_key(k[0], k[1])]!;
    }
    return path;
  }

  /// Walk [t] toward (tr,tc): capture ground, spring traps, eat tesla zaps.
  bool moveTroop(Troop t, int tr, int tc) {
    final path = pathTo(t, tr, tc);
    if (path.isEmpty) return false;
    for (final step in path) {
      if (!_payAction(t.ownerId, WarCosts.move)) break;
      final prevR = t.r, prevC = t.c;
      t.r = step[0];
      t.c = step[1];
      assert(TerrainData.passable(base.grid[t.r][t.c].terrain),
          'moveTroop put ${t.id} on impassable (${t.r},${t.c})');
      if (base.at(t.r, t.c)!.owner != attacker &&
          _payAction(t.ownerId, WarCosts.capture)) {
        base.at(t.r, t.c)!.owner = attacker;
      }
      _reveal(t.r, t.c, radius: t.spec.revealRadius);
      // a SCOUT peers one tile farther in the direction it is moving
      if (t.type == TroopType.runner) {
        final dr = (step[0] - prevR).sign, dc = (step[1] - prevC).sign;
        final ar = t.r + dr * (t.spec.revealRadius + 1);
        final ac = t.c + dc * (t.spec.revealRadius + 1);
        for (var k = -1; k <= 1; k++) {
          final rr = ar + (dr == 0 ? k : 0), cc = ac + (dc == 0 ? k : 0);
          if (base.inBounds(rr, cc)) revealed.add(_key(rr, cc));
        }
      }
      _stepEffects(t);
      if (t.alive) _teslaZap(t); // dynamic defenses fire on movement
      if (!t.alive) {
        troopsLost++;
        _fx(FxEvent(FxKind.death, Cell(t.r, t.c),
            bySide: defender, emoji: t.spec.emoji));
        break;
      }
    }
    troops.removeWhere((x) => !x.alive);
    t.hasMoved = true;
    return true;
  }

  /// Cross [t] into (r,c) — capture, reveal, traps and teslas fire exactly
  /// once, as they do for a normal step. Returns false if the crossing killed
  /// it. Used by the continuous free-move simulator, which owns its own
  /// pathing but still needs every discrete tile effect to land.
  bool stepInto(Troop t, int r, int c) {
    if (!base.inBounds(r, c)) return false;
    final prevR = t.r, prevC = t.c;
    t.r = r;
    t.c = c;
    if (base.at(r, c)!.owner != attacker &&
        _payAction(t.ownerId, WarCosts.capture)) {
      base.at(r, c)!.owner = attacker;
    }
    _reveal(r, c, radius: t.spec.revealRadius);
    if (t.type == TroopType.runner) {
      final dr = (r - prevR).sign, dc = (c - prevC).sign;
      final ar = r + dr * (t.spec.revealRadius + 1);
      final ac = c + dc * (t.spec.revealRadius + 1);
      for (var k = -1; k <= 1; k++) {
        final rr = ar + (dr == 0 ? k : 0), cc = ac + (dc == 0 ? k : 0);
        if (base.inBounds(rr, cc)) revealed.add(_key(rr, cc));
      }
    }
    _stepEffects(t);
    if (t.alive) _teslaZap(t);
    if (!t.alive) {
      troopsLost++;
      _fx(FxEvent(FxKind.death, Cell(t.r, t.c),
          bySide: defender, emoji: t.spec.emoji));
      _cull();
      return false;
    }
    _foggersReact(); // a mine or tesla on the way in can set one off
    return true;
  }

  void _stepEffects(Troop t) {
    final s = base.structAt(t.r, t.c);
    if (s == null || !s.alive) return;
    if (s.spec.chipOnEnter > 0 || s.type == DefType.pitchPot) {
      s.triggered = true;
      // War Elephants shrug barbed wire damage (and its slow via moveCost).
      final chip = (t.type == TroopType.elephant && s.type == DefType.barbedWire)
          ? 0
          : s.spec.chipOnEnter;
      if (chip > 0) t.hp -= chip;
      // Pitch Pot: tar slow across a small radius.
      if (s.type == DefType.pitchPot) {
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            final foe = troopAt(t.r + dr, t.c + dc);
            if (foe != null && foe.side == attacker && foe.alive) {
              foe.tarRounds = math.max(foe.tarRounds, 5);
            }
          }
        }
      }
      _reveal(t.r, t.c, radius: 1);
      _flash(t.r, t.c);
      _fx(FxEvent(FxKind.trap, Cell(t.r, t.c),
          amount: chip, bySide: defender, defType: s.type));
      log.add(AttackEvent(
          '${s.spec.emoji} ${s.spec.name} hit ${t.spec.name}'
          '${chip > 0 ? ' for $chip' : ''}'
          '${s.type == DefType.pitchPot ? ' — tar spreads' : ''}',
          at: Cell(t.r, t.c)));
      if (s.spec.oneShot) s.hp = 0;
    }
  }

  /// Max raiders a Tesla arcs across in one zap (damage pool is split).
  static const int teslaMaxTargets = 4;

  /// Jars-2.0-style dynamic defense: teslas strike the moment a troop moves
  /// within range — the whole arc chain fires (up to [teslaMaxTargets]).
  void _teslaZap(Troop t) {
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s == null || !s.alive || !s.spec.zapsMovers) continue;
        if (s.cooldown > 0) continue;
        final effRange =
            s.spec.range + (base.grid[r][c].terrain == Terrain.hill ? 1 : 0);
        final d = math.max((t.r - r).abs(), (t.c - c).abs());
        if (d > effRange) continue;
        if (!_pay(s.ownerId, WarCosts.defend)) continue;
        _teslaArc(s, r, c, effRange,
            moveTriggered: true, prefer: t);
        if (!t.alive) return;
      }
    }
  }

  /// Chain lightning: dump the Tesla's damage pool across the closest
  /// attackers in range (1 → full hit, 2 → half each, … up to 4).
  void _teslaArc(Structure s, int r, int c, int effRange,
      {bool moveTriggered = false, Troop? prefer}) {
    final hits = _attackersInRange(r, c, effRange,
        max: teslaMaxTargets,
        // a mover already touched the coil — fog can't mute the arc
        ignoreFog: moveTriggered,
        prefer: prefer);
    if (hits.isEmpty) return;
    s.triggered = true;
    s.cooldown = moveTriggered ? 1 : _reloadFor(s, r, c);
    s.aimAngle = math.atan2(
        (hits.first.r - r).toDouble(), (hits.first.c - c).toDouble());
    if (moveTriggered) _reveal(r, c, radius: 1);

    final n = hits.length;
    final pool = s.damage;
    var share = pool ~/ n;
    var rem = pool % n;
    var killed = 0;
    for (final target in hits) {
      var raw = share;
      if (rem > 0) {
        raw++;
        rem--;
      }
      final terr = TerrainData.defBonus(base.at(target.r, target.c)!.terrain);
      final dmg = (raw * (1 - terr)).round();
      if (dmg <= 0) continue;
      target.hp -= dmg;
      _flash(target.r, target.c);
      _fx(FxEvent(FxKind.zap, Cell(target.r, target.c),
          from: Cell(r, c), amount: dmg, bySide: defender, defType: s.type));
      if (!target.alive) {
        troopsLost++;
        killed++;
        _fx(FxEvent(FxKind.death, Cell(target.r, target.c),
            bySide: defender, emoji: target.spec.emoji));
      }
    }
    log.add(AttackEvent(
        n == 1
            ? '⚡ Tesla zapped ${hits.first.spec.name}'
            : '⚡ Tesla arced across $n ($pool pool)${killed > 0 ? ' · $killed fell' : ''}',
        at: Cell(r, c)));
  }

  /// Closest live attackers within Chebyshev [range], capped at [max].
  List<Troop> _attackersInRange(int r, int c, int range,
      {required int max, bool ignoreFog = false, Troop? prefer}) {
    final scored = <(int, Troop)>[];
    for (final t in troops) {
      if (!t.alive) continue;
      final d = math.max((t.r - r).abs(), (t.c - c).abs());
      if (d > range) continue;
      if (!ignoreFog && d > _spotRange(range, t)) continue;
      scored.add((d, t));
    }
    scored.sort((a, b) {
      // the troop that just stepped on the coil goes first in a move-zap
      if (prefer != null) {
        if (identical(a.$2, prefer)) return -1;
        if (identical(b.$2, prefer)) return 1;
      }
      final byDist = a.$1.compareTo(b.$1);
      if (byDist != 0) return byDist;
      return a.$2.hp.compareTo(b.$2.hp);
    });
    return [for (final e in scored.take(max)) e.$2];
  }

  // ── the positional multiplier (Jars 3.0 formula) ────────────────────────────
  double multiplierAt(int r, int c, WarSide side) {
    var friendlyTiles = 0, enemyTiles = 0;
    var friendlyUnits = 0.0, enemyUnits = 0.0;
    for (final d in _orth) {
      final nr = r + d[0], nc = c + d[1];
      if (!base.inBounds(nr, nc)) continue;
      final owner = base.at(nr, nc)!.owner;
      final troop = troopAt(nr, nc);
      final st = base.structAt(nr, nc);
      final structAlive = st != null && st.alive;
      if (owner == side) {
        friendlyTiles++;
        if (troop != null && troop.side == side) friendlyUnits += 1;
        if (structAlive && base.side == side) friendlyUnits += st.isCastle ? 2 : 1;
      } else if (owner == other(side)) {
        enemyTiles++;
        if (troop != null && troop.side != side) enemyUnits += 1;
        if (structAlive && base.side != side) enemyUnits += st.isCastle ? 2 : 1;
      }
    }
    final self = base.structAt(r, c);
    var buff = 0.0;
    if (self != null && self.alive && base.side == side) {
      buff = self.isCastle ? 0.3 : self.effectiveDefBuff;
    }
    // Citadel Core / wall L4+ radiate to adjacent friendlies.
    for (final d in _orth) {
      final ns = base.structAt(r + d[0], c + d[1]);
      if (ns != null &&
          ns.alive &&
          base.side == side &&
          ns.effectiveDefBuff > 0) {
        buff += ns.effectiveDefBuff * 0.5;
      }
    }
    final m = 1 +
        friendlyTiles * 0.1 +
        friendlyUnits * 0.3 -
        (enemyTiles > friendlyTiles ? enemyUnits * 0.3 : 0) +
        buff;
    return m.clamp(0.2, 4.0);
  }

  // ── attacking (structures AND enemy troops) ─────────────────────────────────
  List<Cell> attackTargets(Troop t) {
    final out = <Cell>[];
    // Archers / javelins / generals loose from 2; everyone else is melee
    final reach = (t.type == TroopType.archer ||
            t.type == TroopType.javelin ||
            t.type == TroopType.general)
        ? 2
        : 1;
    for (var dr = -reach; dr <= reach; dr++) {
      for (var dc = -reach; dc <= reach; dc++) {
        if (dr == 0 && dc == 0) continue;
        if (reach == 1 && dr.abs() + dc.abs() != 1) continue; // melee = orth
        final nr = t.r + dr, nc = t.c + dc;
        if (!base.inBounds(nr, nc)) continue;
        if (!visible(nr, nc) && reach > 1) continue; // no blind volleys
        final foe = troopAt(nr, nc);
        if (foe != null && foe.side != t.side) {
          out.add(Cell(nr, nc));
          continue;
        }
        final s = base.structAt(nr, nc);
        if (s != null && s.alive && !(s.spec.hidden && !s.triggered)) {
          out.add(Cell(nr, nc));
        }
      }
    }
    return out;
  }

  CombatPreview previewAttack(Troop t, int r, int c) {
    // a sapper's "attack" is its bomb: no counter — it won't be around for one
    if (t.type == TroopType.sapper) {
      final lvl = Xp.bonus(t.level);
      final sFoe = troopAt(r, c);
      if (sFoe != null && sFoe.side != t.side) {
        final dmg = (sapperSplash * lvl).round();
        return CombatPreview(1, dmg, 0, dmg >= sFoe.hp);
      }
      final s = base.structAt(r, c);
      final wallish =
          s != null && (s.type == DefType.wall || s.type == DefType.gate);
      final dmg = ((wallish ? sapperBomb : sapperBomb ~/ 4) * lvl).round();
      return CombatPreview(1, dmg, 0, s == null || dmg >= s.hp);
    }
    final foe = troopAt(r, c);
    final mult = multiplierAt(t.r, t.c, t.side);
    if (foe != null && foe.side != t.side) {
      final terr = TerrainData.defBonus(base.at(r, c)!.terrain);
      final dmg = (t.atk * mult * (1 - terr)).round();
      final kills = dmg >= foe.hp;
      var counter = 0;
      if (!kills) {
        final dMult = multiplierAt(r, c, foe.side);
        final aTerr = TerrainData.defBonus(base.at(t.r, t.c)!.terrain);
        counter = (foe.atk * dMult * (1 - aTerr)).round();
      }
      return CombatPreview(mult, dmg, counter, kills);
    }
    final s = base.structAt(r, c)!;
    final dmg = (t.atk * mult * t.spec.vsStructure).round();
    var counter = 0;
    final inTowerRange =
        (t.r - r).abs() <= s.spec.range && (t.c - c).abs() <= s.spec.range;
    if (s.spec.isShooter && dmg < s.hp && inTowerRange) {
      final terr = TerrainData.defBonus(base.at(t.r, t.c)!.terrain);
      counter = (s.damage * (1 - terr)).round();
    }
    return CombatPreview(mult, dmg, counter, dmg >= s.hp);
  }

  /// XP only for ATTACKER troops (defenders never level — no more unkillable
  /// guards), at half rate per damage so promotions are earned.
  void _grantXp(Troop t, double amount) {
    if (t.side != attacker) return;
    final before = t.level;
    t.gainXp(amount);
    if (t.level > before) {
      _fx(FxEvent(FxKind.levelup, Cell(t.r, t.c), bySide: t.side));
      log.add(AttackEvent('⭐ ${t.spec.name} reached L${t.level}', at: Cell(t.r, t.c)));
    }
  }

  /// One BOOM per sapper: full charge into a wall, quarter charge into
  /// anything else, splash to every adjacent structure — and the sapper dies.
  static const int sapperBomb = 170; // one-shots a wall (140 hp)
  static const int sapperSplash = 60;

  void _detonate(Troop t, int r, int c) {
    if (!_payAction(t.ownerId, WarCosts.attack)) return;
    final foe = troopAt(r, c);
    final s = base.structAt(r, c);
    final lvl = Xp.bonus(t.level);
    _fx(FxEvent(FxKind.trap, Cell(r, c),
        from: Cell(t.r, t.c), bySide: t.side, defType: DefType.landmine));
    if (foe != null && foe.side != t.side) {
      final dmg = (sapperSplash * lvl).round();
      foe.hp -= dmg;
      _grantXp(t, dmg * 0.5);
      _flash(foe.r, foe.c);
      _fx(FxEvent(FxKind.melee, Cell(foe.r, foe.c),
          amount: dmg, bySide: t.side));
      if (!foe.alive) {
        if (foe.side == attacker) {
          troopsLost++;
        } else {
          garrisonLost++;
        }
        _fx(FxEvent(FxKind.death, Cell(foe.r, foe.c),
            bySide: t.side, emoji: foe.spec.emoji));
      }
    } else if (s != null && s.alive) {
      final wallish = s.type == DefType.wall || s.type == DefType.gate;
      final dmg = ((wallish ? sapperBomb : sapperBomb ~/ 4) * lvl).round();
      s.hp -= dmg;
      s.triggered = true;
      _grantXp(t, dmg * 0.25);
      _flash(r, c);
      log.add(AttackEvent('🧨 → ${s.spec.emoji} $dmg dmg', at: Cell(r, c)));
      if (s.hp <= 0) {
        _grantXp(t, Xp.perStructure.toDouble());
        _fx(FxEvent(FxKind.death, Cell(r, c), bySide: t.side, defType: s.type));
        log.add(
            AttackEvent('${s.spec.emoji} ${s.spec.name} destroyed', at: Cell(r, c)));
      }
    }
    // the blast tears at every neighbouring structure
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final ns = base.structAt(r + dr, c + dc);
        if (ns == null || !ns.alive) continue;
        ns.hp -= (sapperSplash * lvl).round();
        ns.triggered = true;
        _flash(r + dr, c + dc);
        if (ns.hp <= 0) {
          _fx(FxEvent(FxKind.death, Cell(r + dr, c + dc),
              bySide: t.side, defType: ns.type));
        }
      }
    }
    // the charge takes the sapper with it
    t.hp = 0;
    troopsLost++;
    log.add(AttackEvent('🧨 Sapper detonates!', at: Cell(r, c)));
    _fx(FxEvent(FxKind.death, Cell(t.r, t.c),
        bySide: defender, emoji: t.spec.emoji));
    t.done = true;
    _cull();
  }

  /// A healer mends an ally: +14 hp (capped at their max), green light.
  void healTroop(Troop healer, Troop target) {
    final amount = math.min(14, target.maxHp - target.hp);
    if (amount <= 0) return;
    target.hp += amount;
    _fx(FxEvent(FxKind.heal, Cell(target.r, target.c),
        from: Cell(healer.r, healer.c), bySide: healer.side));
    log.add(AttackEvent(
        '💚 ${healer.spec.name} mends ${target.spec.name} +$amount',
        at: Cell(target.r, target.c)));
  }

  /// Strike whatever is at (r,c): an enemy troop or a structure.
  void attackCell(Troop t, int r, int c) {
    // sappers don't fence — they EXPLODE (CoC wall breaker)
    if (t.type == TroopType.sapper) {
      _detonate(t, r, c);
      return;
    }
    final foe = troopAt(r, c);
    if (foe != null && foe.side != t.side) {
      if (!_payAction(t.ownerId, WarCosts.attack)) return;
      _strike(t, foe, counterCost: WarCosts.defend);
      t.done = true;
      _cull();
      return;
    }
    final s = base.structAt(r, c);
    if (s == null || !s.alive) return;
    if (!_payAction(t.ownerId, WarCosts.attack)) return;
    final pv = previewAttack(t, r, c);
    s.hp -= pv.dmg;
    s.triggered = true;
    _grantXp(t, pv.dmg * 0.25); // chipping buildings is slow XP
    _flash(r, c);
    final ranged = t.type == TroopType.archer ||
        t.type == TroopType.javelin ||
        t.type == TroopType.general;
    _fx(FxEvent(ranged ? FxKind.shot : FxKind.melee, Cell(r, c),
        from: Cell(t.r, t.c), amount: pv.dmg, bySide: t.side));
    log.add(AttackEvent('${t.spec.emoji} → ${s.spec.emoji} ${pv.dmg} dmg', at: Cell(r, c)));
    // Spiked walls chip melee attackers.
    if (!ranged && s.meleeChip > 0 && s.hp > 0) {
      t.hp -= s.meleeChip;
      _flash(t.r, t.c);
    }
    if (s.hp <= 0) {
      _grantXp(t, Xp.perStructure.toDouble());
      _fx(FxEvent(FxKind.death, Cell(r, c), bySide: t.side, defType: s.type));
      log.add(AttackEvent('${s.spec.emoji} ${s.spec.name} destroyed', at: Cell(r, c)));
    } else if (pv.counter > 0 && t.alive) {
      t.hp -= pv.counter;
      _flash(t.r, t.c);
      _fx(FxEvent(FxKind.shot, Cell(t.r, t.c),
          from: Cell(r, c), amount: pv.counter, bySide: defender, defType: s.type));
    }
    if (!t.alive) {
      troopsLost++;
      _fx(FxEvent(FxKind.death, Cell(t.r, t.c),
          bySide: defender, emoji: t.spec.emoji));
    }
    t.done = true;
    _cull();
  }

  /// Troop-vs-troop exchange. The defender's counter costs its owner [counterCost].
  void _strike(Troop a, Troop b, {required double counterCost}) {
    final terr = TerrainData.defBonus(base.at(b.r, b.c)!.terrain);
    var raw = a.atk * multiplierAt(a.r, a.c, a.side) * (1 - terr);
    // Javelins spear garrison defenders and Generals.
    if (a.type == TroopType.javelin &&
        (b.type == TroopType.general || b.homeR != null)) {
      raw *= 1.45;
    }
    final dmg = raw.round();
    b.hp -= dmg;
    _grantXp(a, dmg * 0.5);
    _flash(b.r, b.c);
    _fx(FxEvent(a.type == TroopType.archer ? FxKind.shot : FxKind.melee,
        Cell(b.r, b.c),
        from: Cell(a.r, a.c), amount: dmg, bySide: a.side));
    log.add(AttackEvent('${a.spec.emoji} → ${b.spec.emoji} $dmg dmg', at: Cell(b.r, b.c)));
    if (!b.alive) {
      _grantXp(a, Xp.perKill.toDouble());
      if (b.side == attacker) {
        troopsLost++;
      } else {
        garrisonLost++;
      }
      _fx(FxEvent(FxKind.death, Cell(b.r, b.c),
          bySide: a.side, emoji: b.spec.emoji));
      log.add(AttackEvent('${b.spec.emoji} ${b.spec.name} fell', at: Cell(b.r, b.c)));
      return;
    }
    // survivor hits back — defenders counter for free (autonomous defense);
    // an ATTACKER's counter still costs unless the raid runs free actions.
    // Counters are MELEE: they only land when the two stand adjacent.
    final adjacent = (a.r - b.r).abs() <= 1 && (a.c - b.c).abs() <= 1;
    final counterFree = b.side == defender || freeActions;
    if (adjacent && (counterFree || _pay(b.ownerId, counterCost))) {
      final aTerr = TerrainData.defBonus(base.at(a.r, a.c)!.terrain);
      final counter = (b.atk * multiplierAt(b.r, b.c, b.side) * (1 - aTerr)).round();
      a.hp -= counter;
      _flash(a.r, a.c);
      _fx(FxEvent(FxKind.melee, Cell(a.r, a.c),
          from: Cell(b.r, b.c), amount: counter, bySide: b.side));
      if (!a.alive) {
        if (a.side == attacker) {
          troopsLost++;
        } else {
          garrisonLost++;
        }
        _fx(FxEvent(FxKind.death, Cell(a.r, a.c),
            bySide: b.side, emoji: a.spec.emoji));
      }
    }
  }

  // ── the defense acts (towers volley + garrison hunts) ───────────────────────
  void defendersReact() {
    _tickSmoke();
    // Tar fades each beat (slow only — no damage).
    for (final t in [...troops, ...garrison]) {
      if (t.tarRounds > 0) t.tarRounds--;
    }
    // clinging pitch COOKS: 3/beat while it lasts (the SLOW lives in the
    // troops' own movement accumulator)
    for (final t in troops.toList()) {
      if (!t.alive || t.burnRounds <= 0) continue;
      t.burnRounds--;
      t.hp -= 3;
      _flash(t.r, t.c);
      _fx(FxEvent(FxKind.trap, Cell(t.r, t.c),
          amount: 3, bySide: defender, defType: DefType.pitchThrower));
      if (!t.alive) {
        troopsLost++;
        _fx(FxEvent(FxKind.death, Cell(t.r, t.c),
            bySide: defender, emoji: t.spec.emoji));
      }
    }
    // towers
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s == null || !s.alive || !s.spec.isShooter) continue;
        if (s.cooldown > 0) {
          s.cooldown--;
          continue;
        }
        // PITCH THROWER: boiling pitch on EVERYONE beside it — no targeting
        if (s.type == DefType.pitchThrower) {
          _pitchBurn(s, r, c);
          continue;
        }
        // high ground: a tower on a HILL sees one tile farther
        final effRange =
            s.spec.range + (base.grid[r][c].terrain == Terrain.hill ? 1 : 0);
        // TESLA: chain arc — dump its damage pool across up to 4 raiders
        if (s.type == DefType.tesla) {
          _teslaArc(s, r, c, effRange);
          continue;
        }
        final target = _nearestAttackerInRange(r, c, effRange,
            minRange: s.spec.minRange,
            // only CANNONS fire flat — walls block them. Archers loose from
            // height, mortars and ballistae LOB over everything.
            flatShot: s.type == DefType.cannon);
        if (target == null) {
          // a mortar that KNOWS raiders lurk in the trees sometimes lobs a
          // shell at the noise — slow to reload, wide of the mark
          if (s.type == DefType.mortar) _blindMortar(s, r, c, effRange);
          continue;
        }
        // defenses are AUTONOMOUS: a tower never goes silent because its
        // owner's wallet ran dry mid-war (economy gates OFFENSE, not defense)
        s.triggered = true;
        s.cooldown = _reloadFor(s, r, c);
        // swing the barrel onto the target (the painter reads this)
        s.aimAngle =
            math.atan2((target.r - r).toDouble(), (target.c - c).toDouble());
        if (s.type == DefType.mortar) {
          _mortarStrike(s, r, c, target);
          continue;
        }
        final terr = TerrainData.defBonus(base.at(target.r, target.c)!.terrain);
        final dmg = (s.damage * (1 - terr)).round();
        target.hp -= dmg;
        _flash(target.r, target.c);
        _fx(FxEvent(FxKind.shot, Cell(target.r, target.c),
            from: Cell(r, c), amount: dmg, bySide: defender, defType: s.type));
        log.add(AttackEvent('${s.spec.emoji} fires $dmg at ${target.spec.name}',
            at: Cell(target.r, target.c)));
        if (!target.alive) {
          troopsLost++;
          _fx(FxEvent(FxKind.death, Cell(target.r, target.c),
              bySide: defender, emoji: target.spec.emoji));
          log.add(AttackEvent('${target.spec.emoji} ${target.spec.name} fell',
              at: Cell(target.r, target.c)));
        }
      }
    }
    _cull();
    // garrison: patrol a fixed radius around the post — chase intruders inside
    // it, and MARCH HOME when there's nothing to fight (no spawn camping).
    // Defenders move FREELY over their own structures (they climb their walls).
    for (final gTroop in garrison.where((x) => x.alive).toList()) {
      final homeR = gTroop.homeR ?? gTroop.r;
      final homeC = gTroop.homeC ?? gTroop.c;
      // upgraded posts patrol farther; sharp clans keep better watch
      final post = base.structAt(homeR, homeC);
      final leash = garrisonLeash +
          ((post?.type == DefType.guardPost ? post!.level : 1) - 1) * 2 +
          (defenderIq >= 0.7 ? 1 : 0) +
          (_watchtowerNear(homeR, homeC) ? 2 : 0);
      // intruders inside the patrol zone count — and ANYONE within 2 of the
      // guard itself is engaged no matter what the leash math says
      Troop? target;
      var bestD = 1 << 30;
      for (final t in troops) {
        if (!t.alive) continue;
        final fromHome = (t.r - homeR).abs() + (t.c - homeC).abs();
        final d = (t.r - gTroop.r).abs() + (t.c - gTroop.c).abs();
        if (fromHome > leash && d > 2) continue;
        // the POST watches its whole zone even while its guard detours: spot
        // by whichever is closer — the guard's eyes or the sentry line.
        // (Without this, a guard walking AROUND a wall lost sight, marched
        // home, saw the intruder again, and oscillated forever.)
        final spotD = math.min(d, fromHome);
        if (spotD > _spotRange(leash, t) && d > 2) continue; // hidden in trees
        if (d < bestD) {
          bestD = d;
          target = t;
        }
      }
      if (target != null) {
        if (bestD == 1) {
          _strike(gTroop, target, counterCost: WarCosts.attack);
        } else {
          // chase THROUGH the compound — around walls, through the gates.
          // Greedy stepping stalled at corners; a real path never does.
          final step = _garrisonPathStep(
              gTroop, target.r, target.c, homeR, homeC, leash + 2);
          if (step != null &&
              !(step[0] == target.r && step[1] == target.c)) {
            gTroop.r = step[0];
            gTroop.c = step[1];
          }
        }
      } else if (gTroop.r != homeR || gTroop.c != homeC) {
        // nothing to fight → walk back to the post (free — it's their ground)
        final step =
            _garrisonPathStep(gTroop, homeR, homeC, homeR, homeC, 1 << 20);
        if (step != null && troopAt(step[0], step[1]) == null) {
          gTroop.r = step[0];
          gTroop.c = step[1];
        }
      }
    }
    _cull();
  }

  /// First step of a BFS route to (tr,tc) over garrison-passable ground,
  /// never straying more than [maxFromHome] from the post. The goal cell is
  /// terminal (it may hold an enemy, or the post the guard stands on).
  List<int>? _garrisonPathStep(
      Troop g, int tr, int tc, int homeR, int homeC, int maxFromHome) {
    if (g.r == tr && g.c == tc) return null;
    final startK = _key(g.r, g.c);
    final prev = <int, int>{};
    final seen = <int>{startK};
    final q = Queue<List<int>>()..add([g.r, g.c]);
    while (q.isNotEmpty && seen.length < 700) {
      final cur = q.removeFirst();
      for (final d in _orth) {
        final nr = cur[0] + d[0], nc = cur[1] + d[1];
        if (!base.inBounds(nr, nc)) continue;
        final k = _key(nr, nc);
        if (seen.contains(k)) continue;
        if ((nr - homeR).abs() + (nc - homeC).abs() > maxFromHome) continue;
        if (nr == tr && nc == tc) {
          var at = _key(cur[0], cur[1]);
          if (at == startK) return [tr, tc]; // it's right beside us
          while (prev[at] != startK) {
            at = prev[at]!;
          }
          return [at ~/ base.cols, at % base.cols];
        }
        if (!_garrisonPassable(nr, nc)) continue;
        if (!_stepAllowed(cur[0], cur[1], nr, nc)) continue;
        if (troopAt(nr, nc) != null) continue;
        seen.add(k);
        prev[k] = _key(cur[0], cur[1]);
        q.add([nr, nc]);
      }
    }
    return null;
  }

  /// Banner aura: a War Banner within 2 tiles makes the guns reload faster —
  /// ONE banner's worth, no matter how many fly. The colors don't stack.
  int _reloadFor(Structure s, int r, int c) {
    var reload = s.spec.fireEveryTicks - 1;
    var rallied = false;
    var citadel = false;
    for (var dr = -2; dr <= 2; dr++) {
      for (var dc = -2; dc <= 2; dc++) {
        final b = base.structAt(r + dr, c + dc);
        if (b == null || !b.alive) continue;
        if (b.type == DefType.banner) rallied = true;
        if (b.type == DefType.citadelCore) citadel = true;
      }
    }
    if (rallied) reload -= 1;
    if (citadel) reload -= 1;
    return reload < 0 ? 0 : reload;
  }

  /// Watchtower aura: eyes within [radius] of the given cell.
  bool _watchtowerNear(int r, int c, [int radius = 3]) {
    for (var dr = -radius; dr <= radius; dr++) {
      for (var dc = -radius; dc <= radius; dc++) {
        final s = base.structAt(r + dr, c + dc);
        if (s != null && s.alive && s.type == DefType.watchtower) return true;
      }
    }
    return false;
  }

  /// Boiling pitch: every attacker in the 8 cells around the thrower burns.
  void _pitchBurn(Structure s, int r, int c) {
    var hit = false;
    for (final t in troops.toList()) {
      if (!t.alive) continue;
      final d = (t.r - r).abs() > (t.c - c).abs()
          ? (t.r - r).abs()
          : (t.c - c).abs();
      if (d > 1) continue;
      final terr = TerrainData.defBonus(base.at(t.r, t.c)!.terrain);
      final dmg = (s.damage * (1 - terr)).round();
      t.hp -= dmg;
      t.burnRounds = 3; // the pitch CLINGS — it burns and SLOWS for beats
      hit = true;
      _flash(t.r, t.c);
      _fx(FxEvent(FxKind.trap, Cell(t.r, t.c),
          from: Cell(r, c), amount: dmg, bySide: defender, defType: s.type));
      if (!t.alive) {
        troopsLost++;
        _fx(FxEvent(FxKind.death, Cell(t.r, t.c),
            bySide: defender, emoji: t.spec.emoji));
      }
    }
    if (hit) {
      s.triggered = true;
      s.cooldown = _reloadFor(s, r, c);
      log.add(AttackEvent('🔥 boiling pitch pours', at: Cell(r, c)));
      _cull();
    }
  }

  void _cull() {
    _foggersReact();
    // the fallen leave tombstones — on the WORLD itself, forever (base.graves
    // persists across raids and saves); the raid copy feeds the replay frames
    for (final t in [...troops, ...garrison]) {
      if (t.alive) continue;
      final used = {
        for (final g in base.graves)
          if (g[0] == t.r && g[1] == t.c) g[2]
      };
      var slot = 0;
      while (used.contains(slot) && slot < 3) {
        slot++;
      }
      final grave = [t.r, t.c, slot];
      if (base.graves.length < 250) base.graves.add(grave);
      if (graves.length < 120) graves.add(grave);
    }
    troops.removeWhere((t) => !t.alive);
    garrison.removeWhere((t) => !t.alive);
  }

  /// Blind bombardment: pick a concealed raider in range, roll the dice, and
  /// drop a shell NEAR them — poor accuracy, long reload. Deterministic (the
  /// volley counter seeds the roll), so replays and sims agree.
  int _blindVolleys = 0;
  void _blindMortar(Structure s, int r, int c, int effRange) {
    final hidden = <Troop>[];
    for (final t in troops) {
      if (!t.alive) continue;
      final d = math.max((t.r - r).abs(), (t.c - c).abs());
      if (d < s.spec.minRange || d > effRange) continue;
      if (base.at(t.r, t.c)!.terrain == Terrain.forest &&
          !_watchtowerNear(t.r, t.c)) {
        hidden.add(t);
      }
    }
    if (hidden.isEmpty) return;
    _blindVolleys++;
    final rng = SeededRng(
        seedFromParts([r * base.cols + c, _blindVolleys, 'blindfire']));
    if (rng.unit() > 0.2) return; // it usually holds its fire
    final mark = hidden[rng.intRange(0, hidden.length)];
    final ir = (mark.r + rng.intRange(-2, 3)).clamp(0, base.rows - 1);
    final ic = (mark.c + rng.intRange(-2, 3)).clamp(0, base.cols - 1);
    s.triggered = true;
    s.cooldown = _reloadFor(s, r, c) + 2; // blind volleys come SLOW
    s.aimAngle = math.atan2((ir - r).toDouble(), (ic - c).toDouble());
    log.add(AttackEvent('💣 fires BLIND into the trees', at: Cell(ir, ic)));
    _shell(s, r, c, ir, ic);
  }

  /// Mortar shell: splash damage across the impact area (center + neighbours).
  void _mortarStrike(Structure s, int r, int c, Troop target) =>
      _shell(s, r, c, target.r, target.c);

  /// Euclidean splash radius in tiles. ~1.5 covers the full 8-neighbour ring
  /// (diagonal ≈ 1.41); L3+ shells reach past 2 tiles.
  static double mortarSplashRadius(int level) => level >= 3 ? 2.2 : 1.5;

  void _shell(Structure s, int r, int c, int impactR, int impactC) {
    _fx(FxEvent(FxKind.shot, Cell(impactR, impactC),
        from: Cell(r, c), bySide: defender, defType: s.type));
    final splashR = mortarSplashRadius(s.level);
    final scorched = splashR.ceil();
    // the shell TEARS the ground — repeated strikes scar it deeper, and a
    // forest hit is FLATTENED
    for (var dr = -scorched; dr <= scorched; dr++) {
      for (var dc = -scorched; dc <= scorched; dc++) {
        final rr = impactR + dr, cc = impactC + dc;
        if (!base.inBounds(rr, cc)) continue;
        final dist = math.sqrt(dr * dr + dc * dc);
        if (dist > splashR) continue;
        final k = rr * base.cols + cc;
        base.scorch[k] =
            (base.scorch[k] ?? 0) + (dr == 0 && dc == 0 ? 2 : 1);
      }
    }
    if (base.grid[impactR][impactC].terrain == Terrain.forest) {
      base.grid[impactR][impactC].terrain = Terrain.plains;
      base.cleared.add(impactR * base.cols + impactC);
    }
    var hits = 0;
    for (final t in troops.toList()) {
      if (!t.alive) continue;
      final dr = (t.r - impactR).abs();
      final dc = (t.c - impactC).abs();
      final dist = math.sqrt(dr * dr + dc * dc);
      if (dist > splashR) continue;
      final terr = TerrainData.defBonus(base.at(t.r, t.c)!.terrain);
      // Falloff by distance: full at center, ~2/3 in the inner ring, ~1/3 out.
      final falloff = dist < 0.01
          ? 1.0
          : dist <= 1.2
              ? 0.65
              : 0.3;
      final baseDmg = (s.damage * falloff).round().clamp(1, s.damage);
      final dmg = (baseDmg * (1 - terr)).round();
      t.hp -= dmg;
      hits++;
      _flash(t.r, t.c);
      _fx(FxEvent(dist < 0.01 ? FxKind.trap : FxKind.melee, Cell(t.r, t.c),
          amount: dmg, bySide: defender, defType: s.type));
      if (!t.alive) {
        troopsLost++;
        _fx(FxEvent(FxKind.death, Cell(t.r, t.c),
            bySide: defender, emoji: t.spec.emoji));
      }
    }
    log.add(AttackEvent('💣 Mortar shell bursts — $hits hit',
        at: Cell(impactR, impactC)));
    _cull();
  }

  /// Flat-trajectory line of sight: any alive BLOCKING structure between the
  /// shooter and the target stops the shot (endpoints excluded).
  bool _hasLineOfSight(int r0, int c0, int r1, int c1) {
    var r = r0, c = c0;
    final dr = (r1 - r0).abs(), dc = (c1 - c0).abs();
    final sr = r0 < r1 ? 1 : -1, sc = c0 < c1 ? 1 : -1;
    var err = dc - dr;
    while (!(r == r1 && c == c1)) {
      final e2 = 2 * err;
      if (e2 > -dr) {
        err -= dr;
        c += sc;
      }
      if (e2 < dc) {
        err += dc;
        r += sr;
      }
      if (r == r1 && c == c1) break;
      final s = base.structAt(r, c);
      if (s != null && s.alive && s.spec.blocks) return false;
    }
    return true;
  }

  Troop? _nearestAttackerInRange(int r, int c, int range,
      {int minRange = 0, bool flatShot = false}) {
    Troop? best;
    var bestD = 1 << 30;
    final focusFire = defenderIq >= 0.7; // masters finish the wounded first
    for (final t in troops) {
      if (!t.alive) continue;
      final d = (t.r - r).abs() > (t.c - c).abs() ? (t.r - r).abs() : (t.c - c).abs();
      if (d < minRange) continue; // artillery blind spot
      if (d > range || d > _spotRange(range, t)) continue;
      if (flatShot && !_hasLineOfSight(r, c, t.r, t.c)) continue;
      final score = focusFire ? t.hp : d;
      if (score < bestD) {
        bestD = score;
        best = t;
      }
    }
    return best;
  }

  // ── replay recording ────────────────────────────────────────────────────────
  void _flash(int r, int c) => _pendingFlashes.add(Cell(r, c));

  void snapshot([String caption = '']) {
    final structs = <RaidStruct>[];
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s == null) continue;
        if (s.spec.hidden && !s.triggered) continue; // keep secrets secret
        if (!s.alive) {
          // RUINS stay in the record — replays show the rubble of past raids
          structs.add(RaidStruct(r, c, s.type, 0));
          continue;
        }
        // frames record EVERYTHING alive — the viewer applies the watcher's
        // fog (clan raids honor intel; your own base plays back in full)
        structs.add(RaidStruct(r, c, s.type, (s.hp / s.maxHp).clamp(0.0, 1.0)));
      }
    }
    frames.add(RaidFrame(
      [
        for (final t in troops)
          if (t.alive)
            RaidSprite(t.id, t.spec.emoji, t.r, t.c, t.side, t.hp / t.maxHp),
        for (final t in garrison)
          if (t.alive)
            RaidSprite(t.id, t.spec.emoji, t.r, t.c, t.side, t.hp / t.maxHp),
      ],
      structs,
      List.of(_pendingFlashes),
      List.of(_frameFx),
      caption.isEmpty && log.isNotEmpty ? log.last.text : caption,
      // the WORLD's graves, not just this raid's — old wars stay buried here
      graves: [for (final g in base.graves) List.of(g)],
      scorch: [
        for (final e in base.scorch.entries) [e.key, e.value]
      ],
    ));
    _pendingFlashes.clear();
    _frameFx.clear();
  }

  // ── outcome ─────────────────────────────────────────────────────────────────
  bool get exhausted => troops.every((t) => !t.alive);
  double get gained => (base.destructionPercent - _startDestruction).clamp(0.0, 100.0);

  AttackResult finish() => AttackResult(
        attacker: attacker,
        attackerName: attackerName,
        destructionPercent: base.destructionPercent,
        gained: gained,
        troopsLost: troopsLost,
        troopsSent: troopsSent,
        resourcesSpent: resourcesSpent,
        castleRazed: base.allCastlesRazed,
        log: log,
        frames: frames,
        revealed: Set.of(revealed),
      );

  // ── persistence (in-progress raids survive restarts) ────────────────────────
  Map<String, dynamic> toJson() => {
        'attackerName': attackerName,
        'troops': [for (final t in troops) t.toJson()],
        'garrison': [for (final t in garrison) t.toJson()],
        'revealed': revealed.toList(),
        'lost': troopsLost,
        'sent': troopsSent,
        'gLost': garrisonLost,
        'spent': resourcesSpent,
        'seq': _troopSeq,
        'start': _startDestruction,
        'iq': defenderIq,
        'graves': [for (final g in graves) g],
      };

  factory AttackState.restore({
    required Base base,
    required WarSide attacker,
    required WarPools pools,
    required Map<String, dynamic> j,
  }) {
    final st = AttackState(
      base: base,
      attacker: attacker,
      attackerName: j['attackerName'] as String? ?? 'You',
      pools: pools,
      spawnGarrison: false,
      defenderIq: (j['iq'] as num?)?.toDouble() ?? 0.5,
    );
    st.troops.addAll([
      for (final tj in (j['troops'] as List? ?? const []))
        Troop.fromJson(tj as Map<String, dynamic>)
    ]);
    st.garrison.addAll([
      for (final tj in (j['garrison'] as List? ?? const []))
        Troop.fromJson(tj as Map<String, dynamic>)
    ]);
    st.revealed.addAll([
      for (final v in (j['revealed'] as List? ?? const [])) (v as num).toInt()
    ]);
    st.graves.addAll([
      for (final g in (j['graves'] as List? ?? const []))
        [for (final v in (g as List)) (v as num).toInt()]
    ]);
    st.troopsLost = (j['lost'] as num?)?.toInt() ?? 0;
    st.troopsSent = (j['sent'] as num?)?.toInt() ?? 0;
    st.garrisonLost = (j['gLost'] as num?)?.toInt() ?? 0;
    st.resourcesSpent = (j['spent'] as num?)?.toDouble() ?? 0;
    st._troopSeq = (j['seq'] as num?)?.toInt() ?? st.troops.length;
    st._startDestruction =
        (j['start'] as num?)?.toDouble() ?? st._startDestruction;
    return st;
  }
}
