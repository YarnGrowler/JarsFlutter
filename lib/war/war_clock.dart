/// The war-day clock — a self-contained simulated timeline (NOT JarsClock, which
/// is date-only). Fast-forward advances these minutes; AI acts on the schedule.
class WarClock {
  static const int dayMinutes = 24 * 60;
  int simMinutes;
  WarClock([this.simMinutes = 0]);

  int get hour => simMinutes ~/ 60;
  int get minute => simMinutes % 60;
  double get dayFraction => (simMinutes / dayMinutes).clamp(0.0, 1.0);
  bool get dayOver => simMinutes >= dayMinutes;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Advance by [mins], returning the number of whole sim-hours crossed (so the
  /// caller can run that many hourly AI ticks).
  int advance(int mins) {
    final before = hour;
    simMinutes = (simMinutes + mins).clamp(0, dayMinutes);
    return hour - before;
  }
}
