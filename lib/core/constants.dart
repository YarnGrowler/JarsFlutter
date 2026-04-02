const kAppName = 'Jars';
const kRoomCodeLength = 6;
const kDefaultMaxParticipants = 20;
const kDefaultStreakMinimum = 10;
const kDefaultDailyGoal = 100;
const kFeedPageSize = 50;
const kUndoDurationSeconds = 8;

/// Basic RFC 5322-style check — Supabase Auth expects a deliverable email.
bool isValidEmailFormat(String value) {
  final v = value.trim();
  if (v.length < 5 || !v.contains('@')) return false;
  final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  return re.hasMatch(v);
}
