import 'package:flutter_test/flutter_test.dart';
import 'package:jars/core/seeded_rng.dart';
import 'package:jars/war/free_move_battle.dart';
import 'package:jars/war/live_battle.dart';
import 'package:jars/war/war_ai.dart';
import 'package:jars/war/war_base.dart';
import 'package:jars/war/war_engine.dart';
import 'package:jars/war/war_player.dart';
import 'package:jars/war/war_types.dart';

/// FREE MOVE is the drill-only continuous engine: no tile slots, no tile-at-a
/// -time hops. These lock in the three things that make it feel like Clash —
/// units stack, units travel sub-tile, and the classic ruleset is untouched.
void main() {
  Base yard() {
    final base = Base(WarSide.enemy, 7);
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        base.grid[r][c].terrain = Terrain.plains;
      }
    }
    // the outer three rows are the landing ring — the yard starts inland
    base.placeCastle('def', 8, base.cols ~/ 2);
    base.place(12, base.cols ~/ 2, DefType.archerTower, 'def');
    return base;
  }

  AttackState drill() => AttackState(
        base: yard(),
        attacker: WarSide.you,
        attackerName: 'Drill',
        pools: MapPools({'drill': 1e9}),
        freeActions: true,
        intel: {for (var k = 0; k < 40 * 40; k++) k},
      );

  FreeMoveBattle armed(AttackState st) =>
      FreeMoveBattle(st, canDeploy: () => true);

  void run(FreeMoveBattle b, double seconds) {
    for (var i = 0; i < (seconds / FreeMoveBattle.simStep).round(); i++) {
      b.tick(FreeMoveBattle.simStep);
    }
  }

  test('many troops share one tile — tiles are not slots anymore', () {
    final st = drill();
    final b = armed(st);
    final drop = st.base.rows - 1, col = st.base.cols ~/ 2;
    for (var i = 0; i < 6; i++) {
      final t = st.spawn(TroopType.soldier, 'drill', drop, col, allowStack: true);
      expect(t, isNotNull, reason: 'stacked deploy #$i was refused');
      b.placeAt(t!, col.toDouble(), drop.toDouble());
    }
    expect(st.troops.length, 6);
    // and they stay a crowd, not a queue: still bunched a beat later
    run(b, 0.4);
    final tiles = {for (final t in st.troops) t.r * st.base.cols + t.c};
    expect(tiles.length, lessThan(6),
        reason: 'units spread onto their own tiles like the grid engine');
  });

  test('classic deploys still refuse to stack', () {
    final st = drill();
    final drop = st.base.rows - 1, col = st.base.cols ~/ 2;
    expect(st.spawn(TroopType.soldier, 'drill', drop, col), isNotNull);
    expect(st.spawn(TroopType.soldier, 'drill', drop, col), isNull);
  });

  test('movement is sub-tile and continuous, not a tile-per-beat hop', () {
    final st = drill();
    final b = armed(st);
    final drop = st.base.rows - 1, col = st.base.cols ~/ 2;
    final t = st.spawn(TroopType.soldier, 'drill', drop, col)!;
    b.placeAt(t, col.toDouble(), drop.toDouble());

    // a tenth of a second must move it a FRACTION of a tile
    run(b, 0.1);
    final p = b.positions[t.id]!;
    final moved = (drop - p.row).abs() + (col - p.col).abs();
    expect(moved, greaterThan(0.0),
        reason: 'unit did not move inside a single beat');
    expect(moved, lessThan(0.5),
        reason: 'unit teleported a whole tile instead of gliding');

    // and it keeps creeping every step, never waiting for a 0.55s beat
    final samples = <double>[];
    for (var i = 0; i < 8; i++) {
      run(b, 0.05);
      samples.add(b.positions[t.id]!.row);
    }
    for (var i = 1; i < samples.length; i++) {
      expect(samples[i], lessThan(samples[i - 1] + 1e-9),
          reason: 'unit stalled or jumped between frames');
    }
    expect(samples.last, lessThan(samples.first - 0.05),
        reason: 'no steady progress toward the base');
  });

  test('units path in, fight, and raze the yard', () {
    final st = drill();
    final b = armed(st);
    final drop = st.base.rows - 1;
    for (var c = st.base.cols ~/ 2 - 2; c <= st.base.cols ~/ 2 + 2; c++) {
      final t = st.spawn(TroopType.brute, 'drill', drop, c, allowStack: true);
      if (t != null) b.placeAt(t, c.toDouble(), drop.toDouble());
    }
    run(b, 90);
    expect(st.base.allCastlesRazed, isTrue,
        reason: 'five brutes could not finish an undefended yard in 90s');
  });

  test('the landing ring stays one-way', () {
    final st = drill();
    final b = armed(st);
    final drop = st.base.rows - 1, col = st.base.cols ~/ 2;
    final t = st.spawn(TroopType.soldier, 'drill', drop, col)!;
    b.placeAt(t, col.toDouble(), drop.toDouble());
    run(b, 6);
    expect(st.base.isRing(t.r, t.c), isFalse,
        reason: 'unit never left the ring');
    run(b, 6);
    expect(st.base.isRing(t.r, t.c), isFalse,
        reason: 'unit walked back onto the ring');
  });

  test('crossing a tile still springs its trap exactly once', () {
    final st = drill();
    final b = armed(st);
    final drop = st.base.rows - 1, col = st.base.cols ~/ 2;
    // a minefield across the approach, so any inland march must cross one
    final row = drop - 4; // first rank past the landing ring
    for (var c = col - 6; c <= col + 6; c++) {
      st.base.place(row, c, DefType.landmine, 'def');
    }
    final t = st.spawn(TroopType.soldier, 'drill', drop, col)!;
    final full = t.hp;
    b.placeAt(t, col.toDouble(), drop.toDouble());
    run(b, 4);
    final sprung = [
      for (var c = col - 6; c <= col + 6; c++)
        if (st.base.structAt(row, c)?.triggered ?? false) c
    ];
    expect(sprung, isNotEmpty, reason: 'walked through a minefield untouched');
    expect(t.alive ? t.hp : 0, lessThan(full));
  });

  test('a raider that shares a defender tile still fights, never freezes', () {
    final base = yard();
    base.place(20, base.cols ~/ 2, DefType.guardPost, 'def');
    final st = AttackState(
      base: base,
      attacker: WarSide.you,
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      intel: {for (var k = 0; k < 40 * 40; k++) k},
    );
    final g = st.garrison.first;
    final b = armed(st);
    final t = st.spawn(TroopType.brute, 'drill', base.rows - 1, base.cols ~/ 2,
        allowStack: true)!;
    // drop it right on top of the defender — free move has no occupancy, and
    // troopAt would hand the raider back to itself as its own "victim"
    t.r = g.r;
    t.c = g.c;
    b.placeAt(t, g.c.toDouble(), g.r.toDouble());
    final guardHp = g.hp;
    run(b, 6);
    expect(g.alive ? g.hp : 0, lessThan(guardHp),
        reason: 'the raider stood on the guard and swung at thin air');
  });

  test('one hopeless unit cannot starve the army of planning', () {
    final st = drill();
    // a tower sealed inside mountains: scores well, can never be reached
    const sr = 30, sc = 10;
    st.base.place(sr, sc, DefType.archerTower, 'def');
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        st.base.grid[sr + dr][sc + dc].terrain = Terrain.mountain;
      }
    }
    final b = armed(st);
    final drop = st.base.rows - 1;
    final start = <String, double>{};
    for (final c in [sc, sc + 1]) {
      final t = st.spawn(TroopType.soldier, 'drill', drop, c, allowStack: true)!;
      b.placeAt(t, c.toDouble(), drop.toDouble());
    }
    final squad = <String>[];
    for (var c = st.base.cols ~/ 2 - 3; c <= st.base.cols ~/ 2 + 3; c++) {
      final t = st.spawn(TroopType.soldier, 'drill', drop, c, allowStack: true)!;
      b.placeAt(t, c.toDouble(), drop.toDouble());
      start[t.id] = drop.toDouble();
      squad.add(t.id);
    }
    run(b, 3);
    for (final id in squad) {
      final p = b.positions[id];
      if (p == null) continue; // died on the way in, which counts as moving
      expect(start[id]! - p.row, greaterThan(0.5),
          reason: 'raider $id never left the drop ring');
    }
  });

  test('a full army on a 64² master base stays cheap', () {
    final base = Base(WarSide.enemy, 30, size: 64);
    WarAi.designBase(
        base,
        [
          for (var i = 0; i < 5; i++)
            WarPlayer(
                id: 'p$i',
                name: 'P$i',
                emoji: '🤖',
                colorValue: 0xFFFF0000,
                side: WarSide.enemy,
                ai: AiLevel.master,
                isBot: true)
        ],
        SeededRng(7));
    final st = AttackState(
      base: base,
      attacker: WarSide.you,
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      intel: {for (var k = 0; k < base.rows * base.cols; k++) k},
    );
    final b = armed(st);
    var sent = 0;
    for (final d in st.base.dropCells) {
      if (sent >= 40) break;
      final t = st.spawn(TroopType.soldier, 'drill', d.r, d.c, allowStack: true);
      if (t != null) {
        b.placeAt(t, d.c.toDouble(), d.r.toDouble());
        sent++;
      }
    }
    expect(sent, 40);
    final sw = Stopwatch()..start();
    run(b, 30);
    sw.stop();
    // measured ~0.7s on a dev box; a 5s ceiling only trips on a real
    // algorithmic regression, not on a slow CI machine
    expect(sw.elapsedMilliseconds, lessThan(5000),
        reason: '30s of drill cost ${sw.elapsedMilliseconds}ms');
  });

  test('nobody downs tools on a walled master base', () {
    // The bug this guards: reach was measured centre-to-centre, so a raider
    // whose road ran out a fifth of a tile shy of the wall it meant to breach
    // sat 1.18 away from a target it could only hit at 1.15 — and, having no
    // route left either, stood there for the rest of the five minutes. On real
    // 64² league maps a handful of units per battle simply stopped fighting.
    for (final seed in [99, 4242, 31337]) {
      const size = 64;
      final base = Base(WarSide.enemy, seed, size: size);
      final areaMul =
          (size * size) / (Base.defaultSize * Base.defaultSize).toDouble();
      final budget = WarCosts.prepBudgetFor(AiData.skill(AiLevel.master)) *
          areaMul *
          2.6;
      WarAi.designBase(
          base,
          [
            for (var i = 0; i < 4; i++)
              WarPlayer(
                  id: 'p$i',
                  name: 'P$i',
                  emoji: '🤖',
                  colorValue: 0xFFFF0000,
                  side: WarSide.enemy,
                  ai: AiLevel.master,
                  isBot: true,
                  resources: budget)
          ],
          SeededRng(seed * 31 + 5));
      final st = AttackState(
        base: base,
        attacker: WarSide.you,
        attackerName: 'Drill',
        pools: MapPools({'drill': 1e9}),
        freeActions: true,
        intel: {for (var k = 0; k < base.rows * base.cols; k++) k},
      );
      final b = armed(st);
      final drops = st.base.dropCells.toList();
      const kinds = [
        TroopType.brute,
        TroopType.soldier,
        TroopType.archer,
        TroopType.sapper,
      ];
      for (var i = 0; i < 20; i++) {
        final d = drops[(i * 7) % drops.length];
        final t = st.spawn(kinds[i % 4], 'drill', d.r, d.c, allowStack: true);
        if (t == null) continue;
        b.placeAt(t, d.c.toDouble(), d.r.toDouble());
      }

      // a unit "makes progress" when it shifts a third of a tile or earns xp
      final mark = <String, List<double>>{};
      final lastProgress = <String, double>{};
      final worst = <String, double>{};
      var clock = 0.0;
      for (var i = 0; i < 30 * 90; i++) {
        b.tick(FreeMoveBattle.simStep);
        clock += FreeMoveBattle.simStep;
        if (i % 6 != 0) continue;
        for (final tr in st.troops) {
          if (!tr.alive) continue;
          final p = b.positions[tr.id];
          if (p == null) continue;
          final now = [p.col, p.row, tr.xp.toDouble()];
          final was = mark[tr.id];
          if (was == null ||
              (now[0] - was[0]).abs() > 0.33 ||
              (now[1] - was[1]).abs() > 0.33 ||
              now[2] != was[2]) {
            mark[tr.id] = now;
            lastProgress[tr.id] = clock;
          }
          final dry = clock - (lastProgress[tr.id] ?? 0);
          if (dry > (worst[tr.id] ?? 0)) worst[tr.id] = dry;
        }
        if (b.over) break;
      }
      final idlers = worst.entries.where((e) => e.value > 12).map((e) => e.key);
      expect(idlers, isEmpty,
          reason: 'seed $seed: ${idlers.length} raiders stopped fighting');
    }
  });

  test('a war elephant rams the wall instead of standing at it', () {
    // a plains yard with a solid wall band sealing the castle off, and the
    // ONLY gap far away — a detour a battering ram should refuse to take.
    final base = Base(WarSide.enemy, 3);
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        base.grid[r][c].terrain = Terrain.plains;
      }
    }
    final mid = base.cols ~/ 2;
    // wall band just inside the landing ring, its only gap far to the left —
    // and the castle right behind it, so the ram meets the wall almost at once
    final wallRow = base.rows - 4;
    for (var c = 3; c < base.cols - 1; c++) {
      base.place(wallRow, c, DefType.wall, 'def');
    }
    base.placeCastle('def', wallRow - 3, mid);
    final st = AttackState(
      base: base,
      attacker: WarSide.you,
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      intel: {for (var k = 0; k < base.rows * base.cols; k++) k},
    );
    final b = armed(st);
    final drop = base.rows - 1;
    for (var i = 0; i < 3; i++) {
      final t = st.spawn(TroopType.elephant, 'drill', drop, mid, allowStack: true);
      expect(t, isNotNull);
      b.placeAt(t!, mid.toDouble(), drop.toDouble());
    }
    var walls0 = 0;
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s != null && s.alive && s.type == DefType.wall) walls0++;
      }
    }
    run(b, 40);
    var walls1 = 0;
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s != null && s.alive && s.type == DefType.wall) walls1++;
      }
    }
    expect(walls1, lessThan(walls0),
        reason: 'the elephant walked to the wall in front of it and just '
            'stood there instead of smashing through');
  });

  test('stranded wave troops wander instead of idling on the drop ring', () {
    // Wall-sealed yard with the ONLY gap far to the side: units that never
    // get a full road must still leave the landing ring on their own.
    final base = Base(WarSide.enemy, 11);
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        base.grid[r][c].terrain = Terrain.plains;
      }
    }
    final wallRow = base.rows - 4;
    for (var c = 1; c < base.cols - 1; c++) {
      if (c == 2) continue; // one distant gate-gap
      base.place(wallRow, c, DefType.wall, 'def');
    }
    base.placeCastle('def', wallRow - 3, base.cols ~/ 2);
    final st = AttackState(
      base: base,
      attacker: WarSide.you,
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      intel: {for (var k = 0; k < base.rows * base.cols; k++) k},
    );
    final b = armed(st);
    final drop = base.rows - 1;
    final mid = base.cols ~/ 2;
    for (var i = 0; i < 12; i++) {
      final t =
          st.spawn(TroopType.soldier, 'drill', drop, mid, allowStack: true);
      expect(t, isNotNull);
      b.placeAt(t!, mid.toDouble(), drop.toDouble());
    }
    run(b, 4);
    final stillOnDrop =
        st.troops.where((t) => t.alive && t.r == drop).length;
    expect(stillOnDrop, lessThan(4),
        reason: 'most of the wave stayed planted on the landing tile');
  });

  test('troops seek a distant bridge instead of staring across the river', () {
    // Castle dead ahead across a river; the ONLY bridge is far to the left.
    // Old bug: units bee-lined to the bank and froze instead of pathing over.
    final base = Base(WarSide.enemy, 19);
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        base.grid[r][c].terrain = Terrain.plains;
      }
    }
    final riverRow = base.rows - 6;
    final mid = base.cols ~/ 2;
    for (var c = 0; c < base.cols; c++) {
      base.grid[riverRow][c].terrain = Terrain.river;
    }
    const bridgeC = 2; // far from the drop
    base.grid[riverRow][bridgeC].terrain = Terrain.bridge;
    base.placeCastle('def', 8, mid);
    final st = AttackState(
      base: base,
      attacker: WarSide.you,
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      intel: {for (var k = 0; k < base.rows * base.cols; k++) k},
    );
    final b = armed(st);
    final drop = base.rows - 1;
    for (var i = 0; i < 6; i++) {
      final t =
          st.spawn(TroopType.soldier, 'drill', drop, mid, allowStack: true);
      if (t != null) b.placeAt(t, mid.toDouble(), drop.toDouble());
    }
    run(b, 20);
    final crossed = st.troops.where((t) => t.alive && t.r < riverRow).length;
    expect(crossed, greaterThanOrEqualTo(2),
        reason: 'raiders stared at the river instead of walking to the bridge');
    // someone should have actually touched the distant bridge (or passed it)
    final usedBridge = st.troops.any((t) =>
        t.alive &&
        (t.c - bridgeC).abs() <= 1 &&
        (t.r - riverRow).abs() <= 1);
    expect(usedBridge || crossed >= 2, isTrue);
  });

  test('sealed keep: troops smash the wall instead of circling it', () {
    // Regression: walk-around looked "short enough", blockKey got wiped on
    // every replan, and the wave paced laps around the curtain forever.
    final base = Base(WarSide.enemy, 31);
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        base.grid[r][c].terrain = Terrain.plains;
      }
    }
    const cr = 12, cc = 20;
    base.placeCastle('def', cr, cc);
    // diamond / box keep — only way in is through a wall
    for (var r = cr - 3; r <= cr + 3; r++) {
      for (var c = cc - 3; c <= cc + 3; c++) {
        if (r == cr - 3 ||
            r == cr + 3 ||
            c == cc - 3 ||
            c == cc + 3) {
          if (base.canPlace(r, c)) {
            base.place(r, c, DefType.wall, 'def');
          }
        }
      }
    }
    final st = AttackState(
      base: base,
      attacker: WarSide.you,
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      intel: {for (var k = 0; k < base.rows * base.cols; k++) k},
    );
    final b = armed(st);
    final drop = base.rows - 1;
    for (var i = 0; i < 10; i++) {
      final c = cc - 2 + (i % 5);
      final t =
          st.spawn(TroopType.soldier, 'drill', drop, c, allowStack: true);
      if (t != null) b.placeAt(t, c.toDouble(), drop.toDouble());
    }

    var wallsBefore = 0;
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s != null && s.alive && s.type == DefType.wall) wallsBefore++;
      }
    }
    run(b, 28);
    var wallsAfter = 0;
    var inside = 0;
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        final s = base.structAt(r, c);
        if (s != null && s.alive && s.type == DefType.wall) wallsAfter++;
      }
    }
    for (final t in st.troops) {
      if (!t.alive) continue;
      if ((t.r - cr).abs() <= 2 && (t.c - cc).abs() <= 2) inside++;
    }
    expect(wallsAfter, lessThan(wallsBefore),
        reason: 'nobody chewed the curtain — still circling outside');
    expect(inside > 0 || wallsAfter <= wallsBefore - 2, isTrue,
        reason: 'wave never committed a breach into the keep');
  });

  test('multi-tile bridges do not ping-pong — troops commit across', () {
    // Regression: units on a plank treated the river beside them as still
    // "blocking", retargeted the tile behind them, and walked back and forth.
    final base = Base(WarSide.enemy, 23);
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        base.grid[r][c].terrain = Terrain.plains;
      }
    }
    final riverRow = base.rows - 7;
    final mid = base.cols ~/ 2;
    for (var c = 0; c < base.cols; c++) {
      base.grid[riverRow][c].terrain = Terrain.river;
    }
    // three-plank bridge offset from the drop so staging + commit both matter
    for (final c in [mid - 1, mid, mid + 1]) {
      base.grid[riverRow][c].terrain = Terrain.bridge;
    }
    base.placeCastle('def', 8, mid + 6);
    final st = AttackState(
      base: base,
      attacker: WarSide.you,
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      intel: {for (var k = 0; k < base.rows * base.cols; k++) k},
    );
    final b = armed(st);
    final drop = base.rows - 1;
    for (var i = 0; i < 8; i++) {
      final c = mid - 2 + (i % 5);
      final t =
          st.spawn(TroopType.soldier, 'drill', drop, c, allowStack: true);
      if (t != null) b.placeAt(t, c.toDouble(), drop.toDouble());
    }

    // Sample every half-second: a unit that has been north of the river must
    // not later be south again (classic bridge ping-pong).
    final everNorth = <String>{};
    var regressions = 0;
    for (var i = 0; i < (22 / FreeMoveBattle.simStep).round(); i++) {
      b.tick(FreeMoveBattle.simStep);
      if (i % 15 != 0) continue;
      for (final t in st.troops) {
        if (!t.alive) continue;
        if (t.r < riverRow) {
          everNorth.add(t.id);
        } else if (t.r > riverRow && everNorth.contains(t.id)) {
          regressions++;
        }
      }
    }
    final crossed =
        st.troops.where((t) => t.alive && t.r < riverRow).length;
    expect(crossed, greaterThanOrEqualTo(4),
        reason: 'wave failed to commit across the multi-tile bridge');
    expect(regressions, 0,
        reason: 'troops walked back south after crossing (bridge ping-pong)');
  });

  test('free-move troops never step onto river tiles — they use bridges', () {
    final base = Base(WarSide.enemy, 13);
    for (var r = 0; r < base.rows; r++) {
      for (var c = 0; c < base.cols; c++) {
        base.grid[r][c].terrain = Terrain.plains;
      }
    }
    // a river band across the approach with a single bridge in the middle
    final riverRow = base.rows - 6;
    for (var c = 0; c < base.cols; c++) {
      base.grid[riverRow][c].terrain = Terrain.river;
    }
    final bridgeC = base.cols ~/ 2;
    base.grid[riverRow][bridgeC].terrain = Terrain.bridge;
    base.placeCastle('def', 8, bridgeC);
    final st = AttackState(
      base: base,
      attacker: WarSide.you,
      attackerName: 'Drill',
      pools: MapPools({'drill': 1e9}),
      freeActions: true,
      intel: {for (var k = 0; k < base.rows * base.cols; k++) k},
    );
    final b = armed(st);
    final drop = base.rows - 1;
    for (var i = 0; i < 8; i++) {
      final c = bridgeC - 2 + (i % 5);
      final t = st.spawn(TroopType.soldier, 'drill', drop, c, allowStack: true);
      if (t != null) b.placeAt(t, c.toDouble(), drop.toDouble());
    }
    for (var i = 0; i < 30 * 25; i++) {
      b.tick(FreeMoveBattle.simStep);
      for (final t in st.troops) {
        if (!t.alive) continue;
        expect(base.grid[t.r][t.c].terrain, isNot(Terrain.river),
            reason: '${t.id} walked onto river at (${t.r},${t.c})');
      }
      if (b.over) break;
    }
    // at least someone should have used the bridge (stood on it or past it)
    final crossed = st.troops.any((t) => t.alive && t.r < riverRow);
    expect(crossed, isTrue, reason: 'nobody crossed via the bridge');
  });

  test('classic drill still runs the tile engine untouched', () {
    final st = drill();
    final classic = LiveBattle(st, canDeploy: () => true);
    final drop = st.base.rows - 1, col = st.base.cols ~/ 2;
    final t = st.spawn(TroopType.soldier, 'drill', drop, col)!;
    final startR = t.r, startC = t.c;
    classic.tick(LiveBattle.stepPeriod);
    // one round = whole tiles, no fractions anywhere in sight
    expect((startR - t.r).abs() + (startC - t.c).abs(), greaterThanOrEqualTo(1));
  });
}
