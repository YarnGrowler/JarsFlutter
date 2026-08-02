import 'package:flutter_test/flutter_test.dart';
import 'package:jars/core/seeded_rng.dart';
import 'package:jars/war/war_ai.dart';
import 'package:jars/war/war_game.dart';
import 'package:jars/war/war_player.dart';
import 'package:jars/war/war_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('team spend: defense from base, offense from training', () {
    final g = WarGame.fresh()..startPrep();
    // you place a wall + upgrade it once
    expect(g.placeCastle(8, 8), isNull);
    expect(g.placeStructure(9, 8, DefType.wall), isNull);
    final wall = g.youBase.structAt(9, 8)!;
    expect(wall.investedCost, kDefSpecs[DefType.wall]!.cost.toDouble());
    expect(g.upgradeStructure(9, 8), isNull);
    expect(
        wall.investedCost,
        kDefSpecs[DefType.wall]!.cost +
            kDefSpecs[DefType.wall]!.upgradeCost); // L1→L2

    final youDef = g.defenseSpentOf(g.active);
    expect(youDef, wall.investedCost);

    // training counts as offense even in prep
    final before = g.active.resourcesSpent;
    expect(g.trainTroop(TroopType.soldier), isNull);
    expect(g.offenseSpentOf(g.active),
        before + kTroopSpecs[TroopType.soldier]!.cost);

    expect(g.clanOffense(g.youClan), greaterThan(0));
    expect(g.clanDefense(g.youClan), greaterThan(0));
  });

  test('biggest spenders rank attack and defense', () {
    final g = WarGame.fresh()..startPrep();
    // pour some offense into the crew
    g.active.resourcesSpent = 80;
    for (final p in g.enemyClan) {
      p.resources = 400;
    }
    // design the enemy stronghold so defense spend is real
    WarAi.designBase(
        g.enemyBase, g.enemyClan, SeededRng(11));
    g.enemyClan[0].resourcesSpent = 500;
    g.enemyClan[1].resourcesSpent = 120;

    final atk = g.biggestOffenseSpenders(limit: 3);
    expect(atk.first.id, g.enemyClan[0].id);
    expect(atk.map((p) => p.id), contains(g.enemyClan[1].id));

    final def = g.biggestDefenseSpenders(limit: 3);
    expect(def, isNotEmpty);
    expect(g.defenseSpentOf(def.first), greaterThan(0));
    for (var i = 1; i < def.length; i++) {
      expect(g.defenseSpentOf(def[i - 1]),
          greaterThanOrEqualTo(g.defenseSpentOf(def[i])));
    }
  });

  test('war tallies round-trip through player json', () {
    final p = WarPlayer(
        id: 'a',
        name: 'A',
        emoji: '🦊',
        colorValue: 1,
        side: WarSide.you,
        ai: AiLevel.seasoned)
      ..resourcesSpent = 42
      ..destructionDealt = 12.5
      ..troopsLost = 3;
    final back = WarPlayer.fromJson(p.toJson());
    expect(back.resourcesSpent, 42);
    expect(back.destructionDealt, 12.5);
    expect(back.troopsLost, 3);
  });

  test('selling an upgraded piece refunds place cost AND upgrades', () {
    final g = WarGame.fresh()..startPrep();
    expect(g.placeCastle(8, 8), isNull);
    final before = g.active.resources;
    expect(g.placeStructure(9, 8, DefType.wall), isNull);
    expect(g.upgradeStructure(9, 8), isNull); // L1→L2
    expect(g.upgradeStructure(9, 8), isNull); // L2→L3
    final wall = g.youBase.structAt(9, 8)!;
    expect(wall.level, 3);
    final spent = before - g.active.resources;
    expect(spent, wall.investedCost);
    expect(g.removeStructure(9, 8), isNull);
    expect(g.active.resources, closeTo(before, 0.001),
        reason: 'full investment must come back on sell');
    expect(g.youBase.structAt(9, 8), isNull);
  });

  test('enemy chest estimate reacts to difficulty and real crew effort', () {
    final g = WarGame.fresh()..startPrep();
    g.setDifficulty(20);
    final low = g.estimatedEnemyWarChest;
    expect(low, greaterThan(0));
    expect(g.estimatedEnemyWarChestPerFoe * g.enemyClan.length,
        closeTo(low, 0.001));

    g.setDifficulty(99);
    final hard = g.estimatedEnemyWarChest;
    expect(hard, greaterThan(low));

    final effortBefore = g.estimatedEnemyWarChest;
    g.active.prepEarned += 250;
    expect(
        g.estimatedEnemyWarChest,
        closeTo(effortBefore + 250 * WarCosts.enemyPrepMirror, 0.001),
        reason: 'crew prep mirrors into the enemy chest at enemyPrepMirror');
  });
}
