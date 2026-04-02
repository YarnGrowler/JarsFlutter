import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'score_provider.dart';

final currentStreakProvider = Provider<int>((ref) {
  final scoreAsync = ref.watch(myScoreProvider);
  return scoreAsync.maybeWhen(
    data: (score) => score?.streakCurrent ?? 0,
    orElse: () => 0,
  );
});

final highestStreakProvider = Provider<int>((ref) {
  final scoreAsync = ref.watch(myScoreProvider);
  return scoreAsync.maybeWhen(
    data: (score) => score?.streakHighest ?? 0,
    orElse: () => 0,
  );
});
