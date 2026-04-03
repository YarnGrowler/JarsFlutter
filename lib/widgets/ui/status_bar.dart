import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/group_goal.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/score_provider.dart';
import '../../providers/streak_provider.dart';
import '../../services/goal_service.dart';
import '../../services/supabase_service.dart';

class StatusBar extends ConsumerWidget {
  final VoidCallback? onLogTap;
  /// Room admin: tap the group goal strip to open set-goal sheet (Room screen).
  final VoidCallback? onGroupGoalTap;

  const StatusBar({super.key, this.onLogTap, this.onGroupGoalTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(currentStreakProvider);
    final scoreAsync = ref.watch(myScoreProvider);
    final goalProgressAsync = ref.watch(groupGoalProgressProvider);
    final room = ref.watch(activeRoomProvider);
    final uid = SupabaseService.currentUserId;
    final isRoomAdmin =
        room != null && uid != null && uid == room.adminId;

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
                ? _GroupGoalProgressStrip(
                    progress: data,
                    isRoomAdmin: isRoomAdmin,
                    onAdminRowTap: isRoomAdmin ? onGroupGoalTap : null,
                    onCancelGoal: isRoomAdmin
                        ? () async {
                            final g = data.goal;
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: JarsColors.surfaceRaised,
                                title: Text(
                                  'End group goal?',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: JarsColors.textPrimary,
                                  ),
                                ),
                                content: Text(
                                  'Everyone will stop tracking this goal. '
                                  'You can set a new one from room settings.',
                                  style: GoogleFonts.inter(
                                    color: JarsColors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text('Keep goal'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
                                    child: Text(
                                      'End goal',
                                      style: GoogleFonts.inter(
                                        color: JarsColors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true || !context.mounted) return;
                            try {
                              await GoalService.deleteGoal(g.id);
                              ref.invalidate(groupGoalProvider);
                              ref.invalidate(groupGoalProgressProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Group goal ended.',
                                      style: GoogleFonts.inter(),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Could not end goal: $e'),
                                    backgroundColor: JarsColors.red,
                                  ),
                                );
                              }
                            }
                          }
                        : null,
                  )
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
  final bool isRoomAdmin;
  final VoidCallback? onAdminRowTap;
  final VoidCallback? onCancelGoal;

  const _GroupGoalProgressStrip({
    required this.progress,
    required this.isRoomAdmin,
    this.onAdminRowTap,
    this.onCancelGoal,
  });

  @override
  Widget build(BuildContext context) {
    final g = progress.goal;
    final p = progress;
    final desc = (g.description ?? '').trim();
    final title = desc.isEmpty ? 'Group goal' : desc;
    final pct = (p.progress * 100).clamp(0, 100).round();
    final fill = p.progress.clamp(0.0, 1.0);

    final core = Column(
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
    );

    final tappableCore = onAdminRowTap != null
        ? Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAdminRowTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: core,
              ),
            ),
          )
        : core;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tappableCore,
        if (isRoomAdmin && onCancelGoal != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onCancelGoal,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'End group goal',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: JarsColors.red,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: body,
    );
  }
}
