import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/league.dart';
import '../../models/siege.dart';

/// Compact league summary for the room home — division, your position, and this
/// week's live match. Taps through to the full League tab.
class LeagueMiniCard extends StatelessWidget {
  final LeagueTable table;
  final VoidCallback? onTap;
  const LeagueMiniCard({super.key, required this.table, this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = table.division;
    final you = table.yourRow;
    final teams = table.standings.length;
    final pos = you?.position ?? 0;
    final fixtures = table.live != null;
    final live = table.live;

    final subtitle = table.preseason
        ? 'Campaign starts Monday'
        : pos > 0
            ? '$pos${_ord(pos)} of $teams · '
                '${fixtures ? '${you!.wins}-${you.draws}-${you.losses}' : '${you!.pointsFor} pts'}'
            : 'New season · matchweek 1';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JarsColors.surface,
          borderRadius: BorderRadius.circular(JarsRadius.card),
          border: Border.all(color: d.color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: d.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: d.color.withValues(alpha: 0.5)),
              ),
              alignment: Alignment.center,
              child: Text(d.icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.displayName(table.theme),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        table.preseason
                            ? 'PREP'
                            : 'MW ${(table.completedWeeks + 1).clamp(1, table.matchweeks)}/${table.matchweeks}',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: JarsColors.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: JarsColors.textSecondary),
                  ),
                  if (table.preseason) ...[
                    const SizedBox(height: 6),
                    Text(
                      '⚒️ Stockpile supply for Matchweek 1',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: JarsColors.textSecondary),
                    ),
                  ] else if (table.siege != null) ...[
                    const SizedBox(height: 8),
                    _siegeLine(table.siege!),
                  ] else if (live != null) ...[
                    const SizedBox(height: 6),
                    _liveLine(live),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded,
                color: JarsColors.textTertiary, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _siegeLine(SiegeWeekState siege) {
    final frac = (siege.integrity / 100.0).clamp(0.0, 1.0);
    final c = frac > 0.6
        ? JarsColors.green
        : (frac > 0.3 ? JarsColors.gold : JarsColors.red);
    final res = siege.result;
    final label = res == null
        ? 'Day ${(siege.daysResolved + 1).clamp(1, 7)} · vs ${siege.plan.opponentName}'
        : (res.won
            ? '🏆 Held vs ${siege.plan.opponentName}'
            : '💥 Fell — next siege Monday');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🛡', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 7,
                  backgroundColor: JarsColors.background,
                  valueColor: AlwaysStoppedAnimation<Color>(c),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${siege.integrity.round()}',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w800, color: c)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
              fontSize: 12, color: JarsColors.textSecondary),
        ),
      ],
    );
  }

  Widget _liveLine(LiveFixture live) {
    final leading = live.yourScore > live.opponentScore;
    final level = live.yourScore == live.opponentScore;
    final c = leading
        ? JarsColors.green
        : (level ? JarsColors.gold : JarsColors.red);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'This week  ${live.yourScore}–${live.opponentScore}  vs ${live.opponent.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceMono(
                fontSize: 12, color: JarsColors.textSecondary),
          ),
        ),
      ],
    );
  }

  String _ord(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }
}
