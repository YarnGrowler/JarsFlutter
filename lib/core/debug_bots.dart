import 'package:shared_preferences/shared_preferences.dart';

import '../models/siege.dart';

/// Fixed bot user UUIDs — MUST match `supabase_patches/47_debug_bots.sql`.
/// Keyed by [BotMember.id]. These are real `auth.users`/`profiles` rows, so bots
/// are genuine crew everywhere (feed, member faces, leaderboard, siege supply).
const Map<String, String> kDebugBotUuids = {
  'bot_casey': 'b0000000-0000-4000-8000-000000000001',
  'bot_wade': 'b0000000-0000-4000-8000-000000000002',
  'bot_finn': 'b0000000-0000-4000-8000-000000000003',
};

/// Debug-only AI teammate roster (persisted). Bots are real accounts (patch 47)
/// that log REAL workout rows into the active room via [SiegeDevDriver], so the
/// live feed/league/siege screens see them exactly like crewmates. Never active
/// outside DEBUG_TOOLS builds.
class DebugBots {
  static const _key = 'debug_bot_ids';
  static final List<BotMember> roster = [];

  /// The bot's real user UUID (null if unknown / patch not applied).
  static String? uuidFor(BotMember b) => kDebugBotUuids[b.id];

  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? const [];
    roster
      ..clear()
      ..addAll(BotMember.presets.where((p) => ids.contains(p.id)));
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final b in roster) b.id]);
  }

  static bool contains(BotMember p) => roster.any((b) => b.id == p.id);

  static Future<void> toggle(BotMember p) async {
    if (contains(p)) {
      roster.removeWhere((b) => b.id == p.id);
    } else {
      roster.add(p);
    }
    await _persist();
  }

  static Future<void> clear() async {
    roster.clear();
    await _persist();
  }

  /// Expected combined weekly output of the BOTS — used to calibrate the first
  /// week's assault so a bot crew gets a competitive siege, not a trivial one.
  static double expectedWeeklySupply() {
    var t = 0.0;
    for (final b in roster) {
      t += b.meanDailyPoints * b.activeProbability * 7;
    }
    return t;
  }

  /// Expected weekly output of the whole dev crew = the dev player + bots.
  /// Week 1 has no history, so the assault is calibrated to this so the siege is
  /// competitive (and defensible) from the very first jump.
  static double crewExpectedWeekly() =>
      kDevPlayerDailyPoints * 7 + expectedWeeklySupply();
}

/// The dev player's simulated daily output (they "train" each skipped day so the
/// siege always has supply, even before any bots are added / patch 47 applied).
const double kDevPlayerDailyPoints = 220.0;
