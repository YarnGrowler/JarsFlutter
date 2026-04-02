import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/extensions.dart';
import '../../core/level_data.dart';
import '../../models/exercise_log.dart';
import 'reaction_row.dart';

class FeedCard extends StatelessWidget {
  final ExerciseLog log;
  final double? userTotalScore;
  final List<String> reactions;
  final ValueChanged<String>? onReact;

  const FeedCard({
    super.key,
    required this.log,
    this.userTotalScore,
    this.reactions = const [],
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final level = userTotalScore != null
        ? getLevelForScore(userTotalScore!)
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('⚔️ ', style: const TextStyle(fontSize: 16)),
              Expanded(
                child: Text(
                  log.username ?? 'Unknown',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.textPrimary,
                  ),
                ),
              ),
              Text(
                log.createdAt.timeAgo,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: JarsColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${log.count} ${log.exerciseName}${log.weight > 0 ? ' · ${log.weight.toInt()} lbs' : ''}',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: JarsColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '+${log.pointsEarned.toStringAsFixed(1)} pts',
                style: GoogleFonts.spaceMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: JarsColors.gold,
                ),
              ),
              if (level != null) ...[
                const SizedBox(width: 8),
                Text(
                  '→  ${level.icon} ${level.title}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: level.color,
                  ),
                ),
              ],
            ],
          ),
          if (onReact != null) ...[
            const SizedBox(height: 10),
            ReactionRow(
              reactions: reactions,
              onReact: onReact!,
            ),
          ],
        ],
      ),
    );
  }
}
