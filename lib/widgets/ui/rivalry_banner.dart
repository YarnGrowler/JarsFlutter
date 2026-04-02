import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/score.dart';

class RivalryBanner extends StatelessWidget {
  final Score myScore;
  final List<Score> allScores;
  final VoidCallback? onLogTap;

  const RivalryBanner({
    super.key,
    required this.myScore,
    required this.allScores,
    this.onLogTap,
  });

  @override
  Widget build(BuildContext context) {
    final message = _generateMessage();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarsColors.border),
      ),
      child: Row(
        children: [
          const Text('👀', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.title,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.textPrimary,
                  ),
                ),
                if (message.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    message.subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: JarsColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onLogTap != null)
            GestureDetector(
              onTap: onLogTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: JarsColors.primary,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  'Log now',
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

  _RivalryMessage _generateMessage() {
    final sorted = List<Score>.from(allScores)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    final myIndex = sorted.indexWhere((s) => s.userId == myScore.userId);

    if (myScore.dailyPoints == 0) {
      final othersLogged = allScores.where((s) =>
          s.userId != myScore.userId && s.dailyPoints > 0);
      if (othersLogged.isNotEmpty) {
        return _RivalryMessage(
          title: "You haven't logged yet. Everyone else has.",
          subtitle: null,
        );
      }
      return _RivalryMessage(
        title: 'No one has logged today.',
        subtitle: 'Be the first to strike.',
      );
    }

    if (myIndex == 0) {
      if (sorted.length > 1) {
        final second = sorted[1];
        final gap = (myScore.totalScore - second.totalScore).toInt();
        return _RivalryMessage(
          title: "You're leading. ${second.username ?? 'Someone'} is $gap pts behind.",
          subtitle: "Don't let up.",
        );
      }
      return _RivalryMessage(
        title: "You're in first place.",
        subtitle: 'Keep pushing.',
      );
    }

    final ahead = sorted[myIndex - 1];
    final gap = (ahead.totalScore - myScore.totalScore).toInt();
    return _RivalryMessage(
      title: '${ahead.username ?? 'Someone'} is $gap pts ahead of you',
      subtitle: null,
    );
  }
}

class _RivalryMessage {
  final String title;
  final String? subtitle;
  const _RivalryMessage({required this.title, this.subtitle});
}
