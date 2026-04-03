import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/group_goal.dart';
import '../../providers/goal_provider.dart';
import '../../providers/score_provider.dart';
import '../../providers/streak_provider.dart';

class StatusBar extends ConsumerWidget {
  final VoidCallback? onLogTap;

  const StatusBar({super.key, this.onLogTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(currentStreakProvider);
    final scoreAsync = ref.watch(myScoreProvider);
    final goalProgressAsync = ref.watch(groupGoalProgressProvider);

    return Container(
      decoration: const BoxDecoration(
        color: JarsColors.surface,
        border: Border(
          top: BorderSide(color: JarsColors.border, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          goalProgressAsync.when(
            data: (data) => data != null
                ? _GroupGoalProgressStrip(progress: data)
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (streak > 0) ...[
                  Text('🔥', style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    '$streak',
                    style: GoogleFonts.spaceMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: JarsColors.green,
                    ),
                  ),
                  _divider(),
                ],
                scoreAsync.when(
                  data: (score) {
                    final daily = score?.dailyPoints ?? 0;
                    return Text(
                      'Today: ${daily.toInt()} pts',
                      style: GoogleFonts.spaceMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: JarsColors.textSecondary,
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const Spacer(),
                if (onLogTap != null)
                  GestureDetector(
                    onTap: onLogTap,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: JarsColors.primary,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        '+ Log',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: 1,
        height: 14,
        color: JarsColors.border,
      ),
    );
  }
}

class _GroupGoalProgressStrip extends StatelessWidget {
  final GroupGoalProgress progress;

  const _GroupGoalProgressStrip({required this.progress});

  @override
  Widget build(BuildContext context) {
    final g = progress.goal;
    final p = progress;
    final desc = (g.description ?? '').trim();
    final title = desc.isEmpty ? 'Group goal' : desc;
    final pct = (p.progress * 100).clamp(0, 100).round();
    final fill = p.progress.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: JarsColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: GoogleFonts.spaceMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: JarsColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: JarsColors.background,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: JarsColors.border, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fill,
                heightFactor: 1,
                child: Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(9999)),
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF2DD4BF),
                        Color(0xFF0D9488),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${p.earnedRounded} / ${g.targetPoints} pts · '
            '${p.pointsRemaining} pts to go · '
            '${g.daysRemaining} days left',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: JarsColors.textTertiary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
