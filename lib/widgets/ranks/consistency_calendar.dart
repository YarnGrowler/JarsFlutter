import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

class ConsistencyCalendar extends StatelessWidget {
  final Map<DateTime, double> dailyPoints;
  final int weeks;

  const ConsistencyCalendar({
    super.key,
    required this.dailyPoints,
    this.weeks = 8,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startDate = today.subtract(Duration(days: weeks * 7 - 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Consistency',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: JarsColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: List.generate(weeks * 7, (i) {
            final date = startDate.add(Duration(days: i));
            final key = DateTime(date.year, date.month, date.day);
            final points = dailyPoints[key] ?? 0;

            Color color;
            if (points == 0) {
              color = JarsColors.surface;
            } else if (points < 50) {
              color = JarsColors.primary.withValues(alpha: 0.3);
            } else if (points < 150) {
              color = JarsColors.primary.withValues(alpha: 0.6);
            } else {
              color = JarsColors.primary;
            }

            return Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: JarsColors.border,
                  width: 0.5,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
