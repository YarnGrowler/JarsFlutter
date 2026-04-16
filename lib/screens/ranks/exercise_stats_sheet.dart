import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/count_unit.dart';
import '../../core/log_display.dart';
import '../../core/theme.dart';
import '../../services/log_service.dart';

class ExerciseStatsSheet extends StatefulWidget {
  final String roomId;
  final String userId;

  const ExerciseStatsSheet({
    super.key,
    required this.roomId,
    required this.userId,
  });

  @override
  State<ExerciseStatsSheet> createState() => _ExerciseStatsSheetState();
}

class _ExerciseStatsData {
  final String name;
  /// From the first log seen for this exercise name (reps vs time).
  final CountUnit unit;
  int totalCount = 0;
  double totalPoints = 0;
  int personalBest = 0; // max count (reps / sec / min) in a single log
  double personalBestWeight = 0; // heaviest weight logged for this exercise
  int sessions = 0;

  _ExerciseStatsData(this.name, this.unit);
}

class _ExerciseStatsSheetState extends State<ExerciseStatsSheet> {
  List<_ExerciseStatsData> _stats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Load a large batch (up to 1000 logs)
      final logs = await LogService.getUserLogsPaged(
        userId: widget.userId,
        roomId: widget.roomId,
        page: 0,
        pageSize: 1000,
      );

      final map = <String, _ExerciseStatsData>{};
      for (final log in logs) {
        if (log.isAnyBroadcast || log.isRoomStimulus) continue;
        final name = log.exerciseName;
        map.putIfAbsent(
          name,
          () => _ExerciseStatsData(name, log.effectiveCountUnit),
        );
        final stat = map[name]!;
        stat.totalCount += log.count;
        stat.totalPoints += log.pointsEarned;
        stat.sessions++;
        if (log.count > stat.personalBest) stat.personalBest = log.count;
        if (log.weight > stat.personalBestWeight) {
          stat.personalBestWeight = log.weight;
        }
      }

      final sorted = map.values.toList()
        ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

      if (mounted) {
        setState(() {
          _stats = sorted;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'All Exercises',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: JarsColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (!_loading)
                    Text(
                      '${_stats.length} exercises',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: JarsColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: JarsColors.primary),
                    )
                  : _stats.isEmpty
                      ? Center(
                          child: Text(
                            'No exercises logged yet',
                            style: GoogleFonts.inter(
                                color: JarsColors.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          itemCount: _stats.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _ExerciseStatRow(stat: _stats[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseStatRow extends StatelessWidget {
  final _ExerciseStatsData stat;

  const _ExerciseStatRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JarsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.name,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: JarsColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(
                label: _totalVolumeLabel(stat.unit),
                value: _formatTotalVolume(stat),
                color: JarsColors.textPrimary,
              ),
              _BestSetStat(
                unit: stat.unit,
                bestCount: stat.personalBest,
                bestWeightLb: stat.personalBestWeight,
              ),
              _MiniStat(
                label: 'Sessions',
                value: '${stat.sessions}',
                color: JarsColors.primary,
              ),
              _MiniStat(
                label: 'Points',
                value: '${stat.totalPoints.toInt()}',
                color: JarsColors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _totalVolumeLabel(CountUnit u) {
  switch (u) {
    case CountUnit.reps:
      return 'Total reps';
    case CountUnit.seconds:
      return 'Total time';
    case CountUnit.minutes:
      return 'Total minutes';
  }
}

String _formatTotalVolume(_ExerciseStatsData stat) {
  switch (stat.unit) {
    case CountUnit.reps:
      return '${stat.totalCount}';
    case CountUnit.seconds:
      return formatTotalSecondsAsHuman(stat.totalCount);
    case CountUnit.minutes:
      return '${stat.totalCount}';
  }
}

/// Best volume (count) for one log, with heaviest weight underneath when logged.
class _BestSetStat extends StatelessWidget {
  final CountUnit unit;
  final int bestCount;
  final double bestWeightLb;

  const _BestSetStat({
    required this.unit,
    required this.bestCount,
    required this.bestWeightLb,
  });

  static String _lb(double w) {
    if (w % 1 == 0) return '${w.toInt()} lb';
    return '${w.toStringAsFixed(1)} lb';
  }

  String get _bestLine {
    switch (unit) {
      case CountUnit.reps:
        return '$bestCount';
      case CountUnit.seconds:
        return formatSecondsAsHuman(bestCount);
      case CountUnit.minutes:
        return '$bestCount min';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            _bestLine,
            style: GoogleFonts.spaceMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: JarsColors.gold,
            ),
            textAlign: TextAlign.center,
          ),
          if (bestWeightLb > 0)
            Text(
              _lb(bestWeightLb),
              style: GoogleFonts.spaceMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: JarsColors.gold.withValues(alpha: 0.85),
              ),
            ),
          Text(
            'Best set',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: JarsColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.spaceMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: JarsColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
