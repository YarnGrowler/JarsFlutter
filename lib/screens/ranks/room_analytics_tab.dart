import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/room_analytics_provider.dart';
import '../../services/room_analytics_service.dart';
import '../../services/supabase_service.dart';

// ─── Palette for multi-line chart (up to 6 members) ─────────────────────────
const _kLineColors = [
  JarsColors.primary,
  JarsColors.gold,
  JarsColors.green,
  Color(0xFFFF6B6B),
  Color(0xFF4ECDC4),
  Color(0xFFFFD93D),
];

// ─── Root widget ─────────────────────────────────────────────────────────────
class RoomAnalyticsTab extends ConsumerWidget {
  const RoomAnalyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(roomAnalyticsProvider);
    final range = ref.watch(analyticsRangeDaysProvider);

    return async.when(
      data: (snap) {
        if (snap == null) {
          return Center(
            child: Text('Join a room to see analytics',
                style: GoogleFonts.inter(color: JarsColors.textSecondary)),
          );
        }
        return _AnalyticsBody(
          snapshot: snap,
          rangeDays: range,
          onRangeChanged: (d) =>
              ref.read(analyticsRangeDaysProvider.notifier).state = d,
          onRefresh: () async => ref.invalidate(roomAnalyticsProvider),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: JarsColors.primary),
        ),
      ),
      error: (e, _) => Center(
        child: Text('Could not load analytics',
            style: GoogleFonts.inter(color: JarsColors.textSecondary)),
      ),
    );
  }
}

// ─── Body ────────────────────────────────────────────────────────────────────
class _AnalyticsBody extends StatelessWidget {
  final RoomAnalyticsSnapshot snapshot;
  final int rangeDays;
  final ValueChanged<int> onRangeChanged;
  final Future<void> Function() onRefresh;

  const _AnalyticsBody({
    required this.snapshot,
    required this.rangeDays,
    required this.onRangeChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return RefreshIndicator(
      color: JarsColors.primary,
      backgroundColor: JarsColors.surface,
      onRefresh: onRefresh,
      child: ListView(
        clipBehavior: Clip.none,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + bottom),
        children: [
          _RangePills(selected: rangeDays, onSelect: onRangeChanged),
          const SizedBox(height: 20),

          if (!snapshot.hasData) ...[
            _EmptyHint(rangeDays: rangeDays),
          ] else ...[
            _SectionHeader(
              title: 'Leaderboard race',
              subtitle:
                  'Total score over time · workout pts + achievement unlocks on unlock day',
            ),
            const SizedBox(height: 12),
            _MultiLineChart(
              memberSeries: snapshot.memberSeries,
              rangeDays: rangeDays,
              startDay: snapshot.startDay,
            ),
            const SizedBox(height: 8),
            _LineLegend(memberSeries: snapshot.memberSeries),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ─── Range pills ─────────────────────────────────────────────────────────────
class _RangePills extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _RangePills({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const options = [7, 30, 90];
    const labels = {7: '7 days', 30: '30 days', 90: '90 days'};
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JarsColors.border),
      ),
      child: Row(
        children: options.map((d) {
          final sel = d == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: sel ? JarsColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[d]!,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? Colors.white : JarsColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: JarsColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: JarsColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

// ─── Multi-line chart (cumulative leaderboard race) ───────────────────────────
class _MultiLineChart extends StatefulWidget {
  final List<MemberDailySeries> memberSeries;
  final int rangeDays;
  final DateTime startDay;

  const _MultiLineChart({
    required this.memberSeries,
    required this.rangeDays,
    required this.startDay,
  });

  @override
  State<_MultiLineChart> createState() => _MultiLineChartState();
}

class _MultiLineChartState extends State<_MultiLineChart> {
  @override
  Widget build(BuildContext context) {
    final me = SupabaseService.currentUserId;

    double maxY = 10;
    for (final m in widget.memberSeries) {
      for (final v in m.cumulativePoints) {
        if (v > maxY) maxY = v;
      }
    }
    // Extra headroom so lines / gradients don’t hug the top edge; tooltips need room too.
    maxY = (maxY * 1.22).ceilToDouble();
    final interval = _niceInterval(maxY);

    final showEvery = widget.rangeDays <= 14
        ? 1
        : widget.rangeDays <= 35
            ? 5
            : 10;

    final lineBarsData = <LineChartBarData>[];
    for (var mi = 0; mi < widget.memberSeries.length; mi++) {
      final ms = widget.memberSeries[mi];
      final isMe = ms.userId == me;
      final color = _kLineColors[mi % _kLineColors.length];
      final spots = <FlSpot>[];
      for (var i = 0; i < ms.cumulativePoints.length; i++) {
        spots.add(FlSpot(i.toDouble(), ms.cumulativePoints[i]));
      }
      lineBarsData.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.25,
        color: color.withValues(alpha: isMe ? 1.0 : 0.5),
        barWidth: isMe ? 3.0 : 1.8,
        dotData: const FlDotData(show: false),
        belowBarData: isMe
            ? BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.15),
                    color.withValues(alpha: 0.0),
                  ],
                ),
              )
            : BarAreaData(show: false),
      ));
    }

    return Container(
      height: 260,
      padding: const EdgeInsets.only(top: 8, left: 4, right: 10, bottom: 6),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarsColors.border),
      ),
      clipBehavior: Clip.none,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (widget.rangeDays - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: JarsColors.border.withValues(alpha: 0.6),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => JarsColors.surfaceRaised,
              tooltipRoundedRadius: 10,
              // When lines are high, default tooltip sits above the spot and gets clipped.
              fitInsideVertically: true,
              fitInsideHorizontally: true,
              maxContentWidth: 260,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              getTooltipItems: (spots) {
                return spots.map((s) {
                  final mi = s.barIndex;
                  if (mi >= widget.memberSeries.length) return null;
                  final ms = widget.memberSeries[mi];
                  final color = _kLineColors[mi % _kLineColors.length];
                  return LineTooltipItem(
                    '${ms.username}\n',
                    GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color),
                    children: [
                      TextSpan(
                        text: '${s.y.round()} pts',
                        style: GoogleFonts.spaceMono(
                            fontSize: 11, color: JarsColors.textPrimary),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: interval,
                getTitlesWidget: (v, _) => Text(
                  _compact(v),
                  style: GoogleFonts.spaceMono(
                      fontSize: 9, color: JarsColors.textTertiary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (x, _) {
                  final idx = x.toInt();
                  if (idx < 0 || idx >= widget.rangeDays) {
                    return const SizedBox.shrink();
                  }
                  if (idx % showEvery != 0 && idx != widget.rangeDays - 1) {
                    return const SizedBox.shrink();
                  }
                  final d = widget.startDay.add(Duration(days: idx));
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat.Md().format(d),
                      style: GoogleFonts.spaceMono(
                          fontSize: 8, color: JarsColors.textTertiary),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: lineBarsData,
        ),
      ),
    );
  }
}

// ─── Line legend ──────────────────────────────────────────────────────────────
class _LineLegend extends StatelessWidget {
  final List<MemberDailySeries> memberSeries;
  const _LineLegend({required this.memberSeries});

  @override
  Widget build(BuildContext context) {
    final me = SupabaseService.currentUserId;
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (var i = 0; i < memberSeries.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 3,
                decoration: BoxDecoration(
                  color: _kLineColors[i % _kLineColors.length].withValues(
                    alpha: memberSeries[i].userId == me ? 1.0 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                memberSeries[i].username,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: memberSeries[i].userId == me
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: memberSeries[i].userId == me
                      ? JarsColors.textPrimary
                      : JarsColors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────
class _EmptyHint extends StatelessWidget {
  final int rangeDays;
  const _EmptyHint({required this.rangeDays});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarsColors.border),
      ),
      child: Column(
        children: [
          const Text('📊', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 14),
          Text(
            'No data in the last $rangeDays days',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: JarsColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Log some exercises and come back to see the race.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 12, color: JarsColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
double _niceInterval(double maxY) {
  if (maxY <= 0) return 10;
  final raw = maxY / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final nice = (raw / mag).ceil() * mag;
  return nice.clamp(1, double.infinity);
}

String _compact(double v) {
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
  return v.round().toString();
}
