import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/achievement_unlock_toast_provider.dart';

/// Top “push” when achievements unlock after a log (queues in provider).
class AchievementToastLayer extends ConsumerWidget {
  const AchievementToastLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(achievementUnlockToastProvider);
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    final first = items.first;
    final more = items.length - 1;

    void dismiss() {
      ref.read(achievementUnlockToastProvider.notifier).state =
          items.length > 1 ? items.sublist(1) : null;
    }

    void openRanks() {
      ref.read(achievementUnlockToastProvider.notifier).state = null;
      context.go('/ranks');
    }

    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.paddingOf(context).top + 8,
      child: Material(
        color: Colors.transparent,
        child: _ToastCard(
          line: first.line,
          meta: first.meta,
          moreCount: more,
          onDismiss: dismiss,
          onOpen: openRanks,
        )
            .animate(key: ValueKey(first.line))
            .fadeIn(duration: 220.ms)
            .slideY(
              begin: -0.12,
              end: 0,
              duration: 300.ms,
              curve: Curves.easeOutCubic,
            ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  final String line;
  final String? meta;
  final int moreCount;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  const _ToastCard({
    required this.line,
    this.meta,
    required this.moreCount,
    required this.onDismiss,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JarsColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JarsColors.primary.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏅', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Achievement unlocked · tap for Ranks',
                        style: GoogleFonts.spaceMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: JarsColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        line,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: JarsColors.textPrimary,
                        ),
                      ),
                      if (meta != null && meta!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          meta!,
                          style: GoogleFonts.spaceMono(
                            fontSize: 11,
                            color: JarsColors.textTertiary,
                          ),
                        ),
                      ],
                      if (moreCount > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          '+$moreCount more',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: JarsColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: JarsColors.textTertiary,
              ),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
