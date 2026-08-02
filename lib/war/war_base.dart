import 'dart:collection';

import '../core/seeded_rng.dart';
import 'war_types.dart';

/// A placed defense. Owned by the player who built it — it only fires while that
/// owner can pay for the shot.
class Structure {
  final DefType type;
  final String ownerId;
  int hp;
  bool triggered; // hidden pieces (mines/tesla) become visible once sprung
  int cooldown; // ticks until it can fire again
  int level; // upgrades (guard posts get +2 patrol per level)
  double? aimAngle; // transient: where the barrel last pointed (cannon art)

  Structure(this.type, this.ownerId,
      {int? hp, this.triggered = false, this.cooldown = 0, this.level = 1})
      : hp = hp ?? kDefSpecs[type]!.hp;

  DefSpec get spec => kDefSpecs[type]!;
  bool get alive => hp > 0;
  bool get isCastle => type == DefType.castle;

  /// ⚡ poured into this piece so far: place cost + every upgrade rung.
  /// Castles are free landmarks, so they contribute 0.
  double get investedCost {
    if (isCastle) return 0;
    var total = spec.cost.toDouble();
    if (spec.upgradeCost <= 0) return total;
    for (var lv = 1; lv < level; lv++) {
      total += spec.upgradeCost * lv;
    }
    return total;
  }

  /// Upgrades toughen the piece: +30% hp per level past 1.
  /// Walls get an extra +15% from L4 so bastions shrug L1 sapper bombs.
  int get maxHp {
    var mul = 1 + 0.3 * (level - 1);
    if (type == DefType.wall && level >= 4) mul += 0.15 * (level - 3);
    return (spec.hp * mul).round();
  }

  /// Upgrades sharpen the guns: +25% damage per level past 1.
  int get damage => (spec.damage * (1 + 0.25 * (level - 1))).round();

  /// Wall L4+ and Citadel Core radiate a tougher adjacent buff.
  double get effectiveDefBuff {
    var b = spec.defBuffAdj;
    if (type == DefType.wall && level >= 4) b += 0.08;
    if (type == DefType.citadelCore) b += 0.05;
    return b;
  }

  /// Wall L3+ chips troops that melee it.
  int get meleeChip =>
      (type == DefType.wall && level >= 3) ? 4 + (level - 3) * 3 : 0;

  Map<String, dynamic> toJson() =>
      {'t': type.index, 'o': ownerId, 'hp': hp, 'tr': triggered, 'lv': level};
  factory Structure.fromJson(Map<String, dynamic> j) => Structure(
        DefType.values[(j['t'] as num).toInt()],
        j['o'] as String,
        hp: (j['hp'] as num).toInt(),
        triggered: j['tr'] == true,
        level: (j['lv'] as num?)?.toInt() ?? 1,
      );
}

class BaseTile {
  Terrain terrain;
  Structure? structure;
  WarSide? owner; // territory control (drives the positional multiplier + fog)
  BaseTile(this.terrain, {this.structure, this.owner});
}

/// Terrain dials — the game leaves them null/default (seeded variety);
/// the Base Lab turns them by hand. [waterMode] null = seeded dry/light/wet.
class TerrainConfig {
  final int? rivers; // null = derived from waterMode / seeded
  final int? lakes; // null = derived from waterMode / seeded
  final double mountainFrac; // share of the map that is mountain
  final double forestFrac; // share of the map that is forest
  /// 0=dry, 1=light, 2=wet; null = seeded from [waterDry]/[waterWet] weights.
  final int? waterMode;
  final double waterDry;
  final double waterLight;
  final double waterWet;
  const TerrainConfig({
    this.rivers,
    this.lakes,
    this.mountainFrac = 0.11,
    this.forestFrac = 0.16,
    this.waterMode,
    this.waterDry = 0.25,
    this.waterLight = 0.50,
    this.waterWet = 0.25,
  });
}

/// One clan's fortress on a naturally generated battlefield. Attackers land on
/// the OUTER RING (all four sides) and push inward toward the castles.
class Base {
  final WarSide side;
  final int seed;
  final TerrainConfig config;

  /// Classic Bronze floor — also the size tests assume when using [defaultSize].
  static const int defaultSize = 40;

  final int rows;
  final int cols;

  late List<List<BaseTile>> grid;
  final Map<String, Cell> castles = {}; // playerId -> castle cell
  final Set<int> cleared = {}; // forests chopped in prep (persisted)
  final List<List<int>> graves = []; // [r, c, slot] — the war's fallen, forever
  final Map<int, int> scorch = {}; // cellKey → hit count (mortar-torn ground)

  /// Bumped when terrain permanently changes (forest clear, etc.) so the
  /// board painter can drop its cached ground/terrain picture.
  int visualEpoch = 0;

  Base(
    this.side,
    this.seed, {
    this.config = const TerrainConfig(),
    int? size,
  })  : rows = (size ?? defaultSize).clamp(defaultSize, 80),
        cols = (size ?? defaultSize).clamp(defaultSize, 80) {
    _generate();
  }

  bool inBounds(int r, int c) => r >= 0 && r < rows && c >= 0 && c < cols;
  BaseTile? at(int r, int c) => inBounds(r, c) ? grid[r][c] : null;
  Structure? structAt(int r, int c) => inBounds(r, c) ? grid[r][c].structure : null;

  /// The neutral landing ring around the whole map (attack from any side).
  /// The landing BAND: three tiles deep on every side — room to stage a
  /// raid instead of threading a one-tile rim.
  bool isRing(int r, int c) =>
      r < 3 || r >= rows - 3 || c < 3 || c >= cols - 3;
  bool isInterior(int r, int c) => inBounds(r, c) && !isRing(r, c);

  // ── natural terrain generation ──────────────────────────────────────────────
  /// Deterministic lattice value-noise (2 octaves, bilinear, well-scrambled) —
  /// organic shapes, identical on every load for the same seed.
  double _noise(int tag, double x, double y, double scale) {
    double lattice(int xi, int yi) {
      var h = (xi * 73856093) ^
          (yi * 19349663) ^
          (seed * 83492791) ^
          (tag * 0x5bd1e995) ^
          (side.index * 7919);
      h = (h ^ (h >> 13)) * 0x5bd1e995;
      return ((h ^ (h >> 15)) & 0x7fffffff) / 0x7fffffff;
    }

    double sample(double px, double py) {
      final x0 = px.floor(), y0 = py.floor();
      final fx = px - x0, fy = py - y0;
      double sm(double a) => a * a * (3 - 2 * a);
      final u = sm(fx), v = sm(fy);
      final a = lattice(x0, y0), b = lattice(x0 + 1, y0);
      final c = lattice(x0, y0 + 1), d = lattice(x0 + 1, y0 + 1);
      return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
    }

    final n1 = sample(x / scale, y / scale);
    final n2 = sample(x / (scale / 2) + 37, y / (scale / 2) + 91);
    return (n1 * 0.68 + n2 * 0.32).clamp(0.0, 1.0);
  }

  void _generate() {
    final rng = SeededRng(seedFromParts([seed, side.index, 'base']));
    grid = List.generate(
        rows,
        (r) => List.generate(cols, (c) {
              final owner = isRing(r, c) ? null : side;
              return BaseTile(Terrain.plains, owner: owner);
            }));

    // QUANTILE-CAPPED terrain: the noise decides WHERE the ranges/groves are,
    // but coverage is fixed — ~11% mountains, ~16% forest, on every seed.
    final elev = List.generate(rows,
        (r) => List.generate(cols, (c) => _noise(1, c.toDouble(), r.toDouble(), 7.0)));
    final moist = List.generate(rows,
        (r) => List.generate(cols, (c) => _noise(2, c.toDouble(), r.toDouble(), 5.5)));
    final eVals = <double>[];
    for (var r = 1; r < rows - 1; r++) {
      for (var c = 1; c < cols - 1; c++) {
        eVals.add(elev[r][c]);
      }
    }
    eVals.sort();
    final eThresh = eVals[
        (eVals.length * (1 - config.mountainFrac)).floor().clamp(0, eVals.length - 1)];
    for (var r = 1; r < rows - 1; r++) {
      for (var c = 1; c < cols - 1; c++) {
        if (elev[r][c] >= eThresh) {
          grid[r][c].terrain = Terrain.mountain;
        }
      }
    }
    final mVals = <double>[];
    for (var r = 1; r < rows - 1; r++) {
      for (var c = 1; c < cols - 1; c++) {
        if (grid[r][c].terrain == Terrain.plains) mVals.add(moist[r][c]);
      }
    }
    mVals.sort();
    final mThresh = mVals[
        (mVals.length * (1 - config.forestFrac)).floor().clamp(0, mVals.length - 1)];
    for (var r = 1; r < rows - 1; r++) {
      for (var c = 1; c < cols - 1; c++) {
        if (grid[r][c].terrain == Terrain.plains && moist[r][c] >= mThresh) {
          grid[r][c].terrain = Terrain.forest;
        }
      }
    }
    // erosion pass: lone crags and stray trees get smoothed away — ranges and
    // groves survive
    for (var pass = 0; pass < 2; pass++) {
      final toPlains = <Cell>[];
      for (var r = 1; r < rows - 1; r++) {
        for (var c = 1; c < cols - 1; c++) {
          final t = grid[r][c].terrain;
          if (t != Terrain.mountain && t != Terrain.forest) continue;
          var same = 0;
          for (final d in const [
            [-1, 0],
            [1, 0],
            [0, -1],
            [0, 1]
          ]) {
            if (at(r + d[0], c + d[1])?.terrain == t) same++;
          }
          if (t == Terrain.mountain && same < 2) toPlains.add(Cell(r, c));
          if (t == Terrain.forest && same < 1) toPlains.add(Cell(r, c));
        }
      }
      for (final cell in toPlains) {
        grid[cell.r][cell.c].terrain = Terrain.plains;
      }
    }

    // WATER: seeded dry / light / wet (or Lab-forced river/lake counts).
    // Some wars are open plains; some are split by river/lake.
    final mode = config.waterMode ?? _rollWaterMode(rng);
    final riverCount = config.rivers ??
        (mode == 0
            ? 0
            : mode == 1
                ? (rng.unit() < 0.55 ? 1 : 0)
                : 1 + (rng.unit() < 0.45 ? 1 : 0) + (rng.unit() < 0.15 ? 1 : 0));
    final lakeCount = config.lakes ??
        (mode == 0
            ? 0
            : mode == 1
                ? (riverCount == 0 ? 1 : (rng.unit() < 0.35 ? 1 : 0))
                : (rng.unit() < 0.55 ? 1 : 0) + (rng.unit() < 0.2 ? 1 : 0));

    List<Cell> carveRiver(int tag) {
      final riverCells = <Cell>[];
      final horizontal = rng.unit() < 0.5;
      if (horizontal) {
        var r = 4 + rng.intRange(0, rows - 8);
        for (var c = 0; c < cols; c++) {
          grid[r][c].terrain = Terrain.river;
          riverCells.add(Cell(r, c));
          final wob = _noise(tag, c.toDouble(), 0, 3.5);
          if (c % 2 == 1) {
            if (wob > 0.62 && r < rows - 3) {
              r++;
              grid[r][c].terrain = Terrain.river;
              riverCells.add(Cell(r, c));
            } else if (wob < 0.38 && r > 2) {
              r--;
              grid[r][c].terrain = Terrain.river;
              riverCells.add(Cell(r, c));
            }
          }
        }
      } else {
        var c = 4 + rng.intRange(0, cols - 8);
        for (var r = 0; r < rows; r++) {
          grid[r][c].terrain = Terrain.river;
          riverCells.add(Cell(r, c));
          final wob = _noise(tag, r.toDouble(), 0, 3.5);
          if (r % 2 == 1) {
            if (wob > 0.62 && c < cols - 3) {
              c++;
              grid[r][c].terrain = Terrain.river;
              riverCells.add(Cell(r, c));
            } else if (wob < 0.38 && c > 2) {
              c--;
              grid[r][c].terrain = Terrain.river;
              riverCells.add(Cell(r, c));
            }
          }
        }
      }
      return riverCells;
    }

    final rivers = <List<Cell>>[];
    for (var i = 0; i < riverCount; i++) {
      rivers.add(carveRiver(3 + i * 11));
    }
    // lakes: still-water blobs (no bridge needed — walk around)
    // Bigger boards get larger water features.
    final lakeScale = rows >= 52 ? 2 : (rows >= 48 ? 1 : 0);
    for (var i = 0; i < lakeCount; i++) {
      final lr = 6 + rng.intRange(0, rows - 12);
      final lc = 6 + rng.intRange(0, cols - 12);
      final rad = 1 + rng.intRange(0, 2) + lakeScale;
      for (var dr = -rad; dr <= rad; dr++) {
        for (var dc = -rad; dc <= rad; dc++) {
          if (dr * dr + dc * dc > rad * rad + rng.intRange(0, 2)) continue;
          final r = lr + dr, c = lc + dc;
          if (isInterior(r, c)) grid[r][c].terrain = Terrain.river;
        }
      }
    }

    // prebuilt bridges — ONLY at locally straight crossings (water on exactly
    // two opposite sides), evenly spaced along EACH river's course
    bool waterAt(int r, int c) =>
        inBounds(r, c) && grid[r][c].terrain == Terrain.river;
    for (final riverCells in rivers) {
      final straight = <Cell>[];
      for (final cell in riverCells) {
        if (grid[cell.r][cell.c].terrain != Terrain.river) continue;
        final horizWater =
            waterAt(cell.r, cell.c - 1) && waterAt(cell.r, cell.c + 1);
        final vertWater =
            waterAt(cell.r - 1, cell.c) && waterAt(cell.r + 1, cell.c);
        final horizLand =
            !waterAt(cell.r, cell.c - 1) && !waterAt(cell.r, cell.c + 1);
        final vertLand =
            !waterAt(cell.r - 1, cell.c) && !waterAt(cell.r + 1, cell.c);
        if ((horizWater && vertLand) || (vertWater && horizLand)) {
          straight.add(cell);
        }
      }
      final pool = straight.isNotEmpty ? straight : riverCells;
      final spans = rivers.length == 1
          ? const [0.15, 0.38, 0.62, 0.85]
          : const [0.2, 0.5, 0.8];
      for (final f in spans) {
        final cell = pool[(pool.length * f).floor().clamp(0, pool.length - 1)];
        grid[cell.r][cell.c].terrain = Terrain.bridge;
      }
    }

    // the landing ring stays clean and passable on all four sides
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (!isRing(r, c)) continue;
        final t = grid[r][c].terrain;
        if (t == Terrain.mountain || t == Terrain.forest || t == Terrain.hill) {
          grid[r][c].terrain = Terrain.plains;
        } else if (t == Terrain.river) {
          grid[r][c].terrain = Terrain.bridge;
        }
      }
    }

    _ensureConnected();
  }

  int _rollWaterMode(SeededRng rng) {
    final u = rng.unit();
    final d = config.waterDry;
    final l = config.waterLight;
    if (u < d) return 0;
    if (u < d + l) return 1;
    return 2;
  }

  /// Guarantee the map's heart is reachable from the landing ring.
  void _ensureConnected() {
    final center = Cell(rows ~/ 2, cols ~/ 2);
    if (grid[center.r][center.c].terrain == Terrain.mountain) {
      grid[center.r][center.c].terrain = Terrain.plains;
    }
    final seen = <int>{};
    final q = Queue<Cell>();
    for (var c = 0; c < cols; c++) {
      q.add(Cell(0, c));
      seen.add(c);
    }
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      for (final d in const [
        [-1, 0],
        [1, 0],
        [0, -1],
        [0, 1]
      ]) {
        final nr = cur.r + d[0], nc = cur.c + d[1];
        if (!inBounds(nr, nc)) continue;
        if (!TerrainData.passable(grid[nr][nc].terrain)) continue;
        final k = nr * cols + nc;
        if (seen.contains(k)) continue;
        seen.add(k);
        q.add(Cell(nr, nc));
      }
    }
    if (!seen.contains(center.r * cols + center.c)) {
      // carve a straight corridor from the top edge to the center
      for (var r = 0; r <= center.r; r++) {
        final t = grid[r][center.c].terrain;
        if (t == Terrain.mountain) grid[r][center.c].terrain = Terrain.plains;
        if (t == Terrain.river) grid[r][center.c].terrain = Terrain.bridge;
      }
    }
  }

  // ── build-phase queries ─────────────────────────────────────────────────────
  bool isBuildZone(int r, int c) {
    if (!isInterior(r, c)) return false; // never on the landing ring
    return TerrainData.buildable(grid[r][c].terrain);
  }

  bool canPlace(int r, int c) =>
      isBuildZone(r, c) && grid[r][c].structure == null;

  void place(int r, int c, DefType type, String ownerId) {
    if (!canPlace(r, c)) return;
    grid[r][c].structure = Structure(type, ownerId);
    grid[r][c].owner = side;
  }

  void placeCastle(String playerId, int r, int c) {
    if (!canPlace(r, c)) return;
    final prev = castles[playerId];
    if (prev != null) grid[prev.r][prev.c].structure = null;
    grid[r][c].structure = Structure(DefType.castle, playerId);
    castles[playerId] = Cell(r, c);
  }

  /// Refundable structure removal during prep — full investment back:
  /// place cost plus every upgrade rung already paid ([Structure.investedCost]).
  int removeAt(int r, int c) {
    final s = structAt(r, c);
    if (s == null || s.isCastle) return 0;
    final refund = s.investedCost.round();
    grid[r][c].structure = null;
    return refund;
  }

  /// Tears down any castle owned by someone NOT in [validOwnerIds] — for
  /// when a roster reconciliation replaces the whole crew (e.g. the local
  /// solo/offline bot crew hands off to a real room) and the old owners'
  /// castles would otherwise linger forever as orphaned structures.
  void pruneCastlesNotIn(Set<String> validOwnerIds) {
    final stale = castles.keys.where((id) => !validOwnerIds.contains(id)).toList();
    for (final id in stale) {
      final cell = castles.remove(id);
      if (cell != null) grid[cell.r][cell.c].structure = null;
    }
  }

  /// 🪓 Chop a forest tile into buildable plains. Mountains and the river are
  /// permanent. Returns false when there's nothing to clear.
  bool clearForest(int r, int c) {
    if (!isInterior(r, c)) return false;
    if (grid[r][c].terrain != Terrain.forest) return false;
    grid[r][c].terrain = Terrain.plains;
    cleared.add(r * cols + c);
    visualEpoch++;
    return true;
  }

  List<Cell> get castleCells => castles.values.toList();

  /// Landing spots: every open cell of the outer ring, all four sides.
  Iterable<Cell> get dropCells sync* {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (!isRing(r, c)) continue;
        if (!TerrainData.passable(grid[r][c].terrain)) continue;
        if (grid[r][c].structure != null) continue;
        yield Cell(r, c);
      }
    }
  }

  // ── movement ────────────────────────────────────────────────────────────────
  bool passable(int r, int c) {
    if (!inBounds(r, c)) return false;
    if (!TerrainData.passable(grid[r][c].terrain)) return false;
    final s = grid[r][c].structure;
    if (s != null && s.alive && s.spec.blocks) return false;
    return true;
  }

  int moveCost(int r, int c, {TroopType? mover}) {
    var cost = TerrainData.moveCost(grid[r][c].terrain);
    final s = grid[r][c].structure;
    if (s != null && s.alive) {
      // War Elephants shrug barbed wire.
      if (!(mover == TroopType.elephant && s.type == DefType.barbedWire)) {
        cost += s.spec.extraMoveCost;
      }
    }
    return cost;
  }

  // ── scoring ─────────────────────────────────────────────────────────────────
  /// Castles are the PRIZE; walls and traps are furniture — chewing wall all
  /// day shouldn't read as "the base is half destroyed".
  double _weight(Structure s) {
    if (s.isCastle) return 3.0;
    switch (s.type) {
      case DefType.wall:
      case DefType.gate:
        return 0.3;
      case DefType.barbedWire:
      case DefType.landmine:
        return 0.2;
      default:
        return 1.0;
    }
  }

  double get totalWeightHp {
    var t = 0.0;
    for (final row in grid) {
      for (final tile in row) {
        final s = tile.structure;
        if (s != null) t += s.maxHp * _weight(s);
      }
    }
    return t;
  }

  double get aliveWeightHp {
    var t = 0.0;
    for (final row in grid) {
      for (final tile in row) {
        final s = tile.structure;
        if (s != null && s.hp > 0) t += s.hp * _weight(s);
      }
    }
    return t;
  }

  /// 0..100 — how wrecked this base is.
  double get destructionPercent {
    final total = totalWeightHp;
    if (total <= 0) return 0;
    return ((1 - aliveWeightHp / total) * 100).clamp(0, 100);
  }

  /// Total ⚡ cost of every structure currently standing — an honest,
  /// hard-to-dilute measure of "how much did this crew actually invest,"
  /// independent of how many nominal roster seats exist or who personally
  /// earned the ⚡ that got spent (co-op: anyone can build anywhere).
  double get builtValue {
    var v = 0.0;
    for (final row in grid) {
      for (final tile in row) {
        final s = tile.structure;
        if (s != null) v += s.spec.cost;
      }
    }
    return v;
  }

  int get castleCount => castleCells.length;
  int get castlesRazed {
    var n = 0;
    for (final cell in castleCells) {
      final s = structAt(cell.r, cell.c);
      if (s == null || s.hp <= 0) n++;
    }
    return n;
  }

  bool get allCastlesRazed => castleCount > 0 && castlesRazed >= castleCount;

  /// Grow the board to [newSize] by padding new terrain around the edges.
  /// Structures keep their relative positions (shifted toward the new center).
  /// Never shrinks. Returns `this` if already large enough.
  Base expandTo(int newSize, {TerrainConfig? rimConfig}) {
    final n = newSize.clamp(defaultSize, 80);
    if (n <= rows) return this;
    final pad = (n - rows) ~/ 2;
    final fresh = Base(side, seed ^ 0xA5A5, config: rimConfig ?? config, size: n);
    // Overlay the old fortress onto the padded center — keep structures/terrain.
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final nr = r + pad, nc = c + pad;
        fresh.grid[nr][nc].terrain = grid[r][c].terrain;
        fresh.grid[nr][nc].structure = grid[r][c].structure;
        fresh.grid[nr][nc].owner = grid[r][c].owner;
      }
    }
    // Re-assert landing ring ownership (outer pad must stay neutral).
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (fresh.isRing(r, c)) {
          fresh.grid[r][c].owner = null;
          final t = fresh.grid[r][c].terrain;
          if (t == Terrain.mountain ||
              t == Terrain.forest ||
              t == Terrain.hill) {
            fresh.grid[r][c].terrain = Terrain.plains;
          } else if (t == Terrain.river) {
            fresh.grid[r][c].terrain = Terrain.bridge;
          }
        } else if (fresh.grid[r][c].owner == null) {
          fresh.grid[r][c].owner = side;
        }
      }
    }
    for (final e in castles.entries) {
      fresh.castles[e.key] = Cell(e.value.r + pad, e.value.c + pad);
    }
    for (final k in cleared) {
      final r = k ~/ cols, c = k % cols;
      fresh.cleared.add((r + pad) * n + (c + pad));
    }
    for (final g in graves) {
      if (g.length >= 2) {
        fresh.graves.add([g[0] + pad, g[1] + pad, if (g.length > 2) g[2]]);
      }
    }
    for (final e in scorch.entries) {
      final r = e.key ~/ cols, c = e.key % cols;
      fresh.scorch[(r + pad) * n + (c + pad)] = e.value;
    }
    fresh._ensureConnected();
    return fresh;
  }

  // ── persistence ─────────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'side': side.index,
        'seed': seed,
        'size': rows,
        'structs': [
          for (var r = 0; r < rows; r++)
            for (var c = 0; c < cols; c++)
              if (grid[r][c].structure != null)
                {'r': r, 'c': c, ...grid[r][c].structure!.toJson()},
        ],
        'owners': [
          for (var r = 0; r < rows; r++)
            for (var c = 0; c < cols; c++)
              if (grid[r][c].owner != (isRing(r, c) ? null : side))
                {'r': r, 'c': c, 'o': grid[r][c].owner?.index ?? -1},
        ],
        'castles': {for (final e in castles.entries) e.key: [e.value.r, e.value.c]},
        'cleared': cleared.toList(),
        'graves': [for (final g in graves) g],
        'scorch': {for (final e in scorch.entries) '${e.key}': e.value},
      };

  factory Base.fromJson(Map<String, dynamic> j) {
    final size = (j['size'] as num?)?.toInt() ?? defaultSize;
    final b = Base(
      WarSide.values[(j['side'] as num).toInt()],
      (j['seed'] as num).toInt(),
      size: size,
    );
    for (final v in (j['cleared'] as List? ?? const [])) {
      final k = (v as num).toInt();
      final r = k ~/ b.cols, c = k % b.cols;
      if (b.inBounds(r, c) && b.grid[r][c].terrain == Terrain.forest) {
        b.grid[r][c].terrain = Terrain.plains;
      }
      b.cleared.add(k);
    }
    for (final s in (j['structs'] as List? ?? const [])) {
      final m = s as Map<String, dynamic>;
      final r = (m['r'] as num).toInt(), c = (m['c'] as num).toInt();
      if (b.inBounds(r, c)) {
        b.grid[r][c].structure = Structure.fromJson(m);
      }
    }
    for (final o in (j['owners'] as List? ?? const [])) {
      final m = o as Map<String, dynamic>;
      final idx = (m['o'] as num).toInt();
      final r = (m['r'] as num).toInt(), c = (m['c'] as num).toInt();
      if (b.inBounds(r, c)) {
        b.grid[r][c].owner = idx < 0 ? null : WarSide.values[idx];
      }
    }
    final cj = j['castles'] as Map<String, dynamic>? ?? {};
    cj.forEach((k, v) {
      final l = v as List;
      b.castles[k] = Cell((l[0] as num).toInt(), (l[1] as num).toInt());
    });
    b.graves.addAll([
      for (final g in (j['graves'] as List? ?? const []))
        [for (final v in (g as List)) (v as num).toInt()]
    ]);
    (j['scorch'] as Map<String, dynamic>? ?? const {}).forEach((k, v) {
      b.scorch[int.parse(k)] = (v as num).toInt();
    });
    return b;
  }
}
