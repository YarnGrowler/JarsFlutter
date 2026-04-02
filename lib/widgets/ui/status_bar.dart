import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../providers/score_provider.dart';
import '../../providers/streak_provider.dart';

class StatusBar extends ConsumerWidget {
  final VoidCallback? onLogTap;

  const StatusBar({super.key, this.onLogTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(currentStreakProvider);
    final scoreAsync = ref.watch(myScoreProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: JarsColors.surface,
        border: Border(
          top: BorderSide(color: JarsColors.border, width: 0.5),
        ),
      ),
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
