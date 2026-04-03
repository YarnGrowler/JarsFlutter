import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/log_screen_style.dart';
import '../../core/theme.dart';
import '../../models/exercise.dart';
import '../../models/exercise_log.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/exercise_provider.dart';
import '../../providers/score_provider.dart';
import '../../services/log_service.dart';
import '../../services/score_service.dart';
import '../../services/supabase_service.dart';

class LogHistoryScreen extends ConsumerStatefulWidget {
  const LogHistoryScreen({super.key});

  @override
  ConsumerState<LogHistoryScreen> createState() => _LogHistoryScreenState();
}

class _LogHistoryScreenState extends ConsumerState<LogHistoryScreen> {
  static const _pageSize = 30;

  final List<ExerciseLog> _logs = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchPage();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
            _scroll.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _fetchPage();
    }
  }

  Future<void> _fetchPage() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final userId = SupabaseService.currentUserId!;
      final room = ref.read(activeRoomProvider);

      final rows = await LogService.getUserLogsPaged(
        userId: userId,
        roomId: room?.id,
        page: _page,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          _logs.addAll(rows);
          _hasMore = rows.length == _pageSize;
          _page++;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteLog(ExerciseLog log) async {
    final room = ref.read(activeRoomProvider);
    try {
      await LogService.deleteLog(log.id);
      if (room != null) {
        await ScoreService.subtractPoints(
          roomId: room.id,
          points: log.pointsEarned,
        );
        ref.invalidate(myScoreProvider);
        ref.invalidate(roomScoresProvider);
      }
      if (mounted) {
        setState(() => _logs.remove(log));
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _editLog(ExerciseLog log) {
    final exercises = ref.read(roomExercisesProvider).valueOrNull ?? [];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditLogSheet(
        log: log,
        exercises: exercises,
        onSaved: (updated) async {
          if (mounted) {
            final idx = _logs.indexWhere((l) => l.id == log.id);
            if (idx >= 0) setState(() => _logs[idx] = updated);
          }
        },
      ),
    );
  }

  // Group logs by calendar day
  List<_Section> _buildSections() {
    final sections = <_Section>[];
    DateTime? curDay;
    List<ExerciseLog> cur = [];

    for (final log in _logs) {
      final day = DateTime(
          log.createdAt.toLocal().year,
          log.createdAt.toLocal().month,
          log.createdAt.toLocal().day);
      if (curDay == null || day != curDay) {
        if (cur.isNotEmpty) sections.add(_Section(day: curDay!, logs: cur));
        curDay = day;
        cur = [log];
      } else {
        cur.add(log);
      }
    }
    if (cur.isNotEmpty && curDay != null) {
      sections.add(_Section(day: curDay, logs: cur));
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections();

    return Scaffold(
      backgroundColor: kLogNearBlack,
      appBar: AppBar(
        backgroundColor: kLogNearBlack,
        foregroundColor: kLogText,
        title: Text(
          'My Logs',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: kLogText,
          ),
        ),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _logs.isEmpty && !_loading
          ? _EmptyState()
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: sections.length + (_loading ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == sections.length) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: kLogPurple),
                    ),
                  );
                }
                final section = sections[i];
                return _SectionWidget(
                  section: section,
                  onDelete: _deleteLog,
                  onEdit: _editLog,
                );
              },
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _Section {
  final DateTime day;
  final List<ExerciseLog> logs;
  _Section({required this.day, required this.logs});
}

class _SectionWidget extends StatelessWidget {
  final _Section section;
  final Future<void> Function(ExerciseLog) onDelete;
  final void Function(ExerciseLog) onEdit;

  const _SectionWidget({
    required this.section,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String label;
    if (section.day == today) {
      label = 'Today';
    } else if (section.day == yesterday) {
      label = 'Yesterday';
    } else {
      label =
          '${_weekday(section.day.weekday)}, ${_month(section.day.month)} ${section.day.day}';
    }

    final dayPts =
        section.logs.fold(0.0, (s, l) => s + l.pointsEarned);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(),
              Text(
                '+${dayPts.toStringAsFixed(0)} pts',
                style: GoogleFonts.spaceMono(
                  fontSize: 12,
                  color: kLogGold.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        ...section.logs.map(
          (log) => _LogRow(
            log: log,
            onDelete: () => onDelete(log),
            onEdit: () => onEdit(log),
          ),
        ),
      ],
    );
  }

  static const _days = [
    '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];
  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _weekday(int d) => _days[d];
  String _month(int m) => _months[m];
}

class _LogRow extends StatelessWidget {
  final ExerciseLog log;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _LogRow({
    required this.log,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${log.createdAt.toLocal().hour.toString().padLeft(2, '0')}:'
        '${log.createdAt.toLocal().minute.toString().padLeft(2, '0')}';

    return Dismissible(
      key: ValueKey(log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withValues(alpha: 0.85),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return true;
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onEdit,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kLogSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Exercise icon / letter
              _ExerciseIcon(name: log.exerciseName),
              const SizedBox(width: 12),
              // Name + details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      log.exerciseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kLogText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${log.count} reps'
                      '${log.weight > 0 ? ' · ${log.weight.toStringAsFixed(0)} lbs' : ''}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              // Points + time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+${log.pointsEarned.toStringAsFixed(0)} pts',
                    style: GoogleFonts.spaceMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kLogGold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeStr,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseIcon extends StatelessWidget {
  final String name;
  const _ExerciseIcon({required this.name});

  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty
        ? String.fromCharCode(name.runes.first).toUpperCase()
        : '?';
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kLogPurple.withValues(alpha: 0.22),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: kLogPurple,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📋', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'No logs yet',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start logging exercises to see your history',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Edit bottom sheet
// ──────────────────────────────────────────────────────────────────────────────

class _EditLogSheet extends ConsumerStatefulWidget {
  final ExerciseLog log;
  final List<Exercise> exercises;
  final Future<void> Function(ExerciseLog updated) onSaved;

  const _EditLogSheet({
    required this.log,
    required this.exercises,
    required this.onSaved,
  });

  @override
  ConsumerState<_EditLogSheet> createState() => _EditLogSheetState();
}

class _EditLogSheetState extends ConsumerState<_EditLogSheet> {
  late int _count;
  late double _weight;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _count = widget.log.count;
    _weight = widget.log.weight;
  }

  Exercise? get _exercise {
    return widget.exercises
        .where((e) => e.name == widget.log.exerciseName)
        .firstOrNull;
  }

  double get _pts {
    final ex = _exercise;
    if (ex != null) {
      return ex.calculatePoints(_count, _weight > 0 ? _weight : null);
    }
    return widget.log.pointsEarned;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final newPts = _pts;
      await LogService.updateLog(
        widget.log.id,
        count: _count,
        weight: _weight,
        pointsEarned: newPts,
      );

      // Adjust room score
      final room = ref.read(activeRoomProvider);
      if (room != null) {
        final diff = newPts - widget.log.pointsEarned;
        if (diff > 0) {
          await ScoreService.addPoints(
            roomId: room.id,
            points: diff,
            streakMinimum: room.streakMinimum,
          );
        } else if (diff < 0) {
          await ScoreService.subtractPoints(
            roomId: room.id,
            points: -diff,
          );
        }
        ref.invalidate(myScoreProvider);
        ref.invalidate(roomScoresProvider);
      }

      final updated = ExerciseLog(
        id: widget.log.id,
        roomId: widget.log.roomId,
        userId: widget.log.userId,
        exerciseId: widget.log.exerciseId,
        exerciseName: widget.log.exerciseName,
        count: _count,
        weight: _weight,
        pointsEarned: newPts,
        createdAt: widget.log.createdAt,
        username: widget.log.username,
      );

      await widget.onSaved(updated);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111118),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            widget.log.exerciseName,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: kLogText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_pts.toStringAsFixed(0)} pts',
            style: GoogleFonts.spaceMono(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kLogGold,
            ),
          ),
          const SizedBox(height: 24),

          // Reps
          Text(
            'Reps',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _CounterBtn(
                icon: Icons.remove,
                onTap: () {
                  if (_count > 1) setState(() => _count--);
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Center(
                  child: Text(
                    '$_count',
                    style: GoogleFonts.spaceMono(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: kLogText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _CounterBtn(
                icon: Icons.add,
                onTap: () => setState(() => _count++),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Weight (only if exercise supports it)
          if (_exercise?.supportsWeight ?? widget.log.weight > 0) ...[
            Text(
              'Weight (lbs)',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _CounterBtn(
                  icon: Icons.remove,
                  onTap: () {
                    if (_weight >= 5) setState(() => _weight -= 5);
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Center(
                    child: Text(
                      _weight == 0 ? '—' : '${_weight.toStringAsFixed(0)} lbs',
                      style: GoogleFonts.spaceMono(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _weight > 0 ? kLogGold : Colors.white38,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _CounterBtn(
                  icon: Icons.add,
                  onTap: () => setState(() => _weight += 5),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kLogPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Save Changes',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CounterBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: kLogSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: kLogText, size: 20),
      ),
    );
  }
}
