import 'package:flutter_test/flutter_test.dart';
import 'package:jars/core/league_config.dart';
import 'package:jars/war/war_base.dart';
import 'package:jars/war/war_engine.dart';
import 'package:jars/war/war_game.dart';
import 'package:jars/war/war_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final cfg = LeagueConfig.instance;

  void flatten(Base base, List<List<int>> cells) {
    for (final rc in cells) {
      base.grid[rc[0]][rc[1]].terrain = Terrain.plains;
    }
  }

  group('map size / expand', () {
    test('expandTo pads and preserves relative structure positions', () {
      final base = Base(WarSide.you, 42, size: 40);
      flatten(base, [
        [10, 10],
        [11, 10],
        [12, 12],
      ]);
      base.place(10, 10, DefType.wall, 'you');
      base.place(11, 10, DefType.tesla, 'you');
      base.placeCastle('you', 12, 12);

      final grown = base.expandTo(48);
      expect(grown.rows, 48);
      expect(grown.cols, 48);
      final pad = (48 - 40) ~/ 2;
      expect(grown.structAt(10 + pad, 10 + pad)?.type, DefType.wall);
      expect(grown.structAt(11 + pad, 10 + pad)?.type, DefType.tesla);
      expect(grown.castles['you'], Cell(12 + pad, 12 + pad));
      // Never shrinks.
      expect(identical(grown.expandTo(40), grown) || grown.expandTo(40).rows == 48,
          isTrue);
      expect(grown.expandTo(44).rows, 48);
    });

    test('mapSize never shrinks on relegation (peak persists via load)', () {
      final g = WarGame.fresh()..startPrep();
      expect(g.mapSize, Base.defaultSize);
      g.mapSize = 52;
      g.divisionIndex = 0; // Bronze wants 40
      final blob = g.toJson();
      final g2 = WarGame.fresh()..loadFromJson(blob);
      expect(g2.divisionIndex, 0);
      expect(g2.mapSize, 52, reason: 'peak map size must survive bronze relegation');
      expect(g2.youBase.rows, greaterThanOrEqualTo(52));
    });

    test('enemy base size matches mapSize at startPrep', () {
      final g = WarGame.fresh();
      g.mapSize = 48;
      g.divisionIndex = 3; // Platinum
      g.startPrep();
      expect(g.mapSize, greaterThanOrEqualTo(48));
      expect(g.youBase.rows, g.mapSize);
      expect(g.enemyBase.rows, g.mapSize);
      expect(g.enemyBase.cols, g.mapSize);
    });
  });

  group('unlocks', () {
    test('Bronze cannot train Healer; Silver can', () {
      final g = WarGame.fresh()..startPrep();
      g.divisionIndex = 0;
      g.active.resources = 9999;
      expect(g.troopUnlocked(TroopType.healer), isFalse);
      expect(g.trainTroop(TroopType.healer), contains('unlocks'));

      g.divisionIndex = 1; // Silver
      expect(g.troopUnlocked(TroopType.healer), isTrue);
      expect(g.trainTroop(TroopType.healer), isNull);
      expect(g.active.armyCount(TroopType.healer), 1);
    });

    test('Bronze can still place Tesla / Ballista (legacy palette free)', () {
      final g = WarGame.fresh()..startPrep();
      g.divisionIndex = 0;
      g.active.resources = 9999;
      expect(g.defUnlocked(DefType.tesla), isTrue);
      expect(g.defUnlocked(DefType.ballista), isTrue);
      // Find a clearable interior tile.
      var placed = false;
      for (var r = 5; r < g.youBase.rows - 5 && !placed; r++) {
        for (var c = 5; c < g.youBase.cols - 5 && !placed; c++) {
          if (!g.youBase.canPlace(r, c)) continue;
          expect(g.placeStructure(r, c, DefType.tesla), isNull);
          placed = true;
        }
      }
      expect(placed, isTrue);
    });

    test('cumulative unlock ladder matches leagues.json / fallback', () {
      expect(cfg.unlockedTroopsThrough(0), isEmpty);
      expect(cfg.unlockedTroopsThrough(1), contains('healer'));
      expect(cfg.unlockedTroopsThrough(2), containsAll(['healer', 'javelin']));
      expect(cfg.unlockedDefsThrough(2),
          containsAll(['tributeChest', 'commandTent']));
      expect(cfg.unlockedDefsThrough(0), isEmpty);
    });
  });

  group('tribute chest / command tent', () {
    test('chest payout splits among real (non-bot) members; destroyed = none',
        () {
      final g = WarGame.fresh()..startPrep();
      g.divisionIndex = 2; // Gold
      g.active.resources = 9999;
      // Ensure at least one real player and one bot-ish teammate if present.
      final real = g.youClan.where((p) => !p.isBot).toList();
      expect(real, isNotEmpty);

      // Place a surviving chest.
      var rr = -1, cc = -1;
      for (var r = 5; r < g.youBase.rows - 5 && rr < 0; r++) {
        for (var c = 5; c < g.youBase.cols - 5 && rr < 0; c++) {
          if (g.youBase.canPlace(r, c)) {
            rr = r;
            cc = c;
          }
        }
      }
      expect(g.placeStructure(rr, cc, DefType.tributeChest), isNull);
      final before = {for (final p in real) p.id: p.resources};

      g.startWar();
      // startWar resets war-day resources — snapshot again just before payout.
      final prePayout = {for (final p in real) p.id: p.resources};
      g.endWar();
      final share = 200.0 / real.length;
      for (final p in real) {
        expect(p.resources, closeTo(prePayout[p.id]! + share, 0.01));
      }
      expect(before, isNotEmpty); // placed successfully

      // Destroyed chest pays nothing.
      final g2 = WarGame.fresh()..startPrep();
      g2.divisionIndex = 2;
      g2.active.resources = 9999;
      final real2 = g2.youClan.where((p) => !p.isBot).toList();
      var r2 = -1, c2 = -1;
      for (var r = 5; r < g2.youBase.rows - 5 && r2 < 0; r++) {
        for (var c = 5; c < g2.youBase.cols - 5 && r2 < 0; c++) {
          if (g2.youBase.canPlace(r, c)) {
            r2 = r;
            c2 = c;
          }
        }
      }
      expect(g2.placeStructure(r2, c2, DefType.tributeChest), isNull);
      g2.youBase.structAt(r2, c2)!.hp = 0;
      g2.startWar();
      final pre2 = {for (final p in real2) p.id: p.resources};
      g2.endWar();
      for (final p in real2) {
        expect(p.resources, closeTo(pre2[p.id]!, 0.01),
            reason: 'sunk cost — no payout');
      }
    });

    test('one Command Tent per player; General spawns on raid', () {
      final g = WarGame.fresh()..startPrep();
      g.divisionIndex = 2;
      g.active.resources = 9999;
      final spots = <List<int>>[];
      for (var r = 5; r < g.youBase.rows - 5 && spots.length < 2; r++) {
        for (var c = 5; c < g.youBase.cols - 5 && spots.length < 2; c++) {
          if (g.youBase.canPlace(r, c)) spots.add([r, c]);
        }
      }
      expect(spots.length, greaterThanOrEqualTo(2));
      expect(
          g.placeStructure(spots[0][0], spots[0][1], DefType.commandTent),
          isNull);
      expect(
          g.placeStructure(spots[1][0], spots[1][1], DefType.commandTent),
          contains('already'));

      // Raid YOUR base as the enemy would — AttackState on youBase.
      flatten(g.youBase, [
        for (var r = 0; r < g.youBase.rows; r++) [r, spots[0][1]]
      ]);
      final st = AttackState(
        base: g.youBase,
        attacker: WarSide.enemy,
        attackerName: 'Raid',
        pools: MapPools({'raid': 999, g.active.id: 999}),
      );
      expect(st.garrison.any((t) => t.type == TroopType.general), isTrue);
    });
  });

  group('combat rules', () {
    test('smoke blocks long-range spot like forest', () {
      final base = Base(WarSide.enemy, 7);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 6, 3, DefType.archerTower, 'def');
      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}));
      final fogger =
          st.spawn(TroopType.fogger, 'me', Base.defaultSize - 1, 3)!;
      expect(fogger.smokeUsed, isTrue);
      expect(st.smoke, isNotEmpty);

      // Walk into smoke at range 3 from the tower.
      fogger.r = Base.defaultSize - 3;
      fogger.c = 3;
      st.smoke[fogger.r * base.cols + fogger.c] = 8;
      final hp0 = fogger.hp;
      st.defendersReact();
      expect(fogger.hp, hp0, reason: 'smoke conceals at range 3');

      fogger.r = Base.defaultSize - 4; // range 2
      st.smoke[fogger.r * base.cols + fogger.c] = 8;
      st.defendersReact();
      expect(fogger.hp, lessThan(hp0), reason: 'spotted inside short range');
    });

    test('L5 wall survives L1 sapper bomb', () {
      final base = Base(WarSide.enemy, 9);
      flatten(base, [
        for (var r = 0; r < Base.defaultSize; r++) [r, 3]
      ]);
      base.placeCastle('def', 2, 3);
      base.place(Base.defaultSize - 4, 3, DefType.wall, 'def');
      final wall = base.structAt(Base.defaultSize - 4, 3)!;
      wall.level = 5;
      wall.hp = wall.maxHp;
      expect(wall.maxHp, greaterThan(AttackState.sapperBomb));

      final st = AttackState(
          base: base,
          attacker: WarSide.you,
          attackerName: 'Me',
          pools: MapPools({'me': 999, 'def': 999}),
          spawnGarrison: false);
      final sap =
          st.spawn(TroopType.sapper, 'me', Base.defaultSize - 1, 3)!;
      sap.r = Base.defaultSize - 5;
      sap.c = 3;
      st.attackCell(sap, Base.defaultSize - 4, 3);
      expect(wall.alive, isTrue, reason: 'obsidian bastion shrugs L1 sapper');
      expect(wall.hp, greaterThan(0));
    });

    test('wall L3 meleeChip and guard L4 leash scale', () {
      final w3 = Structure(DefType.wall, 'x', level: 3);
      expect(w3.meleeChip, greaterThan(0));
      final w1 = Structure(DefType.wall, 'x', level: 1);
      expect(w1.meleeChip, 0);
      // L4 leash ≈ base 4 + 2*(4-1) = 10
      expect(AttackState.garrisonLeash + (4 - 1) * 2, 10);
      expect(kDefSpecs[DefType.guardPost]!.maxLevel, 5);
      expect(kDefSpecs[DefType.wall]!.maxLevel, 5);
      expect(kDefSpecs[DefType.archerTower]!.maxLevel, 5);
      expect(kDefSpecs[DefType.cannon]!.maxLevel, 5);
    });
  });

  group('climbing the ladder builds a BIGGER, meaner enemy', () {
    /// Drive the real prep→war path at max difficulty for [div].
    ({int structures, int maxWall, int maxTower, int size}) buildAt(int div) {
      final g = WarGame.fresh();
      g.divisionIndex = div;
      g.startPrep();
      g.setDifficulty(100);
      g.startWar();
      var structures = 0;
      var maxWall = 0;
      var maxTower = 0;
      for (var r = 0; r < g.enemyBase.rows; r++) {
        for (var c = 0; c < g.enemyBase.cols; c++) {
          final s = g.enemyBase.structAt(r, c);
          if (s == null) continue;
          structures++;
          if (s.type == DefType.wall && s.level > maxWall) maxWall = s.level;
          if ((s.spec.isShooter || s.type == DefType.guardPost) &&
              s.level > maxTower) {
            maxTower = s.level;
          }
        }
      }
      return (
        structures: structures,
        maxWall: maxWall,
        maxTower: maxTower,
        size: g.enemyBase.rows
      );
    }

    test('REGRESSION: a higher rung never builds a SMALLER fortress', () {
      final bronze = buildAt(0);
      final radiant = buildAt(cfg.divisions.length - 1);
      expect(radiant.size, greaterThan(bronze.size));
      expect(radiant.structures, greaterThan(bronze.structures),
          reason: 'wards must FLOOR the citadel plan, never cap it');
    });

    test('top rung forges deeper walls than Bronze', () {
      final bronze = buildAt(0);
      final radiant = buildAt(cfg.divisions.length - 1);
      expect(radiant.maxWall, greaterThan(bronze.maxWall),
          reason: 'the curtain wall has to visibly climb with the league');
      expect(radiant.maxWall, greaterThanOrEqualTo(4));
      expect(radiant.maxTower, greaterThanOrEqualTo(4),
          reason: 'Radiant guns should be forged past Bronze L3');
    });

    test('the ladder tops out at a 64x64 board', () {
      expect(cfg.divisions.last.mapSize, 64);
      final g = WarGame.fresh();
      g.divisionIndex = cfg.divisions.length - 1;
      g.startPrep();
      expect(g.mapSize, 64);
      expect(g.youBase.rows, 64);
      expect(g.enemyBase.cols, 64);
    });
  });

  group('war generators', () {
    int? findSpot(WarGame g) {
      for (var r = 5; r < g.youBase.rows - 5; r++) {
        for (var c = 5; c < g.youBase.cols - 5; c++) {
          if (g.youBase.canPlace(r, c)) return r * 1000 + c;
        }
      }
      return null;
    }

    test('L1 drips 6⚡/hr on login catch-up; destroyed pays nothing', () {
      final realNow = DateTime.now().millisecondsSinceEpoch;
      WarGame.nowMs = () => realNow;
      addTearDown(() => WarGame.nowMs =
          () => DateTime.now().millisecondsSinceEpoch);

      final g = WarGame.fresh()..startPrep();
      g.active.resources = 9999;
      final spot = findSpot(g)!;
      final r = spot ~/ 1000, c = spot % 1000;
      expect(g.placeStructure(r, c, DefType.warGenerator), isNull);
      expect(kDefSpecs[DefType.warGenerator]!.cost, 50);

      g.startWar();
      final owner = g.players.firstWhere((p) => p.id == g.active.id);
      final before = owner.resources;

      // 10 minutes of wall time → 1⚡ at L1 (6/hr).
      WarGame.nowMs = () => realNow + 10 * 60 * 1000;
      g.syncToWallClock();
      expect(owner.resources, closeTo(before + 1.0, 0.05));

      // Smash the pump — further time pays nothing.
      g.youBase.structAt(r, c)!.hp = 0;
      final mid = owner.resources;
      WarGame.nowMs = () => realNow + 40 * 60 * 1000;
      g.syncToWallClock();
      expect(owner.resources, closeTo(mid, 0.05));
    });

    test('L2 upgrade costs 30 and pays 15⚡/hr', () {
      final realNow = DateTime.now().millisecondsSinceEpoch;
      WarGame.nowMs = () => realNow;
      addTearDown(() => WarGame.nowMs =
          () => DateTime.now().millisecondsSinceEpoch);

      final g = WarGame.fresh()..startPrep();
      g.active.resources = 9999;
      final spot = findSpot(g)!;
      final r = spot ~/ 1000, c = spot % 1000;
      expect(g.placeStructure(r, c, DefType.warGenerator), isNull);
      expect(g.upgradeStructure(r, c), isNull);
      expect(g.youBase.structAt(r, c)!.level, 2);

      g.startWar();
      final owner = g.players.firstWhere((p) => p.id == g.active.id);
      final before = owner.resources;
      // 1 hour → 15⚡
      WarGame.nowMs = () => realNow + 60 * 60 * 1000;
      // Avoid ending the war via hour sim: only accrue generators.
      // syncToWallClock would also run AI hours — that's fine for resources.
      g.syncToWallClock();
      expect(owner.resources - before, greaterThanOrEqualTo(14.5));
      expect(warGeneratorRatePerHour(2), 15);
      expect(warGeneratorRatePerHour(1), 6);
    });
  });
}
