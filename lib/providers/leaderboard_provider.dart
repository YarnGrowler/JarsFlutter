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
  /// Points shown/sorted for the current period tab (today/week/month/all-time).
  final double score;
  /// User's official all-time total score (for level/rank display).
  final double totalScore;
  /// Official all-time rank in this room (1 = highest totalScore).
  final int officialRank;
  final double dailyPoints;
  final int streak;

  const LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.score,
    required this.totalScore,
    required this.officialRank,
    required this.dailyPoints,
    required this.streak,
  });
}

final leaderboardProvider =
    FutureProvider<List<LeaderboardEntry>>((ref) async {
  final room = ref.watch(activeRoomProvider);
  final period = ref.watch(leaderboardPeriodProvider);
  if (room == null) return [];

  final scores = await ScoreService.getRoomScores(room.id);
  // Official all-time rank map (stable display across all tabs).
  final sortedAllTime = [...scores]
    ..sort((a, b) {
      final byScore = b.totalScore.compareTo(a.totalScore);
      if (byScore != 0) return byScore;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  final officialRankByUser = <String, int>{
    for (var i = 0; i < sortedAllTime.length; i++) sortedAllTime[i].userId: i + 1,
  };

  if (period == LeaderboardPeriod.allTime) {
    return sortedAllTime
        .map((s) => LeaderboardEntry(
              userId: s.userId,
              username: s.username ?? 'Unknown',
              score: s.totalScore,
              totalScore: s.totalScore,
              officialRank: officialRankByUser[s.userId] ?? 0,
              dailyPoints: s.displayDailyPoints,
              streak: s.streakCurrent,
            ))
        .toList();
  }

  if (period == LeaderboardPeriod.today) {
    return scores
        .map((s) => LeaderboardEntry(
              userId: s.userId,
              username: s.username ?? 'Unknown',
              score: s.displayDailyPoints,
              totalScore: s.totalScore,
              officialRank: officialRankByUser[s.userId] ?? 0,
              dailyPoints: s.displayDailyPoints,
              streak: s.streakCurrent,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

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
      totalScore: score.totalScore,
      officialRank: officialRankByUser[score.userId] ?? 0,
      dailyPoints: score.displayDailyPoints,
      streak: score.streakCurrent,
    ));
  }

  entries.sort((a, b) => b.score.compareTo(a.score));
  return entries;
});
