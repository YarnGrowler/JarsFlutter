import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/extensions.dart';
import '../../core/level_data.dart';
import '../../models/exercise_log.dart';
import '../../models/reaction.dart';
import 'reaction_row.dart';

class FeedCard extends StatelessWidget {
  final ExerciseLog log;
  final double? userTotalScore;
  final List<Reaction> reactions;
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
    if (log.isRankUpBroadcast)    return _RankUpCard(log: log);
    if (log.isOvertake)           return _OvertakeCard(log: log);
    if (log.isStreakMilestone)    return _StreakCard(log: log);
    if (log.isPersonalRecord)     return _PrCard(log: log);
    if (log.isDeadStreak)         return _DeadCard(log: log);
    if (log.isFirstLog)           return _FirstLogCard(log: log);
    if (log.isCloseGap)           return _CloseGapCard(log: log);

    // Normal exercise log card
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
              const Text('💪 ', style: TextStyle(fontSize: 16)),
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
            '${log.count} ${log.exerciseName}${log.weight > 0 ? ' · ${log.weight % 1 == 0 ? log.weight.toInt() : log.weight} lbs' : ''}',
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
          if (onReact != null && reactions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ReactionRow(
              reactions: reactions,
              onReact: onReact!,
            ),
          ] else if (onReact != null) ...[
            const SizedBox(height: 10),
            ReactionRow(
              reactions: const [],
              onReact: onReact!,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Rank Up Card ──────────────────────────────────────────────────────────────

class _RankUpCard extends StatelessWidget {
  final ExerciseLog log;
  const _RankUpCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final title = log.rankUpTitle ?? 'Rank up';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.gold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚔️ ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text(
                  '${log.username ?? 'Someone'} ranked up',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.textPrimary,
                  ),
                ),
              ),
              Text(
                log.createdAt.timeAgo,
                style: GoogleFonts.inter(fontSize: 12, color: JarsColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${log.username ?? 'They'} just hit $title. You falling behind?',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: JarsColors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Overtake Card ─────────────────────────────────────────────────────────────

class _OvertakeCard extends StatelessWidget {
  final ExerciseLog log;
  const _OvertakeCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final payload = log.broadcastPayload ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚔️ ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text(
                  '${log.username ?? 'Someone'} overtook someone',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.textPrimary,
                  ),
                ),
              ),
              Text(
                log.createdAt.timeAgo,
                style: GoogleFonts.inter(fontSize: 12, color: JarsColors.textTertiary),
              ),
            ],
          ),
          if (payload.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              payload,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: JarsColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Streak Milestone Card ─────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  final ExerciseLog log;
  const _StreakCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final payload = log.broadcastPayload ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.green.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: JarsColors.green.withValues(alpha: 0.10),
            blurRadius: 8,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔥 ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text(
                  payload.isNotEmpty ? payload : '${log.username ?? 'Someone'} is on a streak',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.textPrimary,
                  ),
                ),
              ),
              Text(
                log.createdAt.timeAgo,
                style: GoogleFonts.inter(fontSize: 12, color: JarsColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Personal Record Card ──────────────────────────────────────────────────────

class _PrCard extends StatelessWidget {
  final ExerciseLog log;
  const _PrCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final payload = log.broadcastPayload ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.gold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.gold.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💥 ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text(
                  '${log.username ?? 'Someone'} set a new record',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.textPrimary,
                  ),
                ),
              ),
              Text(
                log.createdAt.timeAgo,
                style: GoogleFonts.inter(fontSize: 12, color: JarsColors.textTertiary),
              ),
            ],
          ),
          if (payload.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              payload,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: JarsColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Dead Streak Card ──────────────────────────────────────────────────────────

class _DeadCard extends StatelessWidget {
  final ExerciseLog log;
  const _DeadCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final payload = log.broadcastPayload ?? '';
    return Opacity(
      opacity: 0.75,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(JarsRadius.card),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('💀 ', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Text(
                    payload.isNotEmpty
                        ? payload
                        : "${log.username ?? 'Someone'}'s streak just ended",
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white54,
                    ),
                  ),
                ),
                Text(
                  log.createdAt.timeAgo,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white24),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── First Log of Day Card ─────────────────────────────────────────────────────

class _FirstLogCard extends StatelessWidget {
  final ExerciseLog log;
  const _FirstLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final payload = log.broadcastPayload ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Text('⚡ ', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payload.isNotEmpty ? payload : '${log.username ?? 'Someone'} just woke up',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.textPrimary,
                  ),
                ),
                Text(
                  'First log of the day in the room',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: JarsColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            log.createdAt.timeAgo,
            style: GoogleFonts.inter(fontSize: 12, color: JarsColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ─── Close Gap Card ────────────────────────────────────────────────────────────

class _CloseGapCard extends StatelessWidget {
  final ExerciseLog log;
  const _CloseGapCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final payload = log.broadcastPayload ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Text('👀 ', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              payload.isNotEmpty ? payload : 'Someone is closing the gap',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: JarsColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
          Text(
            log.createdAt.timeAgo,
            style: GoogleFonts.inter(fontSize: 12, color: JarsColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
