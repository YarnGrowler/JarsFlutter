import 'package:flutter_test/flutter_test.dart';
import 'package:jars/models/siege_tactics.dart';

NightPlan plan1({
  double reinforce = 0,
  double fortifyWall = 0,
  double fortifyRoof = 0,
  bool damaged = false,
  List<TacticKind> tactics = const [],
  int? oilFront,
  int morale = 0,
}) =>
    NightPlan(
      reinforce: [reinforce],
      fortifyWall: [fortifyWall],
      fortifyRoof: [fortifyRoof],
      wallDamaged: [damaged],
      tactics: tactics,
      oilFront: oilFront,
      morale: morale,
    );

void main() {
  group('the counter triangle', () {
    test('walls stop infantry', () {
      final r = SiegeTactics.resolveNight(
          [const FrontIncoming(100, 0, 0)], plan1(reinforce: 100));
      expect(r.fronts[0].held, isTrue);
      expect(r.fronts[0].infantryBreach, closeTo(0, 0.001));
    });

    test('walls barely slow rams — but oil obliterates them', () {
      final naked = SiegeTactics.resolveNight(
          [const FrontIncoming(0, 100, 0)], plan1(reinforce: 100));
      expect(naked.fronts[0].ramBreach, greaterThan(50),
          reason: 'walls only bite ~35% of rams');

      final oiled = SiegeTactics.resolveNight(
        [const FrontIncoming(0, 100, 0)],
        plan1(reinforce: 0, tactics: [TacticKind.oil], oilFront: 0),
      );
      expect(oiled.fronts[0].ramBreach, closeTo(0, 0.001));
      expect(oiled.fronts[0].held, isTrue);
    });

    test('archers shoot over any wall — a roof or volley is the only answer',
        () {
      final walled = SiegeTactics.resolveNight(
          [const FrontIncoming(0, 0, 100)], plan1(reinforce: 5000));
      expect(walled.fronts[0].archerBreach, closeTo(100, 0.001),
          reason: 'a mountain of troops does nothing to arrows');

      final roofed = SiegeTactics.resolveNight(
          [const FrontIncoming(0, 0, 100)], plan1(fortifyRoof: 100));
      expect(roofed.fronts[0].held, isTrue);

      final volleyed = SiegeTactics.resolveNight(
        [const FrontIncoming(0, 0, 100)],
        plan1(tactics: [TacticKind.volley]),
        volleyValue: 100,
      );
      expect(volleyed.fronts[0].held, isTrue);
    });
  });

  test('morale makes troops hit harder', () {
    final low = SiegeTactics.resolveNight(
        [const FrontIncoming(100, 0, 0)], plan1(reinforce: 80, morale: 0));
    expect(low.fronts[0].held, isFalse);
    final high = SiegeTactics.resolveNight(
        [const FrontIncoming(100, 0, 0)], plan1(reinforce: 80, morale: 5));
    expect(high.fronts[0].held, isTrue,
        reason: '80 troops × 1.4 morale ≥ 100 infantry');
  });

  test('a cracked wall is weaker until repaired', () {
    final r = SiegeTactics.resolveNight([const FrontIncoming(100, 0, 0)],
        plan1(reinforce: 100, damaged: true));
    expect(r.fronts[0].breach, greaterThan(20),
        reason: 'damaged walls lose 25% effectiveness');
  });

  test('rally boosts reinforcement 50%', () {
    final r = SiegeTactics.resolveNight(
      [const FrontIncoming(140, 0, 0)],
      plan1(reinforce: 100, tactics: [TacticKind.rally]),
    );
    expect(r.fronts[0].held, isTrue, reason: '100 × 1.5 = 150 ≥ 140');
  });

  group('composition', () {
    test('splits sum to the front total and stay non-negative', () {
      final c = SiegeTactics.composition(
        total: 300,
        night: 3,
        totalNights: 7,
        front: 1,
        signatureFront: false,
        signatureDay: false,
        softFront: false,
        seedParts: const ['x', 1, 2, 3, 1],
      );
      expect(c.infantry + c.ram + c.archer, closeTo(300, 1.0));
      expect(c.infantry, greaterThanOrEqualTo(0));
      expect(c.ram, greaterThanOrEqualTo(0));
      expect(c.archer, greaterThanOrEqualTo(0));
    });

    test('is deterministic for the same seed', () {
      FrontIncoming gen() => SiegeTactics.composition(
            total: 240,
            night: 5,
            totalNights: 7,
            front: 2,
            signatureFront: true,
            signatureDay: true,
            softFront: false,
            seedParts: const ['s', 0, 0, 5, 2],
          );
      final a = gen();
      final b = gen();
      expect(a.infantry, b.infantry);
      expect(a.ram, b.ram);
      expect(a.archer, b.archer);
    });

    test('the signature front on its day skews toward rams', () {
      final sig = SiegeTactics.composition(
        total: 300,
        night: 3,
        totalNights: 7,
        front: 1,
        signatureFront: true,
        signatureDay: true,
        softFront: false,
        seedParts: const ['s', 0, 0, 3, 1],
      );
      final plain = SiegeTactics.composition(
        total: 300,
        night: 3,
        totalNights: 7,
        front: 1,
        signatureFront: false,
        signatureDay: false,
        softFront: false,
        seedParts: const ['s', 0, 0, 3, 1],
      );
      expect(sig.ram, greaterThan(plain.ram));
    });
  });
}
