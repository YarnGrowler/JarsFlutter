import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/super_reaction_meta.dart';
import '../../core/theme.dart';
import '../../models/reaction.dart';
import '../../models/score.dart';
import '../../providers/score_provider.dart';
import '../../services/supabase_service.dart';
import 'super_reaction_catalog.dart';

/// Opens the curated emoji grid (compact picker, no full “react” chrome).
Future<void> showReactionEmojiPicker(
  BuildContext context,
  ValueChanged<String> onPicked,
) async {
  HapticFeedback.mediumImpact();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: JarsColors.surfaceRaised,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        return ReactionPickerSheet(
          readMyScore: () => ref.read(myScoreProvider.future),
          onPick: (e) {
            Navigator.pop(ctx);
            onPicked(e);
          },
        );
      },
    ),
  );
}

/// Small [+] only (broadcast cards / tight spaces).
class ReactPlusButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ReactPlusButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JarsColors.background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.add_rounded,
            size: 18,
            color: JarsColors.textSecondary.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// Purple “+ React” pill (primary feed control).
class PurpleReactButton extends StatelessWidget {
  final VoidCallback onPressed;

  const PurpleReactButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JarsColors.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: JarsColors.primary),
              const SizedBox(width: 3),
              Text(
                'React',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: JarsColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reaction chips only (counts + toggle). No add pill.
class ReactionChipStrip extends StatelessWidget {
  final List<Reaction> reactions;
  final ValueChanged<String> onReact;

  const ReactionChipStrip({
    super.key,
    required this.reactions,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final myUserId = SupabaseService.currentUserId;
    final emojiMap = <String, _EmojiData>{};
    for (final r in reactions) {
      final data = emojiMap.putIfAbsent(r.emoji, () => _EmojiData());
      data.count++;
      if (r.userId == myUserId) data.isMine = true;
    }
    final sorted = emojiMap.entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));

    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 6,
      runSpacing: 6,
      children: sorted.map((e) {
        return _ReactionChip(
          emoji: e.key,
          count: e.value.count,
          isMine: e.value.isMine,
          onTap: () {
            HapticFeedback.lightImpact();
            onReact(e.key);
          },
        );
      }).toList(),
    );
  }
}

/// Discord-style reactions including a legacy “+ React” chip (avoid in new UI).
class ReactionRow extends StatelessWidget {
  final List<Reaction> reactions;
  final ValueChanged<String> onReact;

  const ReactionRow({
    super.key,
    required this.reactions,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 6,
      runSpacing: 6,
      children: [
        ReactionChipStrip(reactions: reactions, onReact: onReact),
        PurpleReactButton(
          onPressed: () => showReactionEmojiPicker(context, onReact),
        ),
      ],
    );
  }
}

class _EmojiData {
  int count = 0;
  bool isMine = false;
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool isMine;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final superDef = tryParseSuperReaction(emoji);
    return Material(
      color: isMine
          ? JarsColors.primary.withValues(alpha: 0.25)
          : JarsColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: superDef != null ? 8 : 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: superDef != null
                  ? JarsColors.primary.withValues(alpha: isMine ? 0.55 : 0.35)
                  : (isMine
                      ? JarsColors.primary.withValues(alpha: 0.5)
                      : JarsColors.border),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (superDef != null)
                SuperReactionPreview(id: superDef.id, size: 28)
              else
                Text(emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: GoogleFonts.spaceMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isMine
                      ? JarsColors.primary
                      : JarsColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big tappable row so Standard vs Super is obvious in the bottom sheet.
class _SegmentedPickerTab extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentedPickerTab({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? JarsColors.primary.withValues(alpha: 0.18)
          : JarsColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? JarsColors.primary.withValues(alpha: 0.75)
                  : JarsColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? JarsColors.primary
                      : JarsColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: JarsColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReactionPickerSheet extends StatefulWidget {
  /// Reads current user’s room score (from [Consumer] above the sheet).
  final Future<Score?> Function() readMyScore;
  final ValueChanged<String> onPick;

  const ReactionPickerSheet({
    super.key,
    required this.readMyScore,
    required this.onPick,
  });

  @override
  State<ReactionPickerSheet> createState() => _ReactionPickerSheetState();
}

class _ReactionPickerSheetState extends State<ReactionPickerSheet> {
  /// 0 = Standard emoji grid, 1 = Super (point cost).
  int _segment = 0;

  Future<void> _pickSuper(SuperReactionDef def) async {
    final score = await widget.readMyScore();
    if (!mounted) return;
    if (score == null || score.totalScore < def.cost) {
      final have = score?.totalScore.floor() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Need ${def.cost} points to use ${def.label} (you have $have).',
            style: GoogleFonts.inter(),
          ),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        title: Text(
          'Use ${def.label}?',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: JarsColors.textPrimary,
          ),
        ),
        content: Text(
          'Spend ${def.cost} points from your room score. '
          'You currently have ${score.totalScore.toStringAsFixed(0)}.',
          style: GoogleFonts.inter(color: JarsColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Use', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    widget.onPick(def.storageKey);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JarsColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Pick a reaction',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: JarsColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SegmentedPickerTab(
                    label: 'Standard',
                    subtitle: 'Free',
                    selected: _segment == 0,
                    onTap: () => setState(() => _segment = 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SegmentedPickerTab(
                    label: 'Super',
                    subtitle: 'Points',
                    selected: _segment == 1,
                    onTap: () => setState(() => _segment = 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 380,
              child: _segment == 0
                  ? _buildStandardGrid()
                  : _buildSuperGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardGrid() {
    return GridView.builder(
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: kReactionPickerEmojis.length,
      itemBuilder: (_, i) {
        final emoji = kReactionPickerEmojis[i];
        return Material(
          color: JarsColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPick(emoji);
            },
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuperGrid() {
    return GridView.builder(
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: kSuperReactions.length,
      itemBuilder: (_, i) {
        final def = kSuperReactions[i];
        return Material(
          color: JarsColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: JarsColors.border),
          ),
          child: InkWell(
            onTap: () => _pickSuper(def),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SuperReactionPreview(id: def.id, size: 52),
                  const SizedBox(height: 6),
                  Text(
                    def.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: JarsColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.stars_rounded,
                        size: 12,
                        color: JarsColors.primary.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${def.cost} pts',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Curated emoji grid (Discord-like quick reactions).
const kReactionPickerEmojis = [
  '🔥', '💪', '👏', '💀', '🏆', '❤️', '😂', '👀',
  '🤝', '🎯', '🚀', '🥵', '😈', '👑', '🎉', '💯',
  '✅', '❌', '🤔', '😭', '😍', '😮', '😎', '😡',
  '🤯', '👍', '👎', '💥', '🧠', '💩', '🤡', '👻',
];
