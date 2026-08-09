import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jars/core/seeded_rng.dart';
import 'package:jars/war/live_battle.dart';
import 'package:jars/war/war_ai.dart';
import 'package:jars/war/war_base.dart';
import 'package:jars/war/war_engine.dart';
import 'package:jars/war/war_game.dart';
import 'package:jars/war/war_player.dart';
import 'package:jars/war/war_scoring.dart';
import 'package:jars/war/war_sim.dart';
import 'package:jars/war/war_troop.dart';
import 'package:jars/war/war_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('scoring / verdict', () {
    ClanTally you({double d = 0, bool raze = false, int fell = -1, int lost = 0, double spent = 0}) =>
        ClanTally(WarSide.you,
            destructionDealt: d, razedEnemy: raze, enemyFellAtMin: fell, troopsLost: lost, resourcesSpent: spent);
    ClanTally foe({double d = 0, bool raze = false, int fell = -1, int lost = 0, double spent = 0}) =>
        ClanTally(WarSide.enemy,
            destructionDealt: d, razedEnemy: raze, enemyFellAtMin: fell, troopsLost: lost, resourcesSpent: spent);

    test('a knockout wins outright', () {
      final v = WarScoring.decide(you(raze: true, d: 100), foe(d: 40));
      expect(v.winner, WarSide.you);
      expect(v.knockout, isTrue);
    });
    test('higher destruction wins when neither is razed', () {
      final v = WarScoring.decide(you(d: 70), foe(d: 55));
      expect(v.winner, WarSide.you);
    });
    test('tie on destruction breaks on fewer troops lost', () {
      final v = WarScoring.decide(you(d: 60, lost: 2), foe(d: 60, lost: 5));
      expect(v.winner, WarSide.you);
      expect(v.reasons.any((r) => r.contains('Losses')), isTrue);
    });
  });

  group('engine', () {
    /// Clear a column of terrain so fixed test placements never land on the
    /// generated river/mountains.
    void flatten(Base base, List<List<int>> cells) {
      for (final rc in cells) {
        base.grid[rc[0]][rc[1]].terrain = Terrain.plains;
      }
    }

    AttackState scenario({double defenderFunds = 999, double attackerFunds = 999}) {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.place(Base.defaultSize - 4, 3, DefType.wall, 'def');
      base.place(Base.defaultSize - 5, 3, DefType.archerTower, 'def');
      base.placeCastle('def', 2, 3);
      final pools = MapPools({'me': attackerFunds, 'def': defenderFunds});
      return AttackState(
          base: base, attacker: WarSide.you, attackerName: 'Me', pools: pools);
    }

    test('marching captures ground and clears fog', () {
      final st = scenario();
      // column 3 is flattened by the scenario, so the route is guaranteed
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      expect(st.visible(Base.defaultSize - 1, 3), isTrue);
      st.moveTroop(t, Base.defaultSize - 3, 3);
      expect(t.r, Base.defaultSize - 3);
      expect(st.base.at(t.r, t.c)!.owner, WarSide.you);
      expect(st.visible(t.r, t.c), isTrue);
    });

    test('a troop grinds down a structure and earns XP', () {
      final st = scenario();
      final t = st.spawn(TroopType.sapper, 'me', Base.defaultSize - 1, 3)!;
      t.r = Base.defaultSize - 3;
      final wall = st.base.structAt(Base.defaultSize - 4, 3)!;
      final hp0 = wall.hp;
      st.attackCell(t, Base.defaultSize - 4, 3);
      expect(wall.hp, lessThan(hp0));
      expect(t.xp, greaterThan(0));
    });

    test('a destroyed structure leaves a grave, same as a fallen troop', () {
      final st = scenario();
      final t = st.spawn(TroopType.sapper, 'me', Base.defaultSize - 1, 3)!;
      t.r = Base.defaultSize - 3;
      final wall = st.base.structAt(Base.defaultSize - 4, 3)!;
      wall.hp = 1; // guarantee this hit finishes it off
      st.attackCell(t, Base.defaultSize - 4, 3);
      expect(wall.alive, isFalse, reason: 'sanity: the wall is actually gone');
      expect(
          st.graves.any((g) => g[0] == Base.defaultSize - 4 && g[1] == 3),
          isTrue,
          reason: 'a destroyed structure gets a tombstone too, same as troops');
    });

    test('defenses are AUTONOMOUS — even a broke clan\'s towers fight', () {
      final rich = scenario(defenderFunds: 999);
      final broke = scenario(defenderFunds: 0);
      for (final st in [rich, broke]) {
        final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
        t.r = Base.defaultSize - 4;
      }
      final rt = rich.troops.first;
      final bt = broke.troops.first;
      final rHp0 = rt.hp, bHp0 = bt.hp;
      rich.defendersReact();
      broke.defendersReact();
      expect(rt.hp, lessThan(rHp0), reason: 'the tower fires');
      expect(bt.hp, lessThan(bHp0),
          reason: 'a tower NEVER goes silent over its owner\'s wallet');
    });

    test('an attacker with no resources cannot move', () {
      final st = scenario(attackerFunds: 25);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      final r0 = t.r;
      st.moveTroop(t, Base.defaultSize - 4, 3);
      expect(t.r, r0);
    });

    test('a guard post fields a live defender that hunts inside its patrol zone',
        () {
      final base = Base(WarSide.enemy, 11);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 3],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 4, 4, DefType.guardPost, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      expect(st.garrison, hasLength(1), reason: 'guard post spawns a defender');
      final guard = st.garrison.first;
      // an intruder INSIDE the patrol zone gets hunted
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
      final d0 = (guard.r - t.r).abs() + (guard.c - t.c).abs();
      st.defendersReact();
      final d1 = (guard.r - t.r).abs() + (guard.c - t.c).abs();
      expect(d1, lessThanOrEqualTo(d0), reason: 'the guard closes in');
    });

    test('a garrison defender leashes: never strays, returns home', () {
      final base = Base(WarSide.enemy, 11);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 0],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(4, 4, DefType.guardPost, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final guard = st.garrison.first;
      // drag the guard off its post, then give it nothing to fight
      guard.r = 4 + AttackState.garrisonLeash;
      guard.c = 4;
      // an intruder FAR outside the patrol zone (bottom corner) is ignored
      st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 0);
      st.defendersReact();
      final distHome = (guard.r - 4).abs() + (guard.c - 4).abs();
      expect(distHome, lessThan(AttackState.garrisonLeash),
          reason: 'with no target in the zone, the guard marches home');
    });

    test('a tesla zaps a troop the moment it moves in range', () {
      final base = Base(WarSide.enemy, 13);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 4, 3, DefType.tesla, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      final hp0 = t.hp;
      st.moveTroop(t, Base.defaultSize - 3, 3); // walks into tesla range (2)
      expect(t.hp, lessThan(hp0), reason: 'dynamic zap on movement');
      expect(st.base.structAt(Base.defaultSize - 4, 3)!.triggered, isTrue);
    });

    test('a tesla splits its damage pool across up to 4 raiders', () {
      final base = Base(WarSide.enemy, 17);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++)
          for (var c = 2; c <= 5; c++) [r, c]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(10, 3, DefType.tesla, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}),
          freeActions: true,
          intel: {for (var k = 0; k < base.rows * base.cols; k++) k});
      // land on the ring, then park four soldiers in the coil's bubble
      final spots = [
        [10, 4],
        [10, 5],
        [11, 3],
        [11, 4],
      ];
      final drop = base.rows - 1;
      final squad = <Troop>[];
      for (var i = 0; i < spots.length; i++) {
        final t = st.spawn(TroopType.soldier, 'me', drop, 3 + i)!;
        t.r = spots[i][0];
        t.c = spots[i][1];
        squad.add(t);
      }
      final hp0 = [for (final t in squad) t.hp];
      st.defendersReact();
      final lost = [
        for (var i = 0; i < squad.length; i++) hp0[i] - squad[i].hp
      ];
      expect(lost.every((d) => d > 0), isTrue,
          reason: 'every raider in the pack should take a share');
      expect(lost.reduce((a, b) => a + b), 24,
          reason: 'L1 pool is 24 split across the four');
      expect(lost.toSet().length, 1, reason: 'even split — 6 each');
    });

    test('defenders never gain XP — no unkillable guards', () {
      final base = Base(WarSide.enemy, 11);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 3],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 4, 4, DefType.guardPost, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final guard = st.garrison.first;
      // park a fat target right next to the guard and let it swing repeatedly
      final t = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 4)!;
      t.r = guard.r + 1;
      t.c = guard.c;
      for (var i = 0; i < 5; i++) {
        st.defendersReact();
        if (!t.alive) break;
      }
      expect(guard.xp, 0, reason: 'garrison must not level');
      expect(guard.level, 1);
    });

    test('reachable excludes tiles the owner cannot afford', () {
      // exactly one soldier, 0 left
      final st = scenario(
          attackerFunds: kTroopSpecs[TroopType.soldier]!.cost.toDouble());
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      expect(st.reachable(t), isEmpty,
          reason: 'broke owner → no blue tiles, not a silent no-op');
      // fund them → tiles appear, each with its ⚡ price
      st.pools.add('me', 50);
      final reach = st.reachable(t);
      expect(reach, isNotEmpty);
      expect(reach.values.every((i) => i.energyCost > 0), isTrue);
    });

    test('clash mode: deployed troops act for free', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({
            'me': kTroopSpecs[TroopType.soldier]!.cost.toDouble(),
            'def': 999
          }),
          freeActions: true);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      expect(st.pools.of('me'), 0, reason: 'deploying still costs');
      final reach = st.reachable(t);
      expect(reach, isNotEmpty, reason: 'movement is free in clash mode');
      final k = reach.keys.first;
      st.moveTroop(t, k ~/ Base.defaultSize, k % Base.defaultSize);
      expect(st.pools.of('me'), 0, reason: 'no charge for moving');
    });

    test('prepaid spawn (trained army) charges nothing at deploy time', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 0, 'def': 999}));
      final t = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3, prepaid: true);
      expect(t, isNotNull, reason: 'a trained troop lands even with 0 ⚡');
      expect(st.pools.of('me'), 0);
    });

    test('the landing ring accepts drops on all four sides', () {
      final base = Base(WarSide.enemy, 7);
      final drops = base.dropCells.toList();
      expect(drops.any((c) => c.r == 0), isTrue, reason: 'north side');
      expect(drops.any((c) => c.r == Base.defaultSize - 1), isTrue, reason: 'south side');
      expect(drops.any((c) => c.c == 0), isTrue, reason: 'west side');
      expect(drops.any((c) => c.c == Base.defaultSize - 1), isTrue, reason: 'east side');
    });

    test('fog-honest objectives: unscouted buildings are invisible to the AI',
        () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 5, 3); // deep in the fog (past the band)
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      final obj = WarAi.pickObjective(st, t)!;
      expect(st.visible(5, 3), isFalse);
      expect(obj == const Cell(5, 3), isFalse,
          reason: 'the AI must chase nearby fog, not a castle it cannot see');
    });

    test('clearForest chops forests but never mountains', () {
      final base = Base(WarSide.enemy, 7);
      base.grid[5][5].terrain = Terrain.forest;
      base.grid[6][6].terrain = Terrain.mountain;
      expect(base.clearForest(5, 5), isTrue);
      expect(base.grid[5][5].terrain, Terrain.plains);
      expect(base.clearForest(6, 6), isFalse);
      expect(base.grid[6][6].terrain, Terrain.mountain);
      expect(base.cleared, contains(5 * Base.defaultSize + 5));
    });

    test('the landing ring is one-way: no walking back out', () {
      final st = scenario();
      // clear a second lane — the scenario walls (rows-4, 3)
      flatten(st.base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 4]
      ]);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      st.moveTroop(t, Base.defaultSize - 3, 3); // to the band's inner edge
      st.moveTroop(t, Base.defaultSize - 4, 4); // now the interior is scouted — enter
      expect(st.base.isRing(t.r, t.c), isFalse);
      final reach = st.reachable(t);
      for (final k in reach.keys) {
        expect(st.base.isRing(k ~/ Base.defaultSize, k % Base.defaultSize), isFalse,
            reason: 'interior troops can never re-enter the ring');
      }
    });

    test('one aiStep moves at most 2 tiles (no teleporting)', () {
      final st = scenario();
      final t = st.spawn(TroopType.runner, 'me', Base.defaultSize - 1, 3)!;
      for (var i = 0; i < 10; i++) {
        final r0 = t.r, c0 = t.c;
        WarAi.aiStep(st, t);
        final moved = (t.r - r0).abs() + (t.c - c0).abs();
        expect(moved, lessThanOrEqualTo(2));
        if (!t.alive) break;
      }
    });

    test('troops never stand on impassable terrain', () {
      final st = scenario();
      for (final drop in st.base.dropCells.take(4)) {
        st.spawn(TroopType.soldier, 'me', drop.r, drop.c);
      }
      for (var round = 0; round < 60; round++) {
        for (final t in st.troops.where((x) => x.alive).toList()) {
          WarAi.aiStep(st, t);
          if (t.alive) {
            final terr = st.base.at(t.r, t.c)!.terrain;
            if (terr == Terrain.mountain || terr == Terrain.river) {
              fail('troop ${t.id} standing on $terr at (${t.r},${t.c}) '
                  'round $round — mountain/river hopping');
            }
          }
        }
        st.defendersReact();
      }
    });

    test('level-up patches +25%, never a full heal', () {
      final st = scenario();
      final t = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      t.hp = 40; // badly wounded
      t.gainXp(Xp.perLevel.toDouble()); // ding! level 2
      expect(t.level, 2);
      expect(t.hp, lessThan(t.maxHp),
          reason: 'promotions patch you up, they don\'t resurrect you');
      expect(t.hp, greaterThan(40), reason: 'but they do help');
    });

    test('the mortar has a blind spot up close', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 6, 3, DefType.mortar, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      // adjacent attacker: inside minRange → mortar can't fire
      final close = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      close.r = Base.defaultSize - 7; // chebyshev 1 from the mortar
      final hpClose = close.hp;
      st.defendersReact();
      expect(close.hp, hpClose, reason: 'inside the blind spot');
      // pull back to range 4 → boom
      close.r = Base.defaultSize - 2;
      final hpFar = close.hp;
      st.defendersReact();
      st.defendersReact();
      st.defendersReact();
      expect(close.hp, lessThan(hpFar), reason: 'in range, shells land');
    });

    test('AI raids penetrate deep now (freeActions like the player)', () {
      final base = Base(WarSide.you, 21); // an undefended-ish base
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, Base.defaultSize ~/ 2]
      ]);
      base.placeCastle('you', Base.defaultSize ~/ 2, Base.defaultSize ~/ 2);
      expect(base.castleCells, isNotEmpty, reason: 'castle must actually place');
      final raider = WarPlayer(
          id: 'e1',
          name: 'Grim',
          emoji: '💀',
          colorValue: 0xFFE6483F,
          side: WarSide.enemy,
          ai: AiLevel.seasoned,
          resources: 200);
      final pools = MapPools({'e1': 200});
      final res = WarAi.runAttack(
          base: base,
          attacker: raider,
          pools: pools,
          rng: SeededRng(seedFromParts([1, 2, 3])));
      expect(res.destructionPercent, greaterThan(10),
          reason: 'no more dying broke three tiles in');
    });

    test('troops ignore walls when a route exists, breach when sealed', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 3],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 5, 3);
      base.place(Base.defaultSize - 8, 3, DefType.archerTower, 'def'); // objective
      base.place(Base.defaultSize - 7, 4, DefType.wall, 'def'); // an IGNORABLE wall
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.r = Base.defaultSize - 7; // adjacent to the wall at (rows-7, 4)
      final wall = base.structAt(Base.defaultSize - 7, 4)!;
      final hp0 = wall.hp;
      // reveal the tower so it's a real objective
      for (var r = Base.defaultSize - 10; r < Base.defaultSize - 4; r++) {
        st.revealed.add(r * Base.defaultSize + 3);
        st.revealed.add(r * Base.defaultSize + 4);
      }
      WarAi.aiStep(st, t);
      expect(wall.hp, hp0,
          reason: 'a wall beside the road is IGNORED while a route exists');
    });

    test('forest conceals troops from distant towers', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 6, 3, DefType.archerTower, 'def'); // range 3
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      // stand in forest at range 3 from the tower → invisible
      t.r = Base.defaultSize - 3;
      base.grid[t.r][t.c].terrain = Terrain.forest;
      final hp0 = t.hp;
      st.defendersReact();
      expect(t.hp, hp0, reason: 'hidden in the trees at range 3');
      // step to range 2 → spotted
      t.r = Base.defaultSize - 4;
      base.grid[t.r][t.c].terrain = Terrain.forest;
      st.defendersReact();
      expect(t.hp, lessThan(hp0), reason: 'spotted at close range');
    });

    test('the garrison marches through GATES — walls stop them too now', () {
      AttackState mk(DefType doorway) {
        final base = Base(WarSide.enemy, 11);
        flatten(base, [
          for (var r = 0; r < Base.defaultSize; r++) ...[
            [r, 3],
            [r, 4]
          ]
        ]);
        base.placeCastle('def', 2, 3);
        base.place(6, 4, DefType.guardPost, 'def');
        // directly on the guard's chase path
        base.place(7, 4, doorway, 'def');
        return AttackState(
            base: base,
            attacker: WarSide.you,
            attackerName: 'Me',
            pools: MapPools({'me': 999, 'def': 999}));
      }

      // the gate is THEIR door — one react and the guard stands in it
      final stG = mk(DefType.gate);
      final guardG = stG.garrison.first;
      final intruderG = stG.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
      intruderG.r = 8;
      intruderG.c = 4;
      stG.defendersReact();
      expect(
          (guardG.r - intruderG.r).abs() + (guardG.c - intruderG.c).abs(), 1,
          reason: 'the gate is THEIR door — straight through it');

      // a WALL is never ghosted over — the guard goes AROUND it
      final stW = mk(DefType.wall);
      final guardW = stW.garrison.first;
      final intruderW = stW.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
      intruderW.r = 8;
      intruderW.c = 4;
      final full = intruderW.hp;
      for (var i = 0; i < 8; i++) {
        stW.defendersReact();
        expect(guardW.r == 7 && guardW.c == 4, isFalse,
            reason: 'no more ghosting over the ramparts');
      }
      expect(intruderW.hp, lessThan(full),
          reason: 'around the wall, sword out — the detour works');
    });

    test('mortar shells splash the whole impact area', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 3],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 8, 3, DefType.mortar, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final a = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      final b = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 4)!;
      a.r = Base.defaultSize - 4; // range 4 from the mortar — fair game
      b.r = Base.defaultSize - 4;
      final aHp = a.hp, bHp = b.hp;
      for (var i = 0; i < 3; i++) {
        st.defendersReact(); // cooldown 3 → at least one volley
      }
      expect(a.hp, lessThan(aHp), reason: 'center hit');
      expect(b.hp, lessThan(bHp), reason: 'adjacent troop splashed');
      expect(aHp - a.hp, greaterThan(bHp - b.hp),
          reason: 'center takes more than splash');
    });

    test('scouts reveal a radius-2 area', () {
      final st = scenario();
      final t = st.spawn(TroopType.runner, 'me', Base.defaultSize - 1, 3)!;
      st.moveTroop(t, Base.defaultSize - 3, 3);
      st.moveTroop(t, Base.defaultSize - 4, 3); // march past the band, in hops
      final scoutSees = st.revealed.length;
      final st2 = scenario();
      final t2 = st2.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      st2.moveTroop(t2, Base.defaultSize - 3, 3);
      st2.moveTroop(t2, Base.defaultSize - 4, 3);
      expect(scoutSees, greaterThan(st2.revealed.length),
          reason: 'the scout uncovers more fog than a line trooper');
    });

    test('elite clans build real strongholds (whole arsenal)', () {
      WarPlayer mk(String id, AiLevel ai) => WarPlayer(
          id: id,
          name: id,
          emoji: '💀',
          colorValue: 0xFFE6483F,
          side: WarSide.enemy,
          ai: ai,
          resources: 400); // masters bring a real war chest (startPrep scales)
      final eliteBase = Base(WarSide.enemy, 31);
      final elite = [for (var i = 0; i < 4; i++) mk('e$i', AiLevel.master)];
      WarAi.designBase(eliteBase, elite, SeededRng(seedFromParts([9, 9])));
      final types = <DefType>{};
      var walls = 0;
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          final s = eliteBase.structAt(r, c);
          if (s == null) continue;
          types.add(s.type);
          if (s.type == DefType.wall) walls++;
        }
      }
      expect(types.length, greaterThanOrEqualTo(6),
          reason: 'masters use the whole arsenal: got $types');
      expect(walls, greaterThanOrEqualTo(10),
          reason: 'a stronghold has a real wall ring');

      final rookieBase = Base(WarSide.enemy, 31);
      final rookies = [for (var i = 0; i < 4; i++) mk('r$i', AiLevel.rookie)];
      WarAi.designBase(rookieBase, rookies, SeededRng(seedFromParts([9, 9])));
      var rookieStructs = 0, eliteStructs = 0;
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          if (rookieBase.structAt(r, c) != null) rookieStructs++;
          if (eliteBase.structAt(r, c) != null) eliteStructs++;
        }
      }
      expect(eliteStructs, greaterThan(rookieStructs),
          reason: 'skill shows in the fortifications');
    });

    test('replay frames record the structures as they stood', () {
      final st = scenario();
      st.snapshot('start');
      expect(st.frames.last.structs, isNotEmpty,
          reason: 'walls/towers/castle are in the frame');
      final wall = st.frames.last.structs
          .where((s) => s.type == DefType.wall)
          .toList();
      expect(wall, hasLength(1));
      expect(wall.single.hpFrac, 1.0);
    });

    test('replay frames carry the combat FX', () {
      final st = scenario();
      final t = st.spawn(TroopType.sapper, 'me', Base.defaultSize - 1, 3)!;
      t.r = Base.defaultSize - 3;
      st.attackCell(t, Base.defaultSize - 4, 3); // smash the wall → melee FX
      st.snapshot();
      expect(st.frames.last.fx, isNotEmpty,
          reason: 'replays play the arrows/cannonballs, not emoji');
    });

    test('bridges sit on straight water crossings', () {
      final base = Base(WarSide.enemy, 7);
      bool water(int r, int c) =>
          base.inBounds(r, c) &&
          (base.grid[r][c].terrain == Terrain.river ||
              base.grid[r][c].terrain == Terrain.bridge);
      for (var r = 1; r < Base.defaultSize - 1; r++) {
        for (var c = 1; c < Base.defaultSize - 1; c++) {
          if (base.grid[r][c].terrain != Terrain.bridge) continue;
          final horiz = water(r, c - 1) && water(r, c + 1);
          final vert = water(r - 1, c) && water(r + 1, c);
          expect(horiz || vert, isTrue,
              reason: 'a bridge must span water on opposite sides ($r,$c)');
        }
      }
    });

    test('aiStep marches a troop toward the base and it fights', () {
      final st = scenario();
      final t = st.spawn(TroopType.sapper, 'me', Base.defaultSize - 1, 3)!;
      final d0 = (t.r - 2).abs() + (t.c - 3).abs();
      var guard = 0;
      while (guard++ < 60 && t.alive && !st.base.allCastlesRazed) {
        if (!WarAi.aiStep(st, t)) break;
      }
      final d1 = (t.r - 2).abs() + (t.c - 3).abs();
      final progressed = d1 < d0 || st.base.destructionPercent > 0 || !t.alive;
      expect(progressed, isTrue,
          reason: 'the troop advances, damages the base, or dies trying');
    });

    test('a LiveBattle ticks to completion and deals destruction', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 500, 'def': 200}),
          freeActions: true);
      final battle = LiveBattle(st, canDeploy: () => false);
      for (final drop in base.dropCells.take(4)) {
        st.spawn(TroopType.sapper, 'me', drop.r, drop.c);
      }
      var guard = 0;
      while (!battle.over && guard++ < 500) {
        battle.tick(LiveBattle.stepPeriod);
      }
      expect(battle.over, isTrue);
      expect(st.frames, isNotEmpty, reason: 'the battle records a replay');
    });

    test('a LiveBattle waits for you while trained troops remain', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 0, 'def': 200}),
          freeActions: true);
      final battle = LiveBattle(st, canDeploy: () => true); // army in reserve
      for (var i = 0; i < 30; i++) {
        battle.round(); // empty field, but the commander can still deploy
      }
      expect(battle.over, isFalse,
          reason: 'no more "battle over while I was still placing"');
    });

    test('an in-progress raid survives a save/load round trip', () {
      final st = scenario();
      final drop = st.base.dropCells.first;
      final t = st.spawn(TroopType.soldier, 'me', drop.r, drop.c)!;
      st.moveTroop(t, Base.defaultSize - 3, drop.c);
      final j = st.toJson();
      final restored = AttackState.restore(
        base: st.base,
        attacker: WarSide.you,
        pools: MapPools({'me': 999, 'def': 999}),
        j: j,
      );
      expect(restored.troops, hasLength(st.troops.length));
      expect(restored.troops.first.r, t.r);
      expect(restored.revealed, st.revealed);
      expect(restored.resourcesSpent, closeTo(st.resourcesSpent, 0.001));
    });
  });

  group('war loop (deterministic)', () {
    test('same seed → same fast-forward outcome', () {
      final g1 = WarGame.fresh()..startPrep();
      g1.startWar();
      g1.advanceHours(8);
      final g2 = WarGame.fresh()..startPrep();
      g2.startWar();
      g2.advanceHours(8);
      expect(g1.youDestruction, closeTo(g2.youDestruction, 0.001));
      expect(g1.enemyDestruction, closeTo(g2.enemyDestruction, 0.001));
    });

    test('AI raids chip the bases over a war day', () {
      final g = WarGame.fresh()..startPrep();
      g.startWar();
      g.advanceToEndOfDay();
      expect(g.phase, WarPhase.results);
      expect(g.lastVerdict, isNotNull);
      expect(g.youDestruction + g.enemyDestruction, greaterThan(0));
    });

    test('training builds an army; deploying consumes it, not ⚡', () {
      final g = WarGame.fresh()..startPrep();
      g.startWar();
      final you = g.players.firstWhere((p) => p.id == 'you');
      you.resources = 100;
      expect(g.trainTroop(TroopType.soldier), isNull);
      expect(g.trainTroop(TroopType.soldier), isNull);
      expect(you.armyCount(TroopType.soldier), 2);
      expect(you.resources, closeTo(100 - 2 * kTroopSpecs[TroopType.soldier]!.cost, 0.001));

      final st = g.beginLiveAttack();
      final wallet = you.resources;
      final drop = g.enemyBase.dropCells.first;
      final t = g.deployTrained(st, TroopType.soldier, drop.r, drop.c);
      expect(t, isNotNull);
      expect(you.armyCount(TroopType.soldier), 1, reason: 'one consumed');
      expect(you.resources, closeTo(wallet, 0.001), reason: 'deploy is free');
      // untrained type refuses
      expect(g.deployTrained(st, TroopType.brute, drop.r, drop.c), isNull);
    });

    test('raid survivors return to the army on END RAID / razed bank', () {
      final g = WarGame.fresh()..startPrep();
      g.startWar();
      final you = g.players.firstWhere((p) => p.id == 'you');
      you.resources = 400;
      expect(g.trainTroop(TroopType.soldier), isNull);
      expect(g.trainTroop(TroopType.soldier), isNull);
      expect(g.trainTroop(TroopType.soldier), isNull);
      expect(you.armyCount(TroopType.soldier), 3);

      final st = g.beginLiveAttack();
      final drops = g.enemyBase.dropCells.toList();
      final a = g.deployTrained(st, TroopType.soldier, drops[0].r, drops[0].c)!;
      final b = g.deployTrained(st, TroopType.soldier, drops[1].r, drops[1].c)!;
      final c = g.deployTrained(st, TroopType.soldier, drops[2].r, drops[2].c)!;
      expect(you.armyCount(TroopType.soldier), 0);
      // two make it home; one falls
      a.hp = 0;
      expect(b.alive && c.alive, isTrue);

      g.commitLiveAttack();
      expect(you.armyCount(TroopType.soldier), 2,
          reason: 'living prepaid raiders refill the camp');
    });

    test('clash timer/razed bank also recalls survivors', () {
      final g = WarGame.fresh()..startPrep();
      g.startWar();
      final you = g.players.firstWhere((p) => p.id == 'you');
      you.resources = 200;
      expect(g.trainTroop(TroopType.archer), isNull);
      expect(g.trainTroop(TroopType.archer), isNull);
      final st = g.startClashBattle();
      final drops = g.enemyBase.dropCells.toList();
      g.deployTrained(st, TroopType.archer, drops[0].r, drops[0].c,
          allowStack: true);
      g.deployTrained(st, TroopType.archer, drops[0].r, drops[0].c,
          allowStack: true);
      expect(you.armyCount(TroopType.archer), 0);
      g.bankClashBattle();
      expect(you.armyCount(TroopType.archer), 2,
          reason: 'time-up / battle-over must not delete the camp');
    });

    test('smashing a storehouse / war generator / chest loots their ⚡', () {
      final g = WarGame.fresh()..startPrep();
      g.startWar();
      final you = g.players.firstWhere((p) => p.id == 'you');
      you.resources = 500;
      expect(g.trainTroop(TroopType.brute), isNull);
      final st = g.startClashBattle(); // freeActions — loot isn't masked by spend
      // plant lootables inland on plains
      var br = 12, bc = 12;
      for (var r = 8; r < g.enemyBase.rows - 8; r++) {
        for (var c = 8; c < g.enemyBase.cols - 8; c++) {
          if (g.enemyBase.canPlace(r, c)) {
            br = r;
            bc = c;
            break;
          }
        }
      }
      g.enemyBase.place(br, bc, DefType.storehouse, 'foe');
      expect(g.enemyBase.canPlace(br, bc + 1), isTrue);
      g.enemyBase.place(br, bc + 1, DefType.warGenerator, 'foe');
      expect(g.enemyBase.canPlace(br, bc + 2), isTrue);
      g.enemyBase.place(br, bc + 2, DefType.tributeChest, 'foe');
      final store = g.enemyBase.structAt(br, bc)!;
      final gen = g.enemyBase.structAt(br, bc + 1)!;
      final chest = g.enemyBase.structAt(br, bc + 2)!;
      final expectLoot = WarCosts.plunderAmount(DefType.storehouse, store.level) +
          WarCosts.plunderAmount(DefType.warGenerator, gen.level) +
          WarCosts.plunderAmount(DefType.tributeChest, chest.level);

      final drop = g.enemyBase.dropCells.first;
      final t = g.deployTrained(st, TroopType.brute, drop.r, drop.c)!;
      final wallet = you.resources;
      store.hp = 1;
      t.r = br;
      t.c = bc;
      st.attackCell(t, br, bc);
      gen.hp = 1;
      t.done = false;
      t.r = br;
      t.c = bc + 1;
      st.attackCell(t, br, bc + 1);
      chest.hp = 1;
      t.done = false;
      t.r = br;
      t.c = bc + 2;
      st.attackCell(t, br, bc + 2);

      expect(st.plunderGained, closeTo(expectLoot, 0.01));
      expect(you.resources, closeTo(wallet + expectLoot, 0.01),
          reason: 'loot lands in the raider pool');
    });

    test('scouting is shared clan intel across raids', () {
      final g = WarGame.fresh()..startPrep();
      g.startWar();
      g.players.firstWhere((p) => p.id == 'you').resources = 200;
      g.trainTroop(TroopType.runner);
      final st = g.beginLiveAttack();
      final drop = g.enemyBase.dropCells.first;
      final t = g.deployTrained(st, TroopType.runner, drop.r, drop.c)!;
      final reach = st.reachable(t);
      if (reach.isNotEmpty) {
        final k = reach.keys.first;
        st.moveTroop(t, k ~/ Base.defaultSize, k % Base.defaultSize);
      }
      final revealedCount = st.revealed.length;
      g.commitLiveAttack();
      expect(g.youIntel.length, greaterThanOrEqualTo(revealedCount));
      // the NEXT raid opens with everything the clan already scouted
      final st2 = g.beginLiveAttack();
      expect(st2.revealed.containsAll(g.youIntel), isTrue,
          reason: 'no re-scouting what a clanmate already revealed');
    });

    test('the live raid persists through fast-forward', () {
      final g = WarGame.fresh()..startPrep();
      g.startWar();
      g.players.firstWhere((p) => p.id == 'you').resources = 400;
      final st = g.beginLiveAttack();
      final drop = g.enemyBase.dropCells.first;
      st.spawn(TroopType.soldier, 'you', drop.r, drop.c);
      expect(st.troops, hasLength(1));
      g.advanceHours(2);
      if (g.phase == WarPhase.war) {
        expect(g.liveAttack, isNotNull, reason: 'fast-forward must not eat the raid');
        expect(g.liveAttack!.troops, hasLength(1));
        expect(identical(g.beginLiveAttack(), g.liveAttack), isTrue,
            reason: 're-entering resumes, never resets');
      }
    });

    test('a hands-on raid deals destruction and is banked on END RAID', () {
      final g = WarGame.fresh()..startPrep();
      g.startWar();
      g.players.firstWhere((p) => p.id == 'you').resources = 500;
      final st = g.beginLiveAttack();
      final before = g.enemyBase.destructionPercent;
      for (final drop in g.enemyBase.dropCells.take(3)) {
        st.spawn(TroopType.sapper, 'you', drop.r, drop.c);
      }
      var guard = 0;
      while (st.troops.any((t) => t.alive) && guard++ < 40) {
        for (final t in st.troops.where((x) => x.alive).toList()) {
          final tgts = st.attackTargets(t);
          if (tgts.isNotEmpty) {
            st.attackCell(t, tgts.first.r, tgts.first.c);
          } else {
            final reach = st.reachable(t);
            if (reach.isNotEmpty) {
              final k = reach.keys.first;
              st.moveTroop(t, k ~/ Base.defaultSize, k % Base.defaultSize);
            }
          }
        }
        st.defendersReact();
      }
      g.commitLiveAttack();
      expect(g.liveAttack, isNull);
      expect(g.enemyBase.destructionPercent, greaterThanOrEqualTo(before));
    });
  });

  group('v7: breach, focused assaults, variety, difficulty', () {
    void flatten(Base base, List<List<int>> cells) {
      for (final rc in cells) {
        base.grid[rc[0]][rc[1]].terrain = Terrain.plains;
      }
    }

    WarPlayer mk(String id, AiLevel ai, {double resources = 300}) => WarPlayer(
        id: id,
        name: id,
        emoji: '💀',
        colorValue: 0xFFE6483F,
        side: WarSide.enemy,
        ai: ai,
        resources: resources);

    test('the map is 40×40', () {
      expect(Base.defaultSize, 40);
      expect(Base.defaultSize, 40);
    });

    test('level 2 needs 300 XP; chipping buildings pays quarter XP', () {
      expect(Xp.levelForXp(299), 1);
      expect(Xp.levelForXp(300), 2);
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 4, 3, DefType.wall, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.r = Base.defaultSize - 3;
      final wall = base.structAt(Base.defaultSize - 4, 3)!;
      final hp0 = wall.hp;
      st.attackCell(t, Base.defaultSize - 4, 3);
      final dealt = (hp0 - wall.hp).toDouble();
      expect(t.xp, closeTo(dealt * 0.25, 0.01),
          reason: 'structure chip XP is quartered — no more rocket levels');
    });

    test('a walled-in troop BREACHES the wall on its path (no stare cycle)',
        () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 7; r <= 13; r++)
          for (var c = 7; c <= 13; c++) [r, c],
        for (var r = 0; r <= 13; r++) [r, 10],
      ]);
      base.placeCastle('def', 2, 10);
      // seal the troop inside a full wall box at (10,10)
      final wallCells = <List<int>>[];
      for (final d in const [
        [-1, -1],
        [-1, 0],
        [-1, 1],
        [0, -1],
        [0, 1],
        [1, -1],
        [1, 0],
        [1, 1]
      ]) {
        base.place(10 + d[0], 10 + d[1], DefType.wall, 'def');
        wallCells.add([10 + d[0], 10 + d[1]]);
      }
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final drop = st.base.dropCells.first;
      final t = st.spawn(TroopType.soldier, 'me', drop.r, drop.c)!;
      t.r = 10;
      t.c = 10;
      st.revealed.add(2 * Base.defaultSize + 10); // the castle is a KNOWN objective
      var damaged = false;
      for (var i = 0; i < 8 && !damaged; i++) {
        WarAi.aiStep(st, t);
        damaged = wallCells.any((rc) {
          final s = base.structAt(rc[0], rc[1]);
          return s == null || s.hp < s.spec.hp;
        });
      }
      expect(damaged, isTrue,
          reason: 'sealed in → the wall in the way IS the target');
    });

    test('enemy raids land as one focused push (clustered drops)', () {
      final base = Base(WarSide.you, 21);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, Base.defaultSize ~/ 2]
      ]);
      base.placeCastle('you', Base.defaultSize ~/ 2, Base.defaultSize ~/ 2);
      final raider = mk('e1', AiLevel.master, resources: 500);
      final pools = MapPools({'e1': 500.0});
      final res = WarAi.runAttack(
          base: base,
          attacker: raider,
          pools: pools,
          rng: SeededRng(seedFromParts([7, 7])));
      expect(res.frames, isNotEmpty);
      final drops = res.frames.first.sprites;
      expect(drops.length, greaterThanOrEqualTo(4));
      var maxD = 0;
      for (final a in drops) {
        for (final b in drops) {
          final d = (a.r - b.r).abs() + (a.c - b.c).abs();
          if (d > maxD) maxD = d;
        }
      }
      expect(maxD, lessThanOrEqualTo(14),
          reason: 'a planned flank push, not a scatter around the whole map');
    });

    test('the stronghold generator varies: same land, different fortress', () {
      List<WarPlayer> crew() =>
          [for (var i = 0; i < 4; i++) mk('e$i', AiLevel.master)];
      Set<int> layout(Base b) => {
            for (var r = 0; r < Base.defaultSize; r++)
              for (var c = 0; c < Base.defaultSize; c++)
                if (b.structAt(r, c) != null) r * Base.defaultSize + c
          };
      final b1 = Base(WarSide.enemy, 33);
      WarAi.designBase(b1, crew(), SeededRng(seedFromParts([33, 'a'])));
      final b2 = Base(WarSide.enemy, 33); // SAME terrain
      WarAi.designBase(b2, crew(), SeededRng(seedFromParts([33, 'b'])));
      final l1 = layout(b1), l2 = layout(b2);
      expect(l1.difference(l2).isNotEmpty || l2.difference(l1).isNotEmpty,
          isTrue,
          reason: 'no more identical center-square template every war');
    });

    test('cannons cannot shoot over walls; archer towers can', () {
      Base b() {
        final base = Base(WarSide.enemy, 7);
        flatten(base, [
          for (var r = 0; r < Base.defaultSize; r++) [r, 3]
        ]);
        base.placeCastle('def', 2, 3);
        return base;
      }

      // cannon (range 4) at (10,3), wall at (12,3), troop at (13,3)
      final cBase = b();
      cBase.place(10, 3, DefType.cannon, 'def');
      cBase.place(12, 3, DefType.wall, 'def');
      final st1 = AttackState(
          base: cBase,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t1 = st1.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      t1.r = 13;
      final hp1 = t1.hp;
      st1.defendersReact();
      st1.defendersReact();
      expect(t1.hp, hp1, reason: 'the flat shot is blocked by the wall');

      // archer tower (range 3), same geometry — arrows fly over the ramparts
      final aBase = b();
      aBase.place(10, 3, DefType.archerTower, 'def');
      aBase.place(12, 3, DefType.wall, 'def');
      final st2 = AttackState(
          base: aBase,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t2 = st2.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      t2.r = 13;
      final hp2 = t2.hp;
      st2.defendersReact();
      expect(t2.hp, lessThan(hp2), reason: 'archers shoot over walls');
    });

    test('difficulty scales the enemy war chest (master builds more)', () {
      double value(Base b) {
        var v = 0.0;
        for (var r = 0; r < Base.defaultSize; r++) {
          for (var c = 0; c < Base.defaultSize; c++) {
            final s = b.structAt(r, c);
            if (s != null) v += s.spec.cost;
          }
        }
        return v;
      }

      // the enemy's stronghold is sized and built at startWar() now — not
      // startPrep() — since it's floored against what the real crew earned
      // that prep (see 'the enemy war chest reflects real crew effort').
      final g1 = WarGame.fresh();
      g1.startPrep();
      g1.setDifficulty(1); // rookie-equivalent
      g1.startWar();
      final rookieValue = value(g1.enemyBase);
      final g2 = WarGame.fresh();
      g2.startPrep();
      g2.setDifficulty(50); // master-equivalent
      g2.startWar();
      final masterValue = value(g2.enemyBase);
      expect(masterValue, greaterThan(rookieValue),
          reason: 'the difficulty knob must BITE on defense too');
    });

    test('forest slows the AI march', () {
      int progress({required bool woods}) {
        final base = Base(WarSide.enemy, 7);
        flatten(base, [
          for (var r = 0; r < Base.defaultSize; r++) [r, 3]
        ]);
        base.placeCastle('def', 2, 3);
        for (var r = Base.defaultSize - 7; r <= Base.defaultSize - 2; r++) {
          // canyon walls so there is no dry detour, in BOTH variants
          base.grid[r][2].terrain = Terrain.mountain;
          base.grid[r][4].terrain = Terrain.mountain;
          if (woods) base.grid[r][3].terrain = Terrain.forest;
        }
        final st = AttackState(
            base: base,
            attacker: WarSide.you,
            attackerName: 'Me',
            pools: MapPools({'me': 999, 'def': 999}));
        final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
        st.revealed.add(2 * Base.defaultSize + 3); // march on the castle
        for (var i = 0; i < 6; i++) {
          WarAi.aiStep(st, t);
        }
        return Base.defaultSize - 1 - t.r;
      }

      final plains = progress(woods: false);
      final forest = progress(woods: true);
      expect(forest, lessThan(plains), reason: 'the woods drag the march');
    });
  });

  group('v12: wards, gate spacing, the fallen', () {
    void flatten(Base base, List<List<int>> cells) {
      for (final rc in cells) {
        base.grid[rc[0]][rc[1]].terrain = Terrain.plains;
      }
    }

    List<WarPlayer> masters() => [
          for (var i = 0; i < 4; i++)
            WarPlayer(
                id: 'w$i',
                name: 'w$i',
                emoji: '💀',
                colorValue: 0xFFE6483F,
                side: WarSide.enemy,
                ai: AiLevel.master,
                resources: 400)
        ];

    test('no two gates ever stand next to each other', () {
      for (final seed in [21, 51, 77]) {
        final base = Base(WarSide.enemy, seed);
        WarAi.designBase(base, masters(), SeededRng(seedFromParts([seed, 'gs'])));
        final gates = <List<int>>[];
        for (var r = 0; r < Base.defaultSize; r++) {
          for (var c = 0; c < Base.defaultSize; c++) {
            if (base.structAt(r, c)?.type == DefType.gate) gates.add([r, c]);
          }
        }
        for (var i = 0; i < gates.length; i++) {
          for (var j = i + 1; j < gates.length; j++) {
            final ch = math.max((gates[i][0] - gates[j][0]).abs(),
                (gates[i][1] - gates[j][1]).abs());
            expect(ch, greaterThanOrEqualTo(2),
                reason: 'seed $seed: doors at ${gates[i]} and ${gates[j]}');
          }
        }
      }
    });

    test('WARD LAYERS carve the fort into more rooms and more doors', () {
      int count(Base b, DefType t) {
        var n = 0;
        for (var r = 0; r < Base.defaultSize; r++) {
          for (var c = 0; c < Base.defaultSize; c++) {
            if (b.structAt(r, c)?.type == t) n++;
          }
        }
        return n;
      }

      Base gen(int layers) {
        final base = Base(WarSide.enemy, 88,
            config: const TerrainConfig(rivers: 0, lakes: 0));
        WarAi.designBase(base, masters(), SeededRng(seedFromParts([88, 'w'])),
            // a roomy single keep so the wards have space to carve
            style: StrongholdStyle(layers: layers, archetype: 0, pad: 5));
        return base;
      }

      final flat = gen(0);
      final layered = gen(3);
      expect(count(layered, DefType.wall), greaterThan(count(flat, DefType.wall)),
          reason: 'partitions are real walls');
      expect(count(layered, DefType.gate), greaterThan(count(flat, DefType.gate)),
          reason: 'every ward connects through a door');
    });

    test('the fallen leave tombstones — up to four to a tile', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 3],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 2, 3);
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final a = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      final b = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
      b.r = a.r;
      b.c = a.c; // fell on the same tile
      a.hp = 0;
      b.hp = 0;
      st.defendersReact(); // culls the dead → graves
      expect(st.graves, hasLength(2));
      expect(st.graves[0][0], a.r);
      expect(st.graves[0][2] != st.graves[1][2], isTrue,
          reason: 'two graves on one tile take different corners');
      // an in-progress raid keeps its dead through save/load
      final restored = AttackState.restore(
          base: base,
          attacker: WarSide.you,
          pools: MapPools({'me': 999, 'def': 999}),
          j: st.toJson());
      expect(restored.graves, hasLength(2));
    });

    test('guards chase to 4 tiles now; pavilions to 6', () {
      AttackState mk(int level) {
        final base = Base(WarSide.enemy, 11);
        flatten(base, [
          for (var r = 0; r < Base.defaultSize; r++) ...[
            [r, 3],
            [r, 4]
          ]
        ]);
        base.placeCastle('def', 2, 3);
        base.place(10, 4, DefType.guardPost, 'def');
        base.structAt(10, 4)!.level = level;
        return AttackState(
            base: base,
            attacker: WarSide.you,
            attackerName: 'Me',
            pools: MapPools({'me': 999, 'def': 999}));
      }

      bool chases(AttackState st, int intruderR) {
        final guard = st.garrison.first;
        final intruder = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
        intruder.r = intruderR;
        intruder.c = 4;
        final d0 = (guard.r - intruder.r).abs() + (guard.c - intruder.c).abs();
        st.defendersReact();
        final d1 = (guard.r - intruder.r).abs() + (guard.c - intruder.c).abs();
        return d1 < d0;
      }

      expect(chases(mk(1), 14), isTrue, reason: 'stock leash is 4 now');
      expect(chases(mk(1), 16), isFalse, reason: 'but 6 is beyond a stock tent');
      expect(chases(mk(2), 16), isTrue, reason: 'the pavilion patrols to 6');
    });
  });

  group('v8: sappers, smart defense, no-oscillation pathing', () {
    void flatten(Base base, List<List<int>> cells) {
      for (final rc in cells) {
        base.grid[rc[0]][rc[1]].terrain = Terrain.plains;
      }
    }

    AttackState mkState(Base base, {double iq = 0.5}) => AttackState(
        base: base,
        attacker: WarSide.you,
        attackerName: 'Me',
        pools: MapPools({'me': 999, 'def': 999}),
        defenderIq: iq);

    test('a sapper one-shots a wall, splashes the next one, and dies', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 3],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 4, 3, DefType.wall, 'def');
      base.place(Base.defaultSize - 4, 4, DefType.wall, 'def'); // splash victim
      final st = mkState(base);
      final t = st.spawn(TroopType.sapper, 'me', Base.defaultSize - 1, 3)!;
      t.r = Base.defaultSize - 3;
      final target = base.structAt(Base.defaultSize - 4, 3)!;
      final neighbour = base.structAt(Base.defaultSize - 4, 4)!;
      st.attackCell(t, Base.defaultSize - 4, 3);
      expect(target.alive, isFalse, reason: 'the bomb one-shots a wall');
      expect(neighbour.hp, lessThan(neighbour.spec.hp),
          reason: 'the blast tears at the wall beside it');
      expect(t.alive, isFalse, reason: 'one boom per sapper');
    });

    test('sappers CHASE walls; brutes CHASE defenses', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 18, 3);
      base.place(14, 3, DefType.archerTower, 'def');
      base.place(16, 3, DefType.wall, 'def');
      final st = mkState(base);
      final sapper = st.spawn(TroopType.sapper, 'me', Base.defaultSize - 1, 3)!;
      sapper.r = 20;
      for (final rc in [
        [14, 3],
        [16, 3],
        [18, 3]
      ]) {
        st.revealed.add(rc[0] * Base.defaultSize + rc[1]);
      }
      expect(WarAi.pickObjective(st, sapper), const Cell(16, 3),
          reason: 'the sapper lives to blow the wall');
      final brute = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      brute.r = 21;
      expect(WarAi.pickObjective(st, brute), const Cell(14, 3),
          reason: 'the brute hunts the tower, not the nearer castle');
    });

    test('routes ignore friendly troops (no more convoy oscillation)', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      // canyon: the only road is column 3
      for (var r = 4; r < Base.defaultSize - 1; r++) {
        base.grid[r][2].terrain = Terrain.mountain;
        base.grid[r][4].terrain = Terrain.mountain;
      }
      final st = mkState(base);
      final blocker = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      blocker.r = Base.defaultSize - 5; // parked mid-corridor
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.r = Base.defaultSize - 3;
      final route = st.routeTo(t, 5, 3);
      expect(route, isNotEmpty,
          reason: 'a friend on the road is a beat of patience, not a wall');
    });

    test('master defense focus-fires the weakest intruder', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(10, 3, DefType.archerTower, 'def'); // range 3
      final st = mkState(base, iq: 1.0);
      final healthy = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      healthy.r = 11; // right next to the tower
      final wounded = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      wounded.r = 13; // farther out…
      wounded.hp = 12; // …but nearly dead
      final healthyHp = healthy.hp;
      st.defendersReact();
      expect(healthy.hp, healthyHp,
          reason: 'the master gunner ignores the tank');
      expect(wounded.hp, lessThan(12), reason: 'and finishes the wounded');
    });

    test('an upgraded guard tent patrols 2 tiles farther', () {
      final base = Base(WarSide.enemy, 11);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 3],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(10, 4, DefType.guardPost, 'def');
      base.structAt(10, 4)!.level = 2; // the pavilion
      final st = mkState(base);
      final guard = st.garrison.first;
      final intruder = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
      intruder.r = 14; // 4 from home: outside a stock leash (3), inside 5
      intruder.c = 4;
      final d0 = (guard.r - intruder.r).abs() + (guard.c - intruder.c).abs();
      st.defendersReact();
      final d1 = (guard.r - intruder.r).abs() + (guard.c - intruder.c).abs();
      expect(d1, lessThan(d0),
          reason: 'the upgraded tent patrols the wider ring');
    });

    List<WarPlayer> masters() => [
          for (var i = 0; i < 4; i++)
            WarPlayer(
                id: 'm$i',
                name: 'm$i',
                emoji: '💀',
                colorValue: 0xFFE6483F,
                side: WarSide.enemy,
                ai: AiLevel.master,
                resources: 400)
        ];

    test('nothing is EVER built on a bridge', () {
      for (final seed in [21, 33, 51]) {
        final base = Base(WarSide.enemy, seed);
        WarAi.designBase(base, masters(), SeededRng(seedFromParts([seed, 'b'])));
        for (var r = 0; r < Base.defaultSize; r++) {
          for (var c = 0; c < Base.defaultSize; c++) {
            if (base.grid[r][c].terrain != Terrain.bridge) continue;
            expect(base.structAt(r, c), isNull,
                reason: 'a bridge is a PASSAGE, not a foundation ($seed $r,$c)');
          }
        }
      }
    });

    test(
        'REGRESSION: every passable tile of the RAW terrain (no structures '
        'yet) is reachable from the landing ring — mountains never seal '
        'off a pocket of flat land', () {
      // A mountain range can, by chance, fully enclose a patch of open
      // ground — a castle placed inside one would be permanently
      // unraidable. Deliberately boost mountainFrac far past the default
      // (0.11) across many seeds to reliably provoke that scenario, since
      // it's rare at normal density.
      for (final seed in [3, 11, 22, 34, 47, 58, 69, 81, 93, 104]) {
        final base = Base(WarSide.enemy, seed,
            config: const TerrainConfig(
                rivers: 0, lakes: 0, mountainFrac: 0.38, forestFrac: 0.1));
        final size = base.rows;
        final seen = <int>{};
        final q = <List<int>>[];
        void seedCell(int r, int c) {
          if (base.passable(r, c) && seen.add(r * size + c)) {
            q.add([r, c]);
          }
        }

        for (var c = 0; c < size; c++) {
          seedCell(0, c);
          seedCell(size - 1, c);
        }
        for (var r = 0; r < size; r++) {
          seedCell(r, 0);
          seedCell(r, size - 1);
        }
        while (q.isNotEmpty) {
          final cur = q.removeLast();
          for (final d in const [
            [-1, 0],
            [1, 0],
            [0, -1],
            [0, 1]
          ]) {
            seedCell(cur[0] + d[0], cur[1] + d[1]);
          }
        }
        for (var r = 0; r < size; r++) {
          for (var c = 0; c < size; c++) {
            if (!base.passable(r, c)) continue;
            expect(seen.contains(r * size + c), isTrue,
                reason: 'seed $seed: ($r,$c) is passable terrain but '
                    'unreachable from every side of the landing ring — a '
                    'castle placed here would be permanently unraidable');
          }
        }
      }
    });

    test('a dry-world fortress is SEALED — no forest holes, no open sections',
        () {
      final base = Base(WarSide.enemy, 77,
          config: const TerrainConfig(rivers: 0, lakes: 0));
      WarAi.designBase(base, masters(), SeededRng(seedFromParts([77, 's'])));
      // flood attacker-passable ground from the landing ring
      final seen = <int>{};
      final stack = <List<int>>[];
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          if (base.isRing(r, c) && base.passable(r, c)) {
            if (seen.add(r * Base.defaultSize + c)) stack.add([r, c]);
          }
        }
      }
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        for (final d in const [
          [-1, 0],
          [1, 0],
          [0, -1],
          [0, 1]
        ]) {
          final nr = cur[0] + d[0], nc = cur[1] + d[1];
          if (!base.passable(nr, nc)) continue;
          if (seen.add(nr * Base.defaultSize + nc)) stack.add([nr, nc]);
        }
      }
      for (final castle in base.castleCells) {
        for (final d in const [
          [-1, 0],
          [1, 0],
          [0, -1],
          [0, 1]
        ]) {
          expect(
              seen.contains((castle.r + d[0]) * Base.defaultSize + (castle.c + d[1])),
              isFalse,
              reason: 'a stroll from the ring reaches a castle at '
                  '(${castle.r},${castle.c}) — the wall has a hole');
        }
      }
    });

    test('a wall line crossing a river puts a GATE at the bridge mouth', () {
      // hunt a seed whose outline actually crosses a bridge
      for (final seed in [5, 7, 21, 33, 41, 51, 63, 77, 91]) {
        final base = Base(WarSide.enemy, seed,
            config: const TerrainConfig(rivers: 2, lakes: 0));
        WarAi.designBase(base, masters(), SeededRng(seedFromParts([seed, 'r'])));
        for (var r = 0; r < Base.defaultSize; r++) {
          for (var c = 0; c < Base.defaultSize; c++) {
            if (base.grid[r][c].terrain != Terrain.bridge) continue;
            // a bridge with a wall RIGHT beside it must have a gate within 2
            var walled = false, gated = false;
            for (var dr = -2; dr <= 2; dr++) {
              for (var dc = -2; dc <= 2; dc++) {
                final s = base.structAt(r + dr, c + dc);
                if (s == null) continue;
                if (s.type == DefType.wall &&
                    dr.abs() + dc.abs() == 1) walled = true;
                if (s.type == DefType.gate) gated = true;
              }
            }
            if (walled) {
              expect(gated, isTrue,
                  reason: 'bridge at ($r,$c) pierces the wall line of seed '
                      '$seed but has no door');
            }
          }
        }
      }
    });

    test('generated strongholds have real GATES (and attackers cannot pass)',
        () {
      final base = Base(WarSide.enemy, 51);
      final crew = [
        for (var i = 0; i < 4; i++)
          WarPlayer(
              id: 'e$i',
              name: 'e$i',
              emoji: '💀',
              colorValue: 0xFFE6483F,
              side: WarSide.enemy,
              ai: AiLevel.master,
              resources: 400)
      ];
      WarAi.designBase(base, crew, SeededRng(seedFromParts([51, 'g'])));
      var gates = 0;
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          if (base.structAt(r, c)?.type == DefType.gate) gates++;
        }
      }
      expect(gates, greaterThanOrEqualTo(1),
          reason: 'every fortress has a DOOR now');
      expect(base.passable(0, 0), isTrue); // sanity: ring stays open
    });

    test('a wall-sealed fog pocket cannot freeze the army', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 8; r <= 14; r++)
          for (var c = 8; c <= 14; c++) [r, c]
      ]);
      base.placeCastle('def', 11, 11);
      final pocket = <int>{11 * Base.defaultSize + 11};
      for (final d in const [
        [-1, -1],
        [-1, 0],
        [-1, 1],
        [0, -1],
        [0, 1],
        [1, -1],
        [1, 0],
        [1, 1]
      ]) {
        base.place(11 + d[0], 11 + d[1], DefType.wall, 'def');
        pocket.add((11 + d[0]) * Base.defaultSize + (11 + d[1]));
      }
      // the clan has scouted EVERYTHING except the sealed pocket — the exact
      // endgame that used to freeze every troop mid-raid
      final intel = <int>{
        for (var r = 0; r < Base.defaultSize; r++)
          for (var c = 0; c < Base.defaultSize; c++)
            if (!pocket.contains(r * Base.defaultSize + c)) r * Base.defaultSize + c
      };
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}),
          intel: intel);
      final drop = st.base.dropCells.first;
      final t = st.spawn(TroopType.soldier, 'me', drop.r, drop.c)!;
      t.r = 9;
      t.c = 11; // parked right outside the hidden wall
      expect(WarAi.pickObjective(st, t), isNotNull,
          reason: 'the hidden wall IS the frontier — never a null objective');
      var damaged = false;
      for (var i = 0; i < 10 && !damaged; i++) {
        WarAi.aiStep(st, t);
        damaged = pocket.any((k) {
          final s = base.structAt(k ~/ Base.defaultSize, k % Base.defaultSize);
          return s != null && s.type == DefType.wall && s.hp < s.spec.hp;
        });
      }
      expect(damaged, isTrue, reason: 'crack the pocket open, don\'t stall');
    });

    test('replay sprites carry stable troop ids (no flying garrisons)', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) ...[
          [r, 3],
          [r, 4]
        ]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(10, 4, DefType.guardPost, 'def');
      final st = mkState(base);
      final t1 = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      final t2 = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
      st.snapshot();
      final ids = st.frames.last.sprites.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'every sprite is SOMEONE');
      expect(ids, containsAll([t1.id, t2.id]));
      expect(ids.length, 3, reason: 'both troops + the tent guard');
    });

    test('the water dials work: 0 rivers = dry land, 3 = riverlands', () {
      int water(Base b) {
        var n = 0;
        for (var r = 0; r < Base.defaultSize; r++) {
          for (var c = 0; c < Base.defaultSize; c++) {
            final t = b.grid[r][c].terrain;
            if (t == Terrain.river || t == Terrain.bridge) n++;
          }
        }
        return n;
      }

      final dry = Base(WarSide.enemy, 5,
          config: const TerrainConfig(rivers: 0, lakes: 0));
      expect(water(dry), 0, reason: 'no rivers asked, none carved');
      final wet = Base(WarSide.enemy, 5,
          config: const TerrainConfig(rivers: 3, lakes: 2));
      expect(water(wet), greaterThan(60), reason: 'riverlands are WET');
    });

    test('season reset regenerates the WORLD (new terrain, new seed)', () {
      final g = WarGame.fresh();
      g.startPrep();
      final seedBefore = g.warSeed;
      String fingerprint(Base b) => [
            for (var r = 0; r < Base.defaultSize; r += 3)
              for (var c = 0; c < Base.defaultSize; c += 3) b.grid[r][c].terrain.index
          ].join(',');
      final terrainBefore = fingerprint(g.youBase);
      g.resetSeason();
      expect(g.warSeed, isNot(seedBefore),
          reason: 'a reset rolls a brand-new world seed');
      expect(fingerprint(g.youBase), isNot(terrainBefore),
          reason: 'new season, new land — not a rerun');
    });
  });

  group('v13: scars, upgrades, smart landings', () {
    void flatten(Base base, List<List<int>> cells) {
      for (final rc in cells) {
        base.grid[rc[0]][rc[1]].terrain = Terrain.plains;
      }
    }

    List<WarPlayer> masters() => [
          for (var i = 0; i < 4; i++)
            WarPlayer(
                id: 'v$i',
                name: 'v$i',
                emoji: '💀',
                colorValue: 0xFFE6483F,
                side: WarSide.enemy,
                ai: AiLevel.master,
                resources: 400)
        ];

    test('no FLOATING gates: every door leans on walls or nature', () {
      for (final seed in [21, 51, 77]) {
        final base = Base(WarSide.enemy, seed);
        WarAi.designBase(base, masters(), SeededRng(seedFromParts([seed, 'f'])));
        for (var r = 0; r < Base.defaultSize; r++) {
          for (var c = 0; c < Base.defaultSize; c++) {
            final s = base.structAt(r, c);
            if (s == null || s.type != DefType.gate) continue;
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
            expect(support, greaterThanOrEqualTo(2),
                reason: 'seed $seed: a lone door at ($r,$c) guards nothing');
          }
        }
      }
    });

    test('razing a wall barely moves destruction %; a cannon moves it', () {
      Base build() {
        final base = Base(WarSide.enemy, 7);
        flatten(base, [
          for (var r = 0; r < Base.defaultSize; r++) ...[
            [r, 3],
            [r, 4]
          ]
        ]);
        base.placeCastle('def', 2, 3);
        base.place(10, 3, DefType.wall, 'def');
        base.place(12, 3, DefType.cannon, 'def');
        return base;
      }

      final a = build();
      a.structAt(10, 3)!.hp = 0; // the wall falls
      final wallDelta = a.destructionPercent;
      final b = build();
      b.structAt(12, 3)!.hp = 0; // the cannon falls
      final cannonDelta = b.destructionPercent;
      expect(cannonDelta, greaterThan(wallDelta * 2),
          reason: 'guns are worth far more than masonry');
    });

    test('upgrades bite: L2 cannon hits harder, L2 wall stands taller', () {
      final wall = Structure(DefType.wall, 'def');
      expect(wall.maxHp, kDefSpecs[DefType.wall]!.hp);
      wall.level = 2;
      expect(wall.maxHp, greaterThan(kDefSpecs[DefType.wall]!.hp));

      AttackState mk(int level) {
        final base = Base(WarSide.enemy, 7);
        flatten(base, [
          for (var r = 0; r < Base.defaultSize; r++) [r, 3]
        ]);
        base.placeCastle('def', 2, 3);
        base.place(10, 3, DefType.cannon, 'def');
        base.structAt(10, 3)!.level = level;
        return AttackState(
            base: base,
            attacker: WarSide.you,
            attackerName: 'Me',
            pools: MapPools({'me': 999, 'def': 999}));
      }

      int hurt(AttackState st) {
        final t = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
        t.r = 11; // point blank, clear line
        final hp0 = t.hp;
        st.defendersReact();
        return hp0 - t.hp;
      }

      expect(hurt(mk(2)), greaterThan(hurt(mk(1))),
          reason: 'a gilded cannon throws heavier shot');
    });

    test('raiders LAND next to the base they scouted', () {
      final base = Base(WarSide.you, 21,
          config: const TerrainConfig(rivers: 0, lakes: 0));
      flatten(base, [
        for (var r = 0; r < 12; r++)
          for (var c = 14; c < 26; c++) [r, c]
      ]);
      base.placeCastle('you', 5, 20); // the fort sits NORTH
      base.place(6, 19, DefType.archerTower, 'you');
      final intel = <int>{
        for (var r = 0; r < 12; r++)
          for (var c = 14; c < 26; c++) r * Base.defaultSize + c
      };
      final raider = WarPlayer(
          id: 'e1',
          name: 'Grim',
          emoji: '💀',
          colorValue: 0xFFE6483F,
          side: WarSide.enemy,
          ai: AiLevel.master,
          resources: 500);
      final res = WarAi.runAttack(
          base: base,
          attacker: raider,
          pools: MapPools({'e1': 500.0}),
          rng: SeededRng(seedFromParts([9, 1])),
          intel: intel);
      expect(res.frames, isNotEmpty);
      final drops = res.frames.first.sprites;
      expect(drops, isNotEmpty);
      final avgRow = drops.fold<double>(0, (a, s) => a + s.r) / drops.length;
      expect(avgRow, lessThan(Base.defaultSize / 2),
          reason: 'the base is NORTH and they know it — land north');
    });

    test('mortar fire scars the land and flattens forest', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(10, 3, DefType.mortar, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      t.r = 12; // range 2 — inside forestSpotRange, outside the blind spot
      base.grid[12][3].terrain = Terrain.forest; // standing in the trees
      for (var i = 0; i < 3; i++) {
        st.defendersReact();
      }
      expect(base.scorch, isNotEmpty, reason: 'shells tear the ground');
      expect(base.grid[12][3].terrain, Terrain.plains,
          reason: 'the blast flattens the forest');
    });

    test('the dead persist on the WORLD and through Base save/load', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.hp = 0;
      st.defendersReact();
      expect(base.graves, isNotEmpty, reason: 'the world remembers');
      base.scorch[77] = 2;
      final loaded = Base.fromJson(base.toJson());
      expect(loaded.graves, base.graves);
      expect(loaded.scorch[77], 2);
    });

    test('troops fan out: different troops break path ties differently', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 20; r < Base.defaultSize; r++)
          for (var c = 10; c < 24; c++) [r, c]
      ]);
      base.placeCastle('def', 2, 3);
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      // find two ids whose tie-break rotations differ
      final ids = ['s1', 's2', 's3', 's4', 's5'];
      String? id1, id2;
      for (final a in ids) {
        for (final b in ids) {
          if ((a.hashCode & 3) != (b.hashCode & 3)) {
            id1 = a;
            id2 = b;
            break;
          }
        }
        if (id1 != null) break;
      }
      expect(id1, isNotNull);
      Troop mk(String id) => Troop(
          id: id,
          ownerId: 'me',
          side: WarSide.you,
          type: TroopType.soldier,
          r: 34,
          c: 12);
      final r1 = st.routeTo(mk(id1!), 22, 22);
      final r2 = st.routeTo(mk(id2!), 22, 22);
      expect(r1, isNotEmpty);
      expect(r1.toString() == r2.toString(), isFalse,
          reason: 'same start, same goal, DIFFERENT road');
    });

    test('HOUSING quarters a second defender for nearby tents', () {
      AttackState mk({required bool housed}) {
        final base = Base(WarSide.enemy, 11);
        for (var r = 0; r < Base.defaultSize; r++) {
          base.grid[r][3].terrain = Terrain.plains;
          base.grid[r][4].terrain = Terrain.plains;
          base.grid[r][5].terrain = Terrain.plains;
        }
        base.placeCastle('def', 2, 3);
        base.place(10, 4, DefType.guardPost, 'def');
        if (housed) base.place(10, 5, DefType.housing, 'def');
        return AttackState(
            base: base,
            attacker: WarSide.you,
            attackerName: 'Me',
            pools: MapPools({'me': 999, 'def': 999}));
      }

      expect(mk(housed: false).garrison, hasLength(1));
      expect(mk(housed: true).garrison, hasLength(2),
          reason: 'barracks nearby → the tent fields TWO');
    });

    test(
        'a single L3 Housing alone is enough to field the full 4-guard cap '
        '(pool scales with the house\'s own LEVEL, not just its presence)',
        () {
      final base = Base(WarSide.enemy, 11);
      for (var r = 0; r < Base.defaultSize; r++) {
        base.grid[r][3].terrain = Terrain.plains;
        base.grid[r][4].terrain = Terrain.plains;
        base.grid[r][5].terrain = Terrain.plains;
      }
      base.placeCastle('def', 2, 3);
      base.place(10, 4, DefType.guardPost, 'def');
      base.place(10, 5, DefType.housing, 'def');
      base.structAt(10, 5)!.level = 3;
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      // pool = 1 (the post itself) + 3 (an L3 house) = 4, exactly the cap.
      expect(st.garrison, hasLength(4));
    });

    test(
        'multiple houses STACK, but a post never fields more than 4 live '
        'defenders at once no matter how deep the pool runs', () {
      final base = Base(WarSide.enemy, 11);
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 2; c <= 7; c++) {
          base.grid[r][c].terrain = Terrain.plains;
        }
      }
      base.placeCastle('def', 2, 3);
      base.place(10, 4, DefType.guardPost, 'def');
      base.place(9, 5, DefType.housing, 'def');
      base.place(11, 5, DefType.housing, 'def');
      base.place(10, 6, DefType.housing, 'def');
      for (final cell in [
        [9, 5],
        [11, 5],
        [10, 6]
      ]) {
        base.structAt(cell[0], cell[1])!.level = 2;
      }
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      // pool = 1 (post) + 3 houses × level 2 = 7 — but only 4 can ever be
      // OUT of one tent at the same time.
      expect(st.garrison, hasLength(4));
    });

    test(
        'a depleted guard slot refills from the reinforcement pool one at a '
        'time, until the pool itself runs dry', () {
      final base = Base(WarSide.enemy, 11);
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 2; c <= 7; c++) {
          base.grid[r][c].terrain = Terrain.plains;
        }
      }
      base.placeCastle('def', 2, 3);
      base.place(10, 4, DefType.guardPost, 'def');
      base.place(9, 5, DefType.housing, 'def');
      base.place(11, 5, DefType.housing, 'def');
      base.place(10, 6, DefType.housing, 'def');
      for (final cell in [
        [9, 5],
        [11, 5],
        [10, 6]
      ]) {
        base.structAt(cell[0], cell[1])!.level = 2;
      }
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      expect(st.garrison, hasLength(4));
      // pool = 7 total, 4 already out → 3 reinforcements left in the tent.
      for (var i = 0; i < 3; i++) {
        st.garrison.first.hp = 0;
        st.defendersReact();
        expect(st.garrison, hasLength(4),
            reason: 'reinforcement #$i should refill the fallen slot');
      }
      // the pool is empty now — a fourth death is NOT replaced.
      st.garrison.first.hp = 0;
      st.defendersReact();
      expect(st.garrison, hasLength(3),
          reason: 'the tent has nothing left to send');
    });

    test(
        'a Watchtower ALERTS any Guard Post whose patrol circle reaches its '
        'own vision — those guards charge at anything it spots, even well '
        'past their own leash', () {
      AttackState mk({required bool withTower}) {
        final base = Base(WarSide.enemy, 11);
        for (var r = 0; r < Base.defaultSize; r++) {
          base.grid[r][3].terrain = Terrain.plains;
          base.grid[r][4].terrain = Terrain.plains;
        }
        for (var c = 3; c <= 13; c++) {
          base.grid[10][c].terrain = Terrain.plains;
        }
        base.placeCastle('def', 2, 3);
        base.place(10, 4, DefType.guardPost, 'def');
        // Chebyshev 6 from the post — outside the tower's own flat "+2
        // leash" bounding-box bonus (radius 5) — but Manhattan 6, well
        // inside the leash(4)+watchtowerRadius(5)=9 LINK distance.
        if (withTower) base.place(10, 10, DefType.watchtower, 'def');
        return AttackState(
            base: base,
            attacker: WarSide.you,
            attackerName: 'Me',
            pools: MapPools({'me': 999, 'def': 999}));
      }

      // the intruder sits 9 tiles from home (way past leash 4) but only 3
      // from the tower (well inside its 5-tile vision).
      final without = mk(withTower: false);
      final guardA = without.garrison.first;
      // troops only SPAWN on the landing ring — teleport it inland after.
      final farA =
          without.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
      farA.r = 10;
      farA.c = 13;
      final d0A = (guardA.r - farA.r).abs() + (guardA.c - farA.c).abs();
      without.defendersReact();
      final d1A = (guardA.r - farA.r).abs() + (guardA.c - farA.c).abs();
      expect(d1A, d0A, reason: 'no tower link → the guard never even looks');

      final linked = mk(withTower: true);
      final guardB = linked.garrison.first;
      final farB =
          linked.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 4)!;
      farB.r = 10;
      farB.c = 13;
      final d0B = (guardB.r - farB.r).abs() + (guardB.c - farB.c).abs();
      linked.defendersReact();
      final d1B = (guardB.r - farB.r).abs() + (guardB.c - farB.c).abs();
      expect(d1B, lessThan(d0B),
          reason: 'tower-linked → the guard charges in from home');
    });

    test('scouts peer an extra tile ahead of their march', () {
      final base = Base(WarSide.enemy, 7);
      for (var r = 0; r < Base.defaultSize; r++) {
        base.grid[r][3].terrain = Terrain.plains;
      }
      base.placeCastle('def', 2, 3);
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final t = st.spawn(TroopType.runner, 'me', Base.defaultSize - 1, 3)!;
      st.moveTroop(t, Base.defaultSize - 3, 3); // marching NORTH
      // radius 2 covers rows-5; the look-ahead reveals rows-6 too
      expect(st.visible(Base.defaultSize - 6, 3), isTrue,
          reason: 'the scout sees one tile beyond its circle, ahead');
    });

    test('the war dial pushes the enemy BEYOND master', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.setDifficulty(100);
      final foe = g.enemyClan.first;
      expect(foe.skill, greaterThan(AiData.skill(AiLevel.master)),
          reason: 'dial 100 is crueler than any preset tier');
      g.setDifficulty(10);
      expect(g.enemyClan.first.skill, lessThan(0.5));
    });
  });

  group('v15: new arms, level 3s, knockout, honest feed', () {
    /// A dead-flat board: every cell plains, no structures — tests place
    /// exactly what they need.
    Base flat({WarSide side = WarSide.enemy, int seed = 7}) {
      final b = Base(side, seed);
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          b.grid[r][c].terrain = Terrain.plains;
        }
      }
      return b;
    }

    AttackState raid(Base b, {double funds = 999, bool free = false}) =>
        AttackState(
            base: b,
            attacker: WarSide.you,
            attackerName: 'Me',
            pools: MapPools({'me': funds, 'def': 999}),
            freeActions: free);

    test('an archer strikes from 2 tiles and takes NO counter', () {
      final b = flat();
      b.place(30, 3, DefType.guardPost, 'def');
      final st = raid(b);
      final guard = st.garrison.first; // fielded at the post
      final a = st.spawn(TroopType.archer, 'me', Base.defaultSize - 1, 3)!;
      a.r = 32;
      a.c = 3;
      st.revealed.add(30 * Base.defaultSize + 3); // she can see the post
      expect(st.attackTargets(a).any((c) => c.r == 30 && c.c == 3), isTrue,
          reason: 'range-2 volley over the ground between');
      final guardHp = guard.hp;
      st.attackCell(a, guard.r, guard.c);
      expect(guard.hp, lessThan(guardHp));
      expect(a.hp, kTroopSpecs[TroopType.archer]!.hp,
          reason: 'counters are MELEE — nobody reaches her at 2 tiles');
    });

    test('a healer mends the worst-hurt ally and never fights', () {
      expect(kTroopSpecs[TroopType.healer]!.atk, 0);
      final b = flat();
      b.placeCastle('def', 2, 3);
      final st = raid(b);
      final hurt = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      hurt.hp = 10;
      final h = st.spawn(TroopType.healer, 'me', Base.defaultSize - 1, 4)!;
      WarAi.aiStep(st, h);
      expect(hurt.hp, 24, reason: '+14 from the healer beside him');
    });

    test('boiling pitch burns EVERY attacker beside the thrower', () {
      final b = flat();
      b.place(30, 3, DefType.pitchThrower, 'def');
      final st = raid(b);
      final t1 = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t1.r = 31;
      t1.c = 3;
      final t2 = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 5)!;
      t2.r = 30;
      t2.c = 4;
      st.defendersReact();
      final full = kTroopSpecs[TroopType.soldier]!.hp;
      expect(t1.hp, full - 9);
      expect(t2.hp, full - 9, reason: 'both neighbours burn in ONE volley');
    });

    test('a war banner makes the cannon beside it reload instantly', () {
      Structure fire(bool banner) {
        final b = flat();
        b.place(20, 3, DefType.cannon, 'def');
        if (banner) b.place(20, 5, DefType.banner, 'def');
        final st = raid(b);
        final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
        t.r = 23;
        t.c = 3;
        st.defendersReact();
        return b.structAt(20, 3)!;
      }

      expect(fire(false).cooldown, 1, reason: 'a cannon rests every other volley');
      expect(fire(true).cooldown, 0, reason: 'under the colors it never rests');
    });

    test('the ballista: death at 7 tiles, blind under 2, LOBS over walls', () {
      AttackState shot(int troopR, {bool wall = false}) {
        final b = flat();
        b.place(20, 3, DefType.ballista, 'def');
        if (wall) b.place(24, 3, DefType.wall, 'def');
        final st = raid(b);
        final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
        t.r = troopR;
        t.c = 3;
        st.defendersReact();
        return st;
      }

      final full = kTroopSpecs[TroopType.soldier]!.hp;
      expect(shot(27).troops.first.hp, full - 55,
          reason: 'one bolt from 7 tiles out');
      expect(shot(21).troops.first.hp, full,
          reason: 'helpless against a knife at its throat');
      expect(shot(27, wall: true).troops.first.hp, full - 55,
          reason: 'the bolt ARCS over the wall — only cannons are contained');
    });

    test('a watchtower defeats forest concealment', () {
      final b = flat();
      b.place(20, 3, DefType.archerTower, 'def');
      b.grid[23][3].terrain = Terrain.forest;
      final st = raid(b);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.r = 23;
      t.c = 3;
      st.defendersReact();
      expect(t.hp, kTroopSpecs[TroopType.soldier]!.hp,
          reason: 'the trees hide him at range 3');
      b.place(22, 4, DefType.watchtower, 'def');
      st.defendersReact();
      expect(t.hp, lessThan(kTroopSpecs[TroopType.soldier]!.hp),
          reason: 'nothing hides from the eyes');
    });

    test('a tower on a HILL sees one tile farther', () {
      final b = flat();
      b.place(20, 3, DefType.archerTower, 'def');
      final st = raid(b);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.r = 24;
      t.c = 3; // range 3 tower, distance 4
      st.defendersReact();
      expect(t.hp, kTroopSpecs[TroopType.soldier]!.hp);
      b.grid[20][3].terrain = Terrain.hill;
      st.defendersReact();
      expect(t.hp, lessThan(kTroopSpecs[TroopType.soldier]!.hp));
    });

    test('hills are buildable slow high ground', () {
      expect(TerrainData.buildable(Terrain.hill), isTrue);
      expect(TerrainData.moveCost(Terrain.hill), 2);
      expect(TerrainData.defBonus(Terrain.hill), 0.25);
    });

    test('an L3 mortar splashes a WIDER field', () {
      int bystanderHp(int level) {
        final b = flat();
        b.place(20, 3, DefType.mortar, 'def');
        b.structAt(20, 3)!.level = level;
        final st = raid(b);
        final target = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
        target.r = 23;
        target.c = 3;
        final by = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 5)!;
        by.r = 25;
        by.c = 3; // Chebyshev 2 from the impact
        st.defendersReact();
        return by.hp;
      }

      final full = kTroopSpecs[TroopType.soldier]!.hp;
      expect(bystanderHp(1), full, reason: 'ring 2 is safe from an L1 shell');
      expect(bystanderHp(3), lessThan(full), reason: 'L3 shells reach ring 2');
    });

    test('an L3 wall is 1.6x the stone', () {
      final b = flat();
      b.place(20, 3, DefType.wall, 'def');
      final w = b.structAt(20, 3)!;
      w.level = 3;
      expect(w.maxHp.toDouble(),
          closeTo(kDefSpecs[DefType.wall]!.hp * 1.6, 0.51));
    });

    test('an L3 tent patrols 8 tiles out; an L1 tent will not', () {
      Troop guardAfter(int level) {
        final b = flat();
        b.place(30, 10, DefType.guardPost, 'def');
        b.structAt(30, 10)!.level = level;
        final st = raid(b);
        final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 10)!;
        t.r = 23;
        t.c = 10; // 7 from home
        st.defendersReact();
        return st.garrison.first;
      }

      expect(guardAfter(1).r, 30, reason: 'a 4-leash guard holds his post');
      expect(guardAfter(3).r, lessThan(30),
          reason: 'the L3 watch camp hunts 8 tiles out');
    });

    test('the garrison engages a knife 2 tiles from the GUARD, leash be damned',
        () {
      final b = flat();
      b.place(30, 10, DefType.guardPost, 'def');
      final st = raid(b);
      final guard = st.garrison.first;
      guard.r = 26;
      guard.c = 10; // drifted 4 from home
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 10)!;
      t.r = 24;
      t.c = 10; // 6 from home (outside the leash), 2 from the guard
      st.defendersReact();
      expect(guard.r, 25, reason: 'he closes on the intruder anyway');
    });

    test('AI raids fight FREE like the war machine: only spawns cost', () {
      final b = flat();
      b.place(37, 3, DefType.wall, 'def');
      b.placeCastle('def', 2, 3);
      final st = raid(b, free: true);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      final spawnCost = kTroopSpecs[TroopType.soldier]!.cost.toDouble();
      expect(st.resourcesSpent, spawnCost);
      t.r = 38;
      t.c = 3;
      st.attackCell(t, 37, 3);
      st.moveTroop(t, 38, 4);
      expect(st.resourcesSpent, spawnCost,
          reason: 'moves and strikes charged NOTHING');
    });

    test('a storehouse feeds VETERAN guards — and pays no one', () {
      final b = flat();
      b.place(30, 3, DefType.guardPost, 'def');
      b.place(30, 5, DefType.storehouse, 'def');
      final st = raid(b);
      expect(st.garrison.first.level, greaterThanOrEqualTo(2),
          reason: 'a well-fed watch fights a level stronger');
      // a post with no larder nearby fields a plain rookie
      final b2 = flat();
      b2.place(30, 3, DefType.guardPost, 'def');
      final st2 = raid(b2);
      expect(st2.garrison.first.level, 1);
    });

    test('a mortar sometimes fires BLIND at raiders hiding in the trees', () {
      final b = flat();
      b.place(20, 3, DefType.mortar, 'def');
      b.grid[24][3].terrain = Terrain.forest;
      final st = raid(b);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.r = 24;
      t.c = 3;
      for (var i = 0; i < 200 && b.scorch.isEmpty; i++) {
        st.defendersReact();
      }
      expect(b.scorch, isNotEmpty,
          reason: 'shells eventually probe the treeline');
      // an EMPTY field draws no fire at all
      final b2 = flat();
      b2.place(20, 3, DefType.mortar, 'def');
      final st2 = raid(b2);
      for (var i = 0; i < 200; i++) {
        st2.defendersReact();
      }
      expect(b2.scorch, isEmpty);
    });

    test('a brute treats a guard TENT as the defense it is', () {
      final b = flat();
      b.place(30, 3, DefType.guardPost, 'def');
      b.placeCastle('def', 2, 3);
      final st = raid(b);
      final brute = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      brute.r = 35;
      brute.c = 3;
      st.revealed.add(30 * Base.defaultSize + 3);
      st.revealed.add(2 * Base.defaultSize + 3);
      final obj = WarAi.pickObjective(st, brute)!;
      expect(obj.r == 30 && obj.c == 3, isTrue,
          reason: 'the tent in sight beats the distant castle');
    });

    test('practice drills never scar the REAL base', () {
      final g = WarGame.fresh();
      g.startPrep();
      final st = g.startPracticeBattle();
      expect(st.freeActions, isTrue);
      // wreck something in the drill copy
      late int vr, vc;
      var found = false;
      for (var r = 0; r < Base.defaultSize && !found; r++) {
        for (var c = 0; c < Base.defaultSize && !found; c++) {
          final v = st.base.structAt(r, c);
          if (v != null && !v.isCastle) {
            vr = r;
            vc = c;
            found = true;
          }
        }
      }
      expect(found, isTrue);
      st.base.structAt(vr, vc)!.hp = 0;
      final real = g.youBase.structAt(vr, vc);
      expect(real, isNotNull);
      expect(real!.hp, greaterThan(0),
          reason: 'the real base never felt a thing');
      g.endPractice();
      expect(g.practiceState, isNull);
    });

    test('the sandbox: clean reset sweeps the CLONE, waves summon on demand',
        () {
      final g = WarGame.fresh();
      g.startPrep();
      g.youBase.graves.add([5, 5, 0]);
      g.youBase.scorch[77] = 3;
      final st = g.startPracticeBattle(clean: true);
      expect(st.base.graves, isEmpty, reason: 'the drill yard is swept');
      expect(st.base.scorch, isEmpty);
      expect(g.youBase.graves, isNotEmpty, reason: 'the REAL scars remain');
      g.summonDrillWave(100);
      expect(st.troops, isNotEmpty, reason: 'the summoned wave lands');
      expect(st.troops.any((t) => t.level >= 2), isTrue,
          reason: 'difficulty 100 waves march veterans');
      g.endPractice();
      expect(g.practiceState, isNull);
    });

    test('base codes: export → wreck → import rebuilds the same fortress', () {
      String sig(Base b) {
        final out = <String>[];
        for (var r = 0; r < Base.defaultSize; r++) {
          for (var c = 0; c < Base.defaultSize; c++) {
            final s = b.structAt(r, c);
            if (s != null) out.add('$r.$c.${s.type.index}.${s.level}');
          }
        }
        return (out..sort()).join('|');
      }

      final g = WarGame.fresh();
      g.startPrep();
      final want = sig(g.youBase);
      final code = g.exportBaseCode();
      expect(code, startsWith('JARS1.'));
      // wreck the base, then restore it from the code
      var wrecked = 0;
      for (var r = 0; r < Base.defaultSize && wrecked < 5; r++) {
        for (var c = 0; c < Base.defaultSize && wrecked < 5; c++) {
          final s = g.youBase.structAt(r, c);
          if (s != null && !s.isCastle) {
            g.youBase.removeAt(r, c);
            wrecked++;
          }
        }
      }
      expect(sig(g.youBase), isNot(want));
      expect(g.importBaseCode(code), isNull);
      expect(sig(g.youBase), want, reason: 'stone for stone, the same fort');
      expect(g.importBaseCode('garbage'), isNotNull,
          reason: 'a bad code fails politely');
    });

    test('replays carry the WORLD scars: old graves and standing ruins', () {
      final b = flat();
      b.graves.add([7, 7, 0]); // a past war's fallen
      b.place(20, 3, DefType.cannon, 'def');
      b.structAt(20, 3)!.hp = 0; // an old ruin
      final st = raid(b);
      st.snapshot('x');
      final f = st.frames.last;
      expect(f.graves.any((g) => g[0] == 7 && g[1] == 7), isTrue,
          reason: 'the fallen of raids past stay in the frame');
      expect(f.structs.any((x) => x.r == 20 && x.c == 3 && x.hpFrac <= 0),
          isTrue, reason: 'ruins render as rubble in replays');
    });

    test('a razed castle takes its fighter OUT of the sim war', () {
      List<WarLogEntry> hour({required bool razed}) {
        final you = flat(side: WarSide.you, seed: 3);
        you.placeCastle('casey', 30, 30);
        if (razed) you.structAt(30, 30)!.hp = 0;
        final foe = flat(seed: 4);
        foe.placeCastle('foe', 5, 5);
        final casey = WarPlayer(
            id: 'casey',
            name: 'Casey',
            emoji: '🦊',
            colorValue: 0xFF22C55E,
            side: WarSide.you,
            ai: AiLevel.master,
            isBot: true);
        casey.skillMul = 3; // skill clamps to 1.5 → raid chance > 1
        return WarSim.runHour(
            hour: 1,
            minute: 60,
            youBase: you,
            enemyBase: foe,
            players: [casey],
            pools: MapPools({'casey': 999}),
            warSeed: 99,
            activePlayerId: 'you',
            youIntel: <int>{5 * Base.defaultSize + 5},
            enemyIntel: <int>{},
            raidChance: 1.0); // force the roll — this test is about KO, not dial
      }

      expect(hour(razed: false), isNotEmpty, reason: 'alive → he raids');
      expect(hour(razed: true), isEmpty, reason: 'castle down → spectator');
    });

    test('a knocked-out fighter cannot train or deploy', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.startWar();
      final cell = g.youBase.castles['you']!;
      g.youBase.structAt(cell.r, cell.c)!.hp = 0;
      expect(g.knockedOut(g.active), isTrue);
      expect(g.trainTroop(TroopType.soldier), isNotNull);
      final st = AttackState(
          base: g.enemyBase,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: g.pools);
      expect(g.deployTrained(st, TroopType.soldier, Base.defaultSize - 1, 5), isNull);
    });

    test('the crew edits the crew base: sell refunds the OWNER, castles never',
        () {
      final g = WarGame.fresh();
      g.startPrep();
      final mate = g.youClan.firstWhere((p) => p.id != g.active.id);
      // an open plains cell in the interior
      late int rr, cc;
      outer:
      for (var r = 5; r < Base.defaultSize - 5; r++) {
        for (var c = 5; c < Base.defaultSize - 5; c++) {
          if (g.youBase.structAt(r, c) == null &&
              g.youBase.grid[r][c].terrain == Terrain.plains) {
            rr = r;
            cc = c;
            break outer;
          }
        }
      }
      g.youBase.place(rr, cc, DefType.archerTower, mate.id);
      final before = mate.resources;
      g.removeStructure(rr, cc);
      expect(g.youBase.structAt(rr, cc), isNull);
      expect(mate.resources, greaterThan(before),
          reason: 'the refund goes to whoever paid for it');
      // upgrade a teammate's piece with YOUR funds
      g.youBase.place(rr, cc, DefType.archerTower, mate.id);
      g.active.resources = 999;
      expect(g.upgradeStructure(rr, cc), isNull);
      expect(g.youBase.structAt(rr, cc)!.level, 2);
      // castles are sacred
      final castle = g.youBase.castles[g.active.id];
      if (castle != null) {
        g.removeStructure(castle.r, castle.c);
        expect(g.youBase.structAt(castle.r, castle.c), isNotNull);
      }
    });

    test('replay frames carry the SCORCH so craters appear when shells land',
        () {
      final b = flat();
      b.place(20, 3, DefType.mortar, 'def');
      final st = raid(b);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.r = 23;
      t.c = 3;
      st.defendersReact();
      st.snapshot('shellfall');
      expect(b.scorch, isNotEmpty);
      final frame = st.frames.last;
      expect(frame.scorch.any((e) => e[0] == 23 * Base.defaultSize + 3 && e[1] >= 2),
          isTrue, reason: 'the frame remembers the crater under the impact');
    });

    test('veterans: brutal-skill raiders field leveled troops', () {
      final p = WarPlayer(
          id: 'foe1',
          name: 'Vex',
          emoji: '😈',
          colorValue: 0xFFEF4444,
          side: WarSide.enemy,
          ai: AiLevel.master);
      p.skillMul = 3;
      expect(p.skill, 1.5, reason: 'the dial clamps at nightmare');
      final t = Troop(
          id: 'v',
          ownerId: 'foe1',
          side: WarSide.enemy,
          type: TroopType.brute,
          r: 0,
          c: 0);
      t.gainXp(Xp.perLevel * 2.0 + 1); // the ≥1.3-skill veteran grant
      expect(t.level, greaterThanOrEqualTo(3));
    });

    test('the landing band is three tiles deep', () {
      final b = flat();
      expect(b.isRing(2, 20), isTrue);
      expect(b.isRing(20, Base.defaultSize - 3), isTrue);
      expect(b.isRing(3, 20), isFalse, reason: 'row 3 is buildable ground');
      final st = raid(b);
      expect(st.spawn(TroopType.soldier, 'me', Base.defaultSize - 2, 8), isNotNull,
          reason: 'the second row is a legal drop now');
    });

    test('war banners do NOT stack', () {
      Structure fire(int banners) {
        final b = flat();
        b.place(20, 3, DefType.ballista, 'def');
        if (banners >= 1) b.place(20, 5, DefType.banner, 'def');
        if (banners >= 2) b.place(18, 3, DefType.banner, 'def');
        final st = raid(b);
        final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
        t.r = 27;
        t.c = 3;
        st.defendersReact();
        return b.structAt(20, 3)!;
      }

      expect(fire(1).cooldown, 2);
      expect(fire(2).cooldown, 2, reason: 'a second flag adds NOTHING');
    });

    test('pitch CLINGS: the burn follows for beats and cooks', () {
      final b = flat();
      b.place(30, 3, DefType.pitchThrower, 'def');
      final st = raid(b);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3)!;
      t.r = 31;
      t.c = 3;
      st.defendersReact(); // the splash — and the cling
      expect(t.burnRounds, 3);
      final after = t.hp;
      t.r = 20;
      t.c = 20; // he runs — the fire runs with him
      st.defendersReact();
      expect(t.hp, after - 3);
      expect(t.burnRounds, 2);
    });

    test('troops CUT wire instead of stalling at the fence', () {
      final b = flat();
      b.place(30, 3, DefType.barbedWire, 'def');
      // seal the flanks: the wire is the only road north (a kill-box lane)
      for (var c = 4; c <= 12; c++) {
        b.place(30, c, DefType.wall, 'def');
      }
      b.placeCastle('def', 25, 3);
      final st = raid(b);
      final brute = st.spawn(TroopType.brute, 'me', Base.defaultSize - 1, 3)!;
      brute.r = 31;
      brute.c = 3;
      brute.movePoints = 0;
      st.revealed.add(25 * Base.defaultSize + 3);
      WarAi.aiStep(st, brute);
      expect(b.structAt(30, 3)!.hp,
          lessThan(kDefSpecs[DefType.barbedWire]!.hp),
          reason: 'no legs to cross — so the wire gets the axe');
    });

    test('the garrison paths THROUGH the gate to reach the fight', () {
      final b = flat();
      for (var r = 27; r <= 32; r++) {
        b.place(r, 5, DefType.wall, 'def');
      }
      b.place(33, 5, DefType.gate, 'def');
      b.place(30, 3, DefType.guardPost, 'def');
      final st = raid(b);
      final t = st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 8)!;
      t.r = 30;
      t.c = 7; // the far side of the spine — greedy stepping stalls here
      final full = kTroopSpecs[TroopType.soldier]!.hp;
      for (var i = 0; i < 14 && t.hp == full; i++) {
        st.defendersReact();
      }
      expect(t.hp, lessThan(full),
          reason: 'around the spine, through the gate, sword out');
    });

    test('battles END at five minutes — Clash rules', () {
      final b = flat();
      b.placeCastle('def', 20, 3);
      final st = raid(b);
      final battle = LiveBattle(st, canDeploy: () => true);
      battle.tick(10);
      expect(battle.over, isFalse, reason: 'the clock idles until boots land');
      st.spawn(TroopType.soldier, 'me', Base.defaultSize - 1, 3);
      battle.elapsed = 299;
      battle.tick(2);
      expect(battle.over, isTrue, reason: 'time is up, commander');
      battle.extend();
      expect(battle.over, isFalse);
      expect(battle.elapsed, 0);
    });

    test('archer towers forge to LEVEL 5', () {
      expect(kDefSpecs[DefType.archerTower]!.maxLevel, 5);
    });

    test('the war log tells you how many marched', () {
      final e = WarLogEntry(
          minute: 60,
          attackerSide: WarSide.enemy,
          attackerName: 'Vex',
          gained: 12.4,
          defenderDestruction: 30,
          troopsLost: 2,
          troopsSent: 7,
          resourcesSpent: 210,
          razed: false);
      expect(e.line, contains('with 7'));
      expect(e.line, contains('lost 2'));
    });
  });

  group('v18: citadels — labyrinth fortresses past master', () {
    List<WarPlayer> crew(double skill) => [
          for (var i = 0; i < 4; i++)
            WarPlayer(
                id: 'c$i',
                name: 'C$i',
                emoji: '😈',
                colorValue: 0xFFEF4444,
                side: WarSide.enemy,
                ai: AiLevel.master,
                resources: WarCosts.prepBudgetFor(skill))
              ..skillMul = skill / AiData.skill(AiLevel.master),
        ];

    Base build(int seed, double skill) {
      final b = Base(WarSide.enemy, seed,
          config: TerrainConfig(rivers: 0, lakes: 0));
      WarAi.designBase(b, crew(skill), SeededRng(seed));
      return b;
    }

    /// Flood-fill ground truth: [rooms, vaults] — a room is an enclosed
    /// pocket of open ground (walls AND gates block, so every ward counts
    /// once); a vault is a room with no gate on its rim at all.
    List<int> pockets(Base b) {
      bool blockedAt(int r, int c) {
        if (!TerrainData.passable(b.grid[r][c].terrain)) return true;
        final st = b.structAt(r, c);
        return st != null && st.alive && st.spec.blocks;
      }

      final seen =
          List.generate(Base.defaultSize, (_) => List.filled(Base.defaultSize, false));
      var rooms = 0, vaults = 0;
      for (var r = 3; r < Base.defaultSize - 3; r++) {
        for (var c = 3; c < Base.defaultSize - 3; c++) {
          if (seen[r][c] || blockedAt(r, c)) continue;
          var size = 0;
          var touchesRing = false;
          var hasDoor = false;
          final q = <List<int>>[
            [r, c]
          ];
          seen[r][c] = true;
          while (q.isNotEmpty) {
            final cur = q.removeLast();
            size++;
            if (b.isRing(cur[0], cur[1])) touchesRing = true;
            for (final d in const [
              [-1, 0],
              [1, 0],
              [0, -1],
              [0, 1]
            ]) {
              final nr = cur[0] + d[0], nc = cur[1] + d[1];
              if (nr < 0 || nr >= Base.defaultSize || nc < 0 || nc >= Base.defaultSize) {
                continue;
              }
              final ns = b.structAt(nr, nc);
              if (ns != null && ns.alive && ns.type == DefType.gate) {
                hasDoor = true;
              }
              if (seen[nr][nc] || blockedAt(nr, nc)) continue;
              seen[nr][nc] = true;
              q.add([nr, nc]);
            }
          }
          if (!touchesRing && size >= 4) {
            rooms++;
            if (!hasDoor) vaults++;
          }
        }
      }
      return [rooms, vaults];
    }

    int nonWallPieces(Base b) {
      var n = 0;
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          final st = b.structAt(r, c);
          if (st != null &&
              st.type != DefType.wall &&
              st.type != DefType.gate &&
              !st.isCastle) {
            n++;
          }
        }
      }
      return n;
    }

    test('difficulty 99 builds a CITY: 20+ rooms, structures everywhere', () {
      for (final seed in const [13, 47, 91]) {
        final b = build(seed, 1.49);
        final p = pockets(b);
        expect(p[0], greaterThanOrEqualTo(20),
            reason: 'seed $seed: a citadel, not a yard (${p[0]} rooms)');
        expect(p[1], greaterThanOrEqualTo(2),
            reason: 'seed $seed: sealed VAULTS you can only breach into');
        expect(WarAi.lastBuildStats!.structures, greaterThanOrEqualTo(250),
            reason: 'seed $seed: the city is BUILT, not sketched');
        expect(nonWallPieces(b), greaterThanOrEqualTo(60),
            reason: 'seed $seed: teeth in every ward, not just walls');
      }
    });

    test('difficulty 80 is nearly as vicious', () {
      final b = build(13, 1.26);
      expect(pockets(b)[0], greaterThanOrEqualTo(14));
    });

    test('below master nothing changes — the old fortress stands', () {
      final b = build(13, 0.5);
      expect(pockets(b)[0], lessThanOrEqualTo(8),
          reason: 'the low end of the dial is frozen');
    });

    test('citadels are deterministic: same seed, same city', () {
      final a = jsonEncode(build(13, 1.49).toJson());
      final b = jsonEncode(build(13, 1.49).toJson());
      expect(a, b);
    });

    test('no dead stubs at scale: every wall leans on two friends', () {
      final b = build(47, 1.49);
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          final st = b.structAt(r, c);
          if (st == null ||
              (st.type != DefType.wall && st.type != DefType.gate)) {
            continue;
          }
          var support = 0;
          for (var dr = -1; dr <= 1; dr++) {
            for (var dc = -1; dc <= 1; dc++) {
              if (dr == 0 && dc == 0) continue;
              final nr = r + dr, nc = c + dc;
              if (!b.inBounds(nr, nc)) continue;
              final ns = b.structAt(nr, nc);
              if (ns != null &&
                  ns.alive &&
                  (ns.type == DefType.wall ||
                      ns.type == DefType.gate ||
                      ns.isCastle)) {
                support++;
              } else if (!TerrainData.passable(b.grid[nr][nc].terrain)) {
                support++;
              }
            }
          }
          expect(support, greaterThanOrEqualTo(2),
              reason: 'stub at ($r,$c) survived the cleanup');
        }
      }
    });

    test('gate discipline holds in the labyrinth: no two doors adjacent', () {
      final b = build(91, 1.49);
      final gates = <List<int>>[];
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          final st = b.structAt(r, c);
          if (st != null && st.type == DefType.gate) gates.add([r, c]);
        }
      }
      expect(gates.length, greaterThanOrEqualTo(8),
          reason: 'a city has many doors');
      for (var i = 0; i < gates.length; i++) {
        for (var j = i + 1; j < gates.length; j++) {
          final ch = math.max((gates[i][0] - gates[j][0]).abs(),
              (gates[i][1] - gates[j][1]).abs());
          expect(ch, greaterThanOrEqualTo(2),
              reason: 'doors at ${gates[i]} and ${gates[j]} touch');
        }
      }
    });
  });
}

