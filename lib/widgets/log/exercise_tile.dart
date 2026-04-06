import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/exercise.dart';

class ExerciseTile extends StatelessWidget {
  final Exercise exercise;
  final int? lastCount;
  final bool selected;
  final VoidCallback onTap;

  const ExerciseTile({
    super.key,
    required this.exercise,
    this.lastCount,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? JarsColors.primaryDim : JarsColors.surface,
          borderRadius: BorderRadius.circular(JarsRadius.card),
          border: Border.all(
            color: selected ? JarsColors.primary : JarsColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(exercise.icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            Text(
              exercise.name,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: JarsColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              exercise.pointsPerUnitLabel,
              style: GoogleFonts.spaceMono(
                fontSize: 11,
                color: JarsColors.gold,
              ),
            ),
            if (lastCount != null) ...[
              const SizedBox(height: 2),
              Text(
                'Last: $lastCount',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: JarsColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
