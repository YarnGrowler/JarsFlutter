import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/war_providers.dart';
import '../../war/war_game.dart';
import '../../war/war_types.dart';

/// The Clan War hub — status, your crew + who you're controlling, the phase
/// action (build / fast-forward / report), controls, and the season ladder.
class WarHubScreen extends ConsumerStatefulWidget {
  const WarHubScreen({super.key});

  @override
  ConsumerState<WarHubScreen> createState() => _WarHubScreenState();
}

class _WarHubScreenState extends ConsumerState<WarHubScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // opening the hub is a "login" moment — catch the war up to real time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(warGameProvider).syncToWallClock();
    });
    // then keep it alive while you watch: each second may cross an hour
    // boundary and land a fresh enemy raid, and the countdown ticks down
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final g = ref.read(warGameProvider);
      if (g.phase == WarPhase.war) {
        g.syncToWallClock();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // real crew, real foes: whenever your room's membership resolves (or
    // changes — a friend joins, someone leaves), the war reseats itself; the
    // shared war state syncs to/from Supabase the same way
    ref.watch(warRoomSyncProvider);
    // a teammate's save beat ours to the server — we adopted theirs instead
    // of silently losing it. Say so, once, briefly.
    ref.listen<WarGame>(warGameProvider, (prev, next) {
      if ((prev?.syncConflicts ?? 0) < next.syncConflicts) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⚡ A teammate just updated the base — refreshed.'),
          duration: Duration(seconds: 3),
        ));
      }
    });
    final g = ref.watch(warGameProvider);
    final table = g.buildTable();
    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _header(g, table),
            const SizedBox(height: 14),
            _assaultBars(g),
            const SizedBox(height: 16),
            _phaseCard(context, g),
            const SizedBox(height: 16),
            _crewStrip(g),
            const SizedBox(height: 16),
            _controls(context, g),
            const SizedBox(height: 18),
            _ladder(g, table),
          ],
        ),
      ),
    );
  }

  Widget _header(WarGame g, dynamic table) {
    final phaseLabel = g.phase == WarPhase.prep
        ? 'PREPARATION'
        : (g.phase == WarPhase.war ? 'WAR · ${g.clock.label}' : 'RESULTS');
    return Row(
      children: [
        const Text('⚔️', style: TextStyle(fontSize: 30)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CLAN WAR',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: JarsColors.textPrimary)),
              Text(
                  'S${g.seasonIndex + 1} · War ${g.warIndex + 1} vs ${g.enemyClanName} · ${table.division.displayName(table.theme)}',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: JarsColors.textSecondary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: (g.phase == WarPhase.war ? JarsColors.red : JarsColors.primary)
                .withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
                color: (g.phase == WarPhase.war ? JarsColors.red : JarsColors.primary)
                    .withValues(alpha: 0.5)),
          ),
          child: Text(phaseLabel,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: JarsColors.textPrimary)),
        ),
      ],
    );
  }

  Widget _assaultBars(WarGame g) {
    Widget bar(String label, double pct, Color c, String sub) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: JarsColors.textSecondary)),
              const Spacer(),
              Text('${pct.round()}%',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w800, color: c)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 9,
                backgroundColor: JarsColors.surface,
                valueColor: AlwaysStoppedAnimation<Color>(c),
              ),
            ),
            const SizedBox(height: 2),
            Text(sub,
                style: GoogleFonts.inter(fontSize: 10, color: JarsColors.textTertiary)),
          ],
        );
    return Row(
      children: [
        Expanded(
            child: bar('YOUR ASSAULT', g.youDestruction, const Color(0xFF2E6BE6),
                'damage to enemy stronghold')),
        const SizedBox(width: 16),
        Expanded(
            child: bar('ENEMY ASSAULT', g.enemyDestruction, const Color(0xFFE6483F),
                'damage to your stronghold')),
      ],
    );
  }

  Widget _phaseCard(BuildContext context, WarGame g) {
    switch (g.phase) {
      case WarPhase.prep:
        return _card(
          accent: JarsColors.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BUILD THE STRONGHOLD',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: JarsColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                  'Place your castle and spend points on walls, traps and towers. '
                  'Your crew and the enemy are fortifying too.',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: JarsColors.textSecondary)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _btn('🛠 BUILD BASE', JarsColors.primary,
                        () => context.go('/war/build'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _btn('🎖 TRAIN', JarsColors.gold,
                        () => context.go('/war/train'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _btn(
                        '⚔ START WAR',
                        g.anyCastlePlaced && g.canControlWar
                            ? JarsColors.gold
                            : JarsColors.textTertiary,
                        () {
                          if (!g.canControlWar) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Only the room admin can start the war.')));
                          } else if (!g.anyCastlePlaced) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Nobody has placed a castle yet — build one first.')));
                          } else {
                            g.startWar();
                          }
                        },
                        dark: g.anyCastlePlaced && g.canControlWar)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _btn(
                        '🎯 DRILL — practice-raid your own base',
                        const Color(0xFF9B6BFF),
                        () => context.go('/war/battle?mode=practice'))),
              ]),
            ],
          ),
        );
      case WarPhase.war:
        return _card(
          accent: JarsColors.red,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('THE WAR RAGES',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: JarsColors.textPrimary)),
                const Spacer(),
                Text('⏱ ${g.clock.label}',
                    style: GoogleFonts.spaceMono(
                        fontSize: 13, color: JarsColors.textSecondary)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _btn(
                        g.liveAttack != null ? '⚔ RESUME RAID' : '⚔ RAID ENEMY',
                        JarsColors.gold, () {
                  if (g.knockedOut(g.active)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            '💀 Your castle has fallen — spectate, or switch to a living fighter.')));
                    return;
                  }
                  if (g.liveAttack == null && g.active.armyTotal == 0) {
                    // no army, no raid — straight to the Training Grounds
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content:
                            Text('Your army is empty — train troops first.')));
                    context.go('/war/train');
                    return;
                  }
                  context.go('/war/battle?mode=attack');
                }, dark: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: _btn('🎖 TRAIN', JarsColors.gold,
                        () => context.go('/war/train'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _btn('🛡 DEFENSE', JarsColors.primary,
                        () => context.go('/war/battle?mode=defense'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _btn('🎯 DRILL', const Color(0xFF9B6BFF),
                        () => context.go('/war/battle?mode=practice'))),
              ]),
              if (g.liveAttack != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      '⚠ Raid in progress — ${g.liveAttack!.troops.length} troops on the field. Nothing is lost until you END RAID.',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: JarsColors.gold)),
                ),
              const SizedBox(height: 12),
              _warClockCard(g),
              if (g.canControlWar) ...[
                const SizedBox(height: 8),
                Text('SKIP AHEAD · testing',
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: JarsColors.textTertiary)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                      child: _btn('+1h', JarsColors.surface,
                          () => g.advanceHours(1))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _btn('+6h', JarsColors.surface,
                          () => g.advanceHours(6))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _btn('End Day', JarsColors.surface,
                          () => g.advanceToEndOfDay())),
                ]),
              ],
              if (g.feed.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('WAR FEED',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: JarsColors.textTertiary)),
                const SizedBox(height: 4),
                for (final e in g.feed.reversed.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${e.attackerSide == WarSide.you ? '🔵' : '🔴'} ${e.line}',
                      style: GoogleFonts.inter(
                          fontSize: 11.5, color: JarsColors.textSecondary),
                    ),
                  ),
              ],
            ],
          ),
        );
      case WarPhase.results:
        final v = g.lastVerdict;
        final won = v?.winner == WarSide.you;
        return _card(
          accent: won ? JarsColors.gold : JarsColors.red,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v?.headline ?? 'WAR OVER',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: won ? JarsColors.gold : JarsColors.red)),
              const SizedBox(height: 6),
              Text(
                  'You razed ${g.youDestruction.round()}% · they razed ${g.enemyDestruction.round()}%',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: JarsColors.textSecondary)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _btn('📜 BATTLE REPORT', JarsColors.primary,
                        () => context.go('/war/report'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _btn('➡ NEXT WAR', JarsColors.gold, () => g.nextWar(),
                        dark: true)),
              ]),
            ],
          ),
        );
    }
  }

  Widget _crewStrip(WarGame g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('PLAYING AS',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: JarsColors.textTertiary)),
          const Spacer(),
          Text(
              g.roomId != null
                  ? 'long-press a crewmate to donate ⚡'
                  : 'tap to control · long-press to donate ⚡',
              style: GoogleFonts.inter(fontSize: 10, color: JarsColors.textTertiary)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: g.youClan.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final p = g.youClan[i];
              final active = p.id == g.activePlayerId;
              final canGift = p.id != g.activePlayerId &&
                  !g.knockedOut(g.active) &&
                  g.resourcesOf(g.activePlayerId) >= 1;
              return GestureDetector(
                onTap: () => g.switchActive(p.id),
                onLongPress: canGift
                    ? () => _showDonateSheet(context, g, p)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? Color(p.colorValue).withValues(alpha: 0.22)
                        : JarsColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: active ? Color(p.colorValue) : JarsColors.border,
                        width: active ? 2 : 1),
                  ),
                  child: Row(children: [
                    Text(g.phase == WarPhase.war && g.knockedOut(p)
                            ? '💀'
                            : p.emoji,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(p.name,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: JarsColors.textPrimary)),
                        Text('⚡ ${g.resourcesOf(p.id).round()}',
                            style: GoogleFonts.spaceMono(
                                fontSize: 11, color: JarsColors.gold)),
                      ],
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showDonateSheet(
      BuildContext context, WarGame g, dynamic teammate) async {
    final maxAmt = g.resourcesOf(g.activePlayerId).floor();
    if (maxAmt < 1) return;
    var amount = (maxAmt / 4).clamp(1, maxAmt).floor().toDouble();
    final err = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: JarsColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 20 + MediaQuery.of(ctx).padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Donate ⚡ to ${teammate.name}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: JarsColors.textPrimary)),
                const SizedBox(height: 4),
                Text('From ${g.active.name} · you have $maxAmt⚡',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: JarsColors.textTertiary)),
                const SizedBox(height: 16),
                Row(children: [
                  Text('${amount.round()}⚡',
                      style: GoogleFonts.spaceMono(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: JarsColors.gold)),
                  const Spacer(),
                  TextButton(
                      onPressed: () => setLocal(() => amount = 1),
                      child: const Text('Min')),
                  TextButton(
                      onPressed: () =>
                          setLocal(() => amount = (maxAmt / 2).floorToDouble()),
                      child: const Text('Half')),
                  TextButton(
                      onPressed: () =>
                          setLocal(() => amount = maxAmt.toDouble()),
                      child: const Text('All')),
                ]),
                Slider(
                  value: amount.clamp(1, maxAmt.toDouble()),
                  min: 1,
                  max: maxAmt.toDouble(),
                  divisions: maxAmt > 1 ? maxAmt - 1 : null,
                  activeColor: JarsColors.gold,
                  onChanged: (v) => setLocal(() => amount = v.roundToDouble()),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: JarsColors.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      final e =
                          g.donateResources(teammate.id as String, amount);
                      Navigator.pop(ctx, e ?? 'ok');
                    },
                    child: Text('Send ${amount.round()}⚡',
                        style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
    if (!context.mounted || err == null) return;
    if (err == 'ok') {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent ⚡ to ${teammate.name}')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Widget _controls(BuildContext context, WarGame g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('ENEMY DIFFICULTY',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: JarsColors.textTertiary)),
          if (!g.canControlWar) ...[
            const SizedBox(width: 5),
            Icon(Icons.lock_rounded, size: 11, color: JarsColors.textTertiary),
          ],
          const Spacer(),
          Text(
              '${g.difficulty} · ${AiData.label(g.enemyDifficulty)}'
              '${g.difficulty > 75 ? '+' : ''}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: JarsColors.red)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: g.difficulty.toDouble(),
            min: 1,
            max: 100,
            activeColor:
                g.canControlWar ? JarsColors.red : JarsColors.textTertiary,
            inactiveColor: JarsColors.border,
            // only the room admin sets the difficulty for everyone
            onChanged: g.canControlWar
                ? (v) => g.setDifficulty(v.round())
                : null,
          ),
        ),
        if (!g.canControlWar)
          Text('Only the room admin can change this.',
              style: GoogleFonts.inter(
                  fontSize: 10.5, color: JarsColors.textTertiary)),
        Text(
            'Season: War ${g.warIndex + 1} of ${g.warsPerSeason} · Record '
            '${g.seasonResults.where((w) => w == true).length}W–'
            '${g.seasonResults.where((w) => w == false).length}L',
            style:
                GoogleFonts.inter(fontSize: 11, color: JarsColors.textSecondary)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (g.canControlWar)
              TextButton.icon(
                onPressed: () => context.go('/war/lab'),
                icon: const Icon(Icons.science_rounded, size: 16),
                label: Text('League maps',
                    style: GoogleFonts.inter(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: JarsColors.textTertiary),
              ),
            if (g.canControlWar)
              TextButton.icon(
                onPressed: () => _confirmReset(context, g),
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: Text('Reset season',
                    style: GoogleFonts.inter(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: JarsColors.textTertiary),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context, WarGame g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        title: Text('Reset the season?',
            style: GoogleFonts.spaceGrotesk(color: JarsColors.textPrimary)),
        content: Text('Wipes the ladder and starts a fresh clan war in Bronze.',
            style: GoogleFonts.inter(color: JarsColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text('Reset',
                  style: GoogleFonts.inter(color: JarsColors.red, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) await g.resetSeason();
  }

  Widget _ladder(WarGame g, dynamic table) {
    final total = table.standings.length as int;
    final promote = table.promoteCount as int;
    final relegate = table.relegateCount as int;
    final divColor = table.division.color as Color;

    // header row: #  CLUB  W-L  +/-  PTS
    Widget headerCell(String t, {double? w, bool right = false}) {
      final label = Text(t,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: JarsColors.textTertiary));
      return w == null ? Expanded(child: label) : SizedBox(width: w, child: label);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('CLAN LADDER',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: JarsColors.textTertiary)),
          const Spacer(),
          // the stakes, spelled out — no mystery about who goes up or down
          _zoneKey(JarsColors.green, 'PROMOTION'),
          const SizedBox(width: 10),
          _zoneKey(JarsColors.red, 'DROP'),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(children: [
            headerCell('#', w: 22),
            headerCell('CLUB'),
            headerCell('W-L', w: 44, right: true),
            headerCell('+/–', w: 40, right: true),
            headerCell('PTS', w: 34, right: true),
          ]),
        ),
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
                // the zone rail: a colored spine marking promotion / drop
                Container(
                  width: 3.5,
                  height: 34,
                  decoration: BoxDecoration(
                    color: zone ?? Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(10)),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
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

  static String _fmtDur(Duration d) {
    final s = d.inSeconds;
    if (s >= 3600) {
      return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
    }
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// The living war clock: real time drives the war day, and the crew's raids
  /// land on their own. No button required — the countdown IS the game.
  Widget _warClockCard(WarGame g) {
    final over = g.clock.dayOver;
    final frac = g.clock.dayFraction;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JarsColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JarsColors.red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('⏱', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text('WAR CLOCK',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: JarsColors.textSecondary)),
            const Spacer(),
            Text('hour ${g.clock.hour.toString().padLeft(2, '0')} / 24',
                style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: JarsColors.textPrimary)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: JarsColors.surface,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(JarsColors.red),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            over
                ? 'The war day is done — tap RESULTS to see the verdict.'
                : 'Next raid check in ${_fmtDur(g.untilNextWarHour)}'
                    '  ·  war resolves in ${_fmtDur(g.untilWarEnds)}',
            style: GoogleFonts.inter(
                fontSize: 11, color: JarsColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _zoneKey(Color c, String label) => Row(children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: JarsColors.textTertiary)),
      ]);

  // ── small helpers ────────────────────────────────────────────────────────────
  Widget _card({required Color accent, required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.12), JarsColors.surface],
          ),
          borderRadius: BorderRadius.circular(JarsRadius.card),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: child,
      );

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
                  color: dark ? Colors.black : JarsColors.textPrimary)),
        ),
      );
}
