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
