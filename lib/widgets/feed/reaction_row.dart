import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/reaction.dart';
import '../../services/supabase_service.dart';

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
    builder: (ctx) => ReactionPickerSheet(
      onPick: (e) {
        Navigator.pop(ctx);
        onPicked(e);
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
    return Material(
      color: isMine
          ? JarsColors.primary.withValues(alpha: 0.25)
          : JarsColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isMine
                  ? JarsColors.primary.withValues(alpha: 0.5)
                  : JarsColors.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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

class ReactionPickerSheet extends StatelessWidget {
  final ValueChanged<String> onPick;

  const ReactionPickerSheet({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
                      onPick(emoji);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
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
