import 'dart:math' as math;

import 'war_base.dart';
import 'war_engine.dart';
import 'war_troop.dart';
import 'war_types.dart';

/// Sub-tile position of a unit, in cell space (col, row) — fractional.
class UnitPos {
  final double col, row;
  const UnitPos(this.col, this.row);
}

/// FREE MOVE: a Clash-of-Clans style continuous battle over an [AttackState].
///
/// The classic engine is a turn grid — one troop per tile, one tile per beat.
/// This simulator keeps the SAME combat math (damage, towers, traps, teslas
/// all come from [AttackState]) but owns movement itself: every unit carries a
/// float (col,row), walks along its route at its own metres-per-second, is
/// pushed apart from its neighbours by soft separation, and stops the instant
/// something worth hitting falls inside its reach. Tiles stop being slots —
/// a dozen units can pile through the same gate at once.
///
/// It is DRILL ONLY. Wars, raids and replays still run [LiveBattle] so the
/// competitive ruleset never changes under anyone's feet.
class FreeMoveBattle {
  final AttackState st;

  /// Can the commander still send something? (drills always can)
  final bool Function() canDeploy;

  /// Fixed simulation step — movement integrates here, never on frame time,
  /// so a stuttering device fights exactly like a smooth one.
  static const double simStep = 1 / 30;

  /// The defence answers on the classic beat, so tower DPS, burn ticks and
  /// garrison patrols behave identically to a classic drill.
  static const double beatPeriod = 0.55;

  /// One swing per beat, same as a classic activation.
  static const double attackPeriod = 0.55;

  /// Clash rules: five minutes on the clock once the first boot lands.
  static const double maxDuration = 300;

  /// A troop's tiles-per-second at [Troop.moveBudget] — calibrated so the
  /// average pace matches the classic accumulator (moveBudget/6 per beat).
  static const double paceDivisor = 3.3;

  double elapsed = 0;
  bool over = false;

  double _acc = 0;
  double _beat = 0;
  int _emptyBeats = 0;
  int _thinkBudget = 0;

  final Map<String, _Unit> _units = {};
  final Map<String, UnitPos> _pos = {};
  final Map<int, List<_Unit>> _bins = {};
  final Map<int, Troop> _foeAt = {};
  final List<_Obj> _objs = [];
  final List<_Obj> _walls = [];
  bool _objsStale = true;

  FreeMoveBattle(this.st, {required this.canDeploy});

  double get destruction => st.base.destructionPercent;
  int get troopsAlive => st.troops.where((t) => t.alive).length;
  bool get clockRunning => st.troopsSent > 0 && !over;
  double get timeLeft => (maxDuration - elapsed).clamp(0.0, maxDuration);

  /// Where every live unit is RIGHT NOW, sub-tile. The board paints from this.
  Map<String, UnitPos> get positions => _pos;

  void extend() {
    over = false;
    elapsed = 0;
    _emptyBeats = 0;
  }

  void notifyDeploy() {
    _emptyBeats = 0;
  }

  /// Seat a freshly spawned troop exactly where the commander dropped it.
  void placeAt(Troop t, double col, double row) {
    final u = _Unit(t)
      ..x = col
      ..y = row;
    _units[t.id] = u;
    _pos[t.id] = UnitPos(col, row);
  }

  void tick(double dt) {
    if (over) return;
    if (st.troopsSent > 0) {
      elapsed += dt;
      if (elapsed >= maxDuration) {
        over = true;
        return;
      }
    }
    _acc += dt;
    // never spiral: a backgrounded tab resumes, it doesn't fast-forward
    if (_acc > simStep * 6) _acc = simStep * 6;
    while (_acc >= simStep && !over) {
      _acc -= simStep;
      _step(simStep);
    }
  }

  // ── one simulation step ─────────────────────────────────────────────────────
  void _step(double h) {
    _sync();
    _thinkBudget = 4; // cap the expensive route/objective scans per step
    _bin();
    for (final u in _units.values) {
      if (!u.t.alive) continue;
      _advance(u, h);
    }
    _beat += h;
    if (_beat >= beatPeriod) {
      _beat -= beatPeriod;
      st.defendersReact();
      st.snapshot();
      // drills are never replayed — keep a rolling window instead of five
      // minutes of full-grid frames
      if (st.frames.length > 8) {
        st.frames.removeRange(0, st.frames.length - 8);
      }
      _objsStale = true;
      _beatEnd();
    }
    _publish(h);
  }

  void _beatEnd() {
    if (st.base.allCastlesRazed) {
      over = true;
      return;
    }
    if (st.troops.every((t) => !t.alive)) {
      if (canDeploy()) {
        _emptyBeats = 0;
      } else if (++_emptyBeats >= 4) {
        over = true;
      }
    } else {
      _emptyBeats = 0;
    }
  }

  /// Adopt new troops, bury the fallen, glide the garrison.
  void _sync() {
    for (final t in st.troops) {
      if (!t.alive) continue;
      _units.putIfAbsent(t.id, () => _Unit(t));
    }
    _units.removeWhere((_, u) => !u.t.alive);
    final live = <String>{for (final u in _units.values) u.t.id};
    // the garrison still fights on the tile engine — it just glides between
    // tiles instead of teleporting, so it reads as one continuous army
    for (final g in st.garrison) {
      if (!g.alive) continue;
      live.add(g.id);
      final u = _units.putIfAbsent(g.id, () => _Unit(g)..garrison = true);
      u.garrison = true;
    }
    _pos.removeWhere((id, _) => !live.contains(id));
  }

  void _bin() {
    _bins.clear();
    _foeAt.clear();
    for (final u in _units.values) {
      if (!u.t.alive || u.garrison) continue;
      (_bins[_key(u.t.r, u.t.c)] ??= <_Unit>[]).add(u);
    }
    for (final g in st.garrison) {
      if (g.alive) _foeAt[_key(g.r, g.c)] = g;
    }
  }

  void _publish(double h) {
    for (final u in _units.values) {
      if (!u.t.alive) continue;
      if (u.garrison) {
        // defenders lerp onto their tile — same tile logic, smooth picture
        final tx = u.t.c.toDouble(), ty = u.t.r.toDouble();
        final dx = tx - u.x, dy = ty - u.y;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < 0.02 || d > 6) {
          u.x = tx;
          u.y = ty;
        } else {
          final s = math.min(d, 3.2 * h);
          u.x += dx / d * s;
          u.y += dy / d * s;
        }
      }
      _pos[u.t.id] = UnitPos(u.x, u.y);
    }
  }

  int _key(int r, int c) => r * st.base.cols + c;

  // ── a single unit's slice of the step ───────────────────────────────────────
  void _advance(_Unit u, double h) {
    if (u.garrison) return;
    final t = u.t;
    u.cd -= h;
    u.think -= h;
    u.noSwing -= h;

    if (t.type == TroopType.healer) {
      _healerStep(u, h);
      return;
    }

    // Something worth hitting inside reach? Then plant your feet and swing.
    final hit = u.noSwing > 0 ? null : _targetInReach(u);
    if (hit != null) {
      u.stuck = 0;
      if (u.cd <= 0) {
        u.cd = attackPeriod;
        final before = _victimHp(hit);
        st.attackCell(t, hit.r, hit.c);
        if (_victimHp(hit) < before) {
          u.idle = 0;
        } else {
          // The swing landed on nothing. Whatever the reason, a unit that
          // stands still hitting air is the worst bug in a battle sim — so
          // after a couple of wasted beats it stops swinging and walks.
          u.idle += attackPeriod;
          if (u.idle >= 2.0) {
            u.idle = 0;
            u.noSwing = 1.0;
            u.think = 0;
          }
        }
      }
      return;
    }

    _walk(u, h);
  }

  /// Hit points of whatever a swing at [c] would actually land on, or -1 when
  /// there is nothing there to hit.
  int _victimHp(Cell c) {
    final foe = _foeAt[_key(c.r, c.c)];
    if (foe != null && foe.alive) return foe.hp;
    final s = st.base.structAt(c.r, c.c);
    return s != null && s.alive ? s.hp : -1;
  }

  /// Distance from a unit to a target TILE — measured to the tile's square,
  /// not to its centre point.
  ///
  /// Centre-to-centre was a quiet disaster: a unit whose route ran out a
  /// fifth of a tile short of a wall sat 1.18 away from a target it could
  /// only hit at 1.15, so it stood there for the rest of the battle staring
  /// at a wall it was never allowed to touch. A tile is a square; touching
  /// any part of it counts.
  static double _edgeDist(double ex, double ey) {
    final ax = math.max(0.0, ex.abs() - 0.5);
    final ay = math.max(0.0, ey.abs() - 0.5);
    return math.sqrt(ax * ax + ay * ay);
  }

  /// Stop-and-fight test: the best target whose tile falls inside this unit's
  /// reach, measured from its true sub-tile position.
  Cell? _targetInReach(_Unit u) {
    final t = u.t;
    final ranged = t.type == TroopType.archer ||
        t.type == TroopType.javelin ||
        t.type == TroopType.general;
    // edge reach: 0.85 covers every neighbour, orthogonal or diagonal, with
    // room to spare for a unit that stopped a little short
    final reach = ranged ? 2.0 : 0.85;
    final ri = (reach + 1).ceil();
    final br = u.y.round(), bc = u.x.round();
    Cell? best;
    var bestScore = 0.0;
    for (var dr = -ri; dr <= ri; dr++) {
      for (var dc = -ri; dc <= ri; dc++) {
        final r = br + dr, c = bc + dc;
        if (!st.base.inBounds(r, c)) continue;
        final d = _edgeDist(c - u.x, r - u.y);
        if (d > reach) continue;
        if (ranged && !st.visible(r, c)) continue; // no blind volleys
        final foe = _foeAt[_key(r, c)];
        if (foe != null && foe.side != t.side) {
          // attackCell resolves the victim through troopAt, which hands back
          // ATTACKERS first. If one of ours is standing on this defender the
          // swing would land on nothing at all — and a unit that keeps
          // swinging at nothing never moves again. Skip it; it walks instead.
          if (identical(st.troopAt(r, c), foe)) {
            final s = 100.0 - d;
            if (s > bestScore) {
              bestScore = s;
              best = Cell(r, c);
            }
          }
          continue;
        }
        final st0 = st.base.structAt(r, c);
        if (st0 == null || !st0.alive) continue;
        var v = _structValue(st0, t);
        // a wall is furniture UNLESS it's the one sealing our road
        if (v <= 0 && u.blockKey == _key(r, c)) v = 140;
        if (v <= 0) continue;
        final s = v - d;
        if (s > bestScore) {
          bestScore = s;
          best = Cell(r, c);
        }
      }
    }
    return best;
  }

  double _structValue(Structure s, Troop t) {
    if (s.spec.hidden && !s.triggered) return 0;
    if (s.type == DefType.wall ||
        s.type == DefType.gate ||
        s.type == DefType.barbedWire) {
      if (t.type == TroopType.sapper && s.type != DefType.barbedWire) {
        return s.type == DefType.gate ? 160 : 150;
      }
      return 0;
    }
    if (t.type == TroopType.brute &&
        (s.spec.isShooter ||
            s.type == DefType.banner ||
            s.type == DefType.guardPost)) {
      return 160;
    }
    if (s.isCastle) return 120;
    if (s.type == DefType.storehouse) return 100;
    return s.spec.isShooter ? 90 : 60;
  }

  // ── continuous movement ─────────────────────────────────────────────────────
  void _walk(_Unit u, double h) {
    final t = u.t;
    if (u.route.isNotEmpty && u.leg >= u.route.length) {
      u.route = const []; // arrived — plan the next leg right away
      u.leg = 0;
      u.think = 0;
    }
    // Planning is rationed, so the trigger MUST be the timer and nothing else.
    // Keying it off "no route" instead let a unit that can never find one burn
    // a slot every single step, which starved the whole army — including fresh
    // arrivals, who always start routeless and would sit on the drop ring.
    if (u.think <= 0 && _thinkBudget > 0) {
      _thinkBudget--;
      _replan(u);
    }
    double tx, ty;
    if (u.route.isEmpty || u.leg >= u.route.length) {
      // No road left — but a wall marked for breaching IS a destination. A
      // route that stops one step short of it leaves the unit adrift, so it
      // walks itself onto the wall's face until the swing connects.
      final bk = u.blockKey;
      if (bk == null) return;
      tx = (bk % st.base.cols).toDouble();
      ty = (bk ~/ st.base.cols).toDouble();
    } else {
      var wp = u.route[u.leg];
      if ((wp[1] - u.x).abs() < 0.2 && (wp[0] - u.y).abs() < 0.2) {
        u.leg++;
        if (u.leg >= u.route.length) {
          u.think = 0;
          return;
        }
        wp = u.route[u.leg];
      }
      tx = wp[1].toDouble();
      ty = wp[0].toDouble();
    }
    final dx = tx - u.x, dy = ty - u.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-4) return;
    var ux = dx / d, uy = dy / d;

    // soft separation: the crowd spreads instead of forming a conga line
    final sep = _separation(u);
    ux += sep.$1;
    uy += sep.$2;
    final m = math.sqrt(ux * ux + uy * uy);
    if (m < 1e-4) return;
    ux /= m;
    uy /= m;

    var spd = t.moveBudget / paceDivisor;
    final terr = st.base.grid[t.r][t.c].terrain;
    if (terr == Terrain.forest || terr == Terrain.hill) spd *= 0.55;
    final dist = spd * h;

    // one axis at a time: a unit can never clip a wall's corner
    final movedX = _tryMove(u, u.x + ux * dist, u.y);
    if (!u.t.alive) return;
    final movedY = _tryMove(u, u.x, u.y + uy * dist);
    if (!u.t.alive) return;

    if (!movedX && !movedY) {
      u.stuck += h;
      if (u.stuck > 0.7) {
        u.stuck = 0;
        u.think = 0; // wedged — ask for a new road (or a wall to break)
      }
    } else {
      u.stuck = 0;
    }
  }

  /// Slide to (nx,ny) if the tile it lands on is walkable, firing every
  /// discrete tile effect on the way in. Returns false if the way is blocked.
  bool _tryMove(_Unit u, double nx, double ny) {
    final t = u.t;
    final nr = ny.round(), nc = nx.round();
    if (nr == t.r && nc == t.c) {
      u.x = nx;
      u.y = ny;
      return true;
    }
    if (!_walkable(nr, nc, t)) return false;
    u.x = nx;
    u.y = ny;
    if (!st.stepInto(t, nr, nc)) return true; // died crossing (mine/tesla)
    return true;
  }

  bool _walkable(int r, int c, Troop t) {
    if (!st.base.inBounds(r, c)) return false;
    if (!TerrainData.passable(st.base.grid[r][c].terrain)) return false;
    final s = st.base.grid[r][c].structure;
    if (s != null && s.alive && s.spec.blocks) return false;
    // raiders pile onto each other freely, but a DEFENDER is a body in the
    // way: you stop and fight it instead of walking through it
    final foe = _foeAt[_key(r, c)];
    if (foe != null && foe.alive && foe.side != t.side) return false;
    // the landing ring stays one-way, exactly as in the tile engine
    if (st.base.isRing(r, c) && !st.base.isRing(t.r, t.c)) return false;
    return true;
  }

  (double, double) _separation(_Unit u) {
    const radius = 0.62;
    var sx = 0.0, sy = 0.0;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        final bin = _bins[_key(u.t.r + dr, u.t.c + dc)];
        if (bin == null) continue;
        for (final o in bin) {
          if (identical(o, u)) continue;
          final ex = u.x - o.x, ey = u.y - o.y;
          final d2 = ex * ex + ey * ey;
          if (d2 >= radius * radius) continue;
          final d = math.sqrt(d2);
          if (d < 1e-3) {
            // perfectly stacked: nudge apart deterministically
            sx += ((u.t.id.hashCode & 1) == 0 ? 0.5 : -0.5);
            sy += ((u.t.id.hashCode & 2) == 0 ? 0.5 : -0.5);
            continue;
          }
          final push = (radius - d) / radius * 0.8;
          sx += ex / d * push;
          sy += ey / d * push;
        }
      }
    }
    return (sx, sy);
  }

  // ── objectives and routes ───────────────────────────────────────────────────
  void _replan(_Unit u) {
    final t = u.t;
    if (_objsStale) _rebuildObjectives();
    u.blockKey = null;
    u.leg = 0;

    final obj = _pickObjective(u);
    u.route = obj == null ? const [] : _routeToward(u, obj);
    if (u.route.isEmpty) {
      // Nothing reachable from here — a raider still never just stands there.
      // March for the middle of the yard; a new objective almost always opens
      // up on the way in.
      u.route = _routeToward(
          u, Cell(st.base.rows ~/ 2, st.base.cols ~/ 2),
          plain: true);
    }
    // A failed plan retries soon, but never every step — see _walk.
    u.think = u.route.isEmpty ? 0.6 : 1.4 + (t.id.hashCode & 7) * 0.08;
  }

  /// Best road to [obj]: around the walls if there is one, through them if the
  /// detour is absurd. Marks the wall to smash in [u.blockKey] when breaching.
  List<List<int>> _routeToward(_Unit u, Cell obj, {bool plain = false}) {
    final t = u.t;
    var route = st.routeTo(t, obj.r, obj.c);
    if (route.isEmpty) {
      for (final d in _orth) {
        final nr = obj.r + d[0], nc = obj.c + d[1];
        if (!st.base.passable(nr, nc)) continue;
        route = st.routeTo(t, nr, nc);
        if (route.isNotEmpty) break;
      }
    }
    // a plain march (the fallback to the middle) never smashes its way there
    if (plain) return route;
    // the long way around is a trap: if smashing straight through is far
    // shorter, breach instead — same call the classic engine makes
    if (route.length > 10) {
      final direct = st.routeTo(t, obj.r, obj.c, throughWalls: true);
      if (direct.isNotEmpty && direct.length + 8 < route.length) {
        route = const [];
      }
    }
    if (route.isNotEmpty) return route;

    final breach = st.routeTo(t, obj.r, obj.c, throughWalls: true);
    if (breach.isEmpty) return const [];
    // walk the breach line and mark the first wall on it as the target;
    // _targetInReach will swing at it the moment we're close enough
    final cut = <List<int>>[];
    for (final step in breach) {
      final s = st.base.structAt(step[0], step[1]);
      if (s != null && s.alive && s.spec.blocks) {
        u.blockKey = _key(step[0], step[1]);
        break;
      }
      cut.add(step);
    }
    return cut;
  }

  Cell? _pickObjective(_Unit u) {
    final t = u.t;
    // temperament: some units take the sure thing in front of them, so the
    // army fans out instead of all converging on one "best" building
    final greed = 1.0 + (t.id.hashCode & 3) * 0.45;
    Cell? best;
    var bestScore = -1e9;
    void consider(int r, int c, double value, double k) {
      final dist = ((r - t.r).abs() + (c - t.c).abs()).toDouble();
      final score = value - dist * k * greed;
      if (score > bestScore) {
        bestScore = score;
        best = Cell(r, c);
      }
    }

    final brute = t.type == TroopType.brute;
    // the cache is a beat old at worst, so rubble is skipped on the spot
    for (final o in _objs) {
      final s = st.base.structAt(o.r, o.c);
      if (s == null || !s.alive) continue;
      consider(o.r, o.c, brute && o.defensive ? 160 : o.value, 2.5);
    }
    if (t.type == TroopType.sapper) {
      for (final o in _walls) {
        final s = st.base.structAt(o.r, o.c);
        if (s == null || !s.alive) continue;
        consider(o.r, o.c, o.value, 2.5);
      }
    }
    for (final g in st.garrison) {
      if (g.alive) consider(g.r, g.c, 70, 2.5);
    }
    return best;
  }

  /// Drill bases are fully scouted, so objectives are a flat list of what is
  /// still standing — rebuilt once per beat instead of scanned per troop.
  void _rebuildObjectives() {
    _objsStale = false;
    _objs.clear();
    _walls.clear();
    for (var r = 0; r < st.base.rows; r++) {
      for (var c = 0; c < st.base.cols; c++) {
        final s = st.base.structAt(r, c);
        if (s == null || !s.alive) continue;
        if (s.spec.hidden && !s.triggered) continue;
        if (!st.visible(r, c)) continue;
        if (s.type == DefType.wall || s.type == DefType.gate) {
          _walls.add(_Obj(r, c, s.type == DefType.gate ? 160 : 150, false));
          continue;
        }
        if (s.type == DefType.barbedWire) continue;
        final defensive = s.spec.isShooter ||
            s.type == DefType.banner ||
            s.type == DefType.guardPost;
        final value = s.isCastle
            ? 120.0
            : (s.type == DefType.storehouse
                ? 100.0
                : (s.spec.isShooter ? 90.0 : 60.0));
        _objs.add(_Obj(r, c, value, defensive));
      }
    }
  }

  // ── healers ─────────────────────────────────────────────────────────────────
  void _healerStep(_Unit u, double h) {
    final t = u.t;
    Troop? patient;
    var worst = 1.0;
    _Unit? anchor;
    var anchorD = 1e9;
    for (final o in _units.values) {
      if (o.garrison || !o.t.alive || identical(o, u)) continue;
      if (o.t.type == TroopType.healer) continue;
      final ex = o.x - u.x, ey = o.y - u.y;
      final d2 = ex * ex + ey * ey;
      if (d2 < anchorD) {
        anchorD = d2;
        anchor = o;
      }
      if (d2 > 2.4 * 2.4) continue;
      final frac = o.t.hp / o.t.maxHp;
      if (frac < worst) {
        worst = frac;
        patient = o.t;
      }
    }
    if (patient != null && u.cd <= 0) {
      u.cd = attackPeriod;
      st.healTroop(t, patient);
      return;
    }
    // no one to mend in reach — walk with the push
    if (anchor != null && anchorD > 1.6 * 1.6) {
      var dx = anchor.x - u.x, dy = anchor.y - u.y;
      final d = math.sqrt(dx * dx + dy * dy);
      dx /= d;
      dy /= d;
      final dist = t.moveBudget / paceDivisor * h;
      _tryMove(u, u.x + dx * dist, u.y);
      if (!t.alive) return;
      _tryMove(u, u.x, u.y + dy * dist);
    }
  }

  static const List<List<int>> _orth = [
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1]
  ];
}

class _Unit {
  final Troop t;
  double x, y;
  double cd = 0;
  double think = 0;
  double stuck = 0;
  double idle = 0; // beats spent swinging at nothing
  double noSwing = 0; // forced march: ignore targets until this runs out
  int leg = 0;
  int? blockKey;
  bool garrison = false;
  List<List<int>> route = const [];
  _Unit(this.t)
      : x = t.c.toDouble(),
        y = t.r.toDouble();
}

class _Obj {
  final int r, c;
  final double value;
  final bool defensive;
  const _Obj(this.r, this.c, this.value, this.defensive);
}
