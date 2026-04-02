import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

class StreakIndicator extends StatelessWidget {
  final int streak;
  final double fontSize;

  const StreakIndicator({
    super.key,
    required this.streak,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (streak <= 0) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('🔥', style: TextStyle(fontSize: fontSize)),
        const SizedBox(width: 4),
        Text(
          '$streak',
          style: GoogleFonts.spaceMono(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: JarsColors.green,
          ),
        ),
      ],
    );
  }
}
