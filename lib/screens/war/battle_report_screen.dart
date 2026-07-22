import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/war_providers.dart';
import '../../war/war_base.dart';
import '../../war/war_engine.dart';
import '../../war/war_game.dart';
import '../../war/war_player.dart';
import '../../war/war_sim.dart';
import '../../war/war_types.dart';
import 'war_replay_viewer.dart';

/// The multi-factor battle report — the verdict, both clans' numbers, the MVP,
/// the tiebreak reasoning, and the raid feed with full replays.
class BattleReportScreen extends ConsumerWidget {
  const BattleReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(warGameProvider);
    final v = g.lastVerdict;
    final won = v?.winner == WarSide.you;
    final mvp = _mvp(g);

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
              Text('BATTLE REPORT',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: JarsColors.textPrimary)),
            ]),
            const SizedBox(height: 8),
            Center(
              child: Column(children: [
                Text(won ? '🏆' : (v?.winner == null ? '🤝' : '🏴'),
                    style: const TextStyle(fontSize: 54)),
                Text(v?.headline ?? 'WAR OVER',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: won
                            ? JarsColors.gold
                            : (v?.winner == null ? JarsColors.primary : JarsColors.red))),
              ]),
            ),
            const SizedBox(height: 16),
            _clanCard(g, WarSide.you),
            const SizedBox(height: 10),
            _clanCard(g, WarSide.enemy),
            const SizedBox(height: 16),
            if (mvp != null) _mvpCard(g, mvp),
            const SizedBox(height: 16),
            _topRaiders(g),
            const SizedBox(height: 16),
            if (v != null && v.reasons.isNotEmpty) ...[
              Text('THE VERDICT',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: JarsColors.textTertiary)),
              const SizedBox(height: 6),
              for (final r in v.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $r',
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: JarsColors.textSecondary)),
                ),
            ],
            const SizedBox(height: 16),
            // the war is OVER — both bases lie open, and the whole story plays
            Row(children: [
              Expanded(
                child: _bigChip(
                  label: '▶ FULL WAR REPLAY',
                  color: JarsColors.gold,
                  onTap: () => _watchChronicle(context, g),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _bigChip(
                  label: '🗺 THEIR BASE',
                  color: JarsColors.red,
                  onTap: () => _viewBase(context, g, WarSide.enemy),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _bigChip(
                  label: '🏰 YOUR BASE',
                  color: JarsColors.primary,
                  onTap: () => _viewBase(context, g, WarSide.you),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            if (g.feed.isNotEmpty) ...[
              Text('RAID LOG · tap ▶ to watch the battle',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: JarsColors.textTertiary)),
              const SizedBox(height: 6),
              for (final e in g.feed.reversed.take(12))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                          '${e.attackerSide == WarSide.you ? '🔵' : '🔴'} ${e.line}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 11.5, color: JarsColors.textTertiary)),
                    ),
                    if (e.replay != null && e.replay!.isNotEmpty)
                      GestureDetector(
                        onTap: () => _watchRaid(context, g, e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: JarsColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(
                                color: JarsColors.primary.withValues(alpha: 0.5)),
                          ),
                          child: Text('▶ WATCH',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: JarsColors.textPrimary)),
                        ),
                      ),
                  ]),
                ),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                g.nextWar();
                context.go('/war');
              },
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: JarsColors.gold,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('➡ NEXT WAR',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _watchRaid(BuildContext context, WarGame g, WarLogEntry e) {
    // your clan's raids hit the ENEMY base; theirs hit yours. Once the war is
    // DECIDED there is nothing left to hide — no fog on any replay.
    final over = g.phase == WarPhase.results;
    final base = e.attackerSide == WarSide.you ? g.enemyBase : g.youBase;
    WarReplayViewer.show(context,
        base: base,
        frames: e.replay!,
        fog: !over && e.attackerSide == WarSide.you ? g.youIntel : null,
        title:
            '${e.attackerSide == WarSide.you ? '🔵' : '🔴'} ${e.attackerName}\'s raid');
  }

  /// The WAR, twice over: one continuous TIMELAPSE per base — every raid on
  /// it, chronological, start to finish, with title-card beats in between.
  void _watchChronicle(BuildContext context, WarGame g) {
    List<RaidFrame> timelapse(WarSide attacker) {
      final frames = <RaidFrame>[];
      for (final e in g.feed) {
        if (e.attackerSide != attacker) continue;
        if (e.replay == null || e.replay!.isEmpty) continue;
        // a title-card beat: hold the incoming raid's first frame
        final first = e.replay!.first;
        frames.add(RaidFrame(const [], first.structs, const [], const [],
            '— ${e.attackerName} attacks —',
            graves: first.graves));
        frames.addAll(e.replay!);
      }
      return frames;
    }

    final siege = timelapse(WarSide.you);
    final defense = timelapse(WarSide.enemy);
    final entries = <ReplayEntry>[
      if (siege.isNotEmpty)
        ReplayEntry(
            base: g.enemyBase,
            frames: siege,
            title: '⚔ The siege of ${g.enemyClanName} — the whole war'),
      if (defense.isNotEmpty)
        ReplayEntry(
            base: g.youBase,
            frames: defense,
            title: '🛡 Your Crew holds the line — the whole war'),
    ];
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No replays recorded this war — raid more!')));
      return;
    }
    WarReplayViewer.showChronicle(context, entries: entries);
  }

  /// Post-war base tour: the whole board, no fog, EVERYTHING revealed — even
  /// the mines and teslas they never got to spring.
  void _viewBase(BuildContext context, WarGame g, WarSide side) {
    final base = side == WarSide.you ? g.youBase : g.enemyBase;
    final structs = <RaidStruct>[
      for (var r = 0; r < Base.rows; r++)
        for (var c = 0; c < Base.cols; c++)
          if (base.structAt(r, c) != null && base.structAt(r, c)!.alive)
            RaidStruct(r, c, base.structAt(r, c)!.type,
                base.structAt(r, c)!.hp / base.structAt(r, c)!.maxHp),
    ];
    WarReplayViewer.show(context,
        base: base,
        frames: [RaidFrame(const [], structs, const [], const [], '')],
        title: side == WarSide.you
            ? '🏰 Your base — after the war'
            : '🗺 Their base — fully revealed');
  }

  Widget _bigChip(
      {required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: JarsColors.textPrimary)),
          ),
        ),
      ),
    );
  }

  /// Everyone who fought, BOTH clans, best first — the honest ladder.
  List<WarPlayer> _ranked(WarGame g) {
    final all = [...g.youClan, ...g.enemyClan];
    all.sort((a, b) => b.destructionDealt.compareTo(a.destructionDealt));
    return all;
  }

  WarPlayer? _mvp(WarGame g) {
    final all = _ranked(g);
    if (all.isEmpty) return null;
    return all.first.destructionDealt > 0 ? all.first : null;
  }

  /// 🥇🥈🥉 + the full TOP RAIDERS table across both clans.
  Widget _topRaiders(WarGame g) {
    final all = _ranked(g).where((p) => p.destructionDealt > 0).toList();
    if (all.isEmpty) return const SizedBox.shrink();
    const medals = ['🥇', '🥈', '🥉'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TOP RAIDERS · both clans',
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: JarsColors.textTertiary)),
        const SizedBox(height: 6),
        for (var i = 0; i < all.length && i < 8; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(
                  width: 26,
                  child: Text(i < 3 ? medals[i] : '${i + 1}.',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: i < 3 ? 15 : 12,
                          fontWeight: FontWeight.w800,
                          color: JarsColors.textSecondary))),
              Text(all[i].side == WarSide.you ? '🔵' : '🔴',
                  style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(all[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: i < 3 ? FontWeight.w700 : FontWeight.w400,
                        color: JarsColors.textPrimary)),
              ),
              Text('${all[i].destructionDealt.round()}% ',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: all[i].side == WarSide.you
                          ? const Color(0xFF2E6BE6)
                          : const Color(0xFFE6483F))),
              Text(
                  '· ${all[i].troopsLost} lost · ${all[i].resourcesSpent.round()}⚡',
                  style: GoogleFonts.inter(
                      fontSize: 10.5, color: JarsColors.textTertiary)),
            ]),
          ),
      ],
    );
  }

  Widget _clanCard(WarGame g, WarSide side) {
    final you = side == WarSide.you;
    final clan = you ? g.youClan : g.enemyClan;
    final dealt = you ? g.youDestruction : g.enemyDestruction;
    final razed = you ? g.enemyBase.allCastlesRazed : g.youBase.allCastlesRazed;
    final lost = clan.fold<int>(0, (a, p) => a + p.troopsLost);
    final spent = clan.fold<double>(0, (a, p) => a + p.resourcesSpent);
    final c = you ? const Color(0xFF2E6BE6) : const Color(0xFFE6483F);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(you ? '🔵 YOUR CREW' : '🔴 ${g.enemyClanName.toUpperCase()}',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w800, color: c)),
            const Spacer(),
            if (razed)
              Text('STRONGHOLD RAZED',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, fontWeight: FontWeight.w800, color: JarsColors.gold)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _stat('Destruction dealt', '${dealt.round()}%'),
            _stat('Troops lost', '$lost'),
            _stat('Points spent', spent.round().toString()),
          ]),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: JarsColors.textPrimary)),
            Text(label,
                style: GoogleFonts.inter(fontSize: 10, color: JarsColors.textTertiary)),
          ],
        ),
      );

  Widget _mvpCard(WarGame g, WarPlayer mvp) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [JarsColors.gold.withValues(alpha: 0.18), JarsColors.surface],
        ),
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.gold.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Text(mvp.emoji, style: const TextStyle(fontSize: 30)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '⭐ WAR MVP · ${mvp.side == WarSide.you ? '🔵' : '🔴'} ${mvp.name}',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: JarsColors.textPrimary)),
            Text(
                'Dealt ${mvp.destructionDealt.round()}% — the most of ANYONE in this war, either side',
                style: GoogleFonts.inter(
                    fontSize: 12, color: JarsColors.textSecondary)),
          ],
        ),
      ]),
    );
  }
}
