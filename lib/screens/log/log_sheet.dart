import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/level_data.dart';
import '../../models/exercise.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/exercise_provider.dart';
import '../../providers/score_provider.dart';
import '../../services/log_service.dart';
import '../../services/score_service.dart';
import '../../widgets/log/category_pills.dart';
import '../../widgets/log/exercise_tile.dart';
import '../../widgets/log/swipe_counter.dart';
import '../../widgets/ui/point_counter.dart';
import '../../widgets/ui/rank_badge.dart';

class LogSheet extends ConsumerStatefulWidget {
  const LogSheet({super.key});

  @override
  ConsumerState<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<LogSheet> {
  String? _selectedCategory;
  Exercise? _selectedExercise;
  int _count = 10;
  double _weight = 0;
  bool _logging = false;
  String? _undoLogId;
  double _undoPoints = 0;

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(activeRoomProvider);
    final exercisesAsync = ref.watch(roomExercisesProvider);
    final scoreAsync = ref.watch(myScoreProvider);

    if (room == null) {
      return Scaffold(
        backgroundColor: JarsColors.background,
        body: Center(
          child: Text(
            'Join a room first',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              color: JarsColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header with total score and rank
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: scoreAsync.when(
                data: (score) {
                  final total = score?.totalScore ?? 0;
                  final level = getLevelForScore(total);
                  return Row(
                    children: [
                      Text(
                        'Your total: ',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: JarsColors.textSecondary,
                        ),
                      ),
                      PointCounter(
                        value: total,
                        fontSize: 18,
                        suffix: ' pts',
                      ),
                      const Spacer(),
                      RankBadge(level: level, size: 28),
                    ],
                  );
                },
                loading: () => const SizedBox(height: 28),
                error: (_, __) => const SizedBox(height: 28),
              ),
            ),
            const SizedBox(height: 16),

            // Category pills
            exercisesAsync.when(
              data: (exercises) {
                final categories = exercises
                    .map((e) => e.category)
                    .toSet()
                    .toList()
                  ..sort();
                return CategoryPills(
                  categories: categories,
                  selected: _selectedCategory,
                  onSelected: (cat) => setState(() {
                    _selectedCategory = cat == _selectedCategory ? null : cat;
                    _selectedExercise = null;
                  }),
                );
              },
              loading: () => const SizedBox(height: 38),
              error: (_, __) => const SizedBox(height: 38),
            ),
            const SizedBox(height: 16),

            // Exercise grid or logging zone
            Expanded(
              child: _selectedExercise != null
                  ? _buildLoggingZone()
                  : _buildExerciseGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseGrid() {
    final exercisesAsync = ref.watch(roomExercisesProvider);

    return exercisesAsync.when(
      data: (exercises) {
        final filtered = _selectedCategory != null
            ? exercises.where((e) => e.category == _selectedCategory).toList()
            : exercises;

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.1,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final exercise = filtered[index];
            return ExerciseTile(
              exercise: exercise,
              onTap: () => setState(() {
                _selectedExercise = exercise;
                _count = 10;
                _weight = 0;
              }),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: JarsColors.primary),
      ),
      error: (e, _) => Center(
        child: Text('Error loading exercises',
            style: GoogleFonts.inter(color: JarsColors.textSecondary)),
      ),
    );
  }

  Widget _buildLoggingZone() {
    final exercise = _selectedExercise!;
    final points = exercise.calculatePoints(_count, _weight > 0 ? _weight : null);
    final room = ref.read(activeRoomProvider)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Exercise header
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedExercise = null),
                child: const Icon(Icons.arrow_back_ios,
                    color: JarsColors.textSecondary, size: 20),
              ),
              const SizedBox(width: 8),
              Text(exercise.icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: JarsColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${exercise.points} pts/rep',
                      style: GoogleFonts.spaceMono(
                        fontSize: 12,
                        color: JarsColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Rep counter
          SwipeCounter(
            value: _count,
            onChanged: (v) => setState(() => _count = v),
            min: 1,
            label: 'reps',
          ),
          const SizedBox(height: 24),

          // Weight counter (if applicable)
          if (exercise.supportsWeight) ...[
            SwipeCounter(
              value: _weight.toInt(),
              onChanged: (v) => setState(() => _weight = v.toDouble()),
              min: 0,
              label: 'lbs (optional)',
            ),
            if (_weight > 0 && exercise.weightThreshold != null) ...[
              const SizedBox(height: 8),
              Text(
                '+${((_weight / exercise.weightThreshold!).floor() * (exercise.weightMultiplier ?? 1.0) * _count).toStringAsFixed(1)} pts weight bonus',
                style: GoogleFonts.spaceMono(
                  fontSize: 12,
                  color: JarsColors.primary,
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],

          // Points preview
          Text(
            '= ${points.toStringAsFixed(1)} pts',
            style: GoogleFonts.spaceMono(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: JarsColors.gold,
            ),
          ),
          const SizedBox(height: 32),

          // LOG IT button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _logging
                  ? null
                  : () => _logExercise(exercise, points, room.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: JarsColors.primary,
              ),
              child: _logging
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'LOG IT',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // Undo link
          if (_undoLogId != null)
            GestureDetector(
              onTap: _undoLog,
              child: Text(
                'Undo this log',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: JarsColors.textTertiary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _logExercise(Exercise exercise, double points, String roomId) async {
    setState(() => _logging = true);
    HapticFeedback.mediumImpact();

    try {
      final room = ref.read(activeRoomProvider)!;
      final log = await LogService.insertLog(
        roomId: roomId,
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        count: _count,
        weight: _weight,
        pointsEarned: points,
      );

      await ScoreService.addPoints(
        roomId: roomId,
        points: points,
        streakMinimum: room.streakMinimum,
      );

      ref.invalidate(myScoreProvider);
      ref.invalidate(roomScoresProvider);

      if (mounted) {
        setState(() {
          _undoLogId = log.id;
          _undoPoints = points;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('+${points.toStringAsFixed(1)} pts'),
            duration: const Duration(seconds: 2),
            backgroundColor: JarsColors.surface,
          ),
        );

        Future.delayed(const Duration(seconds: 8), () {
          if (mounted) setState(() => _undoLogId = null);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  Future<void> _undoLog() async {
    if (_undoLogId == null) return;
    final room = ref.read(activeRoomProvider)!;

    try {
      await LogService.deleteLog(_undoLogId!);
      await ScoreService.subtractPoints(
        roomId: room.id,
        points: _undoPoints,
      );

      ref.invalidate(myScoreProvider);
      ref.invalidate(roomScoresProvider);

      if (mounted) {
        setState(() => _undoLogId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Log undone'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error undoing: $e')),
        );
      }
    }
  }
}
