import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../war/war_base.dart';
import '../../war/war_biome.dart';
import '../../war/war_engine.dart' show RaidFrame, RaidSprite;
import '../../war/war_troop.dart';
import '../../war/war_types.dart';

/// The battlefield renderer — a painted scene, not a grid of chips:
/// continuous ground with grass variation, painted pines and snow peaks, a
/// flowing river with plank bridges, walls that join into fortification lines,
/// glowing territory frontiers, a dirt deploy strip, waving castle banners,
/// bobbing troops, and drifting fog.
class WarBoardPainter extends CustomPainter {
  final Base base;
  final double tile, gx, gy, t;
  final Set<int>? fog;
  final List<Troop> troops;
  final Set<int> reachable;
  final Map<int, double> reachCosts; // ⚡ cost labels on reachable tiles
  final List<Cell> targets;
  final Cell? selected;
  final Set<int> buildable;
  final bool ownBase;
  final bool showDropLane;

  /// Paint the enemy-discovery overlay. OFF on attack boards — there the fog
  /// reveal is the signal that matters.
  final bool showTerritory;

  /// Cells the ENEMY clan has scouted of this base — drawn as a red overlay
  /// with a frontier line, so you can see exactly where they have eyes.
  final Set<int> enemyEyes;
  final RaidFrame? replayFrame;

  /// Smooth playback: the frame BEFORE [replayFrame] plus how far we've
  /// blended toward the current one (0..1). Sprites glide between the two.
  final RaidFrame? replayPrev;
  final double replayBlend;
  final Map<String, String> ownerBadges; // troop ownerId → player emoji
  /// CoC-style radius previews: (cell, outer range, inner blind-spot range).
  final List<(Cell, double, double)> rangeRings;
  /// Smooth per-troop display positions (cell-space) — tokens glide between
  /// tiles instead of snapping.
  final Map<String, Offset> troopPositions;

  /// Tombstones: [r, c, slot 0..3] — where troops fell this raid.
  final List<List<int>> graves;

  /// League biome palette — plains, forests, peaks, water, skirt.
  final WarBiome biome;

  /// Fogger smoke cell keys (r * cols + c) currently concealing the board.
  final Set<int> smokeCells;

  WarBoardPainter({
    required this.base,
    required this.tile,
    required this.gx,
    required this.gy,
    required this.t,
    this.fog,
    this.troops = const [],
    this.reachable = const {},
    this.reachCosts = const {},
    this.targets = const [],
    this.selected,
    this.buildable = const {},
    this.ownBase = false,
    this.showDropLane = false,
    this.showTerritory = true,
    this.enemyEyes = const {},
    this.replayFrame,
    this.replayPrev,
    this.replayBlend = 1.0,
    this.ownerBadges = const {},
    this.rangeRings = const [],
    this.troopPositions = const {},
    this.graves = const [],
    this.biome = WarBiome.meadow,
    this.smokeCells = const {},
  });

  static const _you = Color(0xFF3D7BFF);
  static const _enemy = Color(0xFFE6483F);

  int _key(int r, int c) => r * base.cols + c;
  bool _revealed(int r, int c) => fog == null || fog!.contains(_key(r, c));
  Rect _rect(int r, int c) => Rect.fromLTWH(gx + c * tile, gy + r * tile, tile, tile);
  Offset _center(num r, num c) =>
      Offset(gx + (c + 0.5) * tile, gy + (r + 0.5) * tile);

  // visible cell range (viewport culling for the scrolling camera)
  int _r0 = 0, _r1 = 0, _c0 = 0, _c1 = 0;

  /// Ambient motion clock — frozen when zoomed out so tents/people/flags
  /// don't keep thrashing the GPU after terrain has already LODed.
  double _at = 0;
  bool _hiDetail = true;

  void _cull(Size size) {
    _r0 = math.max(0, ((-gy) / tile).floor() - 1);
    _r1 = math.min(base.rows - 1, ((size.height - gy) / tile).ceil() + 1);
    _c0 = math.max(0, ((-gx) / tile).floor() - 1);
    _c1 = math.min(base.cols - 1, ((size.width - gx) / tile).ceil() + 1);
  }

  /// Deterministic per-cell jitter (0..1) so grass/trees vary but never flicker.
  double _hash(int r, int c, [int salt = 0]) {
    var h = (r * 73856093) ^ (c * 19349663) ^ (base.seed * 83492791) ^ (salt * 2971);
    h = (h ^ (h >> 13)) * 0x5bd1e995;
    return ((h ^ (h >> 15)) & 0x7fffffff) / 0x7fffffff;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final board = Rect.fromLTWH(
        gx - 8, gy - 8, tile * base.cols + 16, tile * base.rows + 16);
    _skirtPass(canvas, size, board);
    // outer panel
    canvas.drawRRect(
        RRect.fromRectAndRadius(board.inflate(2), const Radius.circular(18)),
        Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawRRect(
        RRect.fromRectAndRadius(board, const Radius.circular(16)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.10));

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(board, const Radius.circular(16)));

    // Zoom LOD: terrain already dumps detail under ~18px; freeze ambient
    // motion and skip people/dressing so a 64² Radiant board stays playable
    // when fitted to the screen.
    _hiDetail = tile >= 22;
    _at = _hiDetail ? t : 0;
    _cull(size);
    _groundPass(canvas);
    if (showTerritory && _hiDetail) _territoryPass(canvas);
    _terrainPass(canvas);
    if (_hiDetail) _smokePass(canvas);
    if (replayFrame == null) {
      if (_hiDetail || tile >= 14) {
        _scorchPass(canvas, base.scorch);
      }
    } else if (_hiDetail || tile >= 14) {
      _scorchPass(
          canvas, {for (final e in replayFrame!.scorch) e[0]: e[1]});
    }
    if (showDropLane && tile >= 14) _ringPass(canvas);
    if (replayFrame == null) {
      _structurePass(canvas);
      if (_hiDetail) _dressingPass(canvas);
    }
    if (_hiDetail) _gravesPass(canvas, replayFrame?.graves ?? base.graves);
    if (_hiDetail) _rangeRingPass(canvas);
    _highlightPass(canvas);
    if (replayFrame != null) {
      _drawReplay(canvas, replayFrame!);
    } else {
      for (final tr in troops) {
        if (tr.alive) _troop(canvas, tr);
      }
    }
    if (fog != null) _fogPass(canvas);
    canvas.restore();
  }

  /// Scenery OUTSIDE the battlefield — a dark forest skirt so the map floats
  /// in a world (and the camera has something to overscroll onto), CoC-style.
  void _skirtPass(Canvas canvas, Size size, Rect board) {
    canvas.drawRect(Offset.zero & size, Paint()..color = biome.skirt);
    // Zoomed-out / big boards: solid skirt only — pine scatter is expensive
    // and invisible under ~14px tiles anyway.
    if (tile < 16) {
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(
              center: Alignment(
                ((board.center.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
                ((board.center.dy / size.height) * 2 - 1).clamp(-1.0, 1.0),
              ),
              radius: 1.15,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
              ],
              stops: const [0.45, 1.0],
            ).createShader(Offset.zero & size));
      return;
    }
    // scattered dark pines outside the board, deterministic, culled to view
    final leaf = Paint()..color = biome.skirtLeaf;
    final leafD = Paint()..color = biome.skirtLeafDeep;
    final skirt = tile.clamp(14.0, 60.0);
    final c0 = ((-gx) / skirt).floor() - 8, c1 = ((size.width - gx) / skirt).ceil() + 8;
    final r0 = ((-gy) / skirt).floor() - 8, r1 = ((size.height - gy) / skirt).ceil() + 8;
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        final px = gx + c * skirt, py = gy + r * skirt;
        // skip anything inside (or hugging) the board
        if (px > board.left - skirt && px < board.right + skirt * 0.2 &&
            py > board.top - skirt && py < board.bottom + skirt * 0.2) {
          continue;
        }
        final h = _hash(r + 500, c + 500);
        if (h < 0.4) continue; // sparse
        final jx = px + _hash(r + 500, c + 500, 1) * skirt * 0.6;
        final jy = py + _hash(r + 500, c + 500, 2) * skirt * 0.6;
        final s = skirt * (0.3 + h * 0.3);
        for (var i = 0; i < 2; i++) {
          final y = jy - i * s * 0.3;
          final w = s * (0.9 - i * 0.3);
          canvas.drawPath(
              Path()
                ..moveTo(jx, y - s * 0.5)
                ..lineTo(jx + w / 2, y)
                ..lineTo(jx - w / 2, y)
                ..close(),
              i.isEven ? leaf : leafD);
        }
      }
    }
    // vignette so the scenery fades away from the battlefield
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.center,
            radius: 1.1,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
          ).createShader(Offset.zero & size));
  }

  void _rangeRingPass(Canvas canvas) {
    for (final (cell, radius, inner) in rangeRings) {
      final center = _center(cell.r, cell.c);
      final rr = (radius + 0.5) * tile;
      canvas.drawCircle(center, rr,
          Paint()..color = Colors.white.withValues(alpha: 0.07));
      canvas.drawCircle(
          center,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: 0.4 + 0.15 * math.sin(_at * 3)));
      // artillery blind spot: the zone this defense CANNOT hit
      if (inner > 0) {
        final ir = (inner - 0.5) * tile;
        canvas.drawCircle(center, ir,
            Paint()..color = JarsColors.red.withValues(alpha: 0.12));
        canvas.drawCircle(
            center,
            ir,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = JarsColors.red.withValues(alpha: 0.55));
      }
    }
  }

  // ── ground: one continuous field ────────────────────────────────────────────
  void _groundPass(Canvas canvas) {
    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        final rect = _rect(r, c);
        final isLane = base.isRing(r, c);
        final h = _hash(r, c);
        Color col;
        if (isLane) {
          // packed-dirt landing ring around the whole battlefield
          col = Color.lerp(const Color(0xFF4A3B2E), const Color(0xFF3C2F24), h)!;
        } else {
          // grass with SMOOTH macro variation (bilinear over a coarse lattice —
          // rolling meadows, not blocky patches)
          const s = 5;
          final r0 = r ~/ s, c0 = c ~/ s;
          final fr = (r % s) / s, fc = (c % s) / s;
          final a = _hash(r0, c0, 40),
              b = _hash(r0, c0 + 1, 40),
              cc2 = _hash(r0 + 1, c0, 40),
              d = _hash(r0 + 1, c0 + 1, 40);
          final dry =
              a + (b - a) * fc + (cc2 - a) * fr + (a - b - cc2 + d) * fc * fr;
          final grassA = Color.lerp(biome.plains, biome.plainsAlt, dry)!;
          col = Color.lerp(grassA, Color.lerp(grassA, Colors.black, 0.12)!,
              h * 0.5)!;
        }
        canvas.drawRect(rect, Paint()..color = col);
        // sparse decoration: tufts, pebbles, the odd flower (zoomed in only)
        if (!isLane && h > 0.55 && tile >= 18) {
          final tx = rect.left + tile * (0.2 + _hash(r, c, 1) * 0.6);
          final ty = rect.top + tile * (0.2 + _hash(r, c, 2) * 0.6);
          final d = _hash(r, c, 5);
          if (d > 0.93) {
            canvas.drawCircle(Offset(tx, ty), tile * 0.045,
                Paint()..color = const Color(0xFFE8D06A).withValues(alpha: 0.75));
            canvas.drawCircle(Offset(tx, ty), tile * 0.02,
                Paint()..color = const Color(0xFFB4462F));
          } else {
            canvas.drawCircle(Offset(tx, ty), tile * 0.035,
                Paint()..color = Colors.white.withValues(alpha: 0.05));
          }
        }
        if (isLane && h > 0.5) {
          final p = Paint()..color = Colors.black.withValues(alpha: 0.12);
          final tx = rect.left + tile * (0.15 + _hash(r, c, 3) * 0.7);
          final ty = rect.top + tile * (0.15 + _hash(r, c, 4) * 0.7);
          canvas.drawCircle(Offset(tx, ty), tile * 0.05, p);
        }
      }
    }
    // whisper-subtle grid so placement still reads
    final grid = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var r = math.max(1, _r0); r <= _r1; r++) {
      canvas.drawLine(Offset(gx + _c0 * tile, gy + r * tile),
          Offset(gx + (_c1 + 1) * tile, gy + r * tile), grid);
    }
    for (var c = math.max(1, _c0); c <= _c1; c++) {
      canvas.drawLine(Offset(gx + c * tile, gy + _r0 * tile),
          Offset(gx + c * tile, gy + (_r1 + 1) * tile), grid);
    }
  }

  // ── discovery: tiles the ENEMY has scouted of this base (their eyes) ────────
  // NOT the marched trail — the player asked for "what they have uncovered".
  void _territoryPass(Canvas canvas) {
    if (enemyEyes.isEmpty) return;
    bool eyes(int rr, int cc) =>
        base.inBounds(rr, cc) && enemyEyes.contains(rr * base.cols + cc);
    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        if (!eyes(r, c)) continue;
        canvas.drawRect(
            _rect(r, c), Paint()..color = _enemy.withValues(alpha: 0.1));
      }
    }
    final edge = Paint()
      ..strokeWidth = 2.2
      ..color = _enemy.withValues(alpha: 0.5);
    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        if (!eyes(r, c)) continue;
        final rect = _rect(r, c);
        // frontier edge wherever the neighbour is still unscouted by them
        if (!eyes(r - 1, c)) canvas.drawLine(rect.topLeft, rect.topRight, edge);
        if (!eyes(r + 1, c)) {
          canvas.drawLine(rect.bottomLeft, rect.bottomRight, edge);
        }
        if (!eyes(r, c - 1)) canvas.drawLine(rect.topLeft, rect.bottomLeft, edge);
        if (!eyes(r, c + 1)) {
          canvas.drawLine(rect.topRight, rect.bottomRight, edge);
        }
      }
    }
  }

  // ── terrain: continuous landmasses, not per-tile icons ──────────────────────
  bool _terr(int r, int c, Terrain t) =>
      base.inBounds(r, c) && base.grid[r][c].terrain == t;
  bool _water(int r, int c) =>
      _terr(r, c, Terrain.river) || _terr(r, c, Terrain.bridge);

  void _terrainPass(Canvas canvas) {
    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        final rect = _rect(r, c);
        switch (base.grid[r][c].terrain) {
          case Terrain.hill:
            _hillTile(canvas, rect, r, c);
            break;
          case Terrain.forest:
            _forest(canvas, rect, r, c);
            break;
          case Terrain.mountain:
            _mountain(canvas, rect, r, c);
            break;
          case Terrain.river:
            _river(canvas, rect, r, c);
            break;
          case Terrain.bridge:
            _bridge(canvas, rect, r, c);
            break;
          case Terrain.plains:
            break;
        }
      }
    }
  }

  /// Forest = a canopy MASS: full-cell fill that merges with neighbours, a
  /// shaded rim only on the grove's silhouette, and varied trees when zoomed in.
  void _forest(Canvas canvas, Rect rect, int r, int c) {
    final h = _hash(r, c, 5);
    canvas.drawRect(
        rect,
        Paint()
          ..color = Color.lerp(biome.forestCanopy, biome.forestDeep, h)!);
    // silhouette rim toward non-forest neighbours
    final rim = Paint()
      ..color = biome.forestDeep
      ..strokeWidth = 2;
    if (!_terr(r - 1, c, Terrain.forest)) {
      canvas.drawLine(rect.topLeft, rect.topRight, rim);
    }
    if (!_terr(r + 1, c, Terrain.forest)) {
      canvas.drawLine(rect.bottomLeft, rect.bottomRight, rim);
    }
    if (!_terr(r, c - 1, Terrain.forest)) {
      canvas.drawLine(rect.topLeft, rect.bottomLeft, rim);
    }
    if (!_terr(r, c + 1, Terrain.forest)) {
      canvas.drawLine(rect.topRight, rect.bottomRight, rim);
    }
    if (tile < 18) return; // zoomed out: the mass alone reads as a grove

    void pine(double fx, double fy, double s) {
      final bx = rect.left + rect.width * fx;
      final by = rect.top + rect.height * fy;
      final leaf = Paint()..color = biome.forestCanopy;
      final leafD = Paint()..color = biome.forestDeep;
      for (var i = 0; i < 2; i++) {
        final y = by - i * s * 0.3;
        final w = s * (0.9 - i * 0.3);
        canvas.drawPath(
            Path()
              ..moveTo(bx, y - s * 0.5)
              ..lineTo(bx + w / 2, y)
              ..lineTo(bx - w / 2, y)
              ..close(),
            i.isEven ? leaf : leafD);
      }
    }

    // varied count/size/position per cell — no two cells identical
    final n = 1 + (_hash(r, c, 6) * 2.4).floor();
    for (var i = 0; i < n; i++) {
      pine(0.2 + _hash(r, c, 7 + i) * 0.6, 0.45 + _hash(r, c, 17 + i) * 0.4,
          tile * (0.3 + _hash(r, c, 27 + i) * 0.22));
    }
    if (_hash(r, c, 9) > 0.8) {
      // the odd broadleaf for texture
      final bx = rect.left + rect.width * (0.3 + _hash(r, c, 10) * 0.4);
      final by = rect.top + rect.height * (0.3 + _hash(r, c, 11) * 0.4);
      canvas.drawCircle(Offset(bx, by), tile * 0.14,
          Paint()..color = const Color(0xFF3A7A46));
    }
  }

  /// Mountains = a ROCK MASS: cells fuse into one range; a dark silhouette rim
  /// around the outside; ridge peaks + snow only on interior cells.
  void _mountain(Canvas canvas, Rect rect, int r, int c) {
    var neighbours = 0;
    if (_terr(r - 1, c, Terrain.mountain)) neighbours++;
    if (_terr(r + 1, c, Terrain.mountain)) neighbours++;
    if (_terr(r, c - 1, Terrain.mountain)) neighbours++;
    if (_terr(r, c + 1, Terrain.mountain)) neighbours++;
    // depth shading: range cores read higher/darker than the skirts
    final h = _hash(r, c, 30);
    final core = neighbours / 4.0;
    final lo = Color.lerp(biome.mountain, biome.mountainShade, core)!;
    canvas.drawRect(
        rect, Paint()..color = Color.lerp(lo, Colors.black, h * 0.1)!);
    // silhouette rim + foot shadow toward open ground
    final rim = Paint()
      ..color = biome.mountainShade
      ..strokeWidth = 2.2;
    if (!_terr(r - 1, c, Terrain.mountain)) {
      canvas.drawLine(rect.topLeft, rect.topRight, rim);
    }
    if (!_terr(r + 1, c, Terrain.mountain)) {
      canvas.drawLine(rect.bottomLeft, rect.bottomRight, rim);
      canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.bottom - rect.height * 0.16, rect.width,
              rect.height * 0.16),
          Paint()..color = Colors.black.withValues(alpha: 0.18));
    }
    if (!_terr(r, c - 1, Terrain.mountain)) {
      canvas.drawLine(rect.topLeft, rect.bottomLeft, rim);
    }
    if (!_terr(r, c + 1, Terrain.mountain)) {
      canvas.drawLine(rect.topRight, rect.bottomRight, rim);
    }
    if (tile < 18) return; // zoomed out: the mass IS the range

    // rocky texture streaks everywhere
    final streak = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..strokeWidth = 1.4;
    final sx = rect.left + rect.width * (0.25 + _hash(r, c, 31) * 0.5);
    canvas.drawLine(Offset(sx, rect.top + rect.height * 0.3),
        Offset(sx - rect.width * 0.15, rect.top + rect.height * 0.7), streak);
    // a FEW proud summits deep in the range — not a peak sticker per tile
    if (neighbours == 4 && _hash(r, c, 32) > 0.72) {
      final px = rect.left + rect.width * (0.35 + _hash(r, c, 33) * 0.3);
      final baseY = rect.top + rect.height * 0.82;
      final peakY = rect.top + rect.height * (0.16 + _hash(r, c, 34) * 0.12);
      final w = rect.width * 0.62;
      canvas.drawPath(
          Path()
            ..moveTo(px - w / 2, baseY)
            ..lineTo(px, peakY)
            ..lineTo(px + w / 2, baseY)
            ..close(),
          Paint()..color = biome.mountain);
      // lit face
      canvas.drawPath(
          Path()
            ..moveTo(px, peakY)
            ..lineTo(px + w / 2, baseY)
            ..lineTo(px + w * 0.12, baseY)
            ..close(),
          Paint()..color = Colors.white.withValues(alpha: 0.08));
      // snow cap
      final snowY = peakY + rect.height * 0.14;
      canvas.drawPath(
          Path()
            ..moveTo(px, peakY)
            ..lineTo(px + rect.width * 0.1, snowY)
            ..lineTo(px, snowY - rect.height * 0.03)
            ..lineTo(px - rect.width * 0.1, snowY)
            ..close(),
          Paint()..color = biome.mountainSnow);
    }
  }

  /// River = one continuous waterway: banks only where water meets land.
  void _river(Canvas canvas, Rect rect, int r, int c) {
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [biome.water, biome.waterDeep],
          ).createShader(rect));
    final bank = Paint()
      ..color = biome.bridge
      ..strokeWidth = 2.5;
    if (!_water(r - 1, c)) canvas.drawLine(rect.topLeft, rect.topRight, bank);
    if (!_water(r + 1, c)) {
      canvas.drawLine(rect.bottomLeft, rect.bottomRight, bank);
    }
    if (!_water(r, c - 1)) canvas.drawLine(rect.topLeft, rect.bottomLeft, bank);
    if (!_water(r, c + 1)) {
      canvas.drawLine(rect.topRight, rect.bottomRight, bank);
    }
    if (tile < 16) return;
    // drifting sparkle instead of stripey waves
    final glint = Paint()..color = biome.waterFoam.withValues(alpha: 0.55);
    for (var i = 0; i < 2; i++) {
      final phase = (_at * 0.6 + _hash(r, c, 40 + i)) % 1.0;
      final gx0 = rect.left + rect.width * ((_hash(r, c, 42 + i) + phase) % 1.0);
      final gy0 = rect.top + rect.height * (0.25 + 0.5 * _hash(r, c, 44 + i));
      canvas.drawCircle(Offset(gx0, gy0), tile * 0.035, glint);
      canvas.drawLine(Offset(gx0 - tile * 0.08, gy0), Offset(gx0 + tile * 0.08, gy0),
          Paint()
            ..color = biome.waterFoam.withValues(alpha: 0.25)
            ..strokeWidth = 1.2);
    }
  }

  void _bridge(Canvas canvas, Rect rect, int r, int c) {
    _river(canvas, rect, r, c); // water underneath
    // deck spans the crossing direction (water left/right → vertical deck)
    final waterSides = _water(r, c - 1) || _water(r, c + 1);
    final deck = waterSides
        ? Rect.fromLTWH(rect.left + rect.width * 0.12, rect.top,
            rect.width * 0.76, rect.height)
        : Rect.fromLTWH(rect.left, rect.top + rect.height * 0.12, rect.width,
            rect.height * 0.76);
    canvas.drawRRect(RRect.fromRectAndRadius(deck, const Radius.circular(3)),
        Paint()..color = biome.bridge);
    final plank = Paint()
      ..color = const Color(0xFF5E4429)
      ..strokeWidth = 1.6;
    for (var i = 1; i < 5; i++) {
      if (waterSides) {
        final y = rect.top + rect.height * i / 5;
        canvas.drawLine(Offset(deck.left + 2, y), Offset(deck.right - 2, y), plank);
      } else {
        final x = rect.left + rect.width * i / 5;
        canvas.drawLine(Offset(x, deck.top + 2), Offset(x, deck.bottom - 2), plank);
      }
    }
    final rail = Paint()
      ..color = const Color(0xFF8F6B42)
      ..strokeWidth = 2.4;
    if (waterSides) {
      canvas.drawLine(deck.topLeft, deck.bottomLeft, rail);
      canvas.drawLine(deck.topRight, deck.bottomRight, rail);
    } else {
      canvas.drawLine(deck.topLeft, deck.topRight, rail);
      canvas.drawLine(deck.bottomLeft, deck.bottomRight, rail);
    }
  }

  /// Fogger smoke — soft grey billows that read as forest-style concealment.
  void _smokePass(Canvas canvas) {
    if (smokeCells.isEmpty) return;
    for (final k in smokeCells) {
      final r = k ~/ base.cols, c = k % base.cols;
      if (r < _r0 || r > _r1 || c < _c0 || c > _c1) continue;
      if (!_revealed(r, c)) continue;
      final rect = _rect(r, c);
      final pulse = 0.22 + 0.06 * math.sin(_at * 2.4 + r * 0.3 + c * 0.17);
      canvas.drawCircle(
          rect.center,
          tile * 0.55,
          Paint()
            ..color = const Color(0xFFB8C0CC).withValues(alpha: pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(
          rect.center.translate(tile * 0.08, -tile * 0.06),
          tile * 0.32,
          Paint()..color = Colors.white.withValues(alpha: pulse * 0.55));
    }
  }

  /// The 4-side landing ring: soft gold glow + dashed inner frontier + inward
  /// chevrons on every side.
  void _ringPass(Canvas canvas) {
    final glow =
        Paint()..color = JarsColors.gold.withValues(alpha: 0.05 + 0.03 * math.sin(_at * 3));
    canvas.drawRect(Rect.fromLTWH(gx, gy, tile * base.cols, tile), glow);
    canvas.drawRect(
        Rect.fromLTWH(gx, gy + (base.rows - 1) * tile, tile * base.cols, tile), glow);
    canvas.drawRect(
        Rect.fromLTWH(gx, gy + tile, tile, tile * (base.rows - 2)), glow);
    canvas.drawRect(
        Rect.fromLTWH(gx + (base.cols - 1) * tile, gy + tile, tile, tile * (base.rows - 2)),
        glow);
    // dashed inner frontier
    final dash = Paint()
      ..color = JarsColors.gold.withValues(alpha: 0.5)
      ..strokeWidth = 2;
    final inner = Rect.fromLTWH(gx + tile, gy + tile, tile * (base.cols - 2),
        tile * (base.rows - 2));
    void dashLine(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var d = 0.0;
      while (d < total) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + 8, total), dash);
        d += 14;
      }
    }

    dashLine(inner.topLeft, inner.topRight);
    dashLine(inner.bottomLeft, inner.bottomRight);
    dashLine(inner.topLeft, inner.bottomLeft);
    dashLine(inner.topRight, inner.bottomRight);
    // inward chevrons, all four sides
    final chevron = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    void chev(Offset tip, Offset armA, Offset armB, double phase) {
      chevron.color = JarsColors.gold.withValues(alpha: 0.45 * (1 - phase));
      canvas.drawLine(armA, tip, chevron);
      canvas.drawLine(armB, tip, chevron);
    }

    for (var c = 1; c < base.cols - 1; c += 3) {
      final cx = gx + (c + 0.5) * tile;
      final ph = (t * 1.4 + c * 0.23) % 1.0;
      // top edge, pointing down
      var cy = gy + tile * (0.25 + ph * 0.5);
      chev(Offset(cx, cy + tile * 0.1), Offset(cx - tile * 0.14, cy),
          Offset(cx + tile * 0.14, cy), ph);
      // bottom edge, pointing up
      cy = gy + base.rows * tile - tile * (0.25 + ph * 0.5);
      chev(Offset(cx, cy - tile * 0.1), Offset(cx - tile * 0.14, cy),
          Offset(cx + tile * 0.14, cy), ph);
    }
    for (var r = 1; r < base.rows - 1; r += 3) {
      final cy = gy + (r + 0.5) * tile;
      final ph = (t * 1.4 + r * 0.31) % 1.0;
      // left edge, pointing right
      var cx = gx + tile * (0.25 + ph * 0.5);
      chev(Offset(cx + tile * 0.1, cy), Offset(cx, cy - tile * 0.14),
          Offset(cx, cy + tile * 0.14), ph);
      // right edge, pointing left
      cx = gx + base.cols * tile - tile * (0.25 + ph * 0.5);
      chev(Offset(cx - tile * 0.1, cy), Offset(cx, cy - tile * 0.14),
          Offset(cx, cy + tile * 0.14), ph);
    }
  }

  // ── structures ──────────────────────────────────────────────────────────────
  bool _isWall(int r, int c) {
    final s = base.structAt(r, c);
    return s != null && s.alive && s.type == DefType.wall;
  }

  /// Walls AND gates count for connectivity — a rampart run flows into the
  /// gate's jambs. Castles stand APART from the wall line.
  bool _wallish(int r, int c) {
    final s = base.structAt(r, c);
    return s != null &&
        s.alive &&
        (s.type == DefType.wall || s.type == DefType.gate);
  }

  void _structurePass(Canvas canvas) {
    // Fitted big boards: cheap silhouettes. Raise the bar so a 64² map
    // fitted to phone width (~8–12px/tile) never runs full path art.
    final lo = tile < 18;
    // walls first, connected into fortification lines
    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        if (_isWall(r, c) && _revealed(r, c)) {
          final s = base.structAt(r, c)!;
          if (lo) {
            _wallLo(canvas, r, c, s.level);
          } else {
            _wall(canvas, r, c, _wallish, s.hp / s.maxHp, level: s.level);
          }
        }
      }
    }
    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        if (!_revealed(r, c)) continue;
        final s = base.structAt(r, c);
        if (s == null || s.type == DefType.wall) continue;
        if (s.hp <= 0) {
          if (!lo) _rubble(canvas, _rect(r, c), r, c);
          continue;
        }
        final hideHidden = s.spec.hidden && !s.triggered && !ownBase;
        if (hideHidden) continue;
        if (lo) {
          _buildingLo(canvas, _rect(r, c), s);
        } else {
          _building(canvas, _rect(r, c), s, r, c);
        }
      }
    }
  }

  /// Zoomed-out wall stub — solid connected block, no cracks/shadows/HP.
  void _wallLo(Canvas canvas, int r, int c, int level) {
    final rect = _rect(r, c);
    final th = rect.width * 0.5;
    final stone = level >= 5
        ? const Color(0xFF1A1018)
        : level >= 4
            ? const Color(0xFF2A3040)
            : level >= 3
                ? const Color(0xFF3E4650)
                : level >= 2
                    ? const Color(0xFF636E80)
                    : const Color(0xFF808A99);
    final paint = Paint()..color = stone;
    canvas.drawRect(
        Rect.fromCenter(center: rect.center, width: th, height: th), paint);
    if (_wallish(r - 1, c)) {
      canvas.drawRect(
          Rect.fromLTRB(rect.center.dx - th / 2, rect.top, rect.center.dx + th / 2,
              rect.center.dy),
          paint);
    }
    if (_wallish(r + 1, c)) {
      canvas.drawRect(
          Rect.fromLTRB(rect.center.dx - th / 2, rect.center.dy,
              rect.center.dx + th / 2, rect.bottom),
          paint);
    }
    if (_wallish(r, c - 1)) {
      canvas.drawRect(
          Rect.fromLTRB(rect.left, rect.center.dy - th / 2, rect.center.dx,
              rect.center.dy + th / 2),
          paint);
    }
    if (_wallish(r, c + 1)) {
      canvas.drawRect(
          Rect.fromLTRB(rect.center.dx, rect.center.dy - th / 2, rect.right,
              rect.center.dy + th / 2),
          paint);
    }
  }

  /// Zoomed-out building stub — tinted chip, no path art / people / FX.
  void _buildingLo(Canvas canvas, Rect rect, Structure s) {
    final col = switch (s.type) {
      DefType.castle => const Color(0xFFB08D3E),
      DefType.archerTower ||
      DefType.cannon ||
      DefType.tesla ||
      DefType.mortar ||
      DefType.ballista ||
      DefType.pitchThrower =>
        const Color(0xFF6B7482),
      DefType.guardPost || DefType.commandTent || DefType.housing =>
        const Color(0xFFB8544A),
      DefType.gate => const Color(0xFF8F6B42),
      _ => const Color(0xFF4A5568),
    };
    final body = rect.deflate(rect.width * 0.18);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(body.width * 0.2)),
        Paint()..color = col);
    if (s.level >= 3) {
      canvas.drawCircle(
          body.topCenter.translate(0, body.height * 0.15),
          body.width * 0.12,
          Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
  }

  /// Continuous rampart segments: flat runs through the cell center toward
  /// each connected neighbour — orthogonal AND diagonal — uniform thickness,
  /// smooth rounded corners. [isWall] supplies the neighbourhood, so live
  /// boards and replay frames both get fully CONNECTED fortification lines.
  void _wall(Canvas canvas, int r, int c, bool Function(int, int) isWall,
      double hpFrac,
      {int level = 1}) {
    final rect = _rect(r, c);
    final th = rect.width * 0.46; // rampart thickness
    final cx = rect.center.dx, cy = rect.center.dy;
    final rad = Radius.circular(th * 0.32);

    bool rock(int rr, int cc) =>
        base.inBounds(rr, cc) && base.grid[rr][cc].terrain == Terrain.mountain;
    bool joins(int rr, int cc) => isWall(rr, cc) || rock(rr, cc);
    final pieces = <RRect>[
      // the hub — rounded so isolated walls and corners look clean
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: rect.center, width: th, height: th), rad),
      if (joins(r - 1, c))
        RRect.fromRectAndRadius(
            Rect.fromLTRB(cx - th / 2, rect.top, cx + th / 2, cy), rad),
      if (joins(r + 1, c))
        RRect.fromRectAndRadius(
            Rect.fromLTRB(cx - th / 2, cy, cx + th / 2, rect.bottom), rad),
      if (joins(r, c - 1))
        RRect.fromRectAndRadius(
            Rect.fromLTRB(rect.left, cy - th / 2, cx, cy + th / 2), rad),
      if (joins(r, c + 1))
        RRect.fromRectAndRadius(
            Rect.fromLTRB(cx, cy - th / 2, rect.right, cy + th / 2), rad),
    ];
    // DIAGONAL struts: bridge corner-touching wall segments (each cell draws
    // its half to the shared corner) — but only when no orthogonal neighbour
    // already carries the connection
    final diagonals = <Offset>[];
    for (final d in const [
      [-1, -1],
      [-1, 1],
      [1, -1],
      [1, 1]
    ]) {
      if (isWall(r + d[0], c + d[1]) &&
          !isWall(r + d[0], c) &&
          !isWall(r, c + d[1])) {
        diagonals.add(Offset(cx + d[1] * rect.width / 2, cy + d[0] * rect.height / 2));
      }
    }
    void strut(Paint p, Offset shift) {
      for (final corner in diagonals) {
        canvas.drawLine(rect.center + shift, corner + shift, p);
      }
    }

    // drop shadow, body, top light — three passes over the same union.
    // UPGRADED walls are cut from darker, denser stone with pale capstones.
    final stone = level >= 5
        ? const Color(0xFF1A1018) // L5: obsidian bastion
        : level >= 4
            ? const Color(0xFF2A3040) // L4: rampart slate
            : level >= 3
                ? const Color(0xFF3E4650) // L3: near-black
                : level >= 2
                    ? const Color(0xFF636E80)
                    : const Color(0xFF808A99);
    final shadowOff = Offset(0, rect.height * 0.05);
    strut(
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..strokeWidth = th * 0.9
          ..strokeCap = StrokeCap.round,
        shadowOff);
    for (final p in pieces) {
      canvas.drawRRect(p.shift(shadowOff),
          Paint()..color = Colors.black.withValues(alpha: 0.3));
    }
    strut(
        Paint()
          ..color = stone
          ..strokeWidth = th * 0.9
          ..strokeCap = StrokeCap.round,
        Offset.zero);
    for (final p in pieces) {
      canvas.drawRRect(p, Paint()..color = stone);
    }
    if (level >= 2) {
      // pale capstones dress the crest — quarried, not painted
      final cap = Paint()..color = const Color(0xFFAEB9C8);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(cx, cy - th * 0.34),
                  width: th * 0.62,
                  height: th * 0.16),
              Radius.circular(th * 0.08)),
          cap);
      canvas.drawCircle(Offset(cx - th * 0.3, cy - th * 0.1), th * 0.05, cap);
      canvas.drawCircle(Offset(cx + th * 0.28, cy + th * 0.16), th * 0.05, cap);
    }
    if (level >= 3) {
      // spiked crest — iron teeth along the top edge
      final spike = Paint()..color = const Color(0xFFB8C0CC);
      for (final dx in const [-0.28, 0.0, 0.28]) {
        final tip = Offset(cx + th * dx, cy - th * 0.52);
        canvas.drawPath(
            Path()
              ..moveTo(tip.dx - th * 0.06, tip.dy + th * 0.14)
              ..lineTo(tip.dx, tip.dy)
              ..lineTo(tip.dx + th * 0.06, tip.dy + th * 0.14)
              ..close(),
            spike);
      }
    }
    if (level >= 4) {
      // rampart silhouette — thicker outer band + merlon nubs
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: rect.center, width: th * 1.18, height: th * 1.18),
              Radius.circular(th * 0.28)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = th * 0.12
            ..color = const Color(0xFF9AA6B8).withValues(alpha: 0.55));
      final merlon = Paint()..color = const Color(0xFFC4CDD8).withValues(alpha: 0.7);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(cx - th * 0.22, cy - th * 0.42),
              width: th * 0.14,
              height: th * 0.12),
          merlon);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(cx + th * 0.22, cy - th * 0.42),
              width: th * 0.14,
              height: th * 0.12),
          merlon);
    }
    if (level >= 5) {
      // obsidian bastion — violet sheen + hard edge highlight
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: rect.center, width: th * 0.9, height: th * 0.9),
              rad),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = const Color(0xFF7B5CFF).withValues(alpha: 0.45));
      canvas.drawCircle(
          Offset(cx + th * 0.18, cy - th * 0.18),
          th * 0.08,
          Paint()..color = const Color(0xFFE8DEFF).withValues(alpha: 0.35));
    }
    strut(
        Paint()
          ..color = Colors.white.withValues(alpha: 0.1)
          ..strokeWidth = th * 0.35
          ..strokeCap = StrokeCap.round,
        Offset(0, -th * 0.18));
    final light = Paint()..color = Colors.white.withValues(alpha: 0.13);
    for (final p in pieces) {
      final b = p.outerRect;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(b.left, b.top, b.width, b.height * 0.3), rad),
          light);
    }
    // sparse stone seams
    final seam = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    if (_hash(r, c, 60) > 0.35) {
      canvas.drawLine(Offset(cx - th * 0.25, cy - th * 0.15),
          Offset(cx + th * 0.1, cy - th * 0.15), seam);
      canvas.drawLine(Offset(cx - th * 0.05, cy + th * 0.2),
          Offset(cx + th * 0.3, cy + th * 0.2), seam);
    }
    // battle damage: cracks spread as the wall weakens (66% / 33%)
    if (hpFrac < 0.66) {
      final crack = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withValues(alpha: 0.55);
      final j = _hash(r, c, 61) * th * 0.2;
      canvas.drawPath(
          Path()
            ..moveTo(cx - th * 0.3 + j, cy - th * 0.42)
            ..lineTo(cx - th * 0.08, cy - th * 0.05 + j)
            ..lineTo(cx - th * 0.25 + j, cy + th * 0.32),
          crack);
      if (hpFrac < 0.33) {
        canvas.drawPath(
            Path()
              ..moveTo(cx + th * 0.35, cy - th * 0.3 + j)
              ..lineTo(cx + th * 0.08 + j, cy + th * 0.05)
              ..lineTo(cx + th * 0.3, cy + th * 0.42 - j),
            crack);
        // chipped shoulder
        canvas.drawCircle(Offset(cx + th * 0.4, cy - th * 0.42), th * 0.13,
            Paint()..color = Colors.black.withValues(alpha: 0.22));
      }
    }
    _hpBar(canvas, rect, hpFrac);
  }

  /// Painted structure art — no emoji buildings.
  void _building(Canvas canvas, Rect rect, Structure s, int r, int c) {
    switch (s.type) {
      case DefType.castle:
        _castleArt(canvas, rect);
        break;
      case DefType.archerTower:
        _archerTowerArt(canvas, rect, s.level);
        break;
      case DefType.cannon:
        _cannonArt(canvas, rect, s.aimAngle, s.level);
        break;
      case DefType.tesla:
        _teslaArt(canvas, rect, s.level);
        break;
      case DefType.guardPost:
        _guardPostArt(canvas, rect, s.level);
        break;
      case DefType.landmine:
        _mineArt(canvas, rect);
        break;
      case DefType.barbedWire:
        _wireArt(canvas, rect, r, c);
        break;
      case DefType.mortar:
        _mortarArt(canvas, rect, s.level);
        break;
      case DefType.gate:
        _gateArt(canvas, rect, r, c, s.level);
        break;
      case DefType.housing:
        _housingArt(canvas, rect, r, c);
        break;
      case DefType.pitchThrower:
        _pitchArt(canvas, rect);
        break;
      case DefType.banner:
        _warBannerArt(canvas, rect);
        break;
      case DefType.ballista:
        _ballistaArt(canvas, rect, s.aimAngle, s.level);
        break;
      case DefType.watchtower:
        _watchtowerArt(canvas, rect);
        break;
      case DefType.storehouse:
        _storehouseArt(canvas, rect);
        break;
      case DefType.tributeChest:
        _tributeChestArt(canvas, rect);
        break;
      case DefType.commandTent:
        _commandTentArt(canvas, rect);
        break;
      case DefType.pitchPot:
        _pitchPotArt(canvas, rect);
        break;
      case DefType.citadelCore:
        _citadelCoreArt(canvas, rect);
        break;
      case DefType.warGenerator:
        _warGeneratorArt(canvas, rect, s.level);
        break;
      case DefType.wall:
        break; // painted in the wall pass
    }
    // stealth shimmer on hidden pieces you own
    if (s.spec.hidden && ownBase) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(2), Radius.circular(tile * 0.18)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.14 + 0.1 * math.sin(_at * 3)));
    }
    // a badly wounded building BURNS
    if (s.hp / s.maxHp < 0.4 &&
        s.type != DefType.landmine &&
        s.type != DefType.barbedWire) {
      _burnFx(canvas, rect, r, c, s.hp / s.maxHp);
    }
    _hpBar(canvas, rect, s.hp / s.maxHp);
  }

  void _shadow(Canvas canvas, Rect rect, {double w = 0.66, double y = 0.86}) {
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(rect.center.dx, rect.top + rect.height * y),
            width: rect.width * w,
            height: rect.height * 0.16),
        Paint()..color = Colors.black.withValues(alpha: 0.35));
  }

  void _castleArt(Canvas canvas, Rect rect) {
    _shadow(canvas, rect, w: 0.85, y: 0.9);
    const stone = Color(0xFF8A93A3);
    const stoneD = Color(0xFF6C7482);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    // corner towers
    for (final dx in [-w * 0.3, w * 0.3]) {
      final tr = Rect.fromCenter(
          center: Offset(cx + dx, rect.top + h * 0.52), width: w * 0.22, height: h * 0.62);
      canvas.drawRect(tr, Paint()..color = stoneD);
      for (var i = 0; i < 2; i++) {
        canvas.drawRect(
            Rect.fromLTWH(tr.left + i * tr.width * 0.55, tr.top - h * 0.07,
                tr.width * 0.4, h * 0.08),
            Paint()..color = stoneD);
      }
    }
    // keep body
    final body = Rect.fromCenter(
        center: Offset(cx, rect.top + h * 0.6), width: w * 0.52, height: h * 0.5);
    canvas.drawRect(body, Paint()..color = stone);
    canvas.drawRect(
        Rect.fromLTWH(body.left, body.top, body.width, body.height * 0.2),
        Paint()..color = Colors.white.withValues(alpha: 0.12));
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
          Rect.fromLTWH(body.left + i * body.width * 0.38, body.top - h * 0.07,
              body.width * 0.24, h * 0.08),
          Paint()..color = stone);
    }
    // gate
    final gate = Rect.fromCenter(
        center: Offset(cx, body.bottom - h * 0.11), width: w * 0.16, height: h * 0.22);
    canvas.drawRRect(
        RRect.fromRectAndCorners(gate,
            topLeft: Radius.circular(w * 0.08), topRight: Radius.circular(w * 0.08)),
        Paint()..color = const Color(0xFF2A2118));
    // waving banner
    final poleTop = Offset(cx, rect.top + h * 0.06);
    canvas.drawLine(poleTop, Offset(cx, body.top - h * 0.06),
        Paint()
          ..color = Colors.white70
          ..strokeWidth = 1.6);
    final sway = math.sin(_at * 4) * w * 0.05;
    final flag = Path()
      ..moveTo(poleTop.dx, poleTop.dy)
      ..quadraticBezierTo(poleTop.dx + w * 0.14 + sway, poleTop.dy + h * 0.04,
          poleTop.dx + w * 0.26 + sway, poleTop.dy + h * 0.02)
      ..lineTo(poleTop.dx + w * 0.24 + sway, poleTop.dy + h * 0.12)
      ..quadraticBezierTo(
          poleTop.dx + w * 0.12, poleTop.dy + h * 0.13, poleTop.dx, poleTop.dy + h * 0.11)
      ..close();
    canvas.drawPath(flag, Paint()..color = JarsColors.gold);
  }

  void _archerTowerArt(Canvas canvas, Rect rect, [int level = 1]) {
    _shadow(canvas, rect);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final up = level >= 2;
    final elite = level >= 3;
    final apex = level >= 4;
    final mythic = level >= 5;
    // veterans hold a TALLER tower of darker cut stone; L5 is near-obsidian
    final stone = mythic
        ? const Color(0xFF1A1018)
        : apex
            ? const Color(0xFF2A3040)
            : elite
                ? const Color(0xFF59626F)
                : up
                    ? const Color(0xFF6B7688)
                    : const Color(0xFF7E8798);
    final trim = mythic
        ? const Color(0xFF7B5CFF)
        : apex
            ? const Color(0xFF9AA6B8)
            : up
                ? const Color(0xFF565F6E)
                : const Color(0xFF69707E);
    final topY = rect.top + (mythic
        ? h * 0.16
        : apex
            ? h * 0.2
            : up
                ? h * 0.24
                : h * 0.3);
    final body = Path()
      ..moveTo(cx - w * (apex ? 0.22 : 0.2), rect.top + h * 0.82)
      ..lineTo(cx - w * (apex ? 0.15 : 0.14), topY)
      ..lineTo(cx + w * (apex ? 0.15 : 0.14), topY)
      ..lineTo(cx + w * (apex ? 0.22 : 0.2), rect.top + h * 0.82)
      ..close();
    canvas.drawPath(body, Paint()..color = stone);
    if (up) {
      // banded masonry — the upgrade is in the STONEWORK
      final bandP = Paint()
        ..color = mythic ? const Color(0xFF4A3A6A) : const Color(0xFF59626F)
        ..strokeWidth = 1.3;
      for (var i = 1; i <= (apex ? 3 : 2); i++) {
        final y = rect.top + h * (0.38 + i * 0.12);
        canvas.drawLine(Offset(cx - w * 0.165, y), Offset(cx + w * 0.165, y), bandP);
      }
    }
    final plat = Rect.fromCenter(
        center: Offset(cx, topY - h * 0.02),
        width: w * (apex ? 0.54 : (up ? 0.48 : 0.42)),
        height: h * 0.1);
    canvas.drawRect(plat, Paint()..color = trim);
    final merlons = apex ? 5 : (up ? 4 : 3);
    for (var i = 0; i < merlons; i++) {
      canvas.drawRect(
          Rect.fromLTWH(plat.left + i * plat.width / merlons * 1.06,
              plat.top - h * 0.06, plat.width / merlons * 0.62, h * 0.06),
          Paint()..color = trim);
      if (elite) {
        // gilded / violet merlon caps
        canvas.drawRect(
            Rect.fromLTWH(plat.left + i * plat.width / merlons * 1.06,
                plat.top - h * 0.075, plat.width / merlons * 0.62, h * 0.02),
            Paint()
              ..color = mythic
                  ? const Color(0xFFE8DEFF)
                  : const Color(0xFFB08D3E));
      }
    }
    if (mythic) {
      // obsidian halo — reads across the map
      canvas.drawCircle(
          Offset(cx, topY),
          w * 0.28,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = const Color(0xFF7B5CFF).withValues(alpha: 0.55));
    }
    if (up) {
      // a red war pennant flies from the parapet
      final poleX = plat.right - w * 0.02;
      canvas.drawLine(Offset(poleX, plat.top - h * 0.05),
          Offset(poleX, plat.top - h * 0.2),
          Paint()
            ..color = const Color(0xFF8F6B42)
            ..strokeWidth = 1.4);
      final flap = math.sin(_at * 5 + poleX) * w * 0.02;
      canvas.drawPath(
          Path()
            ..moveTo(poleX, plat.top - h * 0.2)
            ..lineTo(poleX + w * 0.12, plat.top - h * 0.17 + flap)
            ..lineTo(poleX, plat.top - h * 0.13)
            ..close(),
          Paint()
            ..color = mythic
                ? const Color(0xFFB07BFF)
                : const Color(0xFFB8443C));
    }
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(cx, rect.top + h * 0.55), width: w * 0.045, height: h * 0.2),
        Paint()..color = const Color(0xFF1C212B));
    // the archer on the platform — skip when zoomed out (LOD)
    if (!_hiDetail) return;
    final headC = Offset(cx - w * 0.03, plat.top - h * 0.1);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: headC.translate(0, h * 0.065), width: w * 0.11, height: h * 0.1),
            Radius.circular(w * 0.03)),
        Paint()..color = const Color(0xFF2F5138)); // cloak
    canvas.drawCircle(headC, w * 0.042, Paint()..color = const Color(0xFF3A6647));
    canvas.drawCircle(headC.translate(w * 0.01, 0), w * 0.022,
        Paint()..color = const Color(0xFFE9C39A)); // face under the hood
    final bowC = Offset(cx + w * 0.09, plat.top - h * 0.065);
    canvas.drawArc(
        Rect.fromCircle(center: bowC, radius: w * 0.065),
        -math.pi / 2,
        math.pi,
        false,
        Paint()
          ..color = const Color(0xFF8F6B42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7);
    canvas.drawLine(bowC.translate(0, -w * 0.065), bowC.translate(0, w * 0.065),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..strokeWidth = 1);
  }

  /// Top-down CoC-style cannon: round base plate with bolts + a slowly
  /// sweeping barrel.
  void _cannonArt(Canvas canvas, Rect rect, [double? aim, int level = 1]) {
    _shadow(canvas, rect, w: 0.6, y: 0.78);
    final w = rect.width;
    final c = rect.center;
    final up = level >= 2;
    final apex = level >= 4;
    final mythic = level >= 5;
    // base plate — the veteran gun sits on a heavier, darker mount
    final plate = mythic
        ? const Color(0xFF1A1018)
        : apex
            ? const Color(0xFF252A35)
            : up
                ? const Color(0xFF31363F)
                : const Color(0xFF3A3F49);
    canvas.drawCircle(c, w * (mythic ? 0.36 : (up ? 0.33 : 0.3)),
        Paint()..color = plate);
    canvas.drawCircle(
        c,
        w * (mythic ? 0.36 : (up ? 0.33 : 0.3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = mythic ? 2.6 : (up ? 2.2 : 1.6)
          ..color = mythic
              ? const Color(0xFF7B5CFF)
              : const Color(0xFF1E232B));
    // bolts (rivets double up on the reinforced mount)
    final bolt = Paint()
      ..color = mythic ? const Color(0xFFE8DEFF) : const Color(0xFF6B7482);
    final nBolts = mythic ? 10 : (up ? 8 : 6);
    for (var i = 0; i < nBolts; i++) {
      final a = i * math.pi * 2 / nBolts;
      canvas.drawCircle(
          c + Offset(math.cos(a), math.sin(a)) * w * (up ? 0.27 : 0.24),
          w * 0.025,
          bolt);
    }
    // the barrel FACES its last target; with no target it idly scans
    final ang = aim ??
        math.pi / 2 + math.sin(_at * 0.8 + c.dx * 0.01) * (_hiDetail ? 0.7 : 0);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(ang);
    final barLen = w * (mythic ? 0.5 : (apex ? 0.46 : (up ? 0.43 : 0.4)));
    final barrel = RRect.fromRectAndRadius(
        Rect.fromLTWH(-w * 0.07, -w * 0.06, barLen, w * 0.12),
        Radius.circular(w * 0.05));
    canvas.drawRRect(
        barrel,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: mythic
                ? const [Color(0xFF3A2A55), Color(0xFF120818)]
                : up
                    ? const [Color(0xFF3A4450), Color(0xFF161B22)]
                    : const [Color(0xFF454D58), Color(0xFF20262E)],
          ).createShader(barrel.outerRect));
    if (up) {
      // brass / violet reinforcing rings along the tube
      final brass = Paint()
        ..color = mythic ? const Color(0xFFB07BFF) : const Color(0xFFB08D3E)
        ..strokeWidth = w * 0.028;
      for (final fx in (apex ? const [0.1, 0.2, 0.3] : const [0.12, 0.24])) {
        canvas.drawLine(Offset(w * fx, -w * 0.06), Offset(w * fx, w * 0.06), brass);
      }
    }
    // muzzle ring
    canvas.drawCircle(Offset(barLen - w * 0.07, 0), w * 0.07,
        Paint()..color = const Color(0xFF14181E));
    if (up) {
      canvas.drawCircle(
          Offset(barLen - w * 0.07, 0),
          w * 0.07,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = mythic
                ? const Color(0xFFE8DEFF)
                : const Color(0xFFB08D3E));
    }
    canvas.restore();
    // pivot cap
    canvas.drawCircle(c, w * 0.1, Paint()..color = const Color(0xFF262C35));
    canvas.drawCircle(c, w * 0.05,
        Paint()
          ..color = mythic
              ? const Color(0xFF7B5CFF)
              : up
                  ? const Color(0xFFB08D3E)
                  : const Color(0xFF6B7482));
  }

  void _teslaArt(Canvas canvas, Rect rect, [int level = 1]) {
    _shadow(canvas, rect, w: 0.5);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final up = level >= 2;
    final plinth = Path()
      ..moveTo(cx - w * 0.2, rect.top + h * 0.84)
      ..lineTo(cx - w * 0.1, rect.top + h * 0.62)
      ..lineTo(cx + w * 0.1, rect.top + h * 0.62)
      ..lineTo(cx + w * 0.2, rect.top + h * 0.84)
      ..close();
    canvas.drawPath(plinth,
        Paint()..color = up ? const Color(0xFF31363F) : const Color(0xFF3A4048));
    final mastTop = rect.top + (up ? h * 0.26 : h * 0.32);
    canvas.drawLine(Offset(cx, rect.top + h * 0.62), Offset(cx, mastTop),
        Paint()
          ..color = const Color(0xFF6B7482)
          ..strokeWidth = up ? 3.0 : 2.4);
    if (up) {
      // twin coil discs on the mast — MORE machine, more menace
      final disc = Paint()..color = const Color(0xFF525C6B);
      for (final fy in const [0.5, 0.42]) {
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(cx, rect.top + h * fy),
                width: w * 0.24,
                height: h * 0.05),
            disc);
      }
    }
    final orb = Offset(cx, mastTop - h * 0.06);
    final pulse = 0.75 + 0.25 * math.sin(_at * 6);
    canvas.drawCircle(
        orb,
        w * (up ? 0.26 : 0.2),
        Paint()
          ..color = const Color(0xFF57D9FF).withValues(alpha: 0.22 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(orb, w * (up ? 0.13 : 0.1),
        Paint()..color = const Color(0xFFB9EFFF).withValues(alpha: pulse));
    final arc = Paint()
      ..color = const Color(0xFF7FE3FF).withValues(alpha: 0.5 + 0.4 * math.sin(_at * 9))
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var k = 0; k < (up ? 3 : 2); k++) {
      final dir = k == 0 ? 1.0 : (k == 1 ? -1.0 : 0.4);
      final path = Path()..moveTo(orb.dx, orb.dy);
      var p = orb;
      for (var i = 1; i <= 3; i++) {
        p = Offset(
            orb.dx + dir * w * 0.09 * i + math.sin(_at * 11 + i + k * 3) * w * 0.05,
            orb.dy + h * 0.07 * i);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, arc);
    }
  }

  /// Barracks quarters: a stout cottage — plank walls, pitched roof, smoking
  /// chimney. Guard posts nearby field a second defender.
  void _housingArt(Canvas canvas, Rect rect, [int r = 0, int c = 0]) {
    _shadow(canvas, rect, w: 0.66);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final variant = (_hash(r, c, 140) * 3).floor().clamp(0, 2);
    if (variant == 1) {
      _longhouseArt(canvas, rect);
      return;
    }
    if (variant == 2) {
      _roundHutArt(canvas, rect);
      return;
    }
    // variant 0: the cottage — walls
    final bodyR = Rect.fromLTWH(
        cx - w * 0.26, rect.top + h * 0.46, w * 0.52, h * 0.34);
    canvas.drawRect(bodyR, Paint()..color = const Color(0xFF9A7E58));
    // plank seams
    final seamP = Paint()
      ..color = const Color(0xFF7A6244)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final y = bodyR.top + bodyR.height * i / 3;
      canvas.drawLine(Offset(bodyR.left, y), Offset(bodyR.right, y), seamP);
    }
    // pitched roof
    canvas.drawPath(
        Path()
          ..moveTo(cx - w * 0.32, rect.top + h * 0.46)
          ..lineTo(cx, rect.top + h * 0.2)
          ..lineTo(cx + w * 0.32, rect.top + h * 0.46)
          ..close(),
        Paint()..color = const Color(0xFF6E4A38));
    // door + window
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - w * 0.06, bodyR.bottom - h * 0.18, w * 0.12,
                h * 0.18),
            Radius.circular(w * 0.03)),
        Paint()..color = const Color(0xFF3B2C1A));
    canvas.drawRect(
        Rect.fromLTWH(cx + w * 0.1, bodyR.top + h * 0.06, w * 0.09, h * 0.08),
        Paint()..color = const Color(0xFFE9DFA8));
    // chimney + drifting smoke
    canvas.drawRect(
        Rect.fromLTWH(cx + w * 0.14, rect.top + h * 0.22, w * 0.07, h * 0.14),
        Paint()..color = const Color(0xFF565E6A));
    for (var i = 0; i < 2; i++) {
      final ph = (_at * 0.3 + i * 0.5) % 1.0;
      canvas.drawCircle(
          Offset(cx + w * 0.18 + math.sin(_at + i * 2) * w * 0.03,
              rect.top + h * 0.18 - ph * h * 0.3),
          w * (0.03 + ph * 0.035),
          Paint()
            ..color = const Color(0xFFB9C0CB).withValues(alpha: 0.4 * (1 - ph)));
    }
  }

  /// Level 1: a scout's tent. Level 2 (upgraded): a war pavilion — taller,
  /// red-striped canvas, a pennant snapping at the pole.
  void _guardPostArt(Canvas canvas, Rect rect, [int level = 1]) {
    _shadow(canvas, rect, w: 0.7);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final up = level >= 2;
    final peak = up ? 0.18 : 0.3;
    final span = up ? 0.34 : 0.28;
    final tent = Path()
      ..moveTo(cx - w * span, rect.top + h * 0.78)
      ..lineTo(cx, rect.top + h * peak)
      ..lineTo(cx + w * span, rect.top + h * 0.78)
      ..close();
    canvas.drawPath(
        tent,
        Paint()
          ..color =
              up ? const Color(0xFFB8544A) : const Color(0xFFC9B08A));
    if (up) {
      // pavilion stripes
      final stripe = Paint()..color = const Color(0xFFE8DCC4);
      for (var i = -1; i <= 1; i++) {
        canvas.drawPath(
            Path()
              ..moveTo(cx + w * 0.12 * i, rect.top + h * 0.78)
              ..lineTo(cx + w * 0.03 * i, rect.top + h * (peak + 0.12))
              ..lineTo(cx + w * (0.03 * i + 0.045), rect.top + h * (peak + 0.14))
              ..lineTo(cx + w * (0.12 * i + 0.05), rect.top + h * 0.78)
              ..close(),
            stripe);
      }
    }
    canvas.drawPath(
        Path()
          ..moveTo(cx - w * 0.1, rect.top + h * 0.78)
          ..lineTo(cx, rect.top + h * (up ? 0.44 : 0.5))
          ..lineTo(cx + w * 0.1, rect.top + h * 0.78)
          ..close(),
        Paint()..color = const Color(0xFF5E4A30));
    canvas.drawLine(
        Offset(cx, rect.top + h * peak),
        Offset(cx, rect.top + h * (peak - 0.1)),
        Paint()
          ..color = const Color(0xFF8F6B42)
          ..strokeWidth = 1.6);
    if (level >= 3) {
      // the WATCH CAMP: a ring of sharpened palisade stakes
      final stake = Paint()
        ..color = level >= 5
            ? const Color(0xFF2A1830)
            : const Color(0xFF6B4E2E)
        ..strokeWidth = w * (level >= 4 ? 0.055 : 0.045)
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < (level >= 4 ? 8 : 6); i++) {
        final a = i * math.pi / (level >= 4 ? 4 : 3) + 0.3;
        final sx = cx + math.cos(a) * w * 0.4;
        final sy = rect.top + h * 0.55 + math.sin(a) * h * 0.28;
        canvas.drawLine(
            Offset(sx, sy + h * 0.08), Offset(sx, sy - h * 0.06), stake);
        canvas.drawCircle(Offset(sx, sy - h * 0.07), w * 0.02,
            Paint()
              ..color = level >= 5
                  ? const Color(0xFF7B5CFF)
                  : const Color(0xFF4E3920));
      }
    }
    if (level >= 5) {
      // command pavilion glow
      canvas.drawCircle(
          Offset(cx, rect.top + h * peak),
          w * 0.22,
          Paint()
            ..color = const Color(0xFF7B5CFF).withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    if (up) {
      // snapping pennant
      final flap = math.sin(_at * 6) * w * 0.03;
      canvas.drawPath(
          Path()
            ..moveTo(cx, rect.top + h * (peak - 0.1))
            ..lineTo(cx + w * 0.16, rect.top + h * (peak - 0.07) + flap)
            ..lineTo(cx, rect.top + h * (peak - 0.03))
            ..close(),
          Paint()..color = const Color(0xFFFFD34D));
    }
    final fire = Offset(cx + w * 0.3, rect.top + h * 0.8);
    final flick = 0.7 + 0.3 * math.sin(_at * 12);
    canvas.drawCircle(fire, w * 0.07,
        Paint()..color = const Color(0xFFFF8A3D).withValues(alpha: flick));
    canvas.drawCircle(fire.translate(0, -h * 0.03), w * 0.04,
        Paint()..color = const Color(0xFFFFD34D).withValues(alpha: flick));
  }

  void _mineArt(Canvas canvas, Rect rect) {
    final w = rect.width;
    final c = rect.center;
    canvas.drawCircle(c, w * 0.2, Paint()..color = const Color(0xFF2E3037));
    canvas.drawCircle(
        c,
        w * 0.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF15171C));
    final seam = Paint()
      ..color = const Color(0xFF15171C)
      ..strokeWidth = 1;
    canvas.drawLine(c - Offset(w * 0.14, 0), c + Offset(w * 0.14, 0), seam);
    canvas.drawLine(c - Offset(0, w * 0.14), c + Offset(0, w * 0.14), seam);
    final blink = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(_at * 5)).clamp(0.0, 1.0);
    canvas.drawCircle(c, w * 0.045,
        Paint()..color = const Color(0xFFFF3D55).withValues(alpha: blink));
  }

  /// Barbed wire connects intelligently: strands run edge-to-edge toward
  /// neighbouring wire cells; posts stand only at the free ends of a run.
  /// [at] overrides the neighbourhood source (replay frames pass their own).
  void _wireArt(Canvas canvas, Rect rect, int r, int c,
      {bool Function(int, int)? at}) {
    bool wireAt(int rr, int cc) {
      if (at != null) return at(rr, cc);
      final s = base.structAt(rr, cc);
      return s != null && s.alive && s.type == DefType.barbedWire;
    }

    final w = rect.width, h = rect.height;
    final left = wireAt(r, c - 1),
        right = wireAt(r, c + 1),
        up = wireAt(r - 1, c),
        down = wireAt(r + 1, c);
    final wire = Paint()
      ..color = const Color(0xFF9AA2AE)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final post = Paint()..color = const Color(0xFF5E4429);

    void hRun(double x0, double x1) {
      for (var strand = 0; strand < 2; strand++) {
        final yBase = rect.top + h * (0.42 + strand * 0.18);
        final path = Path()..moveTo(x0, yBase);
        const seg = 8;
        for (var i = 1; i <= seg; i++) {
          final x = x0 + (x1 - x0) * i / seg;
          path.lineTo(x, yBase + (i.isEven ? -h * 0.05 : h * 0.05));
        }
        canvas.drawPath(path, wire);
      }
      for (var i = 0; i < 3; i++) {
        final x = x0 + (x1 - x0) * (0.25 + i * 0.25);
        final y = rect.top + h * (i.isEven ? 0.42 : 0.6);
        canvas.drawLine(Offset(x - 2, y - 2), Offset(x + 2, y + 2), wire);
        canvas.drawLine(Offset(x - 2, y + 2), Offset(x + 2, y - 2), wire);
      }
    }

    void vRun(double y0, double y1) {
      for (var strand = 0; strand < 2; strand++) {
        final xBase = rect.left + w * (0.42 + strand * 0.18);
        final path = Path()..moveTo(xBase, y0);
        const seg = 8;
        for (var i = 1; i <= seg; i++) {
          final y = y0 + (y1 - y0) * i / seg;
          path.lineTo(xBase + (i.isEven ? -w * 0.05 : w * 0.05), y);
        }
        canvas.drawPath(path, wire);
      }
    }

    // DIAGONAL strands: like the walls, corner-touching wire links up too
    // (each cell draws its half toward the shared corner)
    void dRun(int dr, int dc) {
      final corner = Offset(
          rect.center.dx + dc * w / 2, rect.center.dy + dr * h / 2);
      for (var strand = 0; strand < 2; strand++) {
        final off = Offset(-dr * w * 0.06, dc * h * 0.06) * (strand - 0.5) * 2;
        final a = rect.center + off, b = corner + off;
        final path = Path()..moveTo(a.dx, a.dy);
        const seg = 5;
        for (var i = 1; i <= seg; i++) {
          final p = Offset.lerp(a, b, i / seg)!;
          final jag = i.isEven ? w * 0.04 : -w * 0.04;
          path.lineTo(p.dx + jag * -dr, p.dy + jag * dc);
        }
        canvas.drawPath(path, wire);
      }
      final x = Offset.lerp(rect.center, corner, 0.55)!;
      canvas.drawLine(x - const Offset(2, 2), x + const Offset(2, 2), wire);
      canvas.drawLine(
          Offset(x.dx - 2, x.dy + 2), Offset(x.dx + 2, x.dy - 2), wire);
    }

    var diag = false;
    for (final d in const [
      [-1, -1],
      [-1, 1],
      [1, -1],
      [1, 1]
    ]) {
      if (wireAt(r + d[0], c + d[1]) &&
          !wireAt(r + d[0], c) &&
          !wireAt(r, c + d[1])) {
        dRun(d[0], d[1]);
        diag = true;
      }
    }

    final horizontal = left || right || (!up && !down && !diag);
    if (horizontal) {
      final x0 = left ? rect.left : rect.left + w * 0.16;
      final x1 = right ? rect.right : rect.right - w * 0.16;
      hRun(x0, x1);
      if (!left) {
        canvas.drawRect(
            Rect.fromLTWH(rect.left + w * 0.12, rect.top + h * 0.3, w * 0.05, h * 0.42),
            post);
      }
      if (!right) {
        canvas.drawRect(
            Rect.fromLTWH(rect.right - w * 0.17, rect.top + h * 0.3, w * 0.05, h * 0.42),
            post);
      }
    }
    if (up || down) {
      final y0 = up ? rect.top : rect.top + h * 0.16;
      final y1 = down ? rect.bottom : rect.bottom - h * 0.16;
      vRun(y0, y1);
      if (!up) {
        canvas.drawRect(
            Rect.fromLTWH(rect.left + w * 0.3, rect.top + h * 0.12, w * 0.42, h * 0.05),
            post);
      }
      if (!down) {
        canvas.drawRect(
            Rect.fromLTWH(rect.left + w * 0.3, rect.bottom - h * 0.17, w * 0.42, h * 0.05),
            post);
      }
    }
    if (diag && !left && !right && !up && !down) {
      // lone diagonal joint gets a post at its center
      canvas.drawRect(
          Rect.fromLTWH(rect.center.dx - w * 0.025, rect.top + h * 0.3,
              w * 0.05, h * 0.42),
          post);
    }
  }

  /// Mortar as MACHINERY: bolted steel base plate, one wide stubby tube on a
  /// pivot yoke, recoil spade at the back, two shells racked beside it.
  void _mortarArt(Canvas canvas, Rect rect, [int level = 1]) {
    _shadow(canvas, rect, w: 0.72, y: 0.84);
    final w = rect.width;
    final c = rect.center;
    final up = level >= 2;
    // rectangular steel base plate (the L3 monster sits on a wider bed)
    final plate = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: c.translate(0, w * 0.1),
            width: w * (level >= 3 ? 0.7 : 0.62),
            height: w * (level >= 3 ? 0.48 : 0.42)),
        Radius.circular(w * 0.06));
    canvas.drawRRect(
        plate,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3C444F), Color(0xFF232932)],
          ).createShader(plate.outerRect));
    canvas.drawRRect(
        plate,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF11151B));
    // corner bolts
    final boltP = Paint()..color = const Color(0xFF7E8794);
    for (final d in const [
      Offset(-0.24, -0.06),
      Offset(0.24, -0.06),
      Offset(-0.24, 0.24),
      Offset(0.24, 0.24)
    ]) {
      canvas.drawCircle(c + d * w, w * 0.028, boltP);
    }
    if (up) {
      // welded corner gussets — the plate is REINFORCED
      final gusset = Paint()..color = const Color(0xFF262C35);
      for (final d in const [Offset(-0.27, 0.24), Offset(0.27, 0.24)]) {
        canvas.drawRect(
            Rect.fromCenter(
                center: c + d * w, width: w * 0.09, height: w * 0.12),
            gusset);
      }
    }
    // recoil spade dug in at the back
    final spade = Path()
      ..moveTo(c.dx - w * 0.1, c.dy + w * 0.3)
      ..lineTo(c.dx + w * 0.1, c.dy + w * 0.3)
      ..lineTo(c.dx + w * 0.05, c.dy + w * 0.42)
      ..lineTo(c.dx - w * 0.05, c.dy + w * 0.42)
      ..close();
    canvas.drawPath(spade, Paint()..color = const Color(0xFF1A1F26));
    // pivot yoke (two arms holding the tube)
    final yokeP = Paint()
      ..color = const Color(0xFF515B68)
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c.translate(-w * 0.16, w * 0.12),
        c.translate(-w * 0.07, -w * 0.05), yokeP);
    canvas.drawLine(c.translate(w * 0.16, w * 0.12),
        c.translate(w * 0.07, -w * 0.05), yokeP);
    // the WIDE stubby tube, angled skyward — recoil-breathes on reload
    final breathe = 1 + math.sin(_at * 2.2) * 0.025;
    canvas.save();
    canvas.translate(c.dx, c.dy + w * 0.02);
    canvas.rotate(-0.34);
    canvas.scale(breathe);
    final tubeW = up ? w * 0.31 : w * 0.27;
    final tube = RRect.fromRectAndRadius(
        Rect.fromLTWH(-tubeW / 2, -w * 0.34, tubeW, w * 0.4),
        Radius.circular(w * 0.07));
    canvas.drawRRect(
        tube,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF4A525E), Color(0xFF1E242C)],
          ).createShader(tube.outerRect));
    // reinforcing bands (veterans wear brass; the L3 wears TWO girdles)
    canvas.drawRect(Rect.fromLTWH(-tubeW / 2, -w * 0.14, tubeW, w * 0.04),
        Paint()
          ..color = up ? const Color(0xFFB08D3E) : const Color(0xFF161B22));
    canvas.drawRect(Rect.fromLTWH(-tubeW / 2, -w * 0.26, tubeW, w * 0.03),
        Paint()
          ..color = level >= 3
              ? const Color(0xFFB08D3E)
              : const Color(0xFF161B22));
    // gaping muzzle
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, -w * 0.34), width: w * 0.25, height: w * 0.1),
        Paint()..color = const Color(0xFF0C0F14));
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, -w * 0.34), width: w * 0.25, height: w * 0.1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFF5A6270));
    canvas.restore();
    if (up) {
      // ammunition CRATE: a wooden box with two shell tips showing
      final crate = Rect.fromCenter(
          center: c.translate(w * 0.36, w * 0.1), width: w * 0.22, height: w * 0.18);
      canvas.drawRect(crate, Paint()..color = const Color(0xFF6B4E2E));
      canvas.drawRect(
          crate,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFF4E3920));
      canvas.drawLine(Offset(crate.center.dx, crate.top),
          Offset(crate.center.dx, crate.bottom),
          Paint()
            ..color = const Color(0xFF4E3920)
            ..strokeWidth = 1);
      for (final fx in const [0.3, 0.7]) {
        canvas.drawCircle(
            Offset(crate.left + crate.width * fx, crate.top - w * 0.015),
            w * 0.028,
            Paint()..color = const Color(0xFF11151B));
      }
    } else {
      for (var i = 0; i < 2; i++) {
        final sc = c.translate(w * 0.34, w * 0.14 - i * w * 0.12);
        canvas.drawOval(
            Rect.fromCenter(center: sc, width: w * 0.09, height: w * 0.14),
            Paint()..color = const Color(0xFF11151B));
        canvas.drawCircle(sc.translate(0, -w * 0.055), w * 0.026,
            Paint()..color = const Color(0xFFB8543C));
      }
    }
  }

  void _rubble(Canvas canvas, Rect rect, int r, int c) {
    final p = Paint()..color = const Color(0xFF3A3F49).withValues(alpha: 0.8);
    for (var i = 0; i < 4; i++) {
      final fx = 0.25 + _hash(r, c, 10 + i) * 0.5;
      final fy = 0.35 + _hash(r, c, 20 + i) * 0.4;
      canvas.drawCircle(
          Offset(rect.left + rect.width * fx, rect.top + rect.height * fy),
          rect.width * (0.05 + _hash(r, c, 30 + i) * 0.05),
          p);
    }
    // it SMOLDERS: glowing embers + a thin wisp of smoke
    for (var i = 0; i < 2; i++) {
      final ex = rect.left + rect.width * (0.35 + _hash(r, c, 40 + i) * 0.3);
      final ey = rect.top + rect.height * (0.45 + _hash(r, c, 50 + i) * 0.25);
      final glow = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(_at * 3 + i * 2.4 + r));
      canvas.drawCircle(Offset(ex, ey), rect.width * 0.035,
          Paint()..color = const Color(0xFFFF6A2D).withValues(alpha: glow));
    }
    final drift = (_at * 0.18 + _hash(r, c, 55)) % 1.0;
    canvas.drawCircle(
        Offset(rect.center.dx + math.sin(_at * 1.5) * rect.width * 0.05,
            rect.center.dy - drift * rect.height * 0.6),
        rect.width * (0.04 + drift * 0.05),
        Paint()
          ..color = const Color(0xFF6B7482).withValues(alpha: 0.3 * (1 - drift)));
    // smoke wisp
    final smoke = Paint()
      ..color = Colors.white.withValues(alpha: 0.06 + 0.03 * math.sin(_at * 2 + r + c));
    canvas.drawCircle(rect.center.translate(0, -rect.height * 0.18 - (_at * 6 % 8)),
        rect.width * 0.12, smoke);
  }

  void _hpBar(Canvas canvas, Rect rect, double frac) {
    final f = frac.clamp(0.0, 1.0);
    if (f >= 1) return;
    final bw = rect.width * 0.68;
    final bx = rect.center.dx - bw / 2, by = rect.bottom - 5.5;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, 3.6), const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.6));
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw * f, 3.6), const Radius.circular(2)),
        Paint()
          ..color = f > 0.5
              ? JarsColors.green
              : (f > 0.25 ? JarsColors.gold : JarsColors.red));
  }

  // ── highlights ──────────────────────────────────────────────────────────────
  void _highlightPass(Canvas canvas) {
    for (final k in buildable) {
      _cellGlow(canvas, k ~/ base.cols, k % base.cols,
          JarsColors.gold.withValues(alpha: 0.3), fill: JarsColors.gold.withValues(alpha: 0.05));
    }
    for (final k in reachable) {
      final r = k ~/ base.cols, c = k % base.cols;
      _cellGlow(canvas, r, c, _you.withValues(alpha: 0.7),
          fill: _you.withValues(alpha: 0.22));
      // ⚡ cost of walking here (only when tiles are big enough to read)
      final cost = reachCosts[k];
      if (cost != null && tile >= 30) {
        _textAt(
            canvas,
            _center(r, c).translate(0, tile * 0.28),
            cost < 1 ? 'free' : '⚡${cost.round()}',
            tile * 0.22,
            JarsColors.gold);
      }
    }
    final pulse = 0.55 + 0.45 * math.sin(_at * 4);
    for (final tg in targets) {
      _cellGlow(canvas, tg.r, tg.c, _enemy.withValues(alpha: 0.35 + 0.55 * pulse),
          fill: _enemy.withValues(alpha: 0.24));
    }
  }

  void _cellGlow(Canvas canvas, int r, int c, Color border, {Color? fill}) {
    final rect = _rect(r, c).deflate(1.5);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(tile * 0.18));
    if (fill != null) canvas.drawRRect(rr, Paint()..color = fill);
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = border);
  }

  // ── fog: deep cover with large drifting clouds (no per-tile dot pattern) ────
  void _fogPass(Canvas canvas) {
    if (fog == null) return;
    // 1) flat deep cover — and where fog meets scouted ground it FEATHERS
    // into the light instead of cutting a hard geometric edge
    final cover = Paint()..color = const Color(0xFF0A0D16).withValues(alpha: 0.95);
    const fogColor = Color(0xFF0A0D16);
    final featherOk = _hiDetail;
    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        if (_revealed(r, c)) continue;
        final rect = _rect(r, c);
        canvas.drawRect(rect, cover);
        if (!featherOk) continue;
        bool rev(int nr, int nc) => base.inBounds(nr, nc) && _revealed(nr, nc);
        // soft spill into each revealed neighbour (≈ half a tile of gradient)
        void feather(Rect strip, Alignment from, Alignment to) {
          canvas.drawRect(
              strip,
              Paint()
                ..shader = LinearGradient(
                  begin: from,
                  end: to,
                  colors: [
                    fogColor.withValues(alpha: 0.75),
                    fogColor.withValues(alpha: 0.0),
                  ],
                ).createShader(strip));
        }

        final d = tile * 0.55;
        if (rev(r - 1, c)) {
          feather(Rect.fromLTWH(rect.left, rect.top - d, rect.width, d),
              Alignment.bottomCenter, Alignment.topCenter);
        }
        if (rev(r + 1, c)) {
          feather(Rect.fromLTWH(rect.left, rect.bottom, rect.width, d),
              Alignment.topCenter, Alignment.bottomCenter);
        }
        if (rev(r, c - 1)) {
          feather(Rect.fromLTWH(rect.left - d, rect.top, d, rect.height),
              Alignment.centerRight, Alignment.centerLeft);
        }
        if (rev(r, c + 1)) {
          feather(Rect.fromLTWH(rect.right, rect.top, d, rect.height),
              Alignment.centerLeft, Alignment.centerRight);
        }
      }
    }
    // 2) a handful of LARGE drifting cloud blobs across the whole fog field
    final cloud = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    for (var i = 0; i < 10; i++) {
      final baseR = _hash(i, 7) * base.rows;
      final baseC = _hash(i, 13) * base.cols;
      final drift = math.sin(_at * 0.25 + i * 1.7) * 1.6;
      final r = baseR.round(), c = (baseC + drift).round();
      if (!base.inBounds(r, c) || _revealed(r, c)) continue;
      canvas.drawCircle(_center(r.toDouble(), baseC + drift),
          tile * (1.1 + _hash(i, 21) * 0.9), cloud);
    }
  }

  // ── units ───────────────────────────────────────────────────────────────────
  void _troop(Canvas canvas, Troop tr) {
    final bob = math.sin(_at * 3.2 + (tr.id.hashCode % 7)) * tile * 0.03;
    // glide: draw at the animated position when the screen provides one
    final pos = troopPositions[tr.id];
    final center = (pos != null
            ? _center(pos.dy, pos.dx)
            : _center(tr.r, tr.c))
        .translate(0, bob);
    _sprite(canvas, center, tr.spec.emoji, tr.side, tr.hp / tr.maxHp,
        selected: selected != null && selected!.r == tr.r && selected!.c == tr.c,
        level: tr.level);
    // ON FIRE: clinging pitch — a flame tag until it gutters out
    if (tr.burnRounds > 0) {
      _emojiAt(canvas, center.translate(-tile * 0.28, -tile * 0.32), '🔥',
          tile * 0.3);
    }
    // CONCEALED: in the trees the guns can't see them from afar — a green
    // veil + leaf tag says WHY the defense went quiet
    if (base.inBounds(tr.r, tr.c) &&
        base.grid[tr.r][tr.c].terrain == Terrain.forest) {
      canvas.drawCircle(
          center,
          tile * 0.36,
          Paint()..color = const Color(0xFF224422).withValues(alpha: 0.32));
      _emojiAt(canvas, center.translate(tile * 0.28, -tile * 0.32), '🌿',
          tile * 0.32);
    }
    // whose troop is this? (owner badge, top-left)
    final badge = ownerBadges[tr.ownerId];
    if (badge != null && tile >= 34) {
      final s = tile * 0.32;
      final pos = center.translate(-s * 0.95, -s * 0.95);
      canvas.drawCircle(pos, s * 0.42,
          Paint()..color = Colors.black.withValues(alpha: 0.65));
      canvas.drawCircle(
          pos,
          s * 0.42,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.5));
      _emojiAt(canvas, pos, badge, s * 0.55);
    }
  }

  void _drawReplay(Canvas canvas, RaidFrame f) {
    // structures AS THEY WERE at this moment — walls stand, crack, and fall.
    // Walls draw first and CONNECTED, using the frame itself as neighbourhood.
    // the watcher's fog rules the frame too: unscouted structures never draw
    // (clan-raid replays can't be used to scout the enemy base for free)
    final wallKeys = <int>{
      for (final s in f.structs)
        if ((s.type == DefType.wall || s.type == DefType.gate) &&
            s.hpFrac > 0 &&
            _revealed(s.r, s.c))
          s.r * base.cols + s.c
    };
    final wireKeys = <int>{
      for (final s in f.structs)
        if (s.type == DefType.barbedWire && _revealed(s.r, s.c))
          s.r * base.cols + s.c
    };
    bool frameWall(int r, int c) => wallKeys.contains(r * base.cols + c);
    bool frameWire(int r, int c) => wireKeys.contains(r * base.cols + c);
    for (final s in f.structs) {
      if (s.type != DefType.wall || s.hpFrac <= 0 || !_revealed(s.r, s.c)) {
        continue;
      }
      _wall(canvas, s.r, s.c, frameWall, s.hpFrac);
    }
    for (final s in f.structs) {
      if (s.type == DefType.wall && s.hpFrac > 0) continue;
      if (!_revealed(s.r, s.c)) continue;
      final rect = _rect(s.r, s.c);
      if (s.hpFrac <= 0) {
        // the ruins of raids past — replays carry the world's scars
        _rubble(canvas, rect, s.r, s.c);
        continue;
      }
      if (s.type == DefType.barbedWire) {
        _wireArt(canvas, rect, s.r, s.c, at: frameWire);
      } else {
        _artFor(canvas, rect, s.type, s.r, s.c);
      }
      // replays burn too — the battle looked like this
      if (s.hpFrac < 0.4 &&
          s.type != DefType.landmine &&
          s.type != DefType.barbedWire) {
        _burnFx(canvas, rect, s.r, s.c, s.hpFrac);
      }
      _hpBar(canvas, rect, s.hpFrac);
    }
    // sprites GLIDE between frames — matched by troop IDENTITY, so a death
    // never makes the rest of the roster "fly" into each other's spots
    final prevById = <String, RaidSprite>{
      if (replayPrev != null && replayBlend < 1)
        for (final p in replayPrev!.sprites) p.id: p
    };
    for (final s in f.sprites) {
      var rr = s.r.toDouble(), cc = s.c.toDouble();
      final p = prevById[s.id];
      if (p != null) {
        rr = p.r + (s.r - p.r) * replayBlend;
        cc = p.c + (s.c - p.c) * replayBlend;
      }
      _sprite(canvas, _center(rr, cc), s.emoji, s.side, s.hpFrac);
    }
    for (final flash in f.flashes) {
      // subtle impact ring — the real spectacle comes from the FX overlay
      final c = _center(flash.r, flash.c);
      canvas.drawCircle(
          c,
          tile * 0.36,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = JarsColors.red.withValues(alpha: 0.4));
    }
  }

  /// Structure art by type (shared by the live board and replays).
  void _artFor(Canvas canvas, Rect rect, DefType type, int r, int c) {
    switch (type) {
      case DefType.castle:
        _castleArt(canvas, rect);
        break;
      case DefType.archerTower:
        _archerTowerArt(canvas, rect);
        break;
      case DefType.cannon:
        _cannonArt(canvas, rect);
        break;
      case DefType.tesla:
        _teslaArt(canvas, rect);
        break;
      case DefType.guardPost:
        _guardPostArt(canvas, rect);
        break;
      case DefType.landmine:
        _mineArt(canvas, rect);
        break;
      case DefType.barbedWire:
        _wireArt(canvas, rect, r, c);
        break;
      case DefType.mortar:
        _mortarArt(canvas, rect);
        break;
      case DefType.gate:
        _gateArt(canvas, rect, r, c);
        break;
      case DefType.housing:
        _housingArt(canvas, rect, r, c);
        break;
      case DefType.pitchThrower:
        _pitchArt(canvas, rect);
        break;
      case DefType.banner:
        _warBannerArt(canvas, rect);
        break;
      case DefType.ballista:
        _ballistaArt(canvas, rect, null, 1);
        break;
      case DefType.watchtower:
        _watchtowerArt(canvas, rect);
        break;
      case DefType.storehouse:
        _storehouseArt(canvas, rect);
        break;
      case DefType.tributeChest:
        _tributeChestArt(canvas, rect);
        break;
      case DefType.commandTent:
        _commandTentArt(canvas, rect);
        break;
      case DefType.pitchPot:
        _pitchPotArt(canvas, rect);
        break;
      case DefType.citadelCore:
        _citadelCoreArt(canvas, rect);
        break;
      case DefType.warGenerator:
        _warGeneratorArt(canvas, rect, 1);
        break;
      case DefType.wall:
        break; // walls are painted connected in _drawReplay's wall pass
    }
  }

  /// The fort's doorway: stone jambs matching the ramparts, iron-banded
  /// double doors between them. Oriented to the wall run it sits in, and
  /// connecting DIAGONALLY to corner-touching walls just like walls do.
  void _gateArt(Canvas canvas, Rect rect, int r, int c, [int level = 1]) {
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx, cy = rect.center.dy;
    // diagonal half-struts toward corner-touching walls (all possibilities)
    final th = w * 0.46;
    for (final d in const [
      [-1, -1],
      [-1, 1],
      [1, -1],
      [1, 1]
    ]) {
      if (_wallish(r + d[0], c + d[1]) &&
          !_wallish(r + d[0], c) &&
          !_wallish(r, c + d[1])) {
        final corner = Offset(cx + d[1] * w / 2, cy + d[0] * h / 2);
        canvas.drawLine(
            rect.center.translate(0, h * 0.05),
            corner.translate(0, h * 0.05),
            Paint()
              ..color = Colors.black.withValues(alpha: 0.3)
              ..strokeWidth = th * 0.9
              ..strokeCap = StrokeCap.round);
        canvas.drawLine(
            rect.center,
            corner,
            Paint()
              ..color = const Color(0xFF808A99)
              ..strokeWidth = th * 0.9
              ..strokeCap = StrokeCap.round);
      }
    }
    // orient with the wall line: neighbours left/right → horizontal run
    final horizontalRun = _wallish(r, c - 1) ||
        _wallish(r, c + 1) ||
        !(_wallish(r - 1, c) || _wallish(r + 1, c));
    canvas.save();
    canvas.translate(cx, cy);
    if (!horizontalRun) canvas.rotate(math.pi / 2);
    canvas.translate(-cx, -cy);
    // stone jambs (same stone as the ramparts)
    final jamb = Paint()..color = const Color(0xFF808A99);
    final jambShadow = Paint()..color = Colors.black.withValues(alpha: 0.3);
    for (final side in const [-1, 1]) {
      final jr = Rect.fromCenter(
          center: Offset(cx + side * w * 0.38, cy),
          width: w * 0.24,
          height: h * 0.52);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              jr.translate(0, h * 0.05), Radius.circular(w * 0.07)),
          jambShadow);
      canvas.drawRRect(
          RRect.fromRectAndRadius(jr, Radius.circular(w * 0.07)), jamb);
      canvas.drawRect(
          Rect.fromLTWH(jr.left, jr.top, jr.width, jr.height * 0.3),
          Paint()..color = Colors.white.withValues(alpha: 0.13));
    }
    // wooden double doors
    final door = Rect.fromCenter(
        center: Offset(cx, cy), width: w * 0.52, height: h * 0.44);
    canvas.drawRRect(
        RRect.fromRectAndRadius(door, Radius.circular(w * 0.05)),
        Paint()..color = const Color(0xFF7A5A34));
    // planks + center seam
    final seam = Paint()
      ..color = const Color(0xFF4E3920)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(cx, door.top), Offset(cx, door.bottom), seam);
    for (final fx in const [0.25, 0.75]) {
      canvas.drawLine(Offset(door.left + door.width * fx, door.top),
          Offset(door.left + door.width * fx, door.bottom), seam);
    }
    // iron bands + studs
    final band = Paint()
      ..color = const Color(0xFF3A4048)
      ..strokeWidth = h * 0.06;
    canvas.drawLine(Offset(door.left, cy - h * 0.1),
        Offset(door.right, cy - h * 0.1), band);
    canvas.drawLine(Offset(door.left, cy + h * 0.1),
        Offset(door.right, cy + h * 0.1), band);
    final stud = Paint()..color = const Color(0xFF9AA2AE);
    for (final fx in const [0.18, 0.5, 0.82]) {
      canvas.drawCircle(
          Offset(door.left + door.width * fx, cy - h * 0.1), w * 0.02, stud);
      canvas.drawCircle(
          Offset(door.left + door.width * fx, cy + h * 0.1), w * 0.02, stud);
    }
    if (level >= 2) {
      // a fortified GATEHOUSE: stone arch over darker, strap-hinged doors
      canvas.drawRRect(
          RRect.fromRectAndRadius(door, Radius.circular(w * 0.05)),
          Paint()..color = const Color(0xFF5A4326)); // heavier timber
      final arch = Path()
        ..moveTo(door.left - w * 0.1, door.top + h * 0.04)
        ..quadraticBezierTo(cx, door.top - h * 0.2, door.right + w * 0.1,
            door.top + h * 0.04)
        ..lineTo(door.right + w * 0.1, door.top - h * 0.02)
        ..quadraticBezierTo(
            cx, door.top - h * 0.28, door.left - w * 0.1, door.top - h * 0.02)
        ..close();
      canvas.drawPath(arch, Paint()..color = const Color(0xFF8A93A1));
      // keystone
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(cx, door.top - h * 0.14),
              width: w * 0.1,
              height: h * 0.12),
          Paint()..color = const Color(0xFFAEB9C8));
      // strap hinges
      final strap = Paint()
        ..color = const Color(0xFF23272E)
        ..strokeWidth = h * 0.05
        ..strokeCap = StrokeCap.round;
      for (final fy in const [-0.1, 0.1]) {
        canvas.drawLine(Offset(door.left, cy + h * fy),
            Offset(door.left + door.width * 0.32, cy + h * fy), strap);
        canvas.drawLine(Offset(door.right, cy + h * fy),
            Offset(door.right - door.width * 0.32, cy + h * fy), strap);
      }
    }
    canvas.restore();
  }

  /// Longhouse: a wide low hall with a ridge beam.
  void _longhouseArt(Canvas canvas, Rect rect) {
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final bodyR =
        Rect.fromLTWH(cx - w * 0.34, rect.top + h * 0.5, w * 0.68, h * 0.28);
    canvas.drawRect(bodyR, Paint()..color = const Color(0xFF8F7450));
    canvas.drawPath(
        Path()
          ..moveTo(cx - w * 0.38, rect.top + h * 0.5)
          ..lineTo(cx, rect.top + h * 0.3)
          ..lineTo(cx + w * 0.38, rect.top + h * 0.5)
          ..close(),
        Paint()..color = const Color(0xFF5E4430));
    canvas.drawLine(
        Offset(cx - w * 0.3, rect.top + h * 0.415),
        Offset(cx + w * 0.3, rect.top + h * 0.415),
        Paint()
          ..color = const Color(0xFF4A3524)
          ..strokeWidth = 1.4);
    canvas.drawRect(
        Rect.fromLTWH(cx - w * 0.05, bodyR.bottom - h * 0.14, w * 0.1, h * 0.14),
        Paint()..color = const Color(0xFF3B2C1A));
  }

  /// Round hut: circular walls under a conical thatch roof.
  void _roundHutArt(Canvas canvas, Rect rect) {
    final w = rect.width, h = rect.height;
    final cB = rect.center.translate(0, h * 0.12);
    canvas.drawCircle(cB, w * 0.26, Paint()..color = const Color(0xFF9A7E58));
    canvas.drawPath(
        Path()
          ..moveTo(cB.dx - w * 0.32, cB.dy - h * 0.08)
          ..lineTo(cB.dx, cB.dy - h * 0.42)
          ..lineTo(cB.dx + w * 0.32, cB.dy - h * 0.08)
          ..close(),
        Paint()..color = const Color(0xFFB59B4A));
    canvas.drawLine(
        Offset(cB.dx - w * 0.2, cB.dy - h * 0.16),
        Offset(cB.dx + w * 0.2, cB.dy - h * 0.16),
        Paint()
          ..color = const Color(0xFF98803B)
          ..strokeWidth = 1.2);
    canvas.drawRect(
        Rect.fromLTWH(cB.dx - w * 0.05, cB.dy + h * 0.04, w * 0.1, h * 0.12),
        Paint()..color = const Color(0xFF3B2C1A));
  }

  /// Pitch thrower: an iron cauldron of burning pitch on a stone lip.
  void _pitchArt(Canvas canvas, Rect rect) {
    _shadow(canvas, rect, w: 0.6, y: 0.8);
    final w = rect.width, h = rect.height;
    final cB = rect.center.translate(0, h * 0.06);
    // stone lip
    canvas.drawOval(
        Rect.fromCenter(
            center: cB.translate(0, h * 0.16), width: w * 0.56, height: h * 0.2),
        Paint()..color = const Color(0xFF69707E));
    // cauldron
    canvas.drawArc(
        Rect.fromCenter(center: cB, width: w * 0.44, height: h * 0.4),
        0,
        math.pi,
        true,
        Paint()..color = const Color(0xFF23272E));
    canvas.drawOval(
        Rect.fromCenter(
            center: cB.translate(0, -h * 0.02), width: w * 0.44, height: h * 0.12),
        Paint()..color = const Color(0xFF14181E));
    // the burning pitch
    final flick = 0.6 + 0.4 * math.sin(_at * 8 + cB.dx * 0.1);
    canvas.drawOval(
        Rect.fromCenter(
            center: cB.translate(0, -h * 0.02), width: w * 0.34, height: h * 0.08),
        Paint()..color = const Color(0xFFFF8A3D).withValues(alpha: 0.9));
    for (var i = 0; i < 3; i++) {
      final fx = cB.dx + (i - 1) * w * 0.1;
      canvas.drawCircle(
          Offset(fx, cB.dy - h * (0.08 + 0.05 * flick)),
          w * (0.035 + 0.02 * flick),
          Paint()..color = const Color(0xFFFFD34D).withValues(alpha: 0.85));
    }
    // drifting smoke
    final ph = (_at * 0.3) % 1.0;
    canvas.drawCircle(
        Offset(cB.dx + math.sin(_at * 1.6) * w * 0.05,
            cB.dy - h * 0.2 - ph * h * 0.4),
        w * (0.05 + ph * 0.04),
        Paint()..color = const Color(0xFF6B7482).withValues(alpha: 0.35 * (1 - ph)));
  }

  /// War banner: a tall standard with the clan's colors streaming.
  void _warBannerArt(Canvas canvas, Rect rect) {
    _shadow(canvas, rect, w: 0.4);
    final w = rect.width, h = rect.height;
    final x = rect.center.dx - w * 0.06;
    // stone footing
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, rect.top + h * 0.8),
                width: w * 0.26,
                height: h * 0.12),
            Radius.circular(w * 0.04)),
        Paint()..color = const Color(0xFF69707E));
    canvas.drawLine(
        Offset(x, rect.top + h * 0.8),
        Offset(x, rect.top + h * 0.14),
        Paint()
          ..color = const Color(0xFF6B4E2E)
          ..strokeWidth = w * 0.05);
    // the streaming colors (two-tail banner)
    final flap = math.sin(_at * 4 + x * 0.05) * w * 0.05;
    canvas.drawPath(
        Path()
          ..moveTo(x, rect.top + h * 0.16)
          ..lineTo(x + w * 0.44, rect.top + h * 0.2 + flap)
          ..lineTo(x + w * 0.3, rect.top + h * 0.3)
          ..lineTo(x + w * 0.44, rect.top + h * 0.4 + flap)
          ..lineTo(x, rect.top + h * 0.44)
          ..close(),
        Paint()..color = const Color(0xFFB8443C));
    canvas.drawCircle(Offset(x, rect.top + h * 0.12), w * 0.035,
        Paint()..color = const Color(0xFFB08D3E));
  }

  /// Ballista: a mounted crossbow the size of a cart. Levels darken the
  /// timber, widen the arms, and at L5 add an obsidian bolt rail.
  void _ballistaArt(Canvas canvas, Rect rect, double? aim, [int level = 1]) {
    _shadow(canvas, rect, w: 0.62, y: 0.8);
    final w = rect.width;
    final c = rect.center;
    final up = level >= 2;
    final elite = level >= 3;
    final apex = level >= 4;
    final mythic = level >= 5;
    final timber = mythic
        ? const Color(0xFF1A1018)
        : apex
            ? const Color(0xFF2A1830)
            : elite
                ? const Color(0xFF3A2E1E)
                : up
                    ? const Color(0xFF5A4028)
                    : const Color(0xFF6B4E2E);
    // timber base
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: c.translate(0, w * 0.08),
                width: w * (apex ? 0.56 : 0.5),
                height: w * (apex ? 0.34 : 0.3)),
            Radius.circular(w * 0.05)),
        Paint()..color = timber);
    if (elite) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: c.translate(0, w * 0.08),
                  width: w * (apex ? 0.56 : 0.5),
                  height: w * (apex ? 0.34 : 0.3)),
              Radius.circular(w * 0.05)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = mythic
                ? const Color(0xFF7B5CFF)
                : const Color(0xFFB08D3E));
    }
    final ang = aim ??
        -math.pi / 2 +
            math.sin(_at * 0.6 + c.dx * 0.01) * (_hiDetail ? 0.5 : 0);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(ang);
    // the stock
    canvas.drawRect(
        Rect.fromLTWH(-w * 0.05, -w * 0.06, w * (apex ? 0.48 : 0.42), w * 0.1),
        Paint()
          ..color = mythic
              ? const Color(0xFF2A1830)
              : const Color(0xFF4E3920));
    // the bow arms + string
    final arm = Paint()
      ..color = mythic ? const Color(0xFF7B5CFF) : const Color(0xFF3A2E1E)
      ..strokeWidth = w * (apex ? 0.055 : 0.045)
      ..strokeCap = StrokeCap.round;
    final reach = apex ? 0.24 : 0.2;
    canvas.drawLine(Offset(w * 0.3, 0), Offset(w * 0.18, -w * reach), arm);
    canvas.drawLine(Offset(w * 0.3, 0), Offset(w * 0.18, w * reach), arm);
    canvas.drawLine(
        Offset(w * 0.18, -w * reach),
        Offset(w * 0.18, w * reach),
        Paint()
          ..color = mythic
              ? const Color(0xFFE8DEFF)
              : const Color(0xFFD8C9A3)
          ..strokeWidth = elite ? 1.8 : 1.4);
    // the loaded bolt
    canvas.drawLine(
        Offset(w * 0.02, 0),
        Offset(w * (apex ? 0.4 : 0.34), 0),
        Paint()
          ..color = mythic
              ? const Color(0xFFB07BFF)
              : const Color(0xFF23272E)
          ..strokeWidth = w * (elite ? 0.045 : 0.035));
    canvas.restore();
    // pivot
    canvas.drawCircle(c, w * 0.06, Paint()..color = const Color(0xFF262C35));
    if (mythic) {
      canvas.drawCircle(
          c,
          w * 0.09,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFF7B5CFF).withValues(alpha: 0.7));
    }
  }

  /// Watchtower: a tall wooden lookout with a lit lantern — EYES, not guns.
  void _watchtowerArt(Canvas canvas, Rect rect) {
    _shadow(canvas, rect, w: 0.5);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    // legs
    final leg = Paint()
      ..color = const Color(0xFF6B4E2E)
      ..strokeWidth = w * 0.05;
    canvas.drawLine(Offset(cx - w * 0.18, rect.top + h * 0.82),
        Offset(cx - w * 0.09, rect.top + h * 0.3), leg);
    canvas.drawLine(Offset(cx + w * 0.18, rect.top + h * 0.82),
        Offset(cx + w * 0.09, rect.top + h * 0.3), leg);
    canvas.drawLine(Offset(cx - w * 0.14, rect.top + h * 0.6),
        Offset(cx + w * 0.14, rect.top + h * 0.6),
        Paint()
          ..color = const Color(0xFF6B4E2E)
          ..strokeWidth = w * 0.03);
    // the crow's nest
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(cx, rect.top + h * 0.26), width: w * 0.34, height: h * 0.14),
        Paint()..color = const Color(0xFF8F7450));
    // roof
    canvas.drawPath(
        Path()
          ..moveTo(cx - w * 0.2, rect.top + h * 0.19)
          ..lineTo(cx, rect.top + h * 0.08)
          ..lineTo(cx + w * 0.2, rect.top + h * 0.19)
          ..close(),
        Paint()..color = const Color(0xFF5E4430));
    // the WATCHING lantern (slow pulse)
    final glow = 0.55 + 0.45 * math.sin(_at * 2.2);
    canvas.drawCircle(Offset(cx, rect.top + h * 0.26), w * 0.05,
        Paint()..color = const Color(0xFFFFD34D).withValues(alpha: glow));
    canvas.drawCircle(
        Offset(cx, rect.top + h * 0.26),
        w * 0.12,
        Paint()
          ..color = const Color(0xFFFFD34D).withValues(alpha: 0.2 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }

  /// Storehouse: a fat granary with grain sacks at the door.
  void _storehouseArt(Canvas canvas, Rect rect) {
    _shadow(canvas, rect, w: 0.66);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final bodyR =
        Rect.fromLTWH(cx - w * 0.28, rect.top + h * 0.4, w * 0.56, h * 0.4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bodyR, Radius.circular(w * 0.05)),
        Paint()..color = const Color(0xFF9A7E58));
    // cross-braces
    final brace = Paint()
      ..color = const Color(0xFF6B4E2E)
      ..strokeWidth = w * 0.03;
    canvas.drawLine(bodyR.topLeft, bodyR.bottomRight, brace);
    canvas.drawLine(bodyR.topRight, bodyR.bottomLeft, brace);
    // rounded roof
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx, rect.top + h * 0.42), width: w * 0.66, height: h * 0.4),
        math.pi,
        math.pi,
        true,
        Paint()..color = const Color(0xFF5E4430));
    // grain sacks
    final sack = Paint()..color = const Color(0xFFC9A94E);
    canvas.drawCircle(Offset(cx + w * 0.24, bodyR.bottom - h * 0.05), w * 0.07, sack);
    canvas.drawCircle(Offset(cx + w * 0.33, bodyR.bottom - h * 0.04), w * 0.055, sack);
    // the coin mark
    canvas.drawCircle(Offset(cx, bodyR.top + h * 0.12), w * 0.05,
        Paint()..color = const Color(0xFFB08D3E));
  }

  /// Tribute Chest: a banded oak coffer, lid cracked open, coin spilling.
  void _tributeChestArt(Canvas canvas, Rect rect) {
    _shadow(canvas, rect, w: 0.6, y: 0.82);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final body = Rect.fromLTWH(cx - w * 0.27, rect.top + h * 0.46, w * 0.54, h * 0.3);
    // coin glow spilling from the seam
    final glow = 0.5 + 0.5 * math.sin(_at * 1.8 + cx * 0.02);
    canvas.drawCircle(
        Offset(cx, body.top),
        w * 0.3,
        Paint()
          ..color = const Color(0xFFFFD34D).withValues(alpha: 0.16 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    // coffer body
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(w * 0.04)),
        Paint()..color = const Color(0xFF7A5632));
    // domed lid, tilted ajar
    final lid = Rect.fromLTWH(
        cx - w * 0.29, rect.top + h * 0.32, w * 0.58, h * 0.2);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx, lid.bottom), width: lid.width, height: lid.height * 2),
        math.pi,
        math.pi,
        true,
        Paint()..color = const Color(0xFF976C3E));
    // iron bands
    final band = Paint()
      ..color = const Color(0xFF3A3F48)
      ..strokeWidth = w * 0.045;
    canvas.drawLine(Offset(cx - w * 0.14, body.top),
        Offset(cx - w * 0.14, body.bottom), band);
    canvas.drawLine(Offset(cx + w * 0.14, body.top),
        Offset(cx + w * 0.14, body.bottom), band);
    canvas.drawLine(
        Offset(body.left, body.top + body.height * 0.5),
        Offset(body.right, body.top + body.height * 0.5),
        Paint()
          ..color = const Color(0xFF3A3F48)
          ..strokeWidth = w * 0.03);
    // brass lock
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cx, body.top + body.height * 0.28),
                width: w * 0.12,
                height: h * 0.1),
            Radius.circular(w * 0.02)),
        Paint()..color = const Color(0xFFD8A63C));
    // stacked coins beside it
    final coin = Paint()..color = const Color(0xFFFFD34D);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + w * 0.33, body.bottom - h * 0.02),
            width: w * 0.14,
            height: h * 0.05),
        coin);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + w * 0.33, body.bottom - h * 0.06),
            width: w * 0.12,
            height: h * 0.045),
        coin);
  }

  /// Command Tent: a war pavilion — peaked canvas, guy ropes, map table
  /// glowing inside, the crew's standard flying off the ridge pole.
  void _commandTentArt(Canvas canvas, Rect rect) {
    _shadow(canvas, rect, w: 0.72, y: 0.84);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final baseY = rect.top + h * 0.78;
    final peak = Offset(cx, rect.top + h * 0.22);
    // canvas body: a broad ridge tent
    canvas.drawPath(
        Path()
          ..moveTo(peak.dx, peak.dy)
          ..lineTo(cx + w * 0.36, baseY)
          ..lineTo(cx - w * 0.36, baseY)
          ..close(),
        Paint()..color = const Color(0xFFCBBBA0));
    // shaded right face so it reads 3D
    canvas.drawPath(
        Path()
          ..moveTo(peak.dx, peak.dy)
          ..lineTo(cx + w * 0.36, baseY)
          ..lineTo(cx, baseY)
          ..close(),
        Paint()..color = const Color(0xFFA8977E));
    // doorway flap, with lamplight from the map table inside
    final door = Path()
      ..moveTo(cx - w * 0.1, baseY)
      ..lineTo(cx, rect.top + h * 0.45)
      ..lineTo(cx + w * 0.1, baseY)
      ..close();
    canvas.drawPath(door, Paint()..color = const Color(0xFF3A3226));
    final lamp = 0.55 + 0.45 * math.sin(_at * 2.1 + cx * 0.01);
    canvas.drawPath(
        door,
        Paint()
          ..color = const Color(0xFFFFB74D).withValues(alpha: 0.4 * lamp));
    // guy ropes + pegs
    final rope = Paint()
      ..color = const Color(0xFF6B5B44)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(cx - w * 0.36, baseY),
        Offset(cx - w * 0.46, baseY + h * 0.06), rope);
    canvas.drawLine(Offset(cx + w * 0.36, baseY),
        Offset(cx + w * 0.46, baseY + h * 0.06), rope);
    // ridge pole + the General's standard
    canvas.drawLine(
        peak,
        Offset(peak.dx, rect.top + h * 0.04),
        Paint()
          ..color = const Color(0xFF5E4430)
          ..strokeWidth = w * 0.035);
    final wave = math.sin(_at * 3 + cx * 0.02) * w * 0.03;
    canvas.drawPath(
        Path()
          ..moveTo(peak.dx, rect.top + h * 0.05)
          ..lineTo(peak.dx + w * 0.2 + wave, rect.top + h * 0.1)
          ..lineTo(peak.dx, rect.top + h * 0.17)
          ..close(),
        Paint()..color = const Color(0xFFD84C4C));
  }

  /// Pitch Pot: a squat tar cauldron half-sunk in the dirt, slick black
  /// surface, a bubble breaking now and then. Concealed until it blows.
  void _pitchPotArt(Canvas canvas, Rect rect) {
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx, cy = rect.top + h * 0.6;
    // scraped dirt collar
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + h * 0.1), width: w * 0.62, height: h * 0.24),
        Paint()..color = const Color(0xFF4E3B24));
    // the pot
    canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy), width: w * 0.5, height: h * 0.44),
        0,
        math.pi,
        true,
        Paint()..color = const Color(0xFF2B2622));
    // tar surface
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: w * 0.5, height: h * 0.16),
        Paint()..color = const Color(0xFF14110F));
    // rim
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: w * 0.5, height: h * 0.16),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF554A3C));
    // a slow bubble
    final b = (math.sin(_at * 1.3 + cx * 0.03) + 1) / 2;
    canvas.drawCircle(
        Offset(cx - w * 0.06, cy - h * 0.005),
        w * 0.05 * b,
        Paint()..color = const Color(0xFF3E3630));
  }

  /// Citadel Core: a monolith of dark stone with a lit crystal seam — a
  /// landmark, not a gun. Slow aura ring pulses out from the base.
  void _citadelCoreArt(Canvas canvas, Rect rect) {
    _shadow(canvas, rect, w: 0.6, y: 0.88);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final pulse = 0.5 + 0.5 * math.sin(_at * 1.4 + cx * 0.01);
    // aura ring on the ground
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, rect.top + h * 0.84),
            width: w * (0.72 + 0.12 * pulse),
            height: h * (0.22 + 0.04 * pulse)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFF6FE3FF).withValues(alpha: 0.16 + 0.2 * pulse));
    // stepped plinth
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cx, rect.top + h * 0.78),
                width: w * 0.52,
                height: h * 0.12),
            Radius.circular(w * 0.03)),
        Paint()..color = const Color(0xFF3A4150));
    // the monolith
    final shaft = Path()
      ..moveTo(cx - w * 0.16, rect.top + h * 0.74)
      ..lineTo(cx - w * 0.1, rect.top + h * 0.16)
      ..lineTo(cx, rect.top + h * 0.06)
      ..lineTo(cx + w * 0.1, rect.top + h * 0.16)
      ..lineTo(cx + w * 0.16, rect.top + h * 0.74)
      ..close();
    canvas.drawPath(shaft, Paint()..color = const Color(0xFF2B3040));
    // lit face
    canvas.drawPath(
        Path()
          ..moveTo(cx, rect.top + h * 0.06)
          ..lineTo(cx + w * 0.1, rect.top + h * 0.16)
          ..lineTo(cx + w * 0.16, rect.top + h * 0.74)
          ..lineTo(cx, rect.top + h * 0.74)
          ..close(),
        Paint()..color = const Color(0xFF1E2230));
    // the crystal seam
    canvas.drawLine(
        Offset(cx, rect.top + h * 0.16),
        Offset(cx, rect.top + h * 0.7),
        Paint()
          ..color = const Color(0xFF6FE3FF).withValues(alpha: 0.55 + 0.4 * pulse)
          ..strokeWidth = w * 0.05
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(
        Offset(cx, rect.top + h * 0.36),
        w * 0.16,
        Paint()
          ..color = const Color(0xFF6FE3FF).withValues(alpha: 0.16 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  /// War Generator: an elixir still — copper boiler, coiled pipe, a glowing
  /// vat, and steam puffing off the top. Levels add tanks and brighten it.
  void _warGeneratorArt(Canvas canvas, Rect rect, [int level = 1]) {
    _shadow(canvas, rect, w: 0.66, y: 0.86);
    final w = rect.width, h = rect.height;
    final cx = rect.center.dx;
    final up = level >= 2, maxed = level >= 3;
    // brick footing
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cx, rect.top + h * 0.76),
                width: w * 0.62,
                height: h * 0.14),
            Radius.circular(w * 0.03)),
        Paint()..color = const Color(0xFF54423A));
    // the boiler
    final boiler =
        Rect.fromLTWH(cx - w * 0.22, rect.top + h * 0.38, w * 0.44, h * 0.32);
    canvas.drawRRect(
        RRect.fromRectAndRadius(boiler, Radius.circular(w * 0.09)),
        Paint()..color = maxed
            ? const Color(0xFFB9762E)
            : const Color(0xFF9A6634));
    // glowing sight-glass
    final glow = 0.5 + 0.5 * math.sin(_at * 2.6 + cx * 0.02);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: boiler.center,
                width: w * 0.2,
                height: h * 0.14),
            Radius.circular(w * 0.03)),
        Paint()
          ..color = const Color(0xFF7CE6A8)
              .withValues(alpha: 0.55 + 0.35 * glow));
    canvas.drawCircle(
        boiler.center,
        w * 0.2,
        Paint()
          ..color = const Color(0xFF7CE6A8).withValues(alpha: 0.14 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    // iron hoops
    final hoop = Paint()
      ..color = const Color(0xFF3A3F48)
      ..strokeWidth = w * 0.03;
    canvas.drawLine(Offset(boiler.left, boiler.top + boiler.height * 0.22),
        Offset(boiler.right, boiler.top + boiler.height * 0.22), hoop);
    canvas.drawLine(Offset(boiler.left, boiler.bottom - boiler.height * 0.18),
        Offset(boiler.right, boiler.bottom - boiler.height * 0.18), hoop);
    // coiled condenser pipe up the side
    final pipe = Paint()
      ..color = const Color(0xFFC98B3E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round;
    final coil = Path()..moveTo(boiler.right, boiler.top + h * 0.06);
    for (var i = 0; i < 3; i++) {
      final y = boiler.top + h * 0.06 + i * h * 0.07;
      coil.quadraticBezierTo(
          boiler.right + w * 0.16, y + h * 0.035, boiler.right, y + h * 0.07);
    }
    canvas.drawPath(coil, pipe);
    // chimney + steam
    canvas.drawRect(
        Rect.fromLTWH(cx - w * 0.06, rect.top + h * 0.24, w * 0.12, h * 0.16),
        Paint()..color = const Color(0xFF6B5B44));
    for (var i = 0; i < (maxed ? 3 : 2); i++) {
      final t = (_at * 0.6 + i * 0.34) % 1.0;
      canvas.drawCircle(
          Offset(cx + math.sin(_at * 1.6 + i) * w * 0.05,
              rect.top + h * 0.24 - t * h * 0.2),
          w * (0.05 + t * 0.06),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.22 * (1 - t)));
    }
    // extra holding tank once upgraded
    if (up) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  cx - w * 0.42, rect.top + h * 0.52, w * 0.16, h * 0.2),
              Radius.circular(w * 0.04)),
          Paint()..color = const Color(0xFF7A5632));
      canvas.drawCircle(
          Offset(cx - w * 0.34, rect.top + h * 0.58),
          w * 0.035,
          Paint()..color = const Color(0xFF7CE6A8).withValues(alpha: 0.8));
    }
  }

  // ── tombstones: the fallen rest where they fell (up to 4 per tile);
  // heavier losses become burial mounds, and true massacres leave a
  // bone-pile memorial the whole map can see ──────────────────────────────────
  void _gravesPass(Canvas canvas, List<List<int>> gs) {
    if (gs.isEmpty) return;
    final byCell = <int, int>{};
    for (final g in gs) {
      final k = g[0] * base.cols + g[1];
      byCell[k] = (byCell[k] ?? 0) + 1;
    }
    const quads = [
      [0.28, 0.32],
      [0.72, 0.32],
      [0.28, 0.74],
      [0.72, 0.74]
    ];
    for (final g in gs) {
      final r = g[0], c = g[1];
      if (r < _r0 || r > _r1 || c < _c0 || c > _c1) continue;
      if (!_revealed(r, c)) continue;
      if ((byCell[r * base.cols + c] ?? 0) >= 4) continue; // a mound instead
      final rect = _rect(r, c);
      final q = quads[g[2].clamp(0, 3)];
      final gx0 = rect.left + rect.width * q[0];
      final gy0 = rect.top + rect.height * q[1];
      final s = rect.width * 0.13;
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(gx0, gy0 + s * 0.95),
              width: s * 1.7,
              height: s * 0.5),
          Paint()..color = Colors.black.withValues(alpha: 0.25));
      final slab = RRect.fromRectAndCorners(
          Rect.fromCenter(
              center: Offset(gx0, gy0), width: s * 1.3, height: s * 1.8),
          topLeft: Radius.circular(s * 0.65),
          topRight: Radius.circular(s * 0.65));
      canvas.drawRRect(slab, Paint()..color = const Color(0xFF9AA2AE));
      canvas.drawRRect(
          slab,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF565E6A));
      // a single etched line — no crosses
      canvas.drawLine(
          Offset(gx0 - s * 0.35, gy0 - s * 0.12),
          Offset(gx0 + s * 0.35, gy0 - s * 0.12),
          Paint()
            ..color = const Color(0xFF565E6A)
            ..strokeWidth = 1.2);
    }
    // burial mounds where 4+ fell on one tile
    for (final e in byCell.entries) {
      if (e.value < 4) continue;
      final r = e.key ~/ base.cols, c = e.key % base.cols;
      if (r < _r0 || r > _r1 || c < _c0 || c > _c1) continue;
      if (!_revealed(r, c)) continue;
      _burialMound(canvas, _rect(r, c));
    }
    // the KILLING FIELDS: 8+ dead across a 3×3 → a bone-pile memorial on the
    // bloodiest tile of the cluster
    for (final e in byCell.entries) {
      final r = e.key ~/ base.cols, c = e.key % base.cols;
      var sum = 0;
      var isPeak = true;
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          final n = byCell[(r + dr) * base.cols + (c + dc)] ?? 0;
          sum += n;
          if (!(dr == 0 && dc == 0) && n > e.value) isPeak = false;
        }
      }
      if (sum < 8 || !isPeak) continue;
      if (r < _r0 || r > _r1 || c < _c0 || c > _c1) continue;
      if (!_revealed(r, c)) continue;
      _bonePile(canvas, _rect(r, c));
    }
  }

  /// A mounded mass grave: packed earth with a skull set at its crown.
  void _burialMound(Canvas canvas, Rect rect) {
    final w = rect.width;
    final cB = rect.center;
    canvas.drawOval(
        Rect.fromCenter(
            center: cB.translate(0, w * 0.12), width: w * 0.7, height: w * 0.3),
        Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawOval(
        Rect.fromCenter(center: cB, width: w * 0.62, height: w * 0.42),
        Paint()..color = const Color(0xFF5E4A32));
    canvas.drawOval(
        Rect.fromCenter(
            center: cB.translate(0, -w * 0.05),
            width: w * 0.44,
            height: w * 0.26),
        Paint()..color = const Color(0xFF6E583C));
    // small marker stones ring the crown
    final stone = Paint()..color = const Color(0xFF8A93A1);
    canvas.drawCircle(cB.translate(-w * 0.12, -w * 0.08), w * 0.035, stone);
    canvas.drawCircle(cB.translate(w * 0.1, -w * 0.1), w * 0.03, stone);
    canvas.drawCircle(cB.translate(0, -w * 0.14), w * 0.04, stone);
  }

  /// Where a massacre happened, the ground itself BURNS — flames, embers and
  /// smoke over a charred patch, for the rest of the war.
  void _bonePile(Canvas canvas, Rect rect) {
    final w = rect.width;
    final cB = rect.center;
    // charred earth
    canvas.drawCircle(
        cB,
        w * 0.46,
        Paint()
          ..color = const Color(0xFF14181E).withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    // a ring of flames
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + 0.4;
      final fx = cB.dx + math.cos(a) * w * 0.2;
      final fy = cB.dy + math.sin(a) * w * 0.14;
      final flick = 0.5 + 0.5 * math.sin(_at * (6 + i * 1.7) + i * 2.1);
      canvas.drawCircle(Offset(fx, fy), w * (0.07 + 0.04 * flick),
          Paint()..color = const Color(0xFFFF8A3D).withValues(alpha: 0.7));
      canvas.drawCircle(Offset(fx, fy - w * 0.04 * flick), w * 0.04 * flick,
          Paint()..color = const Color(0xFFFFD34D).withValues(alpha: 0.85));
    }
    // embers popping
    for (var i = 0; i < 3; i++) {
      final ph = (t * (0.5 + i * 0.2) + i * 0.37) % 1.0;
      canvas.drawCircle(
          Offset(cB.dx + math.sin(i * 2.7 + t) * w * 0.15,
              cB.dy - ph * w * 0.5),
          w * 0.025 * (1 - ph),
          Paint()..color = const Color(0xFFFF6A2D).withValues(alpha: 1 - ph));
    }
    // the smoke column
    for (var i = 0; i < 3; i++) {
      final ph = (_at * 0.22 + i * 0.33) % 1.0;
      canvas.drawCircle(
          Offset(cB.dx + math.sin(_at + i * 2) * w * 0.08,
              cB.dy - w * 0.15 - ph * w * 0.8),
          w * (0.08 + ph * 0.1),
          Paint()
            ..color = const Color(0xFF6B7482).withValues(alpha: 0.3 * (1 - ph)));
    }
  }


  // ── dressing: braziers by gates, banners by keeps, clutter by the camps ─────
  void _dressingPass(Canvas canvas) {
    bool typ(int r, int c, DefType t) {
      final s = base.structAt(r, c);
      return s != null && s.alive && s.type == t;
    }

    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        if (!_revealed(r, c)) continue;
        if (base.grid[r][c].structure != null) continue;
        if (base.grid[r][c].terrain != Terrain.plains) continue;
        bool near(DefType t) =>
            typ(r - 1, c, t) ||
            typ(r + 1, c, t) ||
            typ(r, c - 1, t) ||
            typ(r, c + 1, t);
        final rect = _rect(r, c);
        if ((near(DefType.castle) || near(DefType.guardPost)) &&
            _hash(r, c, 71) > 0.62) {
          _farmPlot(canvas, rect, r, c);
        } else if (near(DefType.castle) && _hash(r, c, 72) > 0.55) {
          _bannerPole(canvas, rect);
        } else if (near(DefType.guardPost) && _hash(r, c, 73) > 0.5) {
          _campClutter(canvas, rect, r, c);
        }
      }
    }
    // and the guards PACE — a base that breathes. Big boards never pace at
    // any zoom: a 60²+ city has too many tents to walk a figure around each.
    if (ownBase && _hiDetail && base.rows < 52) _patrolPass(canvas);
  }

  /// A little farm plot: tilled soil rows with green sprouts — the base FEEDS
  /// itself.
  void _farmPlot(Canvas canvas, Rect rect, int r, int c) {
    final w = rect.width;
    final soil = Rect.fromCenter(
        center: rect.center, width: w * 0.72, height: w * 0.56);
    canvas.drawRRect(RRect.fromRectAndRadius(soil, Radius.circular(w * 0.06)),
        Paint()..color = const Color(0xFF4E3B24));
    final rowP = Paint()
      ..color = const Color(0xFF3B2C1A)
      ..strokeWidth = w * 0.05;
    for (var i = 0; i < 3; i++) {
      final y = soil.top + soil.height * (0.25 + i * 0.25);
      canvas.drawLine(Offset(soil.left + w * 0.05, y),
          Offset(soil.right - w * 0.05, y), rowP);
      // sprouts along the furrow
      for (var k = 0; k < 4; k++) {
        if (_hash(r, c, 76 + i * 4 + k) < 0.35) continue;
        final x = soil.left + soil.width * (0.15 + k * 0.24);
        final sway = math.sin(_at * 2 + x * 0.2) * w * 0.01;
        canvas.drawCircle(Offset(x + sway, y - w * 0.045), w * 0.032,
            Paint()..color = const Color(0xFF5FA054));
      }
    }
  }

  /// High ground: a mossy rocky knoll — brighter crown, shaded skirt.
  void _hillTile(Canvas canvas, Rect rect, int r, int c) {
    canvas.drawRect(rect, Paint()..color = biome.hill);
    canvas.drawOval(
        Rect.fromCenter(
            center: rect.center.translate(0, -rect.height * 0.06),
            width: rect.width * 0.92,
            height: rect.height * 0.7),
        Paint()..color = Color.lerp(biome.hill, Colors.white, 0.08)!);
    canvas.drawOval(
        Rect.fromCenter(
            center: rect.center.translate(0, -rect.height * 0.12),
            width: rect.width * 0.55,
            height: rect.height * 0.34),
        Paint()..color = Color.lerp(biome.hill, Colors.white, 0.14)!);
    // a couple of embedded stones
    final stone = Paint()..color = biome.mountain;
    if (_hash(r, c, 130) > 0.4) {
      canvas.drawCircle(
          Offset(rect.left + rect.width * (0.3 + _hash(r, c, 131) * 0.4),
              rect.top + rect.height * (0.5 + _hash(r, c, 132) * 0.25)),
          rect.width * 0.05,
          stone);
    }
  }

  // ── scars of war: charred, irregular, layered — not stamped circles ──
  void _scorchPass(Canvas canvas, Map<int, int> scorch) {
    if (scorch.isEmpty) return;
    for (final e in scorch.entries) {
      final r = e.key ~/ base.cols, c = e.key % base.cols;
      if (r < _r0 || r > _r1 || c < _c0 || c > _c1) continue;
      if (!_revealed(r, c)) continue;
      final rect = _rect(r, c);
      final k = e.value.clamp(1, 4);
      // 2–3 offset, squashed, rotated blotches that spill past the tile edge
      for (var i = 0; i < 2 + (k > 2 ? 1 : 0); i++) {
        final ox = (_hash(r, c, 78 + i) - 0.5) * rect.width * 0.9;
        final oy = (_hash(r, c, 82 + i) - 0.5) * rect.height * 0.9;
        final rw = rect.width * (0.35 + _hash(r, c, 86 + i) * 0.35);
        final rh = rw * (0.5 + _hash(r, c, 90 + i) * 0.4);
        canvas.save();
        canvas.translate(rect.center.dx + ox, rect.center.dy + oy);
        canvas.rotate(_hash(r, c, 94 + i) * math.pi);
        canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: rw, height: rh),
            Paint()
              ..color = const Color(0xFF14181E)
                  .withValues(alpha: 0.08 + k * 0.05 + i * 0.02)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        canvas.restore();
      }
    }
  }


  void _bannerPole(Canvas canvas, Rect rect) {
    final w = rect.width, h = rect.height;
    final x = rect.left + w * 0.5, y0 = rect.top + h * 0.22;
    canvas.drawLine(
        Offset(x, y0),
        Offset(x, rect.top + h * 0.85),
        Paint()
          ..color = const Color(0xFF6B4E2E)
          ..strokeWidth = 2);
    final flap = math.sin(_at * 5 + x * 0.03) * w * 0.04;
    canvas.drawPath(
        Path()
          ..moveTo(x, y0)
          ..lineTo(x + w * 0.3, y0 + h * 0.06 + flap)
          ..lineTo(x, y0 + h * 0.16)
          ..close(),
        Paint()..color = const Color(0xFF3D7BFF));
  }

  void _campClutter(Canvas canvas, Rect rect, int r, int c) {
    final w = rect.width;
    if (_hash(r, c, 74) > 0.5) {
      // a proper HAYSTACK — mounded, with a tie post
      final cH = rect.center.translate(0, w * 0.06);
      canvas.drawOval(
          Rect.fromCenter(
              center: cH.translate(0, w * 0.14), width: w * 0.5, height: w * 0.16),
          Paint()..color = Colors.black.withValues(alpha: 0.2));
      final stack = Path()
        ..moveTo(cH.dx - w * 0.24, cH.dy + w * 0.14)
        ..quadraticBezierTo(
            cH.dx - w * 0.2, cH.dy - w * 0.18, cH.dx, cH.dy - w * 0.24)
        ..quadraticBezierTo(
            cH.dx + w * 0.2, cH.dy - w * 0.18, cH.dx + w * 0.24, cH.dy + w * 0.14)
        ..close();
      canvas.drawPath(stack, Paint()..color = const Color(0xFFC9A94E));
      final strand = Paint()
        ..color = const Color(0xFF9A7E33)
        ..strokeWidth = 1;
      for (var i = 0; i < 3; i++) {
        canvas.drawLine(
            Offset(cH.dx - w * (0.12 - i * 0.02), cH.dy - w * (0.02 + i * 0.06)),
            Offset(cH.dx + w * (0.14 - i * 0.02), cH.dy - w * (0.06 + i * 0.05)),
            strand);
      }
      canvas.drawLine(Offset(cH.dx, cH.dy - w * 0.24), Offset(cH.dx, cH.dy - w * 0.34),
          Paint()
            ..color = const Color(0xFF6B4E2E)
            ..strokeWidth = 1.6);
    } else {
      // training dummy
      final cx = rect.center.dx, cy = rect.center.dy;
      final wood = Paint()
        ..color = const Color(0xFF6B4E2E)
        ..strokeWidth = 2;
      canvas.drawLine(
          Offset(cx, cy + w * 0.2), Offset(cx, cy - w * 0.15), wood);
      canvas.drawLine(Offset(cx - w * 0.14, cy - w * 0.05),
          Offset(cx + w * 0.14, cy - w * 0.05), wood);
      canvas.drawCircle(Offset(cx, cy - w * 0.2), w * 0.07,
          Paint()..color = const Color(0xFFC9B08A));
    }
  }

  // ── patrol: a little hooded guard pacing a loop around each tent ────────────
  void _patrolPass(Canvas canvas) {
    for (var r = _r0; r <= _r1; r++) {
      for (var c = _c0; c <= _c1; c++) {
        final s = base.structAt(r, c);
        if (s == null || !s.alive || s.type != DefType.guardPost) continue;
        final rect = _rect(r, c);
        final phase = _hash(r, c, 75) * math.pi * 2;
        final a = _at * 0.9 + phase;
        final rad = rect.width * (s.level >= 2 ? 0.85 : 0.7);
        final px = rect.center.dx + math.cos(a) * rad;
        final py = rect.center.dy +
            math.sin(a) * rad * 0.8 -
            math.sin(a * 6).abs() * rect.height * 0.03; // walking bob
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(px, py + rect.height * 0.09),
                width: rect.width * 0.12,
                height: rect.width * 0.05),
            Paint()..color = Colors.black.withValues(alpha: 0.3));
        canvas.drawCircle(Offset(px, py), rect.width * 0.07,
            Paint()..color = const Color(0xFF5E6B7A));
        canvas.drawCircle(Offset(px, py - rect.height * 0.07),
            rect.width * 0.045, Paint()..color = const Color(0xFFC9B08A));
      }
    }
  }

  // ── fire & smoke on wounded buildings, embers on rubble ─────────────────────
  void _burnFx(Canvas canvas, Rect rect, int r, int c, double hpFrac) {
    if (!_hiDetail) {
      // zoomed out: a single static ember, no smoke particles
      canvas.drawCircle(
          rect.center,
          rect.width * 0.12,
          Paint()..color = const Color(0xFFFF8A3D).withValues(alpha: 0.35));
      return;
    }
    final w = rect.width;
    final n = hpFrac < 0.18 ? 3 : 2;
    for (var i = 0; i < n; i++) {
      final fx = rect.left + w * (0.3 + _hash(r, c, 80 + i) * 0.4);
      final fy = rect.top + rect.height * (0.35 + _hash(r, c, 90 + i) * 0.3);
      final flick = 0.5 + 0.5 * math.sin(_at * (7 + i * 2.3) + i * 2 + r + c);
      canvas.drawCircle(
          Offset(fx, fy),
          w * (0.05 + 0.03 * flick),
          Paint()
            ..color =
                const Color(0xFFFF8A3D).withValues(alpha: 0.5 + 0.3 * flick));
      canvas.drawCircle(Offset(fx, fy - w * 0.03), w * 0.03 * flick,
          Paint()..color = const Color(0xFFFFD34D).withValues(alpha: 0.7));
      // smoke drifting up
      final drift = (_at * 0.25 + _hash(r, c, 100 + i)) % 1.0;
      canvas.drawCircle(
          Offset(fx + math.sin(_at * 2 + i) * w * 0.04,
              fy - drift * rect.height * 0.7),
          w * (0.05 + drift * 0.06),
          Paint()
            ..color =
                const Color(0xFF6B7482).withValues(alpha: 0.35 * (1 - drift)));
    }
  }

  void _sprite(Canvas canvas, Offset center, String emoji, WarSide side, double hpFrac,
      {bool selected = false, int level = 1}) {
    final s = tile * 0.32;
    final col = side == WarSide.you ? _you : _enemy;
    if (selected) {
      canvas.drawCircle(
          center,
          s * 1.65,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = JarsColors.gold);
    }
    canvas.drawOval(
        Rect.fromCenter(center: center.translate(0, s), width: s * 1.5, height: s * 0.5),
        Paint()..color = Colors.black.withValues(alpha: 0.4));
    final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: s * 1.75, height: s * 1.75),
        Radius.circular(s * 0.55));
    canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(col, Colors.white, 0.3)!, col],
          ).createShader(rr.outerRect));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = Colors.white.withValues(alpha: 0.9));
    _emojiAt(canvas, center.translate(0, -1), emoji, s * 1.05);
    final bw = s * 1.75;
    final bx = center.dx - bw / 2, by = center.dy + s * 0.98;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, 3.2), const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.55));
    final frac = hpFrac.clamp(0.0, 1.0);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw * frac, 3.2), const Radius.circular(2)),
        Paint()
          ..color = frac > 0.5
              ? JarsColors.green
              : (frac > 0.25 ? JarsColors.gold : JarsColors.red));
    if (level > 1) {
      _textAt(canvas, center.translate(s * 0.95, -s * 0.95), 'L$level', s * 0.68, JarsColors.gold);
    }
  }

  void _emojiAt(Canvas canvas, Offset center, String e, double size, {double a = 1}) {
    final tp = TextPainter(
      text: TextSpan(
          text: e, style: TextStyle(fontSize: size, color: Colors.white.withValues(alpha: a))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _textAt(Canvas canvas, Offset center, String s, double size, Color c) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: GoogleFonts.spaceGrotesk(
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: c,
              shadows: const [Shadow(color: Colors.black, blurRadius: 2)])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(WarBoardPainter old) => true;
}

/// Geometry helper so screens size the board and map taps consistently.
class BoardGeom {
  final double tile, gx, gy;
  final int rows, cols;
  const BoardGeom(this.tile, this.gx, this.gy,
      {this.rows = Base.defaultSize, this.cols = Base.defaultSize});
  factory BoardGeom.fit(double w, double h, {Base? base}) {
    final rows = base?.rows ?? Base.defaultSize;
    final cols = base?.cols ?? Base.defaultSize;
    final tile = math.min((w - 20) / cols, (h - 20) / rows);
    return BoardGeom(tile, (w - tile * cols) / 2, (h - tile * rows) / 2,
        rows: rows, cols: cols);
  }
  Cell? cellAt(Offset local) {
    final c = ((local.dx - gx) / tile).floor();
    final r = ((local.dy - gy) / tile).floor();
    if (r < 0 || r >= rows || c < 0 || c >= cols) return null;
    return Cell(r, c);
  }
}
