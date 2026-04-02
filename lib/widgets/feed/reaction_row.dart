import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/reaction.dart';

class ReactionRow extends StatelessWidget {
  final List<String> reactions;
  final ValueChanged<String> onReact;

  const ReactionRow({
    super.key,
    required this.reactions,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: kReactionEmojis.map((emoji) {
        final count = reactions.where((r) => r == emoji).length;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onReact(emoji);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: count > 0
                    ? JarsColors.primaryDim
                    : JarsColors.surfaceRaised,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(
                  color: count > 0 ? JarsColors.primary : JarsColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 12,
                        color: JarsColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
