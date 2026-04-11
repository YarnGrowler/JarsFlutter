import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/achievement_unread_version_provider.dart';
import '../../providers/leaderboard_provider.dart';
import '../../providers/room_analytics_provider.dart';
import '../../providers/score_provider.dart';
import '../../services/achievement_service.dart';
import '../../services/log_service.dart';
import '../../services/score_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ranks/leaderboard_row.dart';
import '../../widgets/ranks/rank_progress_arc.dart';
import '../../widgets/ranks/consistency_calendar.dart';
import 'member_profile_sheet.dart';
import 'exercise_stats_sheet.dart';
import 'achievements_sheet.dart';
import 'room_analytics_tab.dart';
import 'room_exercise_records_sheet.dart';

final consistencyProvider =
    FutureProvider.autoDispose<Map<DateTime, double>>((ref) async {
  final room = ref.watch(activeRoomProvider);
  final userId = SupabaseService.currentUserId;
  if (room == null || userId == null) return {};
  return LogService.getDailyPoints(room.id, userId);
});

class RanksScreen extends ConsumerStatefulWidget {
  const RanksScreen({super.key});

  @override
  ConsumerState<RanksScreen> createState() => _RanksScreenState();
}

class _RanksScreenState extends ConsumerState<RanksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _achDotRoomId;
  Future<bool>? _achDotFuture;

  void _ensureAchDotFuture(String roomId) {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      _achDotFuture = Future.value(false);
      return;
    }
    if (_achDotRoomId == roomId && _achDotFuture != null) return;
    _achDotRoomId = roomId;
    _achDotFuture =
        AchievementService.hasUnreadAchievements(roomId: roomId, userId: uid);
  }

  Future<void> _openAchievementsSheet(String roomId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AchievementsSheet(roomId: roomId),
    );
    if (!mounted) return;
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    setState(() {
      _achDotFuture =
          AchievementService.hasUnreadAchievements(roomId: roomId, userId: uid);
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Refresh data when screen first mounts; zero stale daily_points in DB for this user.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final room = ref.read(activeRoomProvider);
      if (room != null && SupabaseService.currentUserId != null) {
        await ScoreService.checkDailyReset(room.id);
      }
      if (!mounted) return;
      ref.invalidate(leaderboardProvider);
      ref.invalidate(myScoreProvider);
      ref.invalidate(roomScoresProvider);
      ref.invalidate(consistencyProvider);
      ref.invalidate(roomAnalyticsProvider);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(activeRoomProvider);
    ref.listen<int>(achievementUnreadVersionProvider, (prev, next) {
      final r = ref.read(activeRoomProvider);
      final uid = SupabaseService.currentUserId;
      if (r == null || uid == null) return;
      setState(() {
        _achDotRoomId = r.id;
        _achDotFuture =
            AchievementService.hasUnreadAchievements(roomId: r.id, userId: uid);
      });
    });
    if (room != null) {
      _ensureAchDotFuture(room.id);
    }

    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Ranks',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: JarsColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Achievements',
                    onPressed: room == null
                        ? null
                        : () => _openAchievementsSheet(room.id),
                    icon: FutureBuilder<bool>(
                      future: _achDotFuture,
                      builder: (context, snap) {
                        final unread = snap.data == true;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              Icons.workspace_premium_outlined,
                              color: JarsColors.primary,
                            ),
                            if (unread)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE53935),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Exercise records',
                    icon: Icon(
                      Icons.emoji_events_outlined,
                      color: JarsColors.gold,
                    ),
                    onPressed: () {
                      final r = ref.read(activeRoomProvider);
                      if (r == null) return;
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => RoomExerciseRecordsSheet(
                          roomId: r.id,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: JarsColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: JarsColors.primary,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: JarsColors.textPrimary,
                unselectedLabelColor: JarsColors.textTertiary,
                dividerHeight: 0,
                labelStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Leaderboard'),
                  Tab(text: 'Breakdown'),
                  Tab(text: 'Analytics'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _LeaderboardTab(),
                  _BreakdownTab(),
                  RoomAnalyticsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(leaderboardPeriodProvider);
    final leaderboardAsync = ref.watch(leaderboardProvider);
    final room = ref.watch(activeRoomProvider);
    final dailyGoal = room?.dailyGoalPoints;
    final streakMin = room?.streakMinimum;

    return Column(
      children: [
        // Period switcher
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: LeaderboardPeriod.values.map((p) {
              final isSelected = p == period;
              final labels = {
                LeaderboardPeriod.today: 'Today',
                LeaderboardPeriod.week: 'Week',
                LeaderboardPeriod.month: 'Month',
                LeaderboardPeriod.allTime: 'All Time',
              };
              return Expanded(
                child: GestureDetector(
                  onTap: () =>
                      ref.read(leaderboardPeriodProvider.notifier).state = p,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? JarsColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Center(
                      child: Text(
                        labels[p]!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? Colors.white
                              : JarsColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        Expanded(
          child: leaderboardAsync.when(
            data: (entries) {
              if (entries.isEmpty) {
                return Center(
                  child: Text(
                    'No data yet',
                    style: GoogleFonts.inter(
                        color: JarsColors.textSecondary),
                  ),
                );
              }
              final maxScore =
                  entries.isNotEmpty ? entries.first.score : 1.0;
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final d = Duration(
                      milliseconds: (index * 40).clamp(0, 400).toInt());
                  return GestureDetector(
                    onTap: () {
                      final roomId = ref.read(activeRoomProvider)?.id;
                      if (roomId == null) return;
                      final sw = MediaQuery.sizeOf(context).width;
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        constraints: BoxConstraints(maxWidth: sw),
                        builder: (_) => SizedBox(
                          width: sw,
                          child: MemberProfileSheet(
                            userId: entry.userId,
                            username: entry.username,
                      totalScore: entry.totalScore,
                            streak: entry.streak,
                            roomId: roomId,
                          ),
                        ),
                      );
                    },
                    child: LeaderboardRow(
                      // Always display the official (all-time) room rank number.
                      rank: entry.officialRank > 0 ? entry.officialRank : (index + 1),
                      entry: entry,
                      maxScore: maxScore,
                      period: period,
                      dailyGoalPoints: dailyGoal,
                      streakMinimum: streakMin,
                    ),
                  )
                      .animate()
                      .fadeIn(
                          delay: d,
                          duration: 300.ms,
                          curve: Curves.easeOutCubic)
                      .slideX(
                        begin: 0.04,
                        delay: d,
                        duration: 300.ms,
                        curve: Curves.easeOutCubic,
                      );
                },
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: JarsColors.primary),
            ),
            error: (e, _) => Center(
              child: Text('Error: $e'),
            ),
          ),
        ),
      ],
    );
  }
}

class _BreakdownTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreAsync = ref.watch(myScoreProvider);
    final room = ref.watch(activeRoomProvider);

    return scoreAsync.when(
      data: (score) {
        if (score == null) {
          return Center(
            child: Text(
              'Join a room to see your breakdown',
              style: GoogleFonts.inter(color: JarsColors.textSecondary),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              RankProgressArc(totalScore: score.totalScore),
              const SizedBox(height: 24),

              Row(
                children: [
                  _StatBox(
                    label: 'Total Points',
                    value: '${score.totalScore.toInt()}',
                    color: JarsColors.gold,
                  ),
                  const SizedBox(width: 12),
                  _StatBox(
                    label: 'Streak',
                    value: '${score.streakCurrent}',
                    icon: '🔥',
                    color: JarsColors.green,
                  ),
                  const SizedBox(width: 12),
                  _StatBox(
                    label: 'Best Streak',
                    value: '${score.streakHighest}',
                    color: JarsColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Exercise breakdown chart
              if (room != null)
                _ExerciseBreakdownChart(
                  roomId: room.id,
                  userId: score.userId,
                ),

              const SizedBox(height: 24),

              // Consistency calendar — wired to real daily logs
              Consumer(
                builder: (ctx, cRef, _) {
                  final calAsync = cRef.watch(consistencyProvider);
                  return calAsync.when(
                    data: (pts) => ConsistencyCalendar(dailyPoints: pts),
                    loading: () => ConsistencyCalendar(dailyPoints: const {}),
                    error: (_, __) => ConsistencyCalendar(dailyPoints: const {}),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: JarsColors.primary),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final String? icon;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
    this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JarsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JarsColors.border),
        ),
        child: Column(
          children: [
            if (icon != null) Text(icon!, style: const TextStyle(fontSize: 18)),
            Text(
              value,
              style: GoogleFonts.spaceMono(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: JarsColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseBreakdownChart extends StatefulWidget {
  final String roomId;
  final String userId;

  const _ExerciseBreakdownChart({
    required this.roomId,
    required this.userId,
  });

  @override
  State<_ExerciseBreakdownChart> createState() =>
      _ExerciseBreakdownChartState();
}

class _ExerciseBreakdownChartState extends State<_ExerciseBreakdownChart> {
  List<_ExerciseBreakdown> _breakdowns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final logs = await LogService.getUserLogs(
        widget.roomId,
        widget.userId,
        limit: 500,
      );

      final map = <String, double>{};
      for (final log in logs) {
        if (log.isAnyBroadcast) continue;
        map[log.exerciseName] =
            (map[log.exerciseName] ?? 0) + log.pointsEarned;
      }

      final sorted = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      setState(() {
        _breakdowns = sorted
            .take(5)
            .map((e) => _ExerciseBreakdown(e.key, e.value))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 120);

    if (_breakdowns.isEmpty) {
      return Text(
        'Log exercises to see your breakdown',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: JarsColors.textSecondary,
        ),
      );
    }

    final maxVal = _breakdowns.first.points;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Top Exercises',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: JarsColors.textPrimary,
              ),
            ),
            GestureDetector(
              onTap: () {
                final userId = SupabaseService.currentUserId;
                if (userId == null) return;
                final sw = MediaQuery.sizeOf(context).width;
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  constraints: BoxConstraints(maxWidth: sw),
                  builder: (_) => SizedBox(
                    width: sw,
                    child: ExerciseStatsSheet(
                      roomId: widget.roomId,
                      userId: userId,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  Text(
                    'All exercises',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: JarsColors.primary,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: JarsColors.primary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...List.generate(_breakdowns.length, (i) {
          final b = _breakdowns[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      b.name,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: JarsColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${b.points.toInt()} pts',
                      style: GoogleFonts.spaceMono(
                        fontSize: 12,
                        color: JarsColors.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxVal > 0 ? b.points / maxVal : 0,
                    minHeight: 8,
                    backgroundColor: JarsColors.border,
                    valueColor:
                        const AlwaysStoppedAnimation(JarsColors.gold),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _ExerciseBreakdown {
  final String name;
  final double points;
  _ExerciseBreakdown(this.name, this.points);
}
