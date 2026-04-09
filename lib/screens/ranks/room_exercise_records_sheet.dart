import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/room_exercise_records.dart';
import '../../services/exercise_service.dart';
import '../../services/log_service.dart';

/// Room hall-of-fame: exercises by total points, top 3 people each.
class RoomExerciseRecordsSheet extends StatefulWidget {
  final String roomId;

  const RoomExerciseRecordsSheet({super.key, required this.roomId});

  @override
  State<RoomExerciseRecordsSheet> createState() =>
      _RoomExerciseRecordsSheetState();
}

class _RoomExerciseRecordsSheetState extends State<RoomExerciseRecordsSheet> {
  List<ExerciseRoomStats>? _data;
  Map<String, String> _iconByExerciseName = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final exercises = await ExerciseService.getRoomExercises(widget.roomId);
      final iconMap = <String, String>{
        for (final e in exercises) e.name: e.icon,
      };
      final rows = await LogService.getRoomExerciseRecords(roomId: widget.roomId);
      if (mounted) {
        setState(() {
          _iconByExerciseName = iconMap;
          _data = rows;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exercise records',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Top exercises by room points · top 3 per move\n'
                          '(from recent logs; huge rooms may be capped)',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.3,
                            color: JarsColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    color: JarsColors.textSecondary,
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _data = null;
                      });
                      _load();
                    },
                  ),
                ],
              ),
            ),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: JarsColors.primary),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(color: JarsColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else if (_data == null || _data!.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'No workouts logged yet',
                    style: GoogleFonts.inter(color: JarsColors.textSecondary),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: _data!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = _data![i];
                    final icon =
                        _iconByExerciseName[s.exerciseName] ?? '🏋️';
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: JarsColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: JarsColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(icon, style: const TextStyle(fontSize: 26)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  s.exerciseName,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: JarsColors.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '${s.totalRoomPoints.round()} pts',
                                style: GoogleFonts.spaceMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: JarsColors.gold,
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 36, top: 10),
                            child: Container(
                              height: 1,
                              color: JarsColors.border.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...List.generate(s.topUsers.length, (j) {
                            final u = s.topUsers[j];
                            final medal = j == 0
                                ? '🥇'
                                : j == 1
                                    ? '🥈'
                                    : '🥉';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: JarsColors.surfaceRaised,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: JarsColors.border,
                                      ),
                                    ),
                                    child: Text(
                                      '#${j + 1}',
                                      style: GoogleFonts.spaceMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: JarsColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    medal,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      u.username,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: JarsColors.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${u.points.round()} pts',
                                    style: GoogleFonts.spaceMono(
                                      fontSize: 12,
                                      color: JarsColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 280.ms, delay: (40 * i).ms)
                        .slideY(
                          begin: 0.05,
                          curve: Curves.easeOutCubic,
                        );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
