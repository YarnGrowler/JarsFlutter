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
/// Default for drills AND live clan raids. Replays of AI hour-raids still use
/// the classic frame log ([LiveBattle] / [WarAi.runAttack]).
class FreeMoveBattle {
  final AttackState st;

  /// Can the commander still send something? (drills always can)
  final bool Function() canDeploy;

  /// Headless raids (AI-hour attacks, played back later from a replay
  /// list) need the FULL frame log; live drills/clan raids don't — nobody
  /// replays their own screen back at them — so they keep the light
  /// rolling window. Off by default so every existing live/drill call
  /// site is unaffected.
  final bool keepHistory;

  /// Does razing the last castle END the fight?
  ///
  /// For a HANDS-ON raid: no. Cracking the keep is usually the halfway point
  /// — the storehouses, war generators and tribute chests are still standing
  /// and still worth plundering, and stopping the battle there took that
  /// choice away from the commander. They fight on until the clock runs out
  /// or the army is spent.
  ///
  /// For a HEADLESS AI raid: yes, unchanged — nobody is watching, there is
  /// nothing to decide, and letting it grind the rest of the 90s budget on
  /// every raid of a season sim is pure cost.
  final bool stopWhenRazed;

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

  FreeMoveBattle(this.st,
      {required this.canDeploy,
      this.keepHistory = false,
      this.stopWhenRazed = true});

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

  /// A fresh deployment resets the wind-down.
  void notifyDeploy() {
    _emptyBeats = 0;
  }

  /// Headless completion (player left mid-battle): run the remaining beats.
  void fastResolve() {
    var guard = 0;
    // ~90s of sim at most — enough to finish a fight or declare it over
    while (!over && guard++ < 30 * 90) {
      if (st.troops.every((t) => !t.alive)) {
        over = true;
        break;
      }
      _step(simStep);
    }
    over = true;
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
    // Cap expensive route scans, but prefer units with nowhere to go so a
    // big wave doesn't freeze on the drop ring while veterans keep re-planning.
    _thinkBudget = 12;
    _bin();
    final order = _units.values.where((u) => u.t.alive).toList()
      ..sort((a, b) {
        final ae = a.route.isEmpty ? 0 : 1;
        final be = b.route.isEmpty ? 0 : 1;
        if (ae != be) return ae - be;
        return a.think.compareTo(b.think);
      });
    for (final u in order) {
      _advance(u, h);
    }
    _beat += h;
    if (_beat >= beatPeriod) {
      _beat -= beatPeriod;
      st.defendersReact();
      st.snapshot();
      // live drills/clan raids are never replayed on their own screen —
      // keep a rolling window instead of five minutes of full-grid frames.
      // Headless raids opt OUT via keepHistory: their frames feed a real
      // replay list later, so trimming here would gut it down to the last
      // ~4 seconds of the fight.
      if (!keepHistory && st.frames.length > 8) {
        st.frames.removeRange(0, st.frames.length - 8);
      }
      _objsStale = true;
      _beatEnd();
    }
    _publish(h);
  }

  void _beatEnd() {
    if (stopWhenRazed && st.base.allCastlesRazed) {
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
      // A War Elephant is a living battering ram — a wall in reach is a wall
      // to flatten, not to walk around. (Barbed wire it just tramples; it
      // shrugs the chip damage, so there's nothing to stop and hit.)
      if (t.type == TroopType.elephant && s.type != DefType.barbedWire) {
        return s.type == DefType.gate ? 110 : 100;
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
    // Still nowhere to go after a plan attempt — scout locally instead of
    // planting on the drop ring until someone else opens a road. Toward a
    // breach mark we still only step on walkable tiles (bridges, not water).
    if (u.route.isEmpty || u.leg >= u.route.length) {
      Cell? toward;
      if (u.blockKey != null) {
        toward = Cell(
            u.blockKey! ~/ st.base.cols, u.blockKey! % st.base.cols);
      }
      _wander(u, h, toward: toward);
      return;
    }
    var wp = u.route[u.leg];
    if ((wp[1] - u.x).abs() < 0.2 && (wp[0] - u.y).abs() < 0.2) {
      u.leg++;
      if (u.leg >= u.route.length) {
        u.think = 0;
        return;
      }
      wp = u.route[u.leg];
    }
    final tx = wp[1].toDouble();
    final ty = wp[0].toDouble();
    _steer(u, h, tx, ty);
  }

  /// Greedy step toward [toward] (or the current objective / map centre) on
  /// walkable neighbours — keeps stranded units moving and probing for a road.
  void _wander(_Unit u, double h, {Cell? toward}) {
    final t = u.t;
    var goal = toward ??
        _pickObjective(u) ??
        Cell(st.base.rows ~/ 2, st.base.cols ~/ 2);
    // If the prize is across water (closer tiles are river), don't bee-line
    // into the bank — walk toward a bridge instead. Never retarget bridges
    // while already on one (that ping-pongs the plank).
    if (!_onBridge(t.r, t.c) && _waterBlocksApproach(t.r, t.c, goal)) {
      final bridge = _bridgeWaypoint(u, goal);
      if (bridge != null) goal = bridge;
    }
    var bestR = t.r, bestC = t.c;
    var best = (t.r - goal.r).abs() + (t.c - goal.c).abs();
    // slight personal bias so a stuck pack fans out instead of oscillating
    final rot = t.id.hashCode & 3;
    for (var di = 0; di < 4; di++) {
      final d = _orth[(di + rot) & 3];
      final nr = t.r + d[0], nc = t.c + d[1];
      if (!_walkable(nr, nc, t)) continue;
      final dist = (nr - goal.r).abs() + (nc - goal.c).abs();
      if (dist < best) {
        best = dist;
        bestR = nr;
        bestC = nc;
      }
    }
    if (bestR == t.r && bestC == t.c) {
      // every step closer is sealed — take ANY walkable neighbour to unstick
      for (var di = 0; di < 4; di++) {
        final d = _orth[(di + rot) & 3];
        final nr = t.r + d[0], nc = t.c + d[1];
        if (!_walkable(nr, nc, t)) continue;
        bestR = nr;
        bestC = nc;
        break;
      }
    }
    if (bestR == t.r && bestC == t.c) {
      u.stuck += h;
      if (u.stuck > 0.5) {
        u.stuck = 0;
        u.think = 0;
      }
      return;
    }
    _steer(u, h, bestC.toDouble(), bestR.toDouble());
  }

  bool _onBridge(int r, int c) =>
      st.base.inBounds(r, c) &&
      st.base.grid[r][c].terrain == Terrain.bridge;

  /// True when the unit is staring across a river at the prize: at least one
  /// manhattan-reducing step is water, and NONE of those steps are walkable
  /// land/bridge. Standing on a bridge never counts — BFS owns the crossing.
  bool _waterBlocksApproach(int r, int c, Cell goal) {
    if (_onBridge(r, c)) return false;
    final dr = (goal.r - r).sign;
    final dc = (goal.c - c).sign;
    var riverHit = false;
    var passableCloser = false;
    void probe(int nr, int nc) {
      if (!st.base.inBounds(nr, nc)) return;
      final terr = st.base.grid[nr][nc].terrain;
      if (terr == Terrain.river) {
        riverHit = true;
        return;
      }
      if (TerrainData.passable(terr)) passableCloser = true;
    }

    if (dr != 0) probe(r + dr, c);
    if (dc != 0) probe(r, c + dc);
    return riverHit && !passableCloser;
  }

  void _steer(_Unit u, double h, double tx, double ty) {
    final t = u.t;
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

    // one axis at a time: a unit can never clip a wall's (or river's) corner
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
    u.leg = 0;
    // Keep a live smash mark across replans — wiping it every think let a unit
    // on a sealed wall flip back to the long walk-around and circle the keep.
    if (u.blockKey != null) {
      final br = u.blockKey! ~/ st.base.cols;
      final bc = u.blockKey! % st.base.cols;
      final wall = st.base.structAt(br, bc);
      if (wall == null || !wall.alive || !wall.spec.blocks) {
        u.blockKey = null;
      }
    }

    final yard = Cell(st.base.rows ~/ 2, st.base.cols ~/ 2);
    final obj = _pickObjective(u);

    // Already committed to a wall — march to a face of it (or stand and swing).
    // Never abandon for a scenic lap around the curtain.
    if (u.blockKey != null) {
      final br = u.blockKey! ~/ st.base.cols;
      final bc = u.blockKey! % st.base.cols;
      final toFace = _shortRoadToWallFace(u, br, bc);
      if (toFace.isNotEmpty) {
        u.route = toFace;
        u.think = 1.2 + (t.id.hashCode & 7) * 0.08;
        return;
      }
      // Adjacent / sealed against it — empty route, _targetInReach smashes.
      u.route = const [];
      u.think = 0.8;
      return;
    }

    // Prefer a real BFS road first — bridges are walkable terrain, so this
    // already crosses rivers. Staging via a bridge tile FIRST made units on a
    // multi-plank crossing retarget the tile behind them and ping-pong forever.
    if (obj != null) {
      final direct = _routeToward(u, obj);
      if (direct.isNotEmpty) {
        u.route = direct;
        u.think = 1.4 + (t.id.hashCode & 7) * 0.08;
        return;
      }
    }
    // Far bank sealed (walls) or no objective yet — stage via a crossing, but
    // never while already on the plank (BFS / smash owns that stretch).
    if (!_onBridge(t.r, t.c) &&
        (obj == null || _waterBlocksApproach(t.r, t.c, obj))) {
      final bridge = _bridgeWaypoint(u, obj ?? yard);
      if (bridge != null) {
        final via = _routeToward(u, bridge, plain: true);
        if (via.isNotEmpty) {
          u.route = via;
          u.think = 1.0 + (t.id.hashCode & 7) * 0.08;
          return;
        }
      }
    }
    u.route = obj == null ? const [] : _routeToward(u, obj);
    if (u.route.isEmpty) {
      // Nothing reachable from here — a raider still never just stands there.
      // March for the middle of the yard; a new objective almost always opens
      // up on the way in.
      u.route = _routeToward(u, yard, plain: true);
    }
    if (u.route.isEmpty) {
      // Fully sealed (or river-cut): smash toward the objective / yard so this
      // unit opens its OWN road instead of waiting for someone else to.
      u.route = _routeToward(u, obj ?? yard);
    }
    if (u.route.isEmpty && !_onBridge(t.r, t.c)) {
      // Classic river stare: BFS can't land next to the prize — march to the
      // far side of a reachable bridge first and replan after.
      final bridge = _bridgeWaypoint(u, obj ?? yard);
      if (bridge != null) {
        u.route = _routeToward(u, bridge, plain: true);
      }
    }
    // A failed plan retries soon, but never every step — see _walk.
    u.think = u.route.isEmpty ? 0.35 : 1.4 + (t.id.hashCode & 7) * 0.08;
  }

  /// Shortest open road to a walkable tile touching the smash wall. If the only
  /// open road is a marathon around the keep, cut through walls toward a face
  /// instead — that was the "dance on the bridge until someone else breaches"
  /// failure mode.
  List<List<int>> _shortRoadToWallFace(_Unit u, int wr, int wc) {
    final t = u.t;
    final crow = (wr - t.r).abs() + (wc - t.c).abs();
    List<List<int>> best = const [];
    for (final d in _orth) {
      final nr = wr + d[0], nc = wc + d[1];
      if (!st.base.passable(nr, nc)) continue;
      // already on the face — nothing to walk
      if (nr == t.r && nc == t.c) return const [];
      final p = st.routeTo(t, nr, nc);
      if (p.isNotEmpty && (best.isEmpty || p.length < best.length)) {
        best = p;
      }
    }
    if (best.isNotEmpty && best.length <= crow * 2 + 2) return best;

    // Open road missing or absurd — push through toward the wall tile and
    // stop on the last open cell before it.
    final smash = st.routeTo(t, wr, wc, throughWalls: true);
    if (smash.isEmpty) return best;
    final cut = <List<int>>[];
    for (final step in smash) {
      if (step[0] == wr && step[1] == wc) break;
      final s = st.base.structAt(step[0], step[1]);
      if (s != null && s.alive && s.spec.blocks) break;
      cut.add(step);
    }
    return cut.isNotEmpty ? cut : best;
  }

  /// Far-side of the nearest useful crossing toward [goal] — the detour troops
  /// should take instead of faceplanting into the riverbank. Returns null when
  /// the unit is already on a bridge (don't bounce between planks).
  Cell? _bridgeWaypoint(_Unit u, Cell goal) {
    final t = u.t;
    if (_onBridge(t.r, t.c)) return null;
    Cell? best;
    var bestScore = 1 << 30;
    for (var r = 0; r < st.base.rows; r++) {
      for (var c = 0; c < st.base.cols; c++) {
        if (st.base.grid[r][c].terrain != Terrain.bridge) continue;
        final path = st.routeTo(t, r, c);
        if (path.isEmpty) continue;
        // Prefer the FAR exit of a multi-tile bridge (closest to the prize),
        // not the near entrance — otherwise units stage onto plank 1, replan
        // to plank 1 again, and never commit across.
        final score =
            path.length * 2 + ((r - goal.r).abs() + (c - goal.c).abs()) * 5;
        if (score < bestScore) {
          bestScore = score;
          best = Cell(r, c);
        }
      }
    }
    return best;
  }

  /// Best road to [obj]: around the walls if there is one, through them if the
  /// detour is absurd. Marks the wall to smash in [u.blockKey] when breaching.
  List<List<int>> _routeToward(_Unit u, Cell obj, {bool plain = false}) {
    final t = u.t;
    var around = st.routeTo(t, obj.r, obj.c);
    if (around.isEmpty) {
      for (final d in _orth) {
        final nr = obj.r + d[0], nc = obj.c + d[1];
        if (!st.base.passable(nr, nc)) continue;
        around = st.routeTo(t, nr, nc);
        if (around.isNotEmpty) break;
      }
    }
    // a plain march (the fallback to the middle) never smashes its way there
    if (plain) return around;

    final smash = st.routeTo(t, obj.r, obj.c, throughWalls: true);
    if (smash.isEmpty) return around;

    // Clash rule: a castle three tiles behind one wall must NEVER lose to a
    // scenic lap around the whole base. Smash if the open road is meaningfully
    // longer than the breach — or longer than ~2× crow-flies.
    final crow = (obj.r - t.r).abs() + (obj.c - t.c).abs();
    final ram = t.type == TroopType.elephant;
    final preferSmash = around.isEmpty ||
        (ram && around.length > smash.length) ||
        around.length > smash.length + 1 ||
        around.length > crow * 2 + 2;

    if (!preferSmash) return around;

    // walk the breach line and mark the first wall on it as the target;
    // _targetInReach will swing at it the moment we're close enough
    final cut = <List<int>>[];
    for (final step in smash) {
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
