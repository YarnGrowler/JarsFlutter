import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// How precisely the crew can scout the upcoming assault.
enum ScoutAccuracy { exact, fuzzed }

class SiegeShopItem {
  final int cost;
  final double value; // reduce / perDay / boostPct — meaning depends on item
  const SiegeShopItem({required this.cost, required this.value});
}

class SiegeShopConfig {
  final bool enabled;
  final Map<String, SiegeShopItem> crew;
  final Map<String, SiegeShopItem> personal;
  const SiegeShopConfig({
    this.enabled = false,
    this.crew = const {},
    this.personal = const {},
  });
}

/// Parsed `assets/siege.json` — all Siege tuning lives here. Loaded once at
/// startup; falls back to safe built-in defaults if the asset is bad/missing.
///
/// NOTE on damage: the spec's absolute `breach × 0.1` isn't scale-invariant
/// (a high-scoring crew would die instantly). We use RELATIVE damage:
///   integrityLoss = (breach / weekTotalAssault) × 100 × damageFactor
/// A FULLY undefended week loses `100 × damageFactor` integrity total, spread by
/// the tempo — so this is a multi-day arc, not a one-shot. At 3.0 a totally
/// undefended week collapses around day 3, letting ~15% through net still holds
/// (with a bruise), and a well-supplied crew holds comfortably. Keep it modest:
/// a big value (e.g. 12) makes a single undefended day fatal — no game.
class SiegeConfig {
  final bool enabled;
  final int days;
  final int resolutionHour;
  final int integrityStart;
  final List<String> fronts;
  final double supplyPerPoint;
  final bool carryUnallocated;
  final double damageFactor;
  final ScoutAccuracy scoutAccuracy;
  final List<String> tempoProfiles;
  final bool signatureEnabled;
  final double signatureMultiplier;
  final int maxSignatureDays;
  final SiegeShopConfig shop;

  const SiegeConfig({
    required this.enabled,
    required this.days,
    required this.resolutionHour,
    required this.integrityStart,
    required this.fronts,
    required this.supplyPerPoint,
    required this.carryUnallocated,
    required this.damageFactor,
    required this.scoutAccuracy,
    required this.tempoProfiles,
    required this.signatureEnabled,
    required this.signatureMultiplier,
    required this.maxSignatureDays,
    required this.shop,
  });

  int get frontCount => fronts.length;

  // ── Loading ────────────────────────────────────────────────────────────────
  static SiegeConfig _instance = fallback;
  static SiegeConfig get instance => _instance;

  /// Test hook: swap the active config (used by unit tests / debug sim).
  @visibleForTesting
  static set instance(SiegeConfig c) => _instance = c;

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('assets/siege.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = fromJson(map);
      validate(parsed);
      _instance = parsed;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SiegeConfig: using fallback ($e)');
      }
      _instance = fallback;
    }
  }

  static SiegeConfig fromJson(Map<String, dynamic> j) {
    double dbl(dynamic v, double d) => (v is num) ? v.toDouble() : d;
    int intOf(dynamic v, int d) => (v is num) ? v.toInt() : d;

    final week = (j['week'] as Map<String, dynamic>?) ?? const {};
    final hold = (j['stronghold'] as Map<String, dynamic>?) ?? const {};
    final supply = (j['supply'] as Map<String, dynamic>?) ?? const {};
    final res = (j['resolution'] as Map<String, dynamic>?) ?? const {};
    final scout = (j['scouting'] as Map<String, dynamic>?) ?? const {};
    final assault = (j['assault'] as Map<String, dynamic>?) ?? const {};
    final sig = (assault['signature'] as Map<String, dynamic>?) ?? const {};
    final shopJ = (j['shop'] as Map<String, dynamic>?) ?? const {};

    Map<String, SiegeShopItem> shelf(dynamic v) {
      final out = <String, SiegeShopItem>{};
      if (v is Map<String, dynamic>) {
        for (final e in v.entries) {
          final m = e.value;
          if (m is Map<String, dynamic>) {
            final value = dbl(
                m['reduce'] ?? m['perDay'] ?? m['boostPct'], 0);
            out[e.key] =
                SiegeShopItem(cost: intOf(m['cost'], 0), value: value);
          }
        }
      }
      return out;
    }

    final frontsRaw = (hold['fronts'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['left', 'center', 'right'];
    final tempoRaw = (assault['tempoProfiles'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['steady', 'lateSurge', 'frontload'];

    return SiegeConfig(
      enabled: j['enabled'] == true,
      days: intOf(week['days'], 7),
      resolutionHour: intOf(week['resolutionHour'], 0),
      integrityStart: intOf(hold['integrityStart'], 100),
      fronts: frontsRaw,
      supplyPerPoint: dbl(supply['supplyPerPoint'], 1.0),
      carryUnallocated: supply['carryUnallocated'] != false,
      damageFactor: dbl(res['damageFactor'], 7.0),
      scoutAccuracy: scout['scoutAccuracy'] == 'exact'
          ? ScoutAccuracy.exact
          : ScoutAccuracy.fuzzed,
      tempoProfiles: tempoRaw,
      signatureEnabled: sig['enabled'] != false,
      signatureMultiplier: dbl(sig['multiplier'], 1.6),
      maxSignatureDays: intOf(sig['maxSignatureDays'], 2),
      shop: SiegeShopConfig(
        enabled: shopJ['enabled'] == true,
        crew: shelf(shopJ['crew']),
        personal: shelf(shopJ['personal']),
      ),
    );
  }

  /// Fail-fast so a fat-fingered siege.json can't produce a broken week.
  static void validate(SiegeConfig c) {
    if (c.days < 1 || c.days > 14) throw StateError('days must be 1..14');
    if (c.fronts.isEmpty) throw StateError('fronts must be non-empty');
    if (c.integrityStart <= 0) throw StateError('integrityStart must be > 0');
    if (c.supplyPerPoint <= 0) throw StateError('supplyPerPoint must be > 0');
    if (c.damageFactor <= 0) throw StateError('damageFactor must be > 0');
    if (c.signatureMultiplier < 1) {
      throw StateError('signatureMultiplier must be >= 1');
    }
    if (c.maxSignatureDays < 0 || c.maxSignatureDays >= c.days) {
      throw StateError('maxSignatureDays must be 0..days-1');
    }
    if (c.tempoProfiles.isEmpty) {
      throw StateError('tempoProfiles must be non-empty');
    }
  }

  /// Safe built-in defaults (used if the asset is missing/invalid, and by the
  /// engine unit tests so they don't depend on asset loading).
  static const SiegeConfig fallback = SiegeConfig(
    enabled: true,
    days: 7,
    resolutionHour: 0,
    integrityStart: 100,
    fronts: ['left', 'center', 'right'],
    supplyPerPoint: 1.0,
    carryUnallocated: true,
    damageFactor: 7.0,
    scoutAccuracy: ScoutAccuracy.fuzzed,
    tempoProfiles: ['steady', 'lateSurge', 'frontload'],
    signatureEnabled: true,
    signatureMultiplier: 1.6,
    maxSignatureDays: 2,
    shop: SiegeShopConfig(),
  );
}
