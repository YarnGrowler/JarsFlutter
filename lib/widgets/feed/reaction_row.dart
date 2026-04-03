import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/reaction.dart';
import '../../services/supabase_service.dart';

/// Discord-style reactions.
/// - Shows existing reaction chips with counts.
/// - Current user's own reactions are highlighted (active state).
/// - Tap existing chip → toggle off (if yours) or add same emoji.
/// - Tap "+" → bottom sheet grid to pick any emoji.
/// - Multiple distinct emojis per user are allowed.
class ReactionRow extends StatelessWidget {
  /// All reaction objects for this log (including userId info).
  final List<Reaction> reactions;
  final ValueChanged<String> onReact;

  const ReactionRow({
    super.key,
    required this.reactions,
    required this.onReact,
  });

  static Future<void> _openPicker(BuildContext context, ValueChanged<String> onPick) async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JarsColors.surfaceRaised,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EmojiPickerSheet(onPick: (e) {
        Navigator.pop(ctx);
        onPick(e);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = SupabaseService.currentUserId;

    // Group by emoji; track counts and whether current user reacted with this emoji
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
      children: [
        ...sorted.take(8).map((e) {
          return _ReactionChip(
            emoji: e.key,
            count: e.value.count,
            isMine: e.value.isMine,
            onTap: () {
              HapticFeedback.lightImpact();
              onReact(e.key);
            },
          );
        }),
        Material(
          color: JarsColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: () => _openPicker(context, onReact),
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

class _EmojiPickerSheet extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _EmojiPickerSheet({required this.onPick});

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
  '🔥', '💪', '👏', '😤', '💀', '⚔️', '🏆', '⭐',
  '❤️', '😂', '🙌', '👀', '🫡', '🤝', '✨', '🎯',
  '🧊', '🚀', '⏱️', '🥵', '😈', '👑', '🎉', '💯',
  '🫶', '🤌', '🙏', '✅', '❌', '🤔', '😭', '🫠',
];
