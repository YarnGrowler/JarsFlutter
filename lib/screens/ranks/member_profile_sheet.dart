import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/level_data.dart';
import '../../services/log_service.dart';
import '../../widgets/ranks/consistency_calendar.dart';
import '../../widgets/ui/rank_badge.dart';
import 'exercise_stats_sheet.dart';

class MemberProfileSheet extends StatefulWidget {
  final String userId;
  final String username;
  final double totalScore;
  final int streak;
  final String roomId;

  const MemberProfileSheet({
    super.key,
    required this.userId,
    required this.username,
    required this.totalScore,
    required this.streak,
    required this.roomId,
  });

  @override
  State<MemberProfileSheet> createState() => _MemberProfileSheetState();
}

class _MemberProfileSheetState extends State<MemberProfileSheet> {
  List<_ExerciseStat> _topExercises = [];
  Map<DateTime, double> _dailyPoints = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final logs = await LogService.getUserLogs(
        widget.roomId,
        widget.userId,
        limit: 500,
      );

      // Build daily points map
      final dpMap = <DateTime, double>{};
      final exMap = <String, double>{};
      for (final log in logs) {
        if (log.isAnyBroadcast) continue;
        final day = DateTime(
          log.createdAt.year,
          log.createdAt.month,
          log.createdAt.day,
        );
        dpMap[day] = (dpMap[day] ?? 0) + log.pointsEarned;
        exMap[log.exerciseName] =
            (exMap[log.exerciseName] ?? 0) + log.pointsEarned;
      }

      final sorted = exMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (mounted) {
        setState(() {
          _dailyPoints = dpMap;
          _topExercises =
              sorted.take(5).map((e) => _ExerciseStat(e.key, e.value)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = getLevelForScore(widget.totalScore);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: JarsColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JarsColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  // Header — rank once (badge ring + title), not duplicated
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RankBadge(
                        level: level,
                        size: 48,
                        showTitle: false,
                        totalScore: widget.totalScore,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.username,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: JarsColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              level.title,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: level.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Stats row — equal visual weight
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _StatBox(
                            label: 'Total Points',
                            value: '${widget.totalScore.toInt()}',
                            color: JarsColors.gold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatBox(
                            label: 'Streak',
                            value: '${widget.streak}',
                            icon: '🔥',
                            color: JarsColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Consistency',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${_dailyPoints.length} active days',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: JarsColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConsistencyCalendar(
                      dailyPoints: _dailyPoints,
                      showHeader: false,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Top exercises
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
                      if (!_loading && _topExercises.isNotEmpty)
                        GestureDetector(
                          onTap: () {
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
                                  userId: widget.userId,
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
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: JarsColors.primary,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(
                          color: JarsColors.primary),
                    )
                  else if (_topExercises.isEmpty)
                    Text(
                      'No exercises yet',
                      style: GoogleFonts.inter(
                          color: JarsColors.textSecondary, fontSize: 13),
                    )
                  else
                    ...List.generate(_topExercises.length, (i) {
                      final ex = _topExercises[i];
                      final maxVal = _topExercises.first.points;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ex.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: JarsColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${ex.points.toInt()} pts',
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
                                value: maxVal > 0 ? ex.points / maxVal : 0,
                                minHeight: 6,
                                backgroundColor: JarsColors.border,
                                valueColor: const AlwaysStoppedAnimation(
                                    JarsColors.gold),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseStat {
  final String name;
  final double points;
  _ExerciseStat(this.name, this.points);
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JarsColors.border),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Text(icon!, style: const TextStyle(fontSize: 16)),
          if (icon != null) const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.spaceMono(
              fontSize: 18,
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
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
