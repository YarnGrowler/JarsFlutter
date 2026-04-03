import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/log_screen_style.dart';
import '../../../models/exercise.dart';

class LogExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final bool selected;
  final VoidCallback onTap;

  const LogExerciseCard({
    super.key,
    required this.exercise,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final letterColor = categoryLetterColor(exercise.category);
    final showEmoji = exerciseIconShowsEmoji(exercise.icon);
    final letter = exercise.name.isNotEmpty
        ? String.fromCharCode(exercise.name.runes.first).toUpperCase()
        : '?';
    final ptsLabel =
        '${exercise.points % 1 == 0 ? exercise.points.toStringAsFixed(0) : exercise.points.toStringAsFixed(1)} pts/rep';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? kLogPurple.withValues(alpha: 0.18)
                : kLogSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? kLogPurple
                  : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 0.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: kLogPurple.withValues(alpha: 0.28),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Icon top-left
                showEmoji
                    ? Text(
                        exercise.icon,
                        style: const TextStyle(fontSize: 22, height: 1),
                      )
                    : Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: letterColor,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          letter,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                      ),

                // Name + pts bottom
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      exercise.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kLogText,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ptsLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: kLogGold.withValues(alpha: 0.85),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
