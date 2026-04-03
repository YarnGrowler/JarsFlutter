/// Copy for idle "wake up" nudges (feed card + push).
class WakeQuips {
  WakeQuips._();

  /// Shown on the feed card (about the absent member).
  static String cardSub(int pick, String absentName) {
    final p = pick % 6;
    switch (p) {
      case 0:
        return 'The room wants to know if $absentName is still alive.';
      case 1:
        return 'Everyone\'s looking around like… where\'s $absentName?';
      case 2:
        return 'Missing persons report energy 👀';
      case 3:
        return 'No logs in a bit — $absentName okay out there?';
      case 4:
        return 'Radio silence. Someone say hi to $absentName.';
      default:
        return 'If $absentName doesn\'t show soon we\'re starting rumors.';
    }
  }

  static String pushLine({
    required String tapperName,
    required String absentName,
    required int pick,
  }) {
    final p = pick % 6;
    switch (p) {
      case 0:
        return '$tapperName: yo $absentName — you alive out there?';
      case 1:
        return '$tapperName tapped the feed: where\'d $absentName go?';
      case 2:
        return '$tapperName says the room is asking about $absentName';
      case 3:
        return '$tapperName wants $absentName back in the fight';
      case 4:
        return '$tapperName sent a wake-up ping for $absentName';
      default:
        return '$tapperName: $absentName, your streak misses you';
    }
  }
}
