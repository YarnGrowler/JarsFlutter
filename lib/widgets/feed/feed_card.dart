import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/log_display.dart';
import '../../core/theme.dart';
import '../../core/extensions.dart';
import '../../core/level_data.dart';
import '../../core/wake_quips.dart';
import '../../models/exercise_log.dart';
import '../../models/reaction.dart';
import 'reaction_row.dart';

/// Chips on the left, purple **React** pinned on the right (always below body text).
Widget _feedReactionBar(
  BuildContext context, {
  required List<Reaction> reactions,
  required ValueChanged<String>? onReact,
  double top = 10,
}) {
  if (onReact == null) return const SizedBox.shrink();
  return Padding(
    padding: EdgeInsets.only(top: top),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: reactions.isNotEmpty
              ? ReactionChipStrip(reactions: reactions, onReact: onReact)
              : const SizedBox.shrink(),
        ),
        PurpleReactButton(
          onPressed: () => showReactionEmojiPicker(context, onReact),
        ),
      ],
    ),
  );
}

class FeedCard extends StatelessWidget {
  final ExerciseLog log;
  final double? userTotalScore;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;
  final VoidCallback? onWakeNudge;

  const FeedCard({
    super.key,
    required this.log,
    this.userTotalScore,
    this.reactions = const [],
    this.onReact,
    this.onWakeNudge,
  });

  @override
  Widget build(BuildContext context) {
    if (log.isMemberJoin) {
      return _MemberJoinCard(log: log);
    }
    if (log.isMemberKick) {
      return _MemberKickCard(log: log);
    }
    if (log.isAiBroadcast) {
      if (log.isAiReply) {
        return _AiReplyCard(log: log, reactions: reactions, onReact: onReact);
      }
      return _AiPostCard(log: log, reactions: reactions, onReact: onReact);
    }
    if (log.isRankUpBroadcast) {
      return _RankUpCard(
        log: log,
        reactions: reactions,
        onReact: onReact,
      );
    }
    if (log.isOvertake) {
      return _OvertakeCard(log: log, reactions: reactions, onReact: onReact);
    }
    if (log.isStreakMilestone) {
      return _StreakCard(log: log, reactions: reactions, onReact: onReact);
    }
    if (log.isPersonalRecord) {
      return _PrCard(log: log, reactions: reactions, onReact: onReact);
    }
    if (log.isDeadStreak) {
      return _DeadCard(log: log, reactions: reactions, onReact: onReact);
    }
    if (log.isFirstLog) {
      return _FirstLogCard(log: log, reactions: reactions, onReact: onReact);
    }
    if (log.isCloseGap) {
      return _CloseGapCard(log: log, reactions: reactions, onReact: onReact);
    }
    if (log.isWakeCard) {
      return _WakeCard(log: log, onNudge: onWakeNudge);
    }

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
            formatExerciseLogQuantityLine(log),
            style: GoogleFonts.inter(
              fontSize: 14,
              color: JarsColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                '+${log.pointsEarned.toStringAsFixed(1)} pts',
                style: GoogleFonts.spaceMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: JarsColors.gold,
                ),
              ),
              if (level != null)
                Text(
                  '→  ${level.icon} ${level.title}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: level.color,
                  ),
                ),
            ],
          ),
          _feedReactionBar(
            context,
            reactions: reactions,
            onReact: onReact,
          ),
        ],
      ),
    );
  }
}

// ─── Room member join / kick (system feed) ─────────────────────────────────────

class _MemberJoinCard extends StatelessWidget {
  final ExerciseLog log;
  const _MemberJoinCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final body = log.broadcastPayload ?? 'Someone joined';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👋 ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(
              body,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: JarsColors.textSecondary,
                height: 1.35,
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
    );
  }
}

class _MemberKickCard extends StatelessWidget {
  final ExerciseLog log;
  const _MemberKickCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final body = log.broadcastPayload ?? 'Someone was removed';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⛔ ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(
              body,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: JarsColors.textSecondary,
                height: 1.35,
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
    );
  }
}

// ─── AI feed cards ────────────────────────────────────────────────────────────

/// Shared header: small Jars label + optional emoji — muted so it doesn't dominate the feed.
Widget _aiHeader(ExerciseLog log) {
  final emoji = log.aiEmoji;

  return Row(
    children: [
      Text(
        'Jars',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: JarsColors.textTertiary,
          letterSpacing: 0.3,
        ),
      ),
      if (emoji != null) ...[
        const SizedBox(width: 6),
        Text(emoji, style: const TextStyle(fontSize: 14)),
      ],
      const Spacer(),
      Text(
        log.createdAt.timeAgo,
        style: GoogleFonts.inter(fontSize: 10, color: JarsColors.textTertiary),
      ),
    ],
  );
}

/// Standalone room-wide AI announcement (milestone, domination, rivalry, cron events).
class _AiPostCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _AiPostCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final text = log.aiText;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(JarsRadius.md),
        border: Border.all(color: JarsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiHeader(log),
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: JarsColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          _feedReactionBar(context, reactions: reactions, onReact: onReact),
        ],
      ),
    );
  }
}

/// AI card generated in direct reaction to a specific person's log.
/// Thread-style: indented in feed, rounded clip so the accent bar matches card corners,
/// collapsible preview for long lines.
class _AiReplyCard extends StatefulWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _AiReplyCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

  @override
  State<_AiReplyCard> createState() => _AiReplyCardState();
}

class _AiReplyCardState extends State<_AiReplyCard> {
  static const double _outerR = JarsRadius.card;
  /// Inner clip: sits just inside the 1px border so corners align visually.
  static const double _innerR = _outerR - 1;

  late bool _expanded;

  @override
  void initState() {
    super.initState();
    final t = widget.log.aiText ?? '';
    final collapsible =
        t.length > 88 || t.contains('\n') || t.split(RegExp(r'\s+')).length > 14;
    _expanded = !collapsible;
  }

  String _replyChipText(ExerciseLog log) {
    final u = log.aiReplyToUsername;
    if (u == null) return '';
    final vol = log.aiReplyToVolumeHuman;
    final ex = log.aiReplyToExercise;
    final reps = log.aiReplyToReps;
    if (vol != null && ex != null && ex.isNotEmpty) return '$u · $vol · $ex';
    if (vol != null) return '$u · $vol';
    if (ex != null && reps != null && reps > 0) return '$u · $ex · ${reps}x';
    if (ex != null) return '$u · $ex';
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final text = log.aiText;
    final isReactOnly = log.isAiReactOnly;
    final hasReplyContext = log.aiReplyToUsername != null;

    final t = text ?? '';
    final canCollapse = !isReactOnly &&
        t.isNotEmpty &&
        (t.length > 88 || t.contains('\n') || t.split(RegExp(r'\s+')).length > 14);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_outerR),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_outerR),
        child: Container(
          decoration: BoxDecoration(
            color: JarsColors.surface,
            borderRadius: BorderRadius.circular(_outerR),
            border: Border.all(
              color: JarsColors.border,
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_innerR),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 3,
                    color: JarsColors.primary.withValues(alpha: 0.14),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Reply target — compact thread label
                          if (hasReplyContext) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.subdirectory_arrow_right_rounded,
                                  size: 14,
                                  color: JarsColors.textTertiary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _replyChipText(log),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      letterSpacing: 0.1,
                                      color: JarsColors.textTertiary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          _aiHeader(log),
                          if (!isReactOnly && t.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            if (canCollapse && !_expanded) ...[
                              Text(
                                t,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: JarsColors.textSecondary,
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () =>
                                      setState(() => _expanded = true),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.only(top: 2),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Show more',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: JarsColors.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              Text(
                                t,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: JarsColors.textSecondary,
                                ),
                              ),
                              if (canCollapse && _expanded)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () =>
                                        setState(() => _expanded = false),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.only(top: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      'Show less',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: JarsColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                          _feedReactionBar(
                            context,
                            reactions: widget.reactions,
                            onReact: widget.onReact,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Rank Up Card ──────────────────────────────────────────────────────────────

class _RankUpCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _RankUpCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

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
          _feedReactionBar(
            context,
            reactions: reactions,
            onReact: onReact,
          ),
        ],
      ),
    );
  }
}

// ─── Overtake Card ─────────────────────────────────────────────────────────────

class _OvertakeCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _OvertakeCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

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
          _feedReactionBar(
            context,
            reactions: reactions,
            onReact: onReact,
          ),
        ],
      ),
    );
  }
}

// ─── Streak Milestone Card ─────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _StreakCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final payload = log.broadcastPayload ?? '';
    final title = payload.isNotEmpty
        ? payload
        : '${log.username ?? 'Someone'} is on a streak';
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🔥 ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text(
                  title,
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
          _feedReactionBar(
            context,
            reactions: reactions,
            onReact: onReact,
          ),
        ],
      ),
    );
  }
}

// ─── Personal Record Card ──────────────────────────────────────────────────────

class _PrCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _PrCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

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
          _feedReactionBar(
            context,
            reactions: reactions,
            onReact: onReact,
          ),
        ],
      ),
    );
  }
}

// ─── Dead Streak Card ──────────────────────────────────────────────────────────

class _DeadCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _DeadCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

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
            _feedReactionBar(
              context,
              reactions: reactions,
              onReact: onReact,
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
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _FirstLogCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚡ ', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payload.isNotEmpty
                          ? payload
                          : '${log.username ?? 'Someone'} just woke up',
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
                style: GoogleFonts.inter(
                    fontSize: 12, color: JarsColors.textTertiary),
              ),
            ],
          ),
          _feedReactionBar(
            context,
            reactions: reactions,
            onReact: onReact,
          ),
        ],
      ),
    );
  }
}

// ─── Close Gap Card ────────────────────────────────────────────────────────────

class _CloseGapCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _CloseGapCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                style: GoogleFonts.inter(
                    fontSize: 12, color: JarsColors.textTertiary),
              ),
            ],
          ),
          _feedReactionBar(
            context,
            reactions: reactions,
            onReact: onReact,
          ),
        ],
      ),
    );
  }
}

// ─── Idle / "wake" ghost card ──────────────────────────────────────────────────

class _WakeCard extends StatelessWidget {
  final ExerciseLog log;
  final VoidCallback? onNudge;

  const _WakeCard({required this.log, this.onNudge});

  String _lastSeenLine(WakeFeedPayload? p) {
    final u = p?.lastSeenUtc;
    if (u == null) return 'No recent workout';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final w = days[u.weekday - 1];
    return 'Last seen $w · Was ranked #${p?.rank ?? 0}';
  }

  @override
  Widget build(BuildContext context) {
    final w = log.wakeFeedPayload;
    final name = log.username ?? 'Teammate';
    final days = w?.days ?? 1;
    final pick = w?.pick ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(
          color: JarsColors.textTertiary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('👻 ', style: TextStyle(fontSize: 18)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name hasn\'t logged in $days ${days == 1 ? 'day' : 'days'}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: JarsColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _lastSeenLine(w),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: JarsColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      WakeQuips.cardSub(pick, name),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: JarsColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
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
          if (onNudge != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onNudge,
                style: FilledButton.styleFrom(
                  foregroundColor: JarsColors.textPrimary,
                  backgroundColor: JarsColors.primary.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(JarsRadius.button),
                  ),
                ),
                child: Text(
                  '👋 Wake them up',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
