import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Product default: Central Time (Chicago). Used for daily goals, streak days,
/// leaderboard "today", and first-log-of-day — not device local, not UTC.
class JarsTimezone {
  JarsTimezone._();

  static const String locationName = 'America/Chicago';

  static bool _ready = false;

  static void ensureInitialized() {
    if (_ready) return;
    tz_data.initializeTimeZones();
    _ready = true;
  }

  static tz.Location get _loc => tz.getLocation(locationName);

  /// "Today" as a calendar date in Chicago (year/month/day only).
  static DateTime todayChicago() {
    ensureInitialized();
    final n = tz.TZDateTime.now(_loc);
    return DateTime(n.year, n.month, n.day);
  }

  /// Start of "today" in Chicago as a UTC instant (midnight Chicago).
  static DateTime startOfTodayChicagoUtc() {
    ensureInitialized();
    final n = tz.TZDateTime.now(_loc);
    final start = tz.TZDateTime(_loc, n.year, n.month, n.day);
    return start.toUtc();
  }
}
