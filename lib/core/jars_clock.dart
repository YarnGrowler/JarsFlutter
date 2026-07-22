import 'package:shared_preferences/shared_preferences.dart';

import 'jars_timezone.dart';

/// Injectable clock for siege/league code. Never read `DateTime.now()` /
/// `JarsTimezone.todayChicago()` directly in game logic — go through
/// [JarsClock.instance] so the DebugSimulator / debug screen can fast-forward
/// days and weeks deterministically.
abstract class JarsClock {
  static JarsClock instance = RealJarsClock();

  /// "Today" as a Chicago calendar date (y/m/d only) — same contract as
  /// [JarsTimezone.todayChicago].
  DateTime todayChicago();
}

class RealJarsClock implements JarsClock {
  @override
  DateTime todayChicago() => JarsTimezone.todayChicago();
}

/// Debug clock: shifts "today" by [dayOffset] (7 per week — this is the
/// long-requested weekOffset). Swapped into [JarsClock.instance] by the debug
/// tools; never active in normal builds.
class DebugJarsClock implements JarsClock {
  int dayOffset;
  DebugJarsClock({this.dayOffset = 0});

  @override
  DateTime todayChicago() =>
      JarsTimezone.todayChicago().add(Duration(days: dayOffset));
}

/// Persists the debug time-travel offset so a hot restart doesn't silently
/// snap "today" back while future-dated bot logs linger. Debug builds only.
class DebugClockStore {
  static const _key = 'debug_clock_offset_days';
  static int offsetDays = 0;

  static void _apply() {
    JarsClock.instance = offsetDays == 0
        ? RealJarsClock()
        : DebugJarsClock(dayOffset: offsetDays);
  }

  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    offsetDays = prefs.getInt(_key) ?? 0;
    _apply();
  }

  static Future<void> set(int days) async {
    offsetDays = days.clamp(0, 3650);
    _apply();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, offsetDays);
  }

  static Future<void> advance(int days) => set(offsetDays + days);
}
