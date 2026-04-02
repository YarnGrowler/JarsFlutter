import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/log_service.dart';
import '../services/score_service.dart';
import '../core/extensions.dart';
import 'active_room_provider.dart';

enum LeaderboardPeriod { today, week, month, allTime }

final leaderboardPeriodProvider =
    StateProvider<LeaderboardPeriod>((ref) => LeaderboardPeriod.allTime);

class LeaderboardEntry {
  final String userId;
  final String username;
  final double score;
  final double dailyPoints;
  final int streak;

  const LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.score,
    required this.dailyPoints,
    required this.streak,
  });
}

final leaderboardProvider =
    FutureProvider<List<LeaderboardEntry>>((ref) async {
  final room = ref.watch(activeRoomProvider);
  final period = ref.watch(leaderboardPeriodProvider);
  if (room == null) return [];

  if (period == LeaderboardPeriod.allTime) {
    final scores = await ScoreService.getRoomScores(room.id);
    return scores
        .map((s) => LeaderboardEntry(
              userId: s.userId,
              username: s.username ?? 'Unknown',
              score: s.totalScore,
              dailyPoints: s.dailyPoints,
              streak: s.streakCurrent,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  if (period == LeaderboardPeriod.today) {
    final scores = await ScoreService.getRoomScores(room.id);
    return scores
        .map((s) => LeaderboardEntry(
              userId: s.userId,
              username: s.username ?? 'Unknown',
              score: s.dailyPoints,
              dailyPoints: s.dailyPoints,
              streak: s.streakCurrent,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  final scores = await ScoreService.getRoomScores(room.id);
  final now = DateTime.now();
  final cutoff = period == LeaderboardPeriod.week
      ? now.startOfWeek
      : now.startOfMonth;

  final entries = <LeaderboardEntry>[];
  for (final score in scores) {
    final logs = await LogService.getUserLogs(room.id, score.userId);
    final periodPoints = logs
        .where((l) => l.createdAt.isAfter(cutoff))
        .fold<double>(0, (sum, l) => sum + l.pointsEarned);

    entries.add(LeaderboardEntry(
      userId: score.userId,
      username: score.username ?? 'Unknown',
      score: periodPoints,
      dailyPoints: score.dailyPoints,
      streak: score.streakCurrent,
    ));
  }

  entries.sort((a, b) => b.score.compareTo(a.score));
  return entries;
});
