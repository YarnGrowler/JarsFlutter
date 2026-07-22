import 'dart:math' as math;

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
  /// Short celebration pulse on the room feed after you just logged this row.
  final bool pulseFresh;

  const FeedCard({
    super.key,
    required this.log,
    this.userTotalScore,
    this.reactions = const [],
    this.onReact,
    this.onWakeNudge,
    this.pulseFresh = false,
  });

  @override
  Widget build(BuildContext context) {
    if (log.isMemberJoin) {
      return _MemberJoinCard(log: log);
    }
    if (log.isMemberKick) {
      return _MemberKickCard(log: log);
    }
    if (log.isAchievementBroadcast) {
      return _AchievementBatchCard(
        log: log,
        reactions: reactions,
        onReact: onReact,
      );
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
    if (log.isComeback) {
      return _ComebackCard(log: log, reactions: reactions, onReact: onReact);
    }
    if (log.isLeague) {
      return _LeagueCard(log: log, reactions: reactions, onReact: onReact);
    }

    // Normal exercise log card
    final level = userTotalScore != null
        ? getLevelForScore(userTotalScore!)
        : null;

    final inner = Container(
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

    if (pulseFresh) {
      return _FreshFeedPulse(child: inner);
    }
    return inner;
  }
}

/// One-shot glow + scale so a new log feels “landed” on the feed.
class _FreshFeedPulse extends StatefulWidget {
  final Widget child;

  const _FreshFeedPulse({required this.child});

  @override
  State<_FreshFeedPulse> createState() => _FreshFeedPulseState();
}

class _FreshFeedPulseState extends State<_FreshFeedPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        // Peak glow mid-animation, then settle.
        final glow = (t < 0.45 ? t / 0.45 : 1.0 - (t - 0.45) / 0.55).clamp(0.0, 1.0);
        final scale = 1.0 + 0.018 * math.sin(t * math.pi * 3) * (1 - t);
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(JarsRadius.card + 2),
              boxShadow: [
                BoxShadow(
                  color: JarsColors.primary.withValues(alpha: 0.12 + 0.38 * glow),
                  blurRadius: 6 + 22 * glow,
                  spreadRadius: 1.5 * glow,
                ),
                BoxShadow(
                  color: const Color(0xFFB8A8FF).withValues(alpha: 0.08 * glow),
                  blurRadius: 28 * glow,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(JarsRadius.card),
                border: Border.all(
                  width: 1.2 + 1.8 * glow,
                  color: Color.lerp(
                        JarsColors.border,
                        JarsColors.primary,
                        0.25 + 0.55 * glow,
                      ) ??
                      JarsColors.border,
                ),
              ),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
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

/// One feed row for multiple achievement unlocks from a single log (expand for list).
class _AchievementBatchCard extends StatefulWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _AchievementBatchCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

  @override
  State<_AchievementBatchCard> createState() => _AchievementBatchCardState();
}

class _AchievementBatchCardState extends State<_AchievementBatchCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final title = log.achTitle ?? 'Achievements';
    final lines = log.achUnlockLines;
    final singleLine = lines.length == 1 ? (lines.first['line'] as String? ?? '') : '';
    final singleMeta = lines.length == 1 ? (lines.first['meta'] as String?) : null;
    final subtitle = lines.isEmpty
        ? ''
        : lines.length == 1
            ? singleLine
            : '${lines.length} unlocks · tap to expand';

    // Rounded rect + non-uniform border colors: use ClipRRect + uniform outline +
    // left accent strip (BoxDecoration forbids borderRadius with mixed border colors).
    return ClipRRect(
      borderRadius: BorderRadius.circular(JarsRadius.card),
      child: Container(
        decoration: BoxDecoration(
          color: JarsColors.surface,
          border: Border.all(color: JarsColors.border),
        ),
        // Stack (not Row+stretch): ListView gives unbounded height; stretch cannot resolve.
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(
                color: JarsColors.primary.withValues(alpha: 0.9),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: lines.length <= 1
                        ? null
                        : () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🏅 ', style: TextStyle(fontSize: 18)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.1,
                                    color: JarsColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: JarsColors.textPrimary,
                                      height: 1.35,
                                    ),
                                  ),
                                if (lines.length == 1 &&
                                    singleMeta != null &&
                                    singleMeta.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    singleMeta,
                                    style: GoogleFonts.spaceMono(
                                      fontSize: 11,
                                      color: JarsColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (lines.length > 1)
                            Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: JarsColors.textTertiary,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_expanded && lines.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 22, top: 4, bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: lines.map((m) {
                          final line = m['line'] as String? ?? '';
                          final meta = m['meta'] as String?;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: JarsColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (meta != null && meta.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    meta,
                                    style: GoogleFonts.spaceMono(
                                      fontSize: 10,
                                      color: JarsColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  _feedReactionBar(
                    context,
                    reactions: widget.reactions,
                    onReact: widget.onReact,
                    top: 8,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _AiReplyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.log.aiText != widget.log.aiText) {
      _expanded = false;
    }
  }

  /// True only when [text] needs more than two lines at [maxWidth] (same style as body).
  bool _exceedsTwoLines(String text, double maxWidth, TextStyle style) {
    if (text.isEmpty || !maxWidth.isFinite || maxWidth <= 0) return false;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return tp.didExceedMaxLines;
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

    final bodyStyle = GoogleFonts.inter(
      fontSize: 13,
      height: 1.45,
      color: JarsColors.textSecondary,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(_outerR),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: JarsColors.surface,
          borderRadius: BorderRadius.circular(_outerR),
          border: Border.all(color: JarsColors.border, width: 1),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_innerR),
            border: Border(
              left: BorderSide(
                color: JarsColors.primary.withValues(alpha: 0.22),
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(13, 10, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final needsTruncation = _exceedsTwoLines(
                      t,
                      constraints.maxWidth,
                      bodyStyle,
                    );

                    if (!needsTruncation) {
                      return Text(t, style: bodyStyle);
                    }

                    if (!_expanded) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: bodyStyle,
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _expanded = true),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.only(top: 4),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Show more',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: JarsColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t, style: bodyStyle),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _expanded = false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.only(top: 6),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Show less',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: JarsColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
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

// ─── Comeback Card ──────────────────────────────────────────────────────────────

class _ComebackCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _ComebackCard({
    required this.log,
    this.reactions = const [],
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final payload = log.broadcastPayload ?? '';
    final title = payload.isNotEmpty
        ? payload
        : '${log.username ?? 'Someone'} is back — welcome back!';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('👋 ', style: TextStyle(fontSize: 16)),
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

// ─── League Card ────────────────────────────────────────────────────────────────

class _LeagueCard extends StatelessWidget {
  final ExerciseLog log;
  final List<Reaction> reactions;
  final ValueChanged<String>? onReact;

  const _LeagueCard({
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
        border: Border.all(color: JarsColors.gold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🏆 ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text(
                  payload.isNotEmpty ? payload : 'League update',
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
    final welfare = w?.welfare ?? 0;
    final shortName =
        name.trim().isEmpty ? name : name.trim().split(RegExp(r'\s+')).first;

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
                    if (welfare > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        '$shortName got +$welfare room welfare (random stimulus — not a workout log).',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: JarsColors.primary.withValues(alpha: 0.9),
                          height: 1.35,
                        ),
                      ),
                    ],
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
