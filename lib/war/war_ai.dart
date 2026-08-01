import 'dart:math' as math;

import '../core/seeded_rng.dart';
import 'war_base.dart';
import 'war_engine.dart';
import 'war_player.dart';
import 'war_troop.dart';
import 'war_types.dart';

/// Dials into the stronghold grammar. The game leaves them null (seeded +
/// skill-driven); the Base Lab turns them by hand.
class StrongholdStyle {
  final int? archetype; // null=seeded: 0 keep, 1 bailey, 2 twin forts
  final int? gates; // doors per compound (1–3)
  final int? pad; // wall distance from the castle cluster (2–5)
  final int? chamfer; // 45° corner cut size (0–3)
  final int? towerSpacing; // outline cells between wall-band towers (2–6)
  final bool? innerKeep; // null=auto (wards replaced it; force via Lab)
  final int? layers; // interior WARD partitions (null = skill-seeded, up to 8)
  final int? rooms; // CITADEL room target (null = auto past skill 1.0)

  /// FLOOR under the citadel room target — raises the auto plan without
  /// capping it. Leagues use this so a bigger rung never builds a smaller
  /// city than the difficulty dial already earns.
  final int? minRooms;

  /// League-gated defenses the builder is allowed to place (tribute chest,
  /// command tent, pitch pot, citadel core). Empty = none of those.
  final Set<DefType> unlockDefs;

  const StrongholdStyle(
      {this.archetype,
      this.gates,
      this.pad,
      this.chamfer,
      this.towerSpacing,
      this.innerKeep,
      this.layers,
      this.rooms,
      this.minRooms,
      this.unlockDefs = const {}});
}

/// What the generator actually built — read by the Lab readout and the tests.
class BuildStats {
  final int rooms, structures, coreArea;
  const BuildStats(
      {required this.rooms, required this.structures, this.coreArea = 0});
}

/// The clan-war brain: designs strongholds in Prep, fights fog-honest battles
/// in War, and meters resource income. Everything scales with [AiLevel];
/// everything is seeded so fast-forward is reproducible.
class WarAi {
  // ── PREP: build a real stronghold ───────────────────────────────────────────
  static void designBase(Base base, List<WarPlayer> players, SeededRng rng,
      {StrongholdStyle style = const StrongholdStyle()}) {
    final n = players.length;
    final avgSkill = players.isEmpty
        ? 0.5
        : players.map((p) => p.skill).reduce((a, b) => a + b) / players.length;
    // CITADEL: past master skill the core stops being a fort and becomes a
    // walled CITY of wards. Auto past skill 1.0; the Lab can force a target.
    final citadel = (style.rooms ?? 0) > 1 ||
        (style.minRooms ?? 0) > 1 ||
        (style.rooms == null && avgSkill > 1.0);
    // every war a different fortress: a seeded archetype shapes the whole
    // base, and the keep is never pinned to dead-center (a citadel never
    // splits into twins — the city IS the map)
    final archetype = style.archetype ??
        rng.intRange(0, citadel ? 2 : 3); // 0 keep, 1 bailey, 2 twins
    final cr = (base.rows ~/ 2 + rng.intRange(-4, 5)).clamp(7, base.rows - 8);
    final cc = (base.cols ~/ 2 + rng.intRange(-4, 5)).clamp(7, base.cols - 8);
    final horizontal = rng.unit() < 0.5; // twin forts split axis
    for (var i = 0; i < n; i++) {
      // citadel castles spread WIDER: at spread 3 two castles' no-split
      // bands touch and block every partition lane between them
      var ar = cr, ac = cc, spread = citadel ? 4 : 3;
      if (archetype == 2 && n >= 2) {
        // two compounds, castles dealt alternately between them
        final off = (i % 2 == 0) ? -5 : 5;
        if (horizontal) {
          ac = (cc + off).clamp(5, base.cols - 6);
        } else {
          ar = (cr + off).clamp(5, base.rows - 6);
        }
        spread = 1;
        // don't pitch a fort in the drink — nudge off water/rock ground
        int badness(int rr, int cc) {
          var bad = 0;
          for (var dr = -2; dr <= 2; dr++) {
            for (var dc = -2; dc <= 2; dc++) {
              final t = base.at(rr + dr, cc + dc)?.terrain;
              if (t == null || t == Terrain.river || t == Terrain.mountain) {
                bad++;
              }
            }
          }
          return bad;
        }

        for (var k = 0; k < 3 && badness(ar, ac) > 8; k++) {
          if (horizontal) {
            ac += ac < base.cols ~/ 2 ? 3 : -3;
          } else {
            ar += ar < base.rows ~/ 2 ? 3 : -3;
          }
        }
        ar = ar.clamp(5, base.rows - 6);
        ac = ac.clamp(5, base.cols - 6);
      }
      final spot = _castleSpot(base, ar, ac, i, n, rng, spread: spread);
      if (spot != null) base.placeCastle(players[i].id, spot.r, spot.c);
    }
    _buildStronghold(base, players, rng, archetype, style);
    for (final p in players) {
      p.ready = true;
    }
  }

  /// Castles cluster TIGHT near their anchor — one keep, not scattered camps.
  static Cell? _castleSpot(
      Base base, int cr, int cc, int i, int n, SeededRng rng,
      {int spread = 2}) {
    final angle = i * (2 * math.pi / (n == 0 ? 1 : n)) + rng.unit() * 0.8;
    final dist = n == 1 ? 0 : spread + rng.intRange(0, 2);
    final row = (cr + (math.sin(angle) * dist).round()).clamp(4, base.rows - 5);
    final col = (cc + (math.cos(angle) * dist).round()).clamp(4, base.cols - 5);
    for (var rad = 0; rad < 6; rad++) {
      for (var dr = -rad; dr <= rad; dr++) {
        for (var dc = -rad; dc <= rad; dc++) {
          final r = (row + dr).clamp(3, base.rows - 4);
          final c = (col + dc).clamp(3, base.cols - 4);
          if (base.canPlace(r, c)) return Cell(r, c);
        }
      }
    }
    return null;
  }

  /// The stronghold algorithm v4 — GRAMMAR, not noise. Every fortress is
  /// composed from deliberate pieces: straight rampart runs with 45° cut
  /// corners, archer towers on the shoulders, real GATES with a kill-box
  /// (mines down the approach lane, wire on the flanks, a tesla hidden just
  /// inside), an inner keep hugging the castles with the mortar at its heart,
  /// and a tower band spaced EVENLY along the walls. Purpose, pattern, rhythm.
  static void _buildStronghold(Base base, List<WarPlayer> players,
      SeededRng rng, int archetype, StrongholdStyle style) {
    final castles = base.castleCells;
    if (castles.isEmpty || players.isEmpty) return;

    // pooled clan treasury: the richest willing payer funds each piece
    bool buy(int r, int c, DefType t) {
      if (!base.canPlace(r, c)) return false;
      final cost = kDefSpecs[t]!.cost;
      for (final p in players) {
        if (p.resources >= cost) {
          base.place(r, c, t, p.id);
          p.resources -= cost;
          return true;
        }
      }
      return false;
    }

    // jittered placement: try the spot, then seeded nudges around it
    bool buyNear(int r, int c, DefType t, {int tries = 8, int spread = 2}) {
      if (buy(r, c, t)) return true;
      for (var i = 0; i < tries; i++) {
        final rr = r + rng.intRange(-spread, spread + 1);
        final cc = c + rng.intRange(-spread, spread + 1);
        if (buy(rr, cc, t)) return true;
      }
      return false;
    }

    final skill =
        players.map((p) => p.skill).reduce((a, b) => a + b) / players.length;
    final depth = (skill * 10).round(); // rookie ~2, seasoned 5, master 10

    // A bigger board has to be FILLED — the same city on a 64² map would
    // rattle around inside it, so the plan grows with the canvas.
    final areaMul = 1 +
        ((base.rows * base.cols) / (Base.defaultSize * Base.defaultSize) - 1) *
            0.6;

    // CITADEL room budget: auto ramps from ~10 rooms just past master to
    // ~35 at the nightmare end of the dial; the Lab can force any target.
    final autoTarget = (style.rooms != null && style.rooms! > 1)
        ? style.rooms!.clamp(2, 72)
        : (style.rooms == null && skill > 1.0)
            ? (((10 + (skill - 1.0) / 0.5 * 24) * areaMul).round() +
                    rng.intRange(-3, 4))
                .clamp(6, 72)
            : null;
    // A league FLOOR only ever raises the plan — never shrinks what the
    // difficulty dial already bought.
    final floorTarget = (style.minRooms != null && style.minRooms! > 1)
        ? (style.minRooms! * areaMul).round().clamp(2, 72)
        : null;
    final int? roomTarget = autoTarget == null
        ? floorTarget
        : (floorTarget == null
            ? autoTarget
            : math.max(autoTarget, floorTarget));
    final citadel = roomTarget != null;

    // Heavy artillery + pitch budgets — scale with the city, but DON'T let
    // leftover-loop spam dump 40 pitch pots on every doorway once the chest
    // is fat. Mortars used to hard-cap at ~4 even on Radiant (rooms~/8).
    var mortarsPlaced = 0;
    var pitchesPlaced = 0;
    final mortarCap = citadel
        ? (2 + roomTarget! ~/ 4 + (base.rows >= 56 ? 2 : 0)).clamp(2, 14)
        : (depth >= 7 ? 1 : 0);
    final pitchCap = citadel
        ? (4 + roomTarget! ~/ 10).clamp(4, 14)
        : (depth >= 6 ? 3 : 0);

    // spacing discipline: towers keep their distance so the base BREATHES —
    // rhythm instead of clumps
    final towerSpots = <List<int>>[];
    bool buyTower(int r, int c, DefType t) {
      for (final p in towerSpots) {
        if (math.max((p[0] - r).abs(), (p[1] - c).abs()) < 2) return false;
      }
      if (!buy(r, c, t)) return false;
      towerSpots.add([r, c]);
      return true;
    }

    bool buyTowerNear(int r, int c, DefType t) =>
        buyTower(r, c, t) ||
        buyTower(r + 1, c, t) ||
        buyTower(r, c + 1, t) ||
        buyTower(r - 1, c, t) ||
        buyTower(r, c - 1, t);

    // seeded draw of n distinct sides (0 top, 1 right, 2 bottom, 3 left)
    List<int> pickSides(int n) {
      final sides = [0, 1, 2, 3];
      final out = <int>[];
      while (out.length < n && sides.isNotEmpty) {
        out.add(sides.removeAt(rng.intRange(0, sides.length)));
      }
      return out;
    }

    // ── compounds: twin forts wall two groups, everyone else walls one ──
    List<List<Cell>> groups = [castles];
    if (archetype == 2 && castles.length >= 2) {
      final minR = castles.map((c) => c.r).reduce(math.min);
      final maxR = castles.map((c) => c.r).reduce(math.max);
      final minC = castles.map((c) => c.c).reduce(math.min);
      final maxC = castles.map((c) => c.c).reduce(math.max);
      final splitRows = (maxR - minR) >= (maxC - minC);
      final mid = splitRows ? (minR + maxR) / 2 : (minC + maxC) / 2;
      final a = <Cell>[], b = <Cell>[];
      for (final c in castles) {
        ((splitRows ? c.r : c.c) <= mid ? a : b).add(c);
      }
      // a real gap or it's just one keep
      if (a.isNotEmpty && b.isNotEmpty && (maxR - minR) + (maxC - minC) >= 6) {
        groups = [a, b];
      }
    }

    final rects = <List<int>>[]; // [r0, r1, c0, c1] per compound
    final gateInfo = <List<int>>[]; // [r, c, outR, outC] per placed OUTER gate
    final innerGates = <List<int>>[]; // ward doors [r, c]

    // gate discipline: no two doors ever stand next to each other
    final gateCells = <int>[];
    bool gateClear(int r, int c) {
      for (final k in gateCells) {
        if ((k ~/ base.cols - r).abs() <= 1 && (k % base.cols - c).abs() <= 1) {
          return false;
        }
      }
      return true;
    }

    void registerGate(int r, int c) => gateCells.add(r * base.cols + c);

    var coreRegions = const <List<int>>[]; // the core's wards, for furnishing
    var coreArea = 0; // the core's footprint (Lab readout + density tests)
    var compound = 0;
    for (final group in groups) {
      // twins are CORE + OUTPOST, not copy-paste: the core gets room, layers,
      // and the full band; the outpost is a lean satellite
      final isCore = compound++ == 0;
      final outpost = groups.length > 1 && !isCore;

      // ── the polygon: castle bbox + per-side padding, corners cut at 45° ──
      final gr0 = group.map((x) => x.r).reduce(math.min);
      final gr1 = group.map((x) => x.r).reduce(math.max);
      final gc0 = group.map((x) => x.c).reduce(math.min);
      final gc1 = group.map((x) => x.c).reduce(math.max);
      int pad() {
        if (outpost) return 2;
        if (citadel && archetype != 2) {
          // a CITADEL sprawls — but only as far as its rooms demand: the
          // DENSITY holds whether the city has ten wards or forty
          return ((style.pad ??
                      (4 + (roomTarget! * 0.3).round() + rng.intRange(0, 2))) +
                  group.length ~/ 2)
              .clamp(2, math.max(14, base.rows ~/ 3));
        }
        return ((style.pad ?? 2 + rng.intRange(0, 2)) +
                rng.intRange(0, archetype == 1 ? 3 : 2) +
                group.length ~/ 2 + // more castles → a GRANDER city
                (groups.length > 1 && isCore ? 1 : 0))
            .clamp(2, 7);
      }
      // the wall NEVER lands on the castles: stay ≥2 beyond their bbox
      var r0 = math.min(gr0 - 2, math.max(gr0 - pad(), 3)).clamp(3, base.rows - 4);
      var r1 = math.max(gr1 + 2, math.min(gr1 + pad(), base.rows - 4)).clamp(3, base.rows - 4);
      var c0 = math.min(gc0 - 2, math.max(gc0 - pad(), 3)).clamp(3, base.cols - 4);
      var c1 = math.max(gc1 + 2, math.min(gc1 + pad(), base.cols - 4)).clamp(3, base.cols - 4);

      // hug the bank: a side drowning in water pulls in toward dry land
      int wet(int side, int a0, int a1, int b0, int b1) {
        var n = 0;
        if (side == 0 || side == 1) {
          final r = side == 0 ? a0 : a1;
          for (var c = b0; c <= b1; c++) {
            final t = base.grid[r][c].terrain;
            if (t == Terrain.river || t == Terrain.bridge) n++;
          }
        } else {
          final c = side == 2 ? b0 : b1;
          for (var r = a0; r <= a1; r++) {
            final t = base.grid[r][c].terrain;
            if (t == Terrain.river || t == Terrain.bridge) n++;
          }
        }
        return n;
      }

      for (var side = 0; side < 4; side++) {
        final len = side < 2 ? (c1 - c0 + 1) : (r1 - r0 + 1);
        if (wet(side, r0, r1, c0, c1) <= len * 0.4) continue;
        for (var pull = 0; pull < 3; pull++) {
          if (side == 0 && r0 + 1 <= gr0 - 2) r0++;
          if (side == 1 && r1 - 1 >= gr1 + 2) r1--;
          if (side == 2 && c0 + 1 <= gc0 - 2) c0++;
          if (side == 3 && c1 - 1 >= gc1 + 2) c1--;
          if (wet(side, r0, r1, c0, c1) == 0) break;
        }
      }
      rects.add([r0, r1, c0, c1]);

      // per-corner cuts — no two corners have to match (unless the Lab says so)
      final chMax =
          math.max(0, math.min((r1 - r0 - 3) ~/ 2, (c1 - c0 - 3) ~/ 2));
      int cut() => math.min(style.chamfer ?? rng.intRange(0, 4), chMax);
      final chNW = cut(), chNE = cut(), chSE = cut(), chSW = cut();

      // four straight runs (with inward normals) + 45° corner staircases —
      // diagonal walls SEAL 4-dir movement, and the rampart art connects them
      final top = [
        for (var c = c0 + chNW; c <= c1 - chNE; c++) [r0, c, 1, 0]
      ];
      final right = [
        for (var r = r0 + chNE; r <= r1 - chSE; r++) [r, c1, 0, -1]
      ];
      final bottom = [
        for (var c = c0 + chSW; c <= c1 - chSE; c++) [r1, c, -1, 0]
      ];
      final left = [
        for (var r = r0 + chNW; r <= r1 - chSW; r++) [r, c0, 0, 1]
      ];
      final cuts = <List<int>>[
        for (var i = 1; i < chNE; i++) [r0 + i, c1 - chNE + i, 1, -1],
        for (var i = 1; i < chSE; i++) [r1 - chSE + i, c1 - i, -1, -1],
        for (var i = 1; i < chSW; i++) [r1 - i, c0 + chSW - i, -1, 1],
        for (var i = 1; i < chNW; i++) [r0 + chNW - i, c0 + i, 1, 1],
      ];
      final runs = [top, right, bottom, left];

      // ── gates: doors mid-run (jittered), never on a corner ──
      final gateKeys = <int>{};
      final gateSides = <int>{};
      final gateCount =
          (style.gates ?? (1 + (depth >= 6 ? rng.intRange(0, 2) : 0)))
              .clamp(1, 3);
      for (final side in pickSides(gateCount)) {
        final run = runs[side];
        if (run.length < 5) continue;
        final j = run.length ~/ 2 +
            rng.intRange(-(run.length ~/ 4), run.length ~/ 4 + 1);
        final g = run[j.clamp(2, run.length - 3)];
        if (!gateClear(g[0], g[1])) continue;
        gateKeys.add(g[0] * base.cols + g[1]);
        registerGate(g[0], g[1]);
        gateSides.add(side);
      }
      if (gateKeys.isEmpty) {
        // every fort has a door — force one onto the longest run
        final longest = runs.reduce((a, b) => a.length >= b.length ? a : b);
        if (longest.length >= 3) {
          final g = longest[longest.length ~/ 2];
          gateKeys.add(g[0] * base.cols + g[1]);
          registerGate(g[0], g[1]);
        }
      }

      // ── the BITE: a rectangular notch on a gate-free face (~40% of forts) ──
      if (depth >= 4 && rng.unit() < 0.4) {
        final bSide = !gateSides.contains(0) && top.length >= 9
            ? 0
            : (!gateSides.contains(2) && bottom.length >= 9 ? 2 : -1);
        if (bSide >= 0) {
          final run = runs[bSide];
          final w = math.min(3 + rng.intRange(0, 3), run.length - 6);
          final bi = 2 + rng.intRange(0, run.length - w - 4);
          final d = 2 + rng.intRange(0, 2);
          final rr = run.first[0]; // the run's row
          final inR = run.first[2]; // +1 on top, -1 on bottom
          final ca = run[bi][1], cb = run[bi + w - 1][1];
          // keep the notch's floor clear of the castles
          if ((bSide == 0 && rr + inR * d <= gr0 - 2) ||
              (bSide == 2 && rr + inR * d >= gr1 + 2)) {
            run.removeWhere((o) => o[1] > ca && o[1] < cb);
            for (var k = 1; k <= d; k++) {
              cuts.add([rr + inR * k, ca, 0, -1]); // left leg
              cuts.add([rr + inR * k, cb, 0, 1]); // right leg
            }
            for (var c = ca + 1; c < cb; c++) {
              cuts.add([rr + inR * d, c, inR, 0]); // notch floor
            }
          }
        }
      }

      final outline = [...top, ...right, ...bottom, ...left, ...cuts];

      // ── raise the walls: terrain is a CONSTRAINT, not a casualty ──
      final piecesBought = <List<int>>[];
      final gateInfoStart = gateInfo.length;
      final gateCellsStart = gateCells.length;
      for (final o in outline) {
        final r = o[0], c = o[1];
        if (!base.inBounds(r, c)) continue;
        final terr = base.grid[r][c].terrain;
        final isGate = gateKeys.contains(r * base.cols + c);
        if (terr == Terrain.bridge) {
          // the bridge is a PASSAGE — the door stands at its landward end
          final dr = r + o[2], dc = c + o[3];
          if (!base.inBounds(dr, dc)) continue;
          if (base.grid[dr][dc].terrain == Terrain.forest) {
            base.grid[dr][dc].terrain = Terrain.plains;
            base.cleared.add(dr * base.cols + dc);
          }
          if (gateClear(dr, dc) && buy(dr, dc, DefType.gate)) {
            gateInfo.add([dr, dc, -o[2], -o[3]]);
            registerGate(dr, dc);
            piecesBought.add([dr, dc]);
          }
          continue;
        }
        if (!TerrainData.passable(terr)) continue; // mountain/river seals free
        if (terr == Terrain.forest) {
          // the clan CLEARS land for its wall — never a forest hole
          base.grid[r][c].terrain = Terrain.plains;
          base.cleared.add(r * base.cols + c);
        }
        if (buy(r, c, isGate ? DefType.gate : DefType.wall)) {
          piecesBought.add([r, c]);
          if (isGate) gateInfo.add([r, c, -o[2], -o[3]]);
        }
        // occupied cell = a castle already seals it
      }
      // a FRAGMENT fort (walls mostly eaten by terrain) is worse than none:
      // tear it down, bank the ⚡, and skip its furnishing entirely
      if (piecesBought.length < 8) {
        for (final pc in piecesBought) {
          players.first.resources += base.removeAt(pc[0], pc[1]);
        }
        gateInfo.removeRange(gateInfoStart, gateInfo.length);
        gateCells.removeRange(gateCellsStart, gateCells.length);
        rects.removeLast();
        continue;
      }

      // ── WARDS: slice the interior into compartments (BSP), each with its
      // own door and its own JOB — randomly layered like a real citadel,
      // not the same outer-wall-plus-keep pattern every time ──
      if (isCore) {
        bool nearCastle(int rr, int cc) =>
            group.any((k) => (k.r - rr).abs() <= 1 && (k.c - cc).abs() <= 1);
        final regions = <List<int>>[
          [r0 + 1, r1 - 1, c0 + 1, c1 - 1]
        ];
        if (citadel) {
          // ── CITADEL BSP: keep splitting the biggest room until the city
          // reaches its roomTarget (or nothing left will split). Rooms bottom
          // out around 3×4 cells; a quarter of the partitions rise DOORLESS —
          // sealed VAULTS you can only breach into, CoC-style. ──
          final active = List<List<int>>.of(regions);
          final done = <List<int>>[];
          var splits = 0;
          var vaults = 0;
          final vaultCap = roomTarget! ~/ 4;
          while (active.isNotEmpty &&
              active.length + done.length < roomTarget) {
            active.sort((a, b) => ((b[1] - b[0]) * (b[3] - b[2]))
                .compareTo((a[1] - a[0]) * (a[3] - a[2])));
            final reg = active.first;
            final h = reg[1] - reg[0], w = reg[3] - reg[2];
            if (math.max(h, w) < 5 || math.min(h, w) < 3) {
              done.add(active.removeAt(0));
              continue;
            }
            // a PERFORATED wall is worse than no wall: if the clan can't
            // afford the whole line, stop carving and bank it for furniture
            final funds = players.fold(0.0, (a, p) => a + p.resources);
            if (funds < math.max(h, w) * 15 + 20) break;
            var vertical = w >= h;
            var placedLine = false;
            var s = 0;
            for (var axis = 0; axis < 2 && !placedLine; axis++) {
              if (axis == 1) vertical = !vertical;
              final span0 = vertical ? h : w;
              final cand0 = vertical
                  ? (reg[2] + reg[3]) ~/ 2 +
                      rng.intRange(-(w ~/ 4), w ~/ 4 + 1)
                  : (reg[0] + reg[1]) ~/ 2 +
                      rng.intRange(-(h ~/ 4), h ~/ 4 + 1);
              final castleMid =
                  vertical ? (gc0 + gc1) ~/ 2 : (gr0 + gr1) ~/ 2;
              final cands = <int>[
                if (splits == 0) ...[
                  castleMid,
                  castleMid + 1,
                  castleMid - 1,
                  castleMid + 2,
                  castleMid - 2
                ],
                cand0,
                cand0 + 1,
                cand0 - 1,
                cand0 + 2,
                cand0 - 2,
                cand0 + 3,
              ];
              for (final cand in cands) {
                final lo = vertical ? reg[2] + 2 : reg[0] + 2;
                final hi = vertical ? reg[3] - 2 : reg[1] - 2;
                if (cand < lo || cand > hi) continue;
                var clearOfCastles = true;
                var blocked = 0;
                for (var i = 0; i <= span0; i++) {
                  final rr = vertical ? reg[0] + i : cand;
                  final cc = vertical ? cand : reg[2] + i;
                  if (nearCastle(rr, cc)) {
                    clearOfCastles = false;
                    break;
                  }
                  if (!TerrainData.passable(base.grid[rr][cc].terrain)) {
                    blocked++;
                  }
                }
                if (!clearOfCastles || blocked > span0 * 0.3) continue;
                s = cand;
                placedLine = true;
                break;
              }
            }
            if (!placedLine) {
              // this room refuses to split both ways — it's done growing
              done.add(active.removeAt(0));
              continue;
            }
            splits++;
            final span = vertical ? h : w;
            // the door: a VAULT keeps none; otherwise scan EVERY cell from a
            // seeded start until one clears the no-adjacent-gates rule —
            // doorless-by-accident never happens
            var doorAt = -1;
            final wantVault =
                splits > 2 && vaults < vaultCap && rng.unit() < 0.25;
            if (wantVault) {
              vaults++;
            } else {
              final int mod = math.max(1, span - 1);
              final start = rng.intRange(0, mod);
              for (var t = 0; t < span - 1 && doorAt < 0; t++) {
                final cand = 1 + (start + t) % mod;
                final dr = vertical ? reg[0] + cand : s;
                final dc = vertical ? s : reg[2] + cand;
                if (gateClear(dr, dc)) doorAt = cand;
              }
              if (doorAt < 0) vaults++; // every spot blocked → a vault then
            }
            for (var i = 0; i <= span; i++) {
              final rr = vertical ? reg[0] + i : s;
              final cc = vertical ? s : reg[2] + i;
              if (!TerrainData.passable(base.grid[rr][cc].terrain)) continue;
              if (base.grid[rr][cc].terrain == Terrain.forest) {
                base.grid[rr][cc].terrain = Terrain.plains;
                base.cleared.add(rr * base.cols + cc);
              }
              if (i == doorAt) {
                if (buy(rr, cc, DefType.gate)) {
                  registerGate(rr, cc);
                  innerGates.add([rr, cc]);
                }
              } else {
                buy(rr, cc, DefType.wall);
              }
            }
            active.removeAt(0);
            if (vertical) {
              active.add([reg[0], reg[1], reg[2], s - 1]);
              active.add([reg[0], reg[1], s + 1, reg[3]]);
            } else {
              active.add([reg[0], s - 1, reg[2], reg[3]]);
              active.add([s + 1, reg[1], reg[2], reg[3]]);
            }
          }
          regions
            ..clear()
            ..addAll(active)
            ..addAll(done);
        } else {
        final layers = (style.layers ??
                (depth <= 3
                    ? rng.intRange(0, 2)
                    : 1 +
                        group.length ~/ 2 +
                        rng.intRange(0, 3) +
                        // brutal clans build CITADELS, not yards
                        (skill >= 1.0 ? 2 : (skill >= 0.7 ? 1 : 0))))
            .clamp(0, 8);
        for (var l = 0; l < layers; l++) {
          // split the biggest room that still has space to give
          regions.sort((a, b) => ((b[1] - b[0]) * (b[3] - b[2]))
              .compareTo((a[1] - a[0]) * (a[3] - a[2])));
          final reg = regions.first;
          final h = reg[1] - reg[0], w = reg[3] - reg[2];
          if (math.max(h, w) < 6 || math.min(h, w) < 4) break;
          // try the longer axis first, then the other — a room blocked one
          // way can still split the other
          var vertical = w >= h;
          var placedLine = false;
          var s = 0;
          for (var axis = 0; axis < 2 && !placedLine; axis++) {
            if (axis == 1) vertical = !vertical;
            final span0 = vertical ? h : w;
            var cand0 = vertical
                ? (reg[2] + reg[3]) ~/ 2 +
                    rng.intRange(-(w ~/ 4), w ~/ 4 + 1)
                : (reg[0] + reg[1]) ~/ 2 +
                    rng.intRange(-(h ~/ 4), h ~/ 4 + 1);
            // aim the FIRST cut through the castle cluster's middle so the
            // castles end up in DIFFERENT wards
            final castleMid = vertical ? (gc0 + gc1) ~/ 2 : (gr0 + gr1) ~/ 2;
            final cands = <int>[
              if (l == 0) ...[
                castleMid,
                castleMid + 1,
                castleMid - 1,
                castleMid + 2,
                castleMid - 2
              ],
              cand0,
              cand0 + 1,
              cand0 - 1,
              cand0 + 2,
              cand0 - 2,
              cand0 + 3,
            ];
            for (final cand in cands) {
              final lo = vertical ? reg[2] + 2 : reg[0] + 2;
              final hi = vertical ? reg[3] - 2 : reg[1] - 2;
              if (cand < lo || cand > hi) continue;
              var clearOfCastles = true;
              var blocked = 0;
              for (var i = 0; i <= span0; i++) {
                final rr = vertical ? reg[0] + i : cand;
                final cc = vertical ? cand : reg[2] + i;
                if (nearCastle(rr, cc)) {
                  clearOfCastles = false;
                  break;
                }
                if (!TerrainData.passable(base.grid[rr][cc].terrain)) {
                  blocked++;
                }
              }
              // a line mostly through rock/water is nature's job, not ours
              if (!clearOfCastles || blocked > span0 * 0.3) continue;
              s = cand;
              placedLine = true;
              break;
            }
          }
          if (!placedLine) break;
          // pick the door BEFORE building, clear of every other gate
          final span = vertical ? h : w;
          var doorAt = -1;
          for (var t = 0; t < 8 && doorAt < 0; t++) {
            final cand = 1 + rng.intRange(0, math.max(1, span - 1));
            final dr = vertical ? reg[0] + cand : s;
            final dc = vertical ? s : reg[2] + cand;
            if (gateClear(dr, dc)) doorAt = cand;
          }
          // raise the partition (forest is cleared, terrain gaps stay natural)
          for (var i = 0; i <= span; i++) {
            final rr = vertical ? reg[0] + i : s;
            final cc = vertical ? s : reg[2] + i;
            if (!TerrainData.passable(base.grid[rr][cc].terrain)) continue;
            if (base.grid[rr][cc].terrain == Terrain.forest) {
              base.grid[rr][cc].terrain = Terrain.plains;
              base.cleared.add(rr * base.cols + cc);
            }
            if (i == doorAt) {
              if (buy(rr, cc, DefType.gate)) {
                registerGate(rr, cc);
                innerGates.add([rr, cc]);
              }
            } else {
              buy(rr, cc, DefType.wall);
            }
          }
          // the room becomes two rooms
          regions.removeAt(0);
          if (vertical) {
            regions.add([reg[0], reg[1], reg[2], s - 1]);
            regions.add([reg[0], reg[1], s + 1, reg[3]]);
          } else {
            regions.add([reg[0], s - 1, reg[2], reg[3]]);
            regions.add([s + 1, reg[1], reg[2], reg[3]]);
          }
        }
        }
        coreRegions = regions;
        coreArea = (r1 - r0 + 1) * (c1 - c0 + 1);
        // every ward gets a JOB
        for (final reg in regions) {
          final midR = (reg[0] + reg[1]) ~/ 2, midC = (reg[2] + reg[3]) ~/ 2;
          final hasCastle = group.any((k) =>
              k.r >= reg[0] && k.r <= reg[1] && k.c >= reg[2] && k.c <= reg[3]);
          if (hasCastle) {
            // the SANCTUM: the mortar guards the heart
            if (depth >= 7 && mortarsPlaced == 0) {
              if (buyNear(midR, midC, DefType.mortar, spread: 2)) {
                mortarsPlaced++;
              }
            }
            continue;
          }
          switch (rng.intRange(0, 4)) {
            case 0: // battery ward — guns, colors, and at the top: a SNIPER
              buyTowerNear(midR, midC,
                  depth >= 5 ? DefType.cannon : DefType.archerTower);
              buyTowerNear(midR + rng.intRange(-1, 2),
                  midC + rng.intRange(-1, 2), DefType.archerTower);
              if (depth >= 7) {
                buyNear(midR + rng.intRange(-1, 2), midC + rng.intRange(-1, 2),
                    DefType.banner,
                    spread: 1);
              }
              if (depth >= 8) {
                buyTowerNear(midR + rng.intRange(-2, 3),
                    midC + rng.intRange(-2, 3), DefType.ballista);
              }
              // a CITY mounts a BATTERY of mortars, not a single tube
              if (citadel &&
                  depth >= 7 &&
                  mortarsPlaced < mortarCap &&
                  rng.unit() < 0.85) {
                if (buyNear(midR + rng.intRange(-1, 2),
                    midC + rng.intRange(-1, 2), DefType.mortar,
                    spread: 2)) {
                  mortarsPlaced++;
                }
              }
            case 1: // camp ward — tents, and HOUSING to double the watch
              if (depth >= 4) {
                buyNear(midR, midC, DefType.guardPost, spread: 1);
                buyNear(midR + rng.intRange(-2, 3), midC + rng.intRange(-2, 3),
                    DefType.guardPost,
                    spread: 1);
                if (depth >= 6) {
                  buyNear(midR + rng.intRange(-1, 2), midC + rng.intRange(-1, 2),
                      DefType.housing,
                      spread: 1);
                }
              }
            case 2: // trap yard — an unassuming room full of teeth
              if (depth >= 5) {
                for (var m = 0; m < 3; m++) {
                  buy(reg[0] + rng.intRange(0, math.max(1, reg[1] - reg[0] + 1)),
                      reg[2] + rng.intRange(0, math.max(1, reg[3] - reg[2] + 1)),
                      DefType.landmine);
                }
                for (var m = 0; m < 2; m++) {
                  buy(reg[0] + rng.intRange(0, math.max(1, reg[1] - reg[0] + 1)),
                      reg[2] + rng.intRange(0, math.max(1, reg[3] - reg[2] + 1)),
                      DefType.barbedWire);
                }
                // an unassuming room — with LIGHTNING coiled in the corner
                if (citadel && depth >= 7 && rng.unit() < 0.5) {
                  buyTowerNear(midR, midC, DefType.tesla);
                }
                // pitch pots: hidden tar bombs in the trap yard
                if (style.unlockDefs.contains(DefType.pitchPot)) {
                  for (var m = 0; m < 2; m++) {
                    buy(
                        reg[0] +
                            rng.intRange(0, math.max(1, reg[1] - reg[0] + 1)),
                        reg[2] +
                            rng.intRange(0, math.max(1, reg[3] - reg[2] + 1)),
                        DefType.pitchPot);
                  }
                }
              }
            default: // open yard — a watcher, and the clan's granary
              if (depth >= 6 || rng.unit() < 0.5) {
                buyTowerNear(midR, midC, DefType.archerTower);
              }
              if (depth >= 5) {
                buyNear(midR + rng.intRange(-1, 2), midC + rng.intRange(-1, 2),
                    DefType.storehouse,
                    spread: 1);
              }
              if (depth >= 7 && rng.unit() < 0.5) {
                buyNear(midR + rng.intRange(-2, 3), midC + rng.intRange(-2, 3),
                    DefType.watchtower,
                    spread: 2);
              }
          }
        }
      }
      // no sanctum roll (or an outpost)? the mortar still takes the center
      if (mortarsPlaced == 0 && depth >= 7) {
        if (buyNear((gr0 + gr1) ~/ 2, (gc0 + gc1) ~/ 2, DefType.mortar,
            spread: 2)) {
          mortarsPlaced++;
        }
      }

      // ── inner keep: the OLD castle ring, off by default now (wards layer
      // instead) — the Lab chip can still force it on ──
      if ((style.innerKeep ?? citadel) &&
          isCore &&
          (r1 - r0) >= 8 &&
          (c1 - c0) >= 8) {
        final ir0 = math.max(gr0 - 1, r0 + 2);
        final ir1 = math.min(gr1 + 1, r1 - 2);
        final ic0 = math.max(gc0 - 1, c0 + 2);
        final ic1 = math.min(gc1 + 1, c1 - 2);
        if (ir1 - ir0 >= 2 && ic1 - ic0 >= 2) {
          // the keep's door faces the main gate — a layered approach
          int doorSide;
          if (gateInfo.isNotEmpty) {
            final g = gateInfo.first;
            doorSide = g[2] == -1
                ? 0
                : g[2] == 1
                    ? 2
                    : (g[3] == 1 ? 1 : 3);
          } else {
            doorSide = rng.intRange(0, 4);
          }
          var door = switch (doorSide) {
            0 => [ir0, (ic0 + ic1) ~/ 2],
            1 => [(ir0 + ir1) ~/ 2, ic1],
            2 => [ir1, (ic0 + ic1) ~/ 2],
            _ => [(ir0 + ir1) ~/ 2, ic0],
          };
          // the keep door must respect gate spacing — try the other faces,
          // and if every face is crowded the keep seals itself (a vault)
          if (!gateClear(door[0], door[1])) {
            door = const [-1, -1];
            for (final alt in [
              [ir0, (ic0 + ic1) ~/ 2],
              [(ir0 + ir1) ~/ 2, ic1],
              [ir1, (ic0 + ic1) ~/ 2],
              [(ir0 + ir1) ~/ 2, ic0],
            ]) {
              if (gateClear(alt[0], alt[1])) {
                door = alt;
                break;
              }
            }
          }
          final keepCells = <List<int>>[
            for (var c = ic0; c <= ic1; c++) ...[
              [ir0, c],
              [ir1, c]
            ],
            for (var r = ir0 + 1; r < ir1; r++) ...[
              [r, ic0],
              [r, ic1]
            ],
          ];
          for (final kc in keepCells) {
            if (base.grid[kc[0]][kc[1]].terrain == Terrain.forest) {
              base.grid[kc[0]][kc[1]].terrain = Terrain.plains;
              base.cleared.add(kc[0] * base.cols + kc[1]);
            }
            final isDoor = kc[0] == door[0] && kc[1] == door[1];
            if (buy(kc[0], kc[1], isDoor ? DefType.gate : DefType.wall) &&
                isDoor) {
              registerGate(kc[0], kc[1]);
              innerGates.add([kc[0], kc[1]]);
            }
          }
        }
      }

      // ── corner towers on the four shoulders (the grammar's signature) ──
      if (depth >= 2) {
        buyTowerNear(r0 + chNW ~/ 2 + 1, c0 + chNW ~/ 2 + 1, DefType.archerTower);
        buyTowerNear(r0 + chNE ~/ 2 + 1, c1 - chNE ~/ 2 - 1, DefType.archerTower);
        buyTowerNear(r1 - chSW ~/ 2 - 1, c0 + chSW ~/ 2 + 1, DefType.archerTower);
        buyTowerNear(r1 - chSE ~/ 2 - 1, c1 - chSE ~/ 2 - 1, DefType.archerTower);
      }

      // ── tower band: EVENLY spaced along the walls, cannons near the gates
      // (the outpost's band is sparser — it's a satellite, not the city;
      // the side FACING the nearest bridge packs its towers denser) ──
      if (depth >= 2) {
        final spacing =
            ((style.towerSpacing ?? (skill >= 1.0 ? 3 : 4)) +
                    (outpost ? 2 : 0))
                .clamp(2, 8);
        // which side does the traffic come from?
        var bridgeSide = -1;
        var bd = 1 << 30;
        for (var r = 0; r < base.rows; r++) {
          for (var c = 0; c < base.cols; c++) {
            if (base.grid[r][c].terrain != Terrain.bridge) continue;
            final d = (r - (r0 + r1) ~/ 2).abs() + (c - (c0 + c1) ~/ 2).abs();
            if (d < bd) {
              bd = d;
              final dr = r - (r0 + r1) ~/ 2, dc = c - (c0 + c1) ~/ 2;
              bridgeSide = dr.abs() >= dc.abs()
                  ? (dr < 0 ? 0 : 2) // top / bottom
                  : (dc < 0 ? 3 : 1); // left / right
            }
          }
        }
        int sideOf(int i) => i < top.length
            ? 0
            : i < top.length + right.length
                ? 1
                : i < top.length + right.length + bottom.length
                    ? 2
                    : 3;
        var beat = 0;
        for (var i = 0; i < outline.length - cuts.length; i++) {
          final o = outline[i];
          final need =
              (sideOf(i) == bridgeSide ? spacing - 1 : spacing).clamp(2, 8);
          if (++beat < need) continue;
          beat = 0;
          final tr = o[0] + o[2], tc = o[1] + o[3]; // one step inward
          // never block a doorway
          if (gateInfo
              .any((g) => (g[0] - tr).abs() + (g[1] - tc).abs() <= 1)) {
            continue;
          }
          final nearGate = gateInfo
              .any((g) => (g[0] - tr).abs() + (g[1] - tc).abs() <= 3);
          buyTower(tr, tc,
              depth >= 5 && nearGate ? DefType.cannon : DefType.archerTower);
        }
      }
    }

    // ── ward doors get a watchman's tent beside them (no kill-box inside) ──
    if (depth >= 4) {
      for (final g in innerGates) {
        buyNear(g[0] + rng.intRange(-1, 2), g[1] + rng.intRange(-1, 2),
            DefType.guardPost,
            spread: 1);
      }
    }

    // ── a bridge butting straight into a rampart gets a DOOR: crossings
    // funnel into gates, never into blank wall ──
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        if (base.grid[r][c].terrain != Terrain.bridge) continue;
        for (final d in const [
          [-1, 0],
          [1, 0],
          [0, -1],
          [0, 1]
        ]) {
          final wr = r + d[0], wc = c + d[1];
          final s = base.structAt(wr, wc);
          if (s == null || s.type != DefType.wall) continue;
          if (!gateClear(wr, wc)) break; // a door already stands nearby
          players.first.resources += base.removeAt(wr, wc);
          if (buy(wr, wc, DefType.gate)) {
            gateInfo.add([wr, wc, -d[0], -d[1]]); // opens toward the bridge
            registerGate(wr, wc);
          }
          break;
        }
      }
    }

    // ── gates get TEETH: a tent garrison inside, a tesla hidden by the
    // door, mines down the approach lane, wire raking the flanks ──
    for (var gi = 0; gi < gateInfo.length; gi++) {
      final g = gateInfo[gi];
      final inR = -g[2], inC = -g[3];
      final perpR = inC.abs(), perpC = inR.abs();
      // GATEHOUSE: two towers flanking the door just inside the wall
      if (depth >= 2) {
        buyTower(g[0] + inR + perpR, g[1] + inC + perpC,
            depth >= 5 && gi == 0 ? DefType.cannon : DefType.archerTower);
        buyTower(g[0] + inR - perpR, g[1] + inC - perpC, DefType.archerTower);
      }
      if (depth >= 4) {
        buyNear(g[0] + inR * 2 + perpR, g[1] + inC * 2 + perpC,
            DefType.guardPost,
            spread: 1);
      }
      if (depth >= 7 && gi == 0) {
        buyNear(g[0] + inR + perpR, g[1] + inC + perpC, DefType.tesla,
            spread: 1);
      }
      // boiling pitch over a FEW doorways — not every ward jamb (that was
      // how Radiant grew 40 pitch pots overnight once leftover coin existed)
      if (depth >= 6 &&
          pitchesPlaced < pitchCap &&
          (gi < 3 || gi % 5 == 0)) {
        if (buyNear(g[0] + inR - perpR, g[1] + inC - perpC, DefType.pitchThrower,
            spread: 1)) {
          pitchesPlaced++;
        }
      }
      if (depth >= 5) {
        // scattered across the approach — a minefield, not a marked path
        for (var k = 1; k <= 3; k++) {
          buy(g[0] + g[2] * k + perpR * rng.intRange(-1, 2),
              g[1] + g[3] * k + perpC * rng.intRange(-1, 2), DefType.landmine);
        }
      }
      if (depth >= 6) {
        for (final s in const [-1, 1]) {
          for (var k = 1; k <= 2; k++) {
            buy(g[0] + g[2] * 2 + perpR * s * k, g[1] + g[3] * 2 + perpC * s * k,
                DefType.barbedWire);
          }
        }
      }
    }

    // ── CITADEL furnish sweep: no ward stands EMPTY — every room gets at
    // least two pieces (cheap teeth; none are towers, so spacing can't
    // refuse them) ──
    if (citadel && coreRegions.isNotEmpty) {
      const filler = [
        DefType.landmine,
        DefType.barbedWire,
        DefType.guardPost,
        DefType.storehouse,
        DefType.housing,
      ];
      var fi = 0;
      for (final reg in coreRegions) {
        var count = 0;
        for (var r = reg[0]; r <= reg[1]; r++) {
          for (var c = reg[2]; c <= reg[3]; c++) {
            final st = base.structAt(r, c);
            if (st != null &&
                st.type != DefType.wall &&
                st.type != DefType.gate &&
                !st.isCastle) {
              count++;
            }
          }
        }
        final area = (reg[1] - reg[0] + 1) * (reg[3] - reg[2] + 1);
        final want = math.min(4, 2 + area ~/ 16); // big rooms, more teeth
        for (var tries = 0; count < want && tries < want * 4; tries++) {
          final r =
              reg[0] + rng.intRange(0, math.max(1, reg[1] - reg[0] + 1));
          final c =
              reg[2] + rng.intRange(0, math.max(1, reg[3] - reg[2] + 1));
          if (buy(r, c, filler[fi++ % filler.length])) count++;
        }
      }
    }

    // twin forts: a mined killing field between the compounds
    if (rects.length == 2 && depth >= 4) {
      final a = rects[0], b = rects[1];
      bool inRect(List<int> x, int r, int c) =>
          r >= x[0] && r <= x[1] && c >= x[2] && c <= x[3];
      final r0 = math.min(a[0], b[0]), r1 = math.max(a[1], b[1]);
      final c0 = math.min(a[2], b[2]), c1 = math.max(a[3], b[3]);
      for (var m = 0; m < 6 + depth; m++) {
        final r = r0 + rng.intRange(0, math.max(1, r1 - r0 + 1));
        final c = c0 + rng.intRange(0, math.max(1, c1 - c0 + 1));
        if (inRect(a, r, c) || inRect(b, r, c)) continue; // the gap only
        buy(r, c, rng.unit() < 0.7 ? DefType.landmine : DefType.barbedWire);
      }
    }

    // mines guard the bridge exits (the highways in)
    if (depth >= 5) {
      for (var r = 0; r < base.rows; r++) {
        for (var c = 0; c < base.cols; c++) {
          if (base.grid[r][c].terrain != Terrain.bridge) continue;
          for (final d in const [
            [-1, 0],
            [1, 0],
            [0, -1],
            [0, 1]
          ]) {
            buy(r + d[0], c + d[1], DefType.landmine);
          }
        }
      }
    }

    // ── league unlock kit: tribute / command / pitch pot / citadel core,
    // plus war generators (always available — raid bait + eco pump) ──
    final kit = style.unlockDefs;
    final keep = castles.isNotEmpty ? castles.first : null;
    if (kit.contains(DefType.citadelCore) && keep != null) {
      buyNear(keep.r, keep.c, DefType.citadelCore, spread: 3);
    }
    if (kit.contains(DefType.commandTent)) {
      for (final p in players) {
        final cell = base.castles[p.id];
        if (cell != null) {
          buyNear(cell.r, cell.c, DefType.commandTent, spread: 2);
        }
      }
    }
    if (kit.contains(DefType.tributeChest)) {
      final n = citadel ? 2 : 1;
      for (var i = 0; i < n; i++) {
        if (coreRegions.isNotEmpty) {
          final reg = coreRegions[rng.intRange(0, coreRegions.length)];
          buyNear((reg[0] + reg[1]) ~/ 2, (reg[2] + reg[3]) ~/ 2,
              DefType.tributeChest,
              spread: 2);
        } else if (keep != null) {
          buyNear(keep.r + rng.intRange(-2, 3), keep.c + rng.intRange(-2, 3),
              DefType.tributeChest,
              spread: 3);
        }
      }
    }
    if (kit.contains(DefType.pitchPot)) {
      var pots = 0;
      final potCap = (6 + (citadel ? (roomTarget! ~/ 8) : 0)).clamp(4, 14);
      for (final g in gateInfo) {
        if (pots >= potCap) break;
        if (rng.unit() > 0.55) continue;
        if (buy(g[0] + g[2] * rng.intRange(1, 4),
            g[1] + g[3] * rng.intRange(1, 4), DefType.pitchPot)) {
          pots++;
        }
      }
    }
    // War generators: 1–3 pumps deep inside (not league-gated)
    if (depth >= 5) {
      final gens = base.rows >= 56 ? 3 : (citadel ? 2 : 1);
      for (var i = 0; i < gens; i++) {
        if (coreRegions.isNotEmpty) {
          final reg = coreRegions[i % coreRegions.length];
          buyNear((reg[0] + reg[1]) ~/ 2 + rng.intRange(-1, 2),
              (reg[2] + reg[3]) ~/ 2 + rng.intRange(-1, 2), DefType.warGenerator,
              spread: 2);
        } else if (keep != null) {
          buyNear(keep.r, keep.c, DefType.warGenerator, spread: 3);
        }
      }
    }

    // ── the FORGE (citadel): a war chest this deep buys STEEL, not just
    // stone — every shooter and tent to the cap, then the doors, then the
    // walls themselves turn to slate ──
    if (citadel) {
      final lvlCap = _towerLevelCap(skill, base.rows);
      final wallCap = _wallLevelCap(skill, base.rows);
      // Big boards spend MORE of the chest on steel — leave a thinner reserve.
      final reserve = base.rows >= 60 ? 120.0 : (base.rows >= 52 ? 220.0 : 400.0);
      bool forge(Structure st, int cap) {
        if (st.spec.upgradeCost <= 0) return false;
        final hardCap = math.min(cap, st.spec.maxLevel);
        var did = false;
        while (st.level < hardCap) {
          final cost = st.spec.upgradeCost * st.level;
          final funds = players.fold(0.0, (a, p) => a + p.resources);
          if (funds - cost < reserve) return did;
          WarPlayer? payer;
          for (final p in players) {
            if (p.resources >= cost) {
              payer = p;
              break;
            }
          }
          if (payer == null) return did;
          payer.resources -= cost;
          st.level += 1;
          st.hp = st.maxHp;
          did = true;
        }
        return did;
      }

      // Phase the forge so GUNS lead and the curtain doesn't devour the chest:
      // 1) gild every battery / tent to the tower cap (the threat)
      // 2) doors
      // 3) raise the WHOLE curtain to a sturdy mid tier (cheap steel)
      // 4) deep walls ONLY beside the keep — blanket L4–L5 on a 64² curtain
      //    ate half the Radiant chest (every wall sat next to a guard post)
      // 5) support buildings
      final wallMid = base.rows >= 56
          ? math.min(2, wallCap)
          : math.min(3, wallCap);
      bool nearKeep(int r, int c) {
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            final s = base.structAt(r + dr, c + dc);
            if (s != null && s.isCastle) return true;
          }
        }
        return false;
      }

      for (final pass in const [0, 1, 2, 3, 4]) {
        for (var r = 0; r < base.rows; r++) {
          for (var c = 0; c < base.cols; c++) {
            final st = base.structAt(r, c);
            if (st == null || st.isCastle) continue;
            final wants = switch (pass) {
              0 => st.spec.isShooter || st.type == DefType.guardPost,
              1 => st.type == DefType.gate,
              2 => st.type == DefType.wall,
              3 => st.type == DefType.wall && nearKeep(r, c),
              _ => st.type == DefType.banner ||
                  st.type == DefType.storehouse ||
                  st.type == DefType.watchtower ||
                  st.type == DefType.housing ||
                  st.type == DefType.warGenerator,
            };
            if (!wants) continue;
            final cap = switch (pass) {
              0 => lvlCap,
              1 => lvlCap,
              2 => wallMid,
              3 => wallCap,
              _ => lvlCap,
            };
            forge(st, cap);
          }
        }
      }
    }

    // leftovers → extra spaced towers inside, mines outside — never wall spam
    // Prefer under-cap mortars over pitch spam when the chest still has coin.
    var guard = 0;
    while (guard++ < 6 + depth * 2 + (citadel ? roomTarget! * 5 : 0)) {
      final towerMoney = players
          .any((p) => p.resources >= kDefSpecs[DefType.archerTower]!.cost);
      final mineMoney = players
          .any((p) => p.resources >= kDefSpecs[DefType.landmine]!.cost);
      if (!towerMoney && !mineMoney) break;
      if (rects.isEmpty) break;
      final rect = rects[guard % rects.length];
      final midR =
          rect[0] + 1 + rng.intRange(0, math.max(1, rect[1] - rect[0] - 1));
      final midC =
          rect[2] + 1 + rng.intRange(0, math.max(1, rect[3] - rect[2] - 1));
      if (depth >= 6 && guard % 3 == 0 && towerSpots.isNotEmpty) {
        // masters GILD their batteries: leftovers buy upgrades
        final spot = towerSpots[rng.intRange(0, towerSpots.length)];
        final s = base.structAt(spot[0], spot[1]);
        // brutal clans on big boards forge the deepest batteries
        final lvlCap = _towerLevelCap(skill, base.rows);
        if (s != null &&
            s.spec.upgradeCost > 0 &&
            s.level < math.min(lvlCap, s.spec.maxLevel)) {
          final cost = s.spec.upgradeCost * s.level;
          for (final p in players) {
            if (p.resources >= cost) {
              p.resources -= cost;
              s.level += 1;
              s.hp = s.maxHp;
              break;
            }
          }
        }
      } else if (citadel &&
          depth >= 7 &&
          mortarsPlaced < mortarCap &&
          guard % 4 == 0) {
        if (buyNear(midR, midC, DefType.mortar, spread: 2)) mortarsPlaced++;
      } else if (citadel &&
          depth >= 8 &&
          pitchesPlaced < pitchCap &&
          guard % 7 == 0 &&
          innerGates.isNotEmpty) {
        final g = innerGates[rng.intRange(0, innerGates.length)];
        if (buyNear(g[0], g[1], DefType.pitchThrower, spread: 1)) {
          pitchesPlaced++;
        }
      } else if (towerMoney && depth >= 3 && guard % 2 == 0) {
        buyTowerNear(midR, midC, DefType.archerTower);
      } else if (mineMoney && depth >= 5) {
        final side = rng.intRange(0, 4);
        int r, c;
        if (side == 0) {
          r = rect[0] - 2;
          c = rect[2] + rng.intRange(0, math.max(1, rect[3] - rect[2] + 1));
        } else if (side == 1) {
          r = rect[1] + 2;
          c = rect[2] + rng.intRange(0, math.max(1, rect[3] - rect[2] + 1));
        } else if (side == 2) {
          c = rect[2] - 2;
          r = rect[0] + rng.intRange(0, math.max(1, rect[1] - rect[0] + 1));
        } else {
          c = rect[3] + 2;
          r = rect[0] + rng.intRange(0, math.max(1, rect[1] - rect[0] + 1));
        }
        buy(r, c, DefType.landmine);
      }
    }

    // ── validation: no dead-end wall stubs. A wall must lean on ≥2 of
    // {wall, gate, castle, impassable terrain} (diagonals count — the corner
    // staircases live on them). Anything looser gets torn down and refunded.
    for (var pass = 0; pass < 2; pass++) {
      for (var r = 0; r < base.rows; r++) {
        for (var c = 0; c < base.cols; c++) {
          final s = base.structAt(r, c);
          if (s == null ||
              (s.type != DefType.wall && s.type != DefType.gate)) {
            continue;
          }
          var support = 0;
          for (var dr = -1; dr <= 1; dr++) {
            for (var dc = -1; dc <= 1; dc++) {
              if (dr == 0 && dc == 0) continue;
              final nr = r + dr, nc = c + dc;
              if (!base.inBounds(nr, nc)) continue;
              final ns = base.structAt(nr, nc);
              if (ns != null &&
                  ns.alive &&
                  (ns.type == DefType.wall ||
                      ns.type == DefType.gate ||
                      ns.isCastle)) {
                support++;
              } else if (!TerrainData.passable(base.grid[nr][nc].terrain)) {
                support++;
              }
            }
          }
          if (support < 2) {
            players.first.resources += base.removeAt(r, c);
          }
        }
      }
    }

    // what actually stands, post-cleanup — the Lab readout and tests read it
    var built = 0;
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        if (base.structAt(r, c) != null) built++;
      }
    }
    lastBuildStats = BuildStats(
        rooms: coreRegions.length, structures: built, coreArea: coreArea);
  }

  /// Stats from the most recent [_buildStronghold] run.
  static BuildStats? lastBuildStats;

  /// Board size band: 0 = Bronze-ish, 1 = mid ladder, 2 = the big leagues.
  static int _sizeBand(int rows) => rows >= 56 ? 2 : (rows >= 48 ? 1 : 0);

  /// How far a clan gilds its guns. Climbs with the dial AND the rung, so a
  /// higher league is visibly meaner even at the same difficulty.
  static int _towerLevelCap(double skill, int rows) {
    var cap = 2;
    if (skill >= 0.9) cap++;
    if (skill >= 1.15) cap++;
    if (skill >= 1.35 || _sizeBand(rows) >= 2) cap++;
    if (rows >= 60 && skill >= 1.2) cap++; // Radiant-band batteries
    return cap.clamp(2, 5);
  }

  /// Curtain walls climb further — spiked crests, ramparts, and at the very
  /// top an obsidian bastion no L1 sapper charge can crack open.
  static int _wallLevelCap(double skill, int rows) {
    var cap = 2 + _sizeBand(rows);
    if (skill >= 1.1) cap++;
    if (skill >= 1.3) cap++;
    if (rows >= 60) cap++; // Radiant curtain is fully forged
    return cap.clamp(2, 5);
  }

  // ── WAR: fog-honest objectives + CoC targeting discipline ───────────────────
  /// Revealed structures beat garrison beat fog — DISTANCE discounts all, and
  /// fog frontier scores rise with depth into the base.
  static Cell? pickObjective(AttackState st, Troop t) {
    Cell? best;
    var bestScore = -1e9;
    // TEMPERAMENT: some troops take the sure thing in front of them over the
    // long march to the "best" target — armies spread instead of conga-lining
    final greed = 1.0 + (t.id.hashCode & 3) * 0.45;
    void consider(Cell cell, double value, double k) {
      final dist = ((cell.r - t.r).abs() + (cell.c - t.c).abs()).toDouble();
      final score = value - dist * k * greed;
      if (score > bestScore) {
        bestScore = score;
        best = cell;
      }
    }

    for (var r = 0; r < st.base.rows; r++) {
      for (var c = 0; c < st.base.cols; c++) {
        if (!st.visible(r, c)) continue;
        final s = st.base.structAt(r, c);
        if (s != null && s.alive && !(s.spec.hidden && !s.triggered)) {
          // walls and gates are OBSTACLES, not objectives — except to the
          // SAPPER, whose whole job is to blow one open (gates first: softer)
          if (s.type == DefType.wall ||
              s.type == DefType.gate ||
              s.type == DefType.barbedWire) {
            if (t.type == TroopType.sapper && s.type != DefType.barbedWire) {
              consider(Cell(r, c), s.type == DefType.gate ? 160.0 : 150.0, 2.5);
            }
            continue;
          }
          var value = s.isCastle ? 120.0 : (s.spec.isShooter ? 90.0 : 60.0);
          if (s.type == DefType.storehouse) value = 100.0; // burn the granary
          // brutes are TOWER HUNTERS: a defense in sight IS the objective —
          // and a guard TENT is a defense, not a scenery piece
          if (t.type == TroopType.brute &&
              (s.spec.isShooter ||
                  s.type == DefType.banner ||
                  s.type == DefType.guardPost)) {
            value = 160.0;
          }
          consider(Cell(r, c), value, 2.5);
        }
      }
    }
    for (final g in st.garrison) {
      if (g.alive && st.visible(g.r, g.c)) {
        consider(Cell(g.r, g.c), 70, 2.5);
      }
    }
    for (final f in st.fogFrontier()) {
      final depth = math.min(math.min(f.r, f.c),
          math.min(st.base.rows - 1 - f.r, st.base.cols - 1 - f.c));
      // NEARBY fog beats a landmark on the far side of the map: scout what's
      // in front of you before committing to the long march
      var v = 60 + depth * 1.5;
      // SCOUTS dive for the DEEPEST fog — the thicker the unknown around a
      // frontier cell, the more a runner wants it
      if (t.type == TroopType.runner) {
        var fogAround = 0;
        for (var dr = -2; dr <= 2; dr++) {
          for (var dc = -2; dc <= 2; dc++) {
            final rr = f.r + dr, cc = f.c + dc;
            if (st.base.inBounds(rr, cc) && !st.visible(rr, cc)) fogAround++;
          }
        }
        v += fogAround * 2.5;
      }
      consider(f, v, 1.7);
    }
    return best;
  }

  /// A target worth stopping for: enemy troops, anything that shoots, castles,
  /// guard camps — and for a SAPPER, the wall it lives to blow open.
  static bool _worthStriking(AttackState st, Troop t, Cell c) {
    final foe = st.troopAt(c.r, c.c);
    if (foe != null) return true;
    final s = st.base.structAt(c.r, c.c);
    if (s == null || !s.alive) return false;
    if (t.type == TroopType.sapper &&
        (s.type == DefType.wall || s.type == DefType.gate)) {
      return true;
    }
    return s.isCastle ||
        s.spec.isShooter ||
        s.type == DefType.guardPost ||
        s.type == DefType.banner ||
        s.type == DefType.storehouse;
  }

  static bool _strikeBestAdjacent(AttackState st, Troop t,
      {required bool valuableOnly}) {
    var adj = st.attackTargets(t);
    if (valuableOnly) {
      adj = adj.where((c) => _worthStriking(st, t, c)).toList();
    }
    if (adj.isEmpty) return false;
    if (!st.freeActions && st.pools.of(t.ownerId) < WarCosts.attack) return false;
    adj.sort((a, b) => _targetScore(st, t, b).compareTo(_targetScore(st, t, a)));
    st.attackCell(t, adj.first.r, adj.first.c);
    return true;
  }

  /// Move-point price of stepping onto a cell: forest slows everyone to half
  /// speed, wire drags too. Capped at 2 (the movePoints ceiling) so nothing
  /// becomes permanently uncrossable.
  static double _stepCost(AttackState st, int r, int c, [Troop? mover]) {
    final terr = st.base.grid[r][c].terrain;
    var cost = (terr == Terrain.forest || terr == Terrain.hill) ? 2.0 : 1.0;
    final s = st.base.structAt(r, c);
    if (s != null &&
        s.alive &&
        !(mover?.type == TroopType.elephant && s.type == DefType.barbedWire)) {
      cost += s.spec.extraMoveCost;
    }
    return math.min(2.0, cost);
  }

  /// One battle activation: strike what matters, march around what doesn't,
  /// and only chew through walls when the way is sealed.
  static bool aiStep(AttackState st, Troop t) {
    if (!t.alive) return false;
    t.done = false;

    // (a fogger's cloud is triggered by DAMAGE now, not by acting — the
    // engine bursts it from _cull wherever the wound came from)

    // HEALERS have one job — mend the wounded, follow the push
    if (t.type == TroopType.healer) return _healerStep(st, t);

    // 1) something WORTH hitting in reach? (towers, garrison, castles)
    if (_strikeBestAdjacent(st, t, valuableOnly: true)) return true;

    // 2) objective (sticky until dead/revealed/stale)
    Cell? objective;
    if (t.objectiveKey != null && t.objectiveAge < 6) {
      final r = t.objectiveKey! ~/ st.base.cols, c = t.objectiveKey! % st.base.cols;
      final s = st.base.structAt(r, c);
      final stillStruct = s != null && s.alive;
      final stillFog = !st.visible(r, c);
      if (stillStruct || stillFog) objective = Cell(r, c);
    }
    objective ??= pickObjective(st, t);
    if (objective == null) return false;
    t.objectiveKey = objective.r * st.base.cols + objective.c;
    t.objectiveAge++;

    // 3) route (around walls, rivers, AND friends)
    var route = st.routeTo(t, objective.r, objective.c);
    if (route.isEmpty) {
      for (final d in const [
        [-1, 0],
        [1, 0],
        [0, -1],
        [0, 1]
      ]) {
        final nr = objective.r + d[0], nc = objective.c + d[1];
        if (st.base.passable(nr, nc)) {
          route = st.routeTo(t, nr, nc);
          if (route.isNotEmpty) break;
        }
      }
    }

    // the LONG WAY AROUND is a trap: when smashing straight through the wall
    // is far shorter than the open detour, breach instead — like CoC troops
    if (route.length > 10) {
      final direct = st.routeTo(t, objective.r, objective.c, throughWalls: true);
      if (direct.isNotEmpty && direct.length + 8 < route.length) {
        route = const [];
      }
    }

    // charge movement ONCE per activation (before walking or sidestepping)
    t.movePoints =
        (t.movePoints + t.moveBudget / (t.burnRounds > 0 ? 12 : 6))
            .clamp(0.0, 2.0);

    // 4) no open road? Plan THROUGH the walls (the CoC breach): walk the
    // breach route and smash the first structure standing on it. Kills the
    // wall-stare cycle — a wall between you and the objective IS the target.
    if (route.isEmpty) {
      final breach = st.routeTo(t, objective.r, objective.c, throughWalls: true);
      if (breach.isNotEmpty) {
        var walked = false;
        for (var i = 0; i < breach.length && i < 2 && t.alive; i++) {
          final next = breach[i];
          final blocker = st.base.structAt(next[0], next[1]);
          if (blocker != null && blocker.alive && blocker.spec.blocks) {
            // adjacent to the wall in the way → BREACH IT
            if ((t.r - next[0]).abs() + (t.c - next[1]).abs() == 1) {
              if (st.freeActions ||
                  st.pools.of(t.ownerId) >= WarCosts.attack) {
                st.attackCell(t, next[0], next[1]);
                return true;
              }
            }
            break; // not adjacent yet — walk closer next rounds
          }
          if (st.troopAt(next[0], next[1]) != null) break;
          final cost = _stepCost(st, next[0], next[1], t);
          if (t.movePoints < cost) {
            // WIRE underfoot and no legs left? CUT it (sappers hold the bomb)
            final w = st.base.structAt(next[0], next[1]);
            if (w != null &&
                w.alive &&
                w.type == DefType.barbedWire &&
                t.type != TroopType.sapper &&
                (t.r - next[0]).abs() + (t.c - next[1]).abs() == 1 &&
                (st.freeActions ||
                    st.pools.of(t.ownerId) >= WarCosts.attack)) {
              st.attackCell(t, next[0], next[1]);
              return true;
            }
            break;
          }
          if (!st.moveTroop(t, next[0], next[1])) break;
          t.movePoints -= cost;
          walked = true;
        }
        if (t.alive || walked) return true; // en route to (or hitting) the breach
        return walked; // died on the way (mine/tesla)
      }
      // no breach plan either (pure congestion): strike anything adjacent,
      // else sidestep toward the objective — and KEEP the objective.
      if (_strikeBestAdjacent(st, t, valuableOnly: false)) return true;
      List<int>? side;
      var bestD = 1 << 30;
      for (final d in const [
        [-1, 0],
        [1, 0],
        [0, -1],
        [0, 1]
      ]) {
        final nr = t.r + d[0], nc = t.c + d[1];
        if (!st.base.passable(nr, nc)) continue;
        if (st.troopAt(nr, nc) != null) continue;
        final nd = (nr - objective.r).abs() + (nc - objective.c).abs();
        if (nd < bestD) {
          bestD = nd;
          side = [nr, nc];
        }
      }
      if (side != null &&
          t.movePoints >= _stepCost(st, side[0], side[1], t) &&
          st.moveTroop(t, side[0], side[1])) {
        t.movePoints -= _stepCost(st, side[0], side[1], t);
        return true;
      }
      // fully boxed with NO breach plan — that's idle, and if the whole army
      // idles the raid is allowed to end (no more standing-still forever)
      return false;
    }

    // 5) walk ONE tile at a time (fractional speed accumulator; forest slows)
    var moved = false;
    var i = 0;
    while (i < route.length && i < 2 && t.alive) {
      final next = route[i];
      if (st.troopAt(next[0], next[1]) != null) break;
      final cost = _stepCost(st, next[0], next[1], t);
      if (t.movePoints < cost) {
        // WIRE underfoot and no legs left? CUT it — nobody stalls at a fence
        // (sappers hold their bomb for something better)
        final w = st.base.structAt(next[0], next[1]);
        if (w != null &&
            w.alive &&
            w.type == DefType.barbedWire &&
            t.type != TroopType.sapper &&
            (t.r - next[0]).abs() + (t.c - next[1]).abs() == 1 &&
            (st.freeActions || st.pools.of(t.ownerId) >= WarCosts.attack)) {
          st.attackCell(t, next[0], next[1]);
          return true;
        }
        break;
      }
      if (!st.moveTroop(t, next[0], next[1])) break;
      t.movePoints -= cost;
      moved = true;
      i++;
    }
    if (!t.alive) return moved;
    if (!moved && route.isNotEmpty) moved = true; // charging counts as acting

    // 6) the march brought something worthwhile into reach? strike it
    if (_strikeBestAdjacent(st, t, valuableOnly: true)) return true;
    if (t.r == objective.r && t.c == objective.c) t.objectiveKey = null;
    return moved;
  }

  /// The healer's beat: heal the most-wounded ally in reach, else walk to the
  /// most-wounded ally on the field, else shadow the nearest friend.
  static bool _healerStep(AttackState st, Troop t) {
    t.movePoints =
        (t.movePoints + t.moveBudget / (t.burnRounds > 0 ? 12 : 6))
            .clamp(0.0, 2.0);
    // 1) heal in reach (Chebyshev ≤ 2)
    Troop? worst;
    var worstFrac = 1.0;
    for (final f in st.troops) {
      if (!f.alive || f.id == t.id) continue;
      final d = (f.r - t.r).abs() > (f.c - t.c).abs()
          ? (f.r - t.r).abs()
          : (f.c - t.c).abs();
      if (d > 2) continue;
      final frac = f.hp / f.maxHp;
      if (frac < worstFrac && frac < 1.0) {
        worstFrac = frac;
        worst = f;
      }
    }
    if (worst != null) {
      st.healTroop(t, worst);
      return true;
    }
    // 2) walk toward the most-wounded ally anywhere; else the nearest friend
    Troop? goal;
    var bestScore = 1e18;
    for (final f in st.troops) {
      if (!f.alive || f.id == t.id) continue;
      final d = ((f.r - t.r).abs() + (f.c - t.c).abs()).toDouble();
      final score = d + (f.hp / f.maxHp) * 20; // wounded pulls harder
      if (score < bestScore) {
        bestScore = score;
        goal = f;
      }
    }
    if (goal == null) return false;
    final route = st.routeTo(t, goal.r, goal.c);
    var i = 0;
    var moved = false;
    while (i < route.length && i < 2 && t.alive) {
      final next = route[i];
      if (st.troopAt(next[0], next[1]) != null) break;
      final cost = _stepCost(st, next[0], next[1], t);
      if (t.movePoints < cost) break;
      if (!st.moveTroop(t, next[0], next[1])) break;
      t.movePoints -= cost;
      moved = true;
      i++;
    }
    return moved || route.isNotEmpty;
  }

  static double _targetScore(AttackState st, Troop t, Cell c) {
    final foe = st.troopAt(c.r, c.c);
    if (foe != null) return 1500 - foe.hp.toDouble();
    final s = st.base.structAt(c.r, c.c)!;
    // a sapper beside a wall/gate spends its bomb THERE, not on the shiny
    if (t.type == TroopType.sapper &&
        (s.type == DefType.wall || s.type == DefType.gate)) {
      return 2000;
    }
    // a brute beside a DEFENSE smashes it — like a giant, always
    if (t.type == TroopType.brute &&
        (s.spec.isShooter || s.type == DefType.guardPost)) {
      return 1800 - s.hp.toDouble();
    }
    return ((s.isCastle ? 1000 : 0) + (500 - s.hp)).toDouble();
  }

  // ── headless raid (AI players on the timeline) ──────────────────────────────
  static AttackResult runAttack({
    required Base base,
    required WarPlayer attacker,
    required WarPools pools,
    required SeededRng rng,
    Set<int>? intel,
    double defenderIq = 0.5,
    Set<TroopType> unlockTroops = const {},
  }) {
    // AI raids fight under the SAME rules as the player's: troops are paid for
    // at spawn ("training"), then act free.
    final st = AttackState(
        base: base,
        attacker: attacker.side,
        attackerName: attacker.name,
        pools: pools,
        freeActions: true,
        defenderIq: defenderIq,
        intel: intel);
    final skill = attacker.skill;
    final drops = base.dropCells.toList();
    if (drops.isEmpty) return st.finish();

    // degenerate-raid guard: nothing to attack or scout? don't raid at all
    final probe = Troop(
        id: 'probe',
        ownerId: attacker.id,
        side: attacker.side,
        type: TroopType.soldier,
        r: drops.first.r,
        c: drops.first.c);
    if (pickObjective(st, probe) == null) return st.finish();

    // FOCUSED ASSAULT: pick the flank with the fewest KNOWN defenses (from
    // clan intel) and cluster the whole wave around one anchor there.
    final anchor = _pickAssaultAnchor(st, drops, rng);
    drops.sort((a, b) {
      final da = (a.r - anchor.r).abs() + (a.c - anchor.c).abs();
      final db = (b.r - anchor.r).abs() + (b.c - anchor.c).abs();
      return da.compareTo(db);
    });
    final cap = 3 + (skill * 7).round();
    // humans don't dump the whole army in one pile — sharp clans land in
    // WAVES, and the follow-up wave hits the FAR flank to split the defense
    final waveCount = skill >= 1.2 ? 3 : (skill >= 0.7 ? 2 : 1);
    final perWave = (cap / waveCount).ceil();
    final anchor2 = drops.last; // farthest ring cell = the opposite flank
    void spawnWave(Cell around) {
      final ordered = drops.toList()
        ..sort((a, b) {
          final da = (a.r - around.r).abs() + (a.c - around.c).abs();
          final db = (b.r - around.r).abs() + (b.c - around.c).abs();
          return da.compareTo(db);
        });
      var n = 0;
      var dropIdx = 0;
      while (n < perWave &&
          pools.of(attacker.id) > 30 &&
          dropIdx < ordered.length) {
        final type = _pickTroop(n, skill, rng, unlockTroops: unlockTroops);
        final drop = ordered[dropIdx];
        final spawned = st.spawn(type, attacker.id, drop.r, drop.c);
        if (spawned == null) {
          dropIdx++;
          continue;
        }
        // VETERANS: at brutal difficulty the enemy fields leveled troops
        if (skill >= 0.9) {
          spawned.gainXp(Xp.perLevel * (skill >= 1.3 ? 2.0 : 1.0) + 1);
        }
        dropIdx++;
        n++;
      }
    }

    spawnWave(anchor);
    if (st.troops.isEmpty) return st.finish();
    st.snapshot('The raid begins');

    var rounds = 0;
    var stalled = 0;
    var wavesSent = 1;
    while (rounds++ < 140 &&
        (st.troops.any((t) => t.alive) || wavesSent < waveCount)) {
      // reinforcements: when the last wave is spent or dug in, the next one
      // lands — alternating flanks so the defense splits
      if (wavesSent < waveCount &&
          (rounds % 16 == 0 ||
              st.troops.where((x) => x.alive).length <= perWave ~/ 3)) {
        spawnWave(wavesSent.isOdd ? anchor2 : anchor);
        wavesSent++;
        stalled = 0;
        st.snapshot('The next wave lands');
      }
      var acted = false;
      for (final t in st.troops.where((x) => x.alive).toList()) {
        if (aiStep(st, t)) acted = true;
      }
      st.defendersReact();
      st.snapshot();
      if (base.allCastlesRazed) break;
      stalled = acted ? 0 : stalled + 1;
      if (stalled >= 4) break;
    }
    st.snapshot('The raid ends');
    return st.finish();
  }

  /// Public wave composition — the sandbox summons waves with the same
  /// doctrine the real AI uses.
  static TroopType waveTroop(int i, double skill, SeededRng rng,
          {Set<TroopType> unlockTroops = const {}}) =>
      _pickTroop(i, skill, rng, unlockTroops: unlockTroops);

  /// Wave doctrine: scout → tank → breach → support. League unlocks slot in
  /// when the rung has earned them (or when [unlockTroops] is empty, skill
  /// approximates the ladder so old call sites still field healers etc.).
  static TroopType _pickTroop(int i, double skill, SeededRng rng,
      {Set<TroopType> unlockTroops = const {}}) {
    bool has(TroopType t) {
      if (!kLeagueGatedTroops.contains(t)) return true;
      if (unlockTroops.isNotEmpty) return unlockTroops.contains(t);
      // skill fallback ≈ Silver / Gold / Platinum / Diamond floors
      return switch (t) {
        TroopType.healer => skill >= 0.9,
        TroopType.javelin => skill >= 1.0,
        TroopType.fogger => skill >= 1.12,
        TroopType.elephant => skill >= 1.25,
        _ => false,
      };
    }

    if (i == 0) {
      // fogger opens the fog on high rungs; else the classic runner scout
      return has(TroopType.fogger) && rng.unit() < 0.55
          ? TroopType.fogger
          : TroopType.runner;
    }
    if (i == 1 && skill > 0.4) {
      return has(TroopType.elephant) && rng.unit() < 0.45
          ? TroopType.elephant
          : TroopType.brute;
    }
    if (i == 3 && has(TroopType.healer)) return TroopType.healer;
    if (skill >= 0.6 && (i == 4 || i == 7)) {
      return has(TroopType.javelin) && rng.unit() < 0.55
          ? TroopType.javelin
          : TroopType.archer;
    }
    if (i % 3 == 2) return TroopType.sapper;
    if (skill > 0.7 && i % 4 == 0) {
      return has(TroopType.elephant) && rng.unit() < 0.35
          ? TroopType.elephant
          : TroopType.brute;
    }
    if (has(TroopType.javelin) && i % 5 == 1 && skill >= 1.0) {
      return TroopType.javelin;
    }
    return TroopType.soldier;
  }

  /// Choose the landing anchor: the map side with the fewest KNOWN shooters
  /// (via clan intel); unknown territory → seeded pick.
  static Cell _pickAssaultAnchor(AttackState st, List<Cell> drops, SeededRng rng) {
    // what do we KNOW? centroid of every scouted structure + guns per half
    var sr = 0.0, sc = 0.0, known = 0;
    final counts = <int>[0, 0, 0, 0]; // N, S, W, E
    final b = st.base;
    for (var r = 0; r < b.rows; r++) {
      for (var c = 0; c < b.cols; c++) {
        if (!st.visible(r, c)) continue;
        final s = b.structAt(r, c);
        if (s == null || !s.alive) continue;
        sr += r;
        sc += c;
        known++;
        if (!s.spec.isShooter) continue;
        if (r < b.rows ~/ 2) counts[0]++;
        if (r >= b.rows ~/ 2) counts[1]++;
        if (c < b.cols ~/ 2) counts[2]++;
        if (c >= b.cols ~/ 2) counts[3]++;
      }
    }
    if (known == 0) {
      // nothing scouted — pick a flank and commit
      final side = rng.intRange(0, 4);
      final mid = b.cols ~/ 2 + rng.intRange(-6, 7);
      switch (side) {
        case 0:
          return Cell(0, mid.clamp(0, b.cols - 1));
        case 1:
          return Cell(b.rows - 1, mid.clamp(0, b.cols - 1));
        case 2:
          return Cell(mid.clamp(0, b.rows - 1), 0);
        default:
          return Cell(mid.clamp(0, b.rows - 1), b.cols - 1);
      }
    }
    // land CLOSE to the base we know about, discounted by the guns watching
    // that approach — no more marching the whole map for no reason
    final cr = sr / known, cc = sc / known;
    final marchDist = <double>[cr, b.rows - 1 - cr, cc, b.cols - 1 - cc];
    var side = 0;
    var best = 1e18;
    for (var s = 0; s < 4; s++) {
      final score = counts[s] * 2.0 + marchDist[s];
      if (score < best) {
        best = score;
        side = s;
      }
    }
    // anchor at the base's projection onto that edge (small jitter)
    final j = rng.intRange(-3, 4);
    switch (side) {
      case 0:
        return Cell(0, (cc.round() + j).clamp(0, b.cols - 1));
      case 1:
        return Cell(b.rows - 1, (cc.round() + j).clamp(0, b.cols - 1));
      case 2:
        return Cell((cr.round() + j).clamp(0, b.rows - 1), 0);
      default:
        return Cell((cr.round() + j).clamp(0, b.rows - 1), b.cols - 1);
    }
  }

  // ── income ──────────────────────────────────────────────────────────────────
  static double hourlyIncome(WarPlayer p, SeededRng rng) {
    final base = 26.0 * p.incomeMul;
    return base * (0.6 + rng.unit() * 0.9);
  }
}
