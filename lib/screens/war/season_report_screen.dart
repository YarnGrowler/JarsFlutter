import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/war_providers.dart';
import '../../war/war_game.dart';

/// Shown once the season's final war (7, by default) ends — the crew's
/// whole W-L record, the final standings, and the promotion/relegation
/// outcome, before anyone can start the next season. Captured once, like
/// [BattleReportScreen] — a teammate elsewhere confirming the season
/// (or logging a workout, or anything else that mutates [WarGame]) can't
/// yank these numbers out from under whoever's still reading them.
class SeasonReportScreen extends ConsumerStatefulWidget {
  const SeasonReportScreen({super.key});

  @override
  ConsumerState<SeasonReportScreen> createState() =>
      _SeasonReportScreenState();
}

class _SeasonReportScreenState extends ConsumerState<SeasonReportScreen> {
  bool _captured = false;
  int _seasonIndex = 0;
  List<bool?> _results = const [];
  dynamic _table; // LeagueTable — kept dynamic to match this screen family's
  // existing style (war_hub_screen's _ladder does the same).
  bool? _promotion;

  void _captureOnce(WarGame g) {
    if (_captured) return;
    _captured = true;
    _seasonIndex = g.seasonIndex;
    _results = List<bool?>.of(g.seasonResults);
    _table = g.buildTable();
    _promotion = g.seasonPromotionPreview;
  }

  @override
  void initState() {
    super.initState();
    // Read, not watch: this screen must never react to later state changes —
    // that's the whole point of the snapshot below.
    _captureOnce(ref.read(warGameProvider));
  }

  @override
  Widget build(BuildContext context) {
    // A cold deep-link can mount this screen before the room's remote state
    // has finished loading. Keep trying on each rebuild until real data
    // shows up — the instant it does, this screen never looks live again.
    if (!_captured) {
      _captureOnce(ref.watch(warGameProvider));
    }
    final table = _table;
    if (table == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final wins = _results.where((r) => r == true).length;
    final losses = _results.where((r) => r == false).length;
    final draws = _results.where((r) => r == null).length;
    final division = table.division;
    final theme = table.theme;
    final position = table.yourRow?.position;

    final promoted = _promotion == true;
    final relegated = _promotion == false;

    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                onPressed: () => context.go('/war'),
              ),
              Text('SEASON ${_seasonIndex + 1} COMPLETE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: JarsColors.textPrimary)),
            ]),
            const SizedBox(height: 8),
            Center(
              child: Column(children: [
                Text(promoted ? '⬆' : (relegated ? '⬇' : '➡'),
                    style: const TextStyle(fontSize: 54)),
                Text(
                    promoted
                        ? 'PROMOTED!'
                        : (relegated ? 'RELEGATED' : 'HOLDING STEADY'),
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: promoted
                            ? JarsColors.green
                            : (relegated ? JarsColors.red : JarsColors.primary))),
                const SizedBox(height: 6),
                Text(
                    '$wins-$losses${draws > 0 ? '-$draws' : ''} this season · '
                    'finished #${position ?? '-'} in ${division.displayName(theme) as String}',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: JarsColors.textSecondary)),
              ]),
            ),
            const SizedBox(height: 20),
            Text('EVERY WAR THIS SEASON',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: JarsColors.textTertiary)),
            const SizedBox(height: 8),
            _warChips(),
            const SizedBox(height: 20),
            Text('FINAL STANDINGS',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: JarsColors.textTertiary)),
            const SizedBox(height: 8),
            _standings(table),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _btn('🏁 START NEXT SEASON', JarsColors.gold, () {
                WarGame.instance.startNextSeason();
                context.go('/war');
              }, dark: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _warChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < _results.length; i++)
          Builder(builder: (_) {
            final r = _results[i];
            final color = r == true
                ? JarsColors.green
                : (r == false ? JarsColors.red : JarsColors.textTertiary);
            final label = r == true ? 'W' : (r == false ? 'L' : '–');
            return Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            );
          }),
      ],
    );
  }

  Widget _standings(dynamic table) {
    final total = table.standings.length as int;
    final promote = table.promoteCount as int;
    final relegate = table.relegateCount as int;
    final divColor = table.division.color as Color;

    return Column(
      children: [
        for (final s in table.standings)
          Builder(builder: (_) {
            final pos = s.position as int;
            final inPromo = pos <= promote;
            final inDrop = pos > total - relegate;
            final zone = inPromo
                ? JarsColors.green
                : inDrop
                    ? JarsColors.red
                    : null;
            final diff = s.diff as int;
            return Container(
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: s.isYou
                    ? JarsColors.primary.withValues(alpha: 0.14)
                    : JarsColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: s.isYou
                        ? JarsColors.primary.withValues(alpha: 0.55)
                        : JarsColors.border),
              ),
              child: Row(children: [
                Container(
                  width: 3.5,
                  height: 34,
                  decoration: BoxDecoration(
                    color: zone ?? Colors.transparent,
                    borderRadius:
                        const BorderRadius.horizontal(left: Radius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 22,
                  child: Text('$pos',
                      style: GoogleFonts.spaceMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: zone ?? JarsColors.textSecondary)),
                ),
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(s.name as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13.5,
                              fontWeight:
                                  s.isYou ? FontWeight.w800 : FontWeight.w600,
                              color: JarsColors.textPrimary)),
                    ),
                    if (s.isYou) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: divColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('YOU',
                            style: GoogleFonts.inter(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: divColor)),
                      ),
                    ],
                  ]),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${s.wins}-${s.losses}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.spaceMono(
                          fontSize: 11.5, color: JarsColors.textSecondary)),
                ),
                SizedBox(
                  width: 40,
                  child: Text(diff > 0 ? '+$diff' : '$diff',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.spaceMono(
                          fontSize: 11,
                          color: diff > 0
                              ? JarsColors.green
                              : diff < 0
                                  ? JarsColors.red
                                  : JarsColors.textTertiary)),
                ),
                SizedBox(
                  width: 34,
                  child: Text('${s.leaguePoints}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: s.isYou
                              ? JarsColors.primary
                              : JarsColors.textPrimary)),
                ),
                const SizedBox(width: 10),
              ]),
            );
          }),
      ],
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap, {bool dark = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dark ? color : color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: dark ? 1 : 0.6)),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: dark ? Colors.black : color)),
        ),
      );
}
