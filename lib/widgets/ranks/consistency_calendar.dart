import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

/// GitHub-style contribution graph.
///
/// Layout: weeks as *columns* (oldest left → newest right), days as rows
/// (Mon top → Sun bottom), so time flows left-to-right, top-to-bottom.
///
/// Color intensity is relative — the max-points day gets full opacity so
/// even a light user sees colour. Zero days remain dark.
class ConsistencyCalendar extends StatelessWidget {
  final Map<DateTime, double> dailyPoints;

  /// How many weeks to show (columns). Default 16 ≈ 4 months.
  final int weeks;

  /// When false, the built-in "Consistency" title row is omitted (parent supplies it).
  final bool showHeader;

  const ConsistencyCalendar({
    super.key,
    required this.dailyPoints,
    this.weeks = 16,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    // Start on the Monday of the week [weeks] ago
    final todayWeekday = today.weekday; // 1=Mon … 7=Sun
    final startOfThisWeek =
        today.subtract(Duration(days: todayWeekday - 1));
    final startDate =
        startOfThisWeek.subtract(Duration(days: (weeks - 1) * 7));

    // Build a flat list of [weeks*7] days, left-column-first (Mon→Sun)
    final days = List.generate(
      weeks * 7,
      (i) {
        final col = i ~/ 7; // 0 = oldest week
        final row = i % 7; // 0 = Mon, 6 = Sun
        return startDate.add(Duration(days: col * 7 + row));
      },
    );

    // Relative scaling: find max pts across shown days
    double maxPts = 0;
    for (final d in days) {
      final key = DateTime(d.year, d.month, d.day);
      final v = dailyPoints[key] ?? 0;
      if (v > maxPts) maxPts = v;
    }
    if (maxPts == 0) maxPts = 1; // avoid division by zero

    // Month labels (one per unique month that starts inside our range)
    // We'll overlay them as a header row aligned to columns.
    final monthLabels = <int, String>{}; // column index → label
    for (var col = 0; col < weeks; col++) {
      final d = startDate.add(Duration(days: col * 7));
      if (col == 0 || d.day <= 7) {
        monthLabels[col] = _shortMonth(d.month);
      }
    }

    const cellSize = 13.0;
    const gap = 3.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Consistency',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: JarsColors.textPrimary,
                ),
              ),
              Text(
                '${dailyPoints.length} active days',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: JarsColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // Month header
        SizedBox(
          height: 14,
          child: Row(
            children: List.generate(weeks, (col) {
              final label = monthLabels[col];
              return SizedBox(
                width: cellSize + gap,
                child: label != null
                    ? Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: JarsColors.textTertiary,
                        ),
                      )
                    : null,
              );
            }),
          ),
        ),
        const SizedBox(height: 4),

        // Grid — [weeks] columns × 7 rows
        SizedBox(
          height: 7 * (cellSize + gap) - gap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(weeks, (col) {
              return Padding(
                padding: EdgeInsets.only(right: col < weeks - 1 ? gap : 0),
                child: Column(
                  children: List.generate(7, (row) {
                    final d = days[col * 7 + row];
                    final key = DateTime(d.year, d.month, d.day);
                    final pts = dailyPoints[key] ?? 0;
                    final fraction = pts / maxPts;

                    // Future days — dim placeholder
                    final isFuture = d.isAfter(today);

                    Color cellColor;
                    if (isFuture || pts == 0) {
                      cellColor = JarsColors.surface;
                    } else {
                      // Scale from 0.15 → 1.0 opacity so even light days show
                      final opacity = 0.15 + fraction * 0.85;
                      cellColor =
                          JarsColors.primary.withValues(alpha: opacity);
                    }

                    return Padding(
                      padding: EdgeInsets.only(
                          bottom: row < 6 ? gap : 0),
                      child: Tooltip(
                        message: pts > 0
                            ? '${_dateLabel(d)}: ${pts.toStringAsFixed(0)} pts'
                            : _dateLabel(d),
                        preferBelow: true,
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          decoration: BoxDecoration(
                            color: cellColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 8),

        // Legend
        Row(
          children: [
            Text(
              'Less',
              style: GoogleFonts.inter(
                  fontSize: 10, color: JarsColors.textTertiary),
            ),
            const SizedBox(width: 4),
            ...List.generate(5, (i) {
              final opacity = i == 0 ? 0.0 : 0.15 + (i / 4) * 0.85;
              return Container(
                width: cellSize,
                height: cellSize,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: i == 0
                      ? JarsColors.surface
                      : JarsColors.primary.withValues(alpha: opacity),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
            const SizedBox(width: 4),
            Text(
              'More',
              style: GoogleFonts.inter(
                  fontSize: 10, color: JarsColors.textTertiary),
            ),
          ],
        ),
      ],
    );
  }

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _shortMonth(int m) => _months[m];

  String _dateLabel(DateTime d) =>
      '${_shortMonth(d.month)} ${d.day}';
}
