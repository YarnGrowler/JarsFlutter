import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/level_data.dart';
import '../../providers/leaderboard_provider.dart';
import '../../services/supabase_service.dart';

class LeaderboardRow extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final double maxScore;
  final LeaderboardPeriod period;
  final int? dailyGoalPoints;

  /// Room streak floor (pts today) — shown for you on Today tab only.
  final int? streakMinimum;

  const LeaderboardRow({
    super.key,
    required this.rank,
    required this.entry,
    required this.maxScore,
    required this.period,
    this.dailyGoalPoints,
    this.streakMinimum,
  });

  /// Bar fill: goal-based when [dailyGoalPoints] is set; otherwise relative to [maxScore].
  double get _barFraction {
    final g = dailyGoalPoints;
    if (g != null && g > 0) {
      switch (period) {
        case LeaderboardPeriod.today:
          return (entry.score / g).clamp(0.0, 1.0);
        case LeaderboardPeriod.week:
          return (entry.score / (g * 7)).clamp(0.0, 1.0);
        case LeaderboardPeriod.month:
          return (entry.score / (g * 30)).clamp(0.0, 1.0);
        case LeaderboardPeriod.allTime:
          break;
      }
    }
    if (maxScore <= 0) return 0.0;
    return (entry.score / maxScore).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isMe = entry.userId == SupabaseService.currentUserId;
    // Always show the user's *official* level based on all-time total score,
    // even when the list is sorted by Today/Week/Month points.
    final level = getLevelForScore(entry.totalScore);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isMe ? JarsColors.primaryDim : JarsColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe
              ? JarsColors.primary.withValues(alpha: 0.4)
              : JarsColors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  style: GoogleFonts.spaceMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: rank <= 3 ? JarsColors.gold : JarsColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.username,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: JarsColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${level.icon} ${level.title}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: level.color,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entry.score.toInt()} pts',
                    style: GoogleFonts.spaceMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: JarsColors.textPrimary,
                    ),
                  ),
                  if (entry.dailyPoints > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '+${entry.dailyPoints.toInt()} today',
                      style: GoogleFonts.spaceMono(
                        fontSize: 11,
                        color: JarsColors.green,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _barFraction,
              minHeight: 4,
              backgroundColor: JarsColors.border,
              valueColor: AlwaysStoppedAnimation(
                isMe ? JarsColors.primary : JarsColors.gold,
              ),
            ),
          ),
          if (isMe &&
              period == LeaderboardPeriod.today &&
              streakMinimum != null &&
              streakMinimum! > 0) ...[
            const SizedBox(height: 6),
            Text(
              entry.score >= streakMinimum!
                  ? 'Streak minimum met for today'
                  : '${(streakMinimum! - entry.score).ceil()} pts to go to keep your streak',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: entry.score >= streakMinimum!
                    ? JarsColors.green
                    : JarsColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
