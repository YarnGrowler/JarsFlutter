import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/war_providers.dart';
import '../../war/war_base.dart';
import '../../war/war_biome.dart';
import '../../war/war_engine.dart';
import '../../war/war_game.dart';
import '../../war/war_player.dart';
import '../../war/war_scoring.dart';
import '../../war/war_sim.dart';
import '../../war/war_types.dart';
import 'war_replay_viewer.dart';

/// A frozen read of one player's war performance — captured once, so a
/// teammate advancing to the next war on their own device (or this device's
/// own eventual NEXT WAR tap) can never rewrite the numbers out from under
/// someone still reading this report.
class _ReportPlayer {
  final String name;
  final String emoji;
  final WarSide side;
  final double destructionDealt;
  final int troopsLost;
  final double resourcesSpent;
  const _ReportPlayer({
    required this.name,
    required this.emoji,
    required this.side,
    required this.destructionDealt,
    required this.troopsLost,
    required this.resourcesSpent,
  });
}

/// The multi-factor battle report — the verdict, both clans' numbers, the MVP,
/// the tiebreak reasoning, and the raid feed with full replays.
///
/// Everything shown here is captured ONCE, the first time real data is
/// available, into local state — never read live off [WarGame]. The war's
/// shared state can legitimately change out from under this screen at any
/// moment (a teammate elsewhere tapping NEXT WAR, which pushes a fresh
/// prep-phase state over realtime); without a frozen snapshot, that shared
/// mutation used to yank the verdict, feed, and both bases out from under
/// whoever was still reading the report — including corrupting the replay
/// viewer, which would then render old raid frames against a brand new,
/// unrelated base.
class BattleReportScreen extends ConsumerStatefulWidget {
  const BattleReportScreen({super.key});

  @override
  ConsumerState<BattleReportScreen> createState() => _BattleReportScreenState();
}

class _BattleReportScreenState extends ConsumerState<BattleReportScreen> {
  bool _captured = false;
  WarVerdict? _verdict;
  List<WarLogEntry> _feed = const [];
  late Base _youBase;
  late Base _enemyBase;
  WarBiome _biome = WarBiome.meadow;
  double _youDestruction = 0;
  double _enemyDestruction = 0;
  bool _enemyBaseRazed = false;
  bool _youBaseRazed = false;
  String _enemyClanName = '';
  List<_ReportPlayer> _youClan = const [];
  List<_ReportPlayer> _enemyClan = const [];
  // Garrison (defender) deaths — the honest OTHER half of "who died this
  // war". Raider losses alone (`troopsLost`, above) undercounted casualties
  // by ignoring every defender that fell holding a wall.
  int _enemyGarrisonLost = 0; // their defenders, killed by YOUR raids
  int _youGarrisonLost = 0; // your defenders, killed by THEIR raids

  _ReportPlayer _snap(WarPlayer p) => _ReportPlayer(
        name: p.name,
        emoji: p.emoji,
        side: p.side,
        destructionDealt: p.destructionDealt,
        troopsLost: p.troopsLost,
        resourcesSpent: p.resourcesSpent,
      );

  void _captureOnce(WarGame g) {
    if (_captured) return;
    _captured = true;
    _verdict = g.lastVerdict;
    _feed = List<WarLogEntry>.of(g.feed);
    _youBase = g.youBase;
    _enemyBase = g.enemyBase;
    _biome = g.currentBiome;
    _youDestruction = g.youDestruction;
    _enemyDestruction = g.enemyDestruction;
    _enemyBaseRazed = g.enemyBase.allCastlesRazed;
    _youBaseRazed = g.youBase.allCastlesRazed;
    _enemyClanName = g.enemyClanName;
    _youClan = [for (final p in g.youClan) _snap(p)];
    _enemyClan = [for (final p in g.enemyClan) _snap(p)];
    _enemyGarrisonLost = g.enemyGarrisonLostThisWar;
    _youGarrisonLost = g.youGarrisonLostThisWar;
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
    // has finished loading (initState's read may have caught the local
    // pre-sync default). If we haven't captured a real verdict yet, keep
    // trying on each rebuild until we have — but the INSTANT we do, we never
    // look at live game state again.
    if (!_haveRealData) {
      _captured = false;
      _captureOnce(ref.watch(warGameProvider));
    }

    final v = _verdict;
    final won = v?.winner == WarSide.you;
    final mvp = _mvp();

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
            _clanCard(WarSide.you),
            const SizedBox(height: 10),
            _clanCard(WarSide.enemy),
            const SizedBox(height: 16),
            if (mvp != null) _mvpCard(mvp),
            const SizedBox(height: 16),
            _topRaiders(),
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
                  onTap: () => _watchChronicle(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _bigChip(
                  label: '🗺 THEIR BASE',
                  color: JarsColors.red,
                  onTap: () => _viewBase(context, WarSide.enemy),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _bigChip(
                  label: '🏰 YOUR BASE',
                  color: JarsColors.primary,
                  onTap: () => _viewBase(context, WarSide.you),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            if (_feed.isNotEmpty) ...[
              Text('RAID LOG · tap ▶ to watch the battle',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: JarsColors.textTertiary)),
              const SizedBox(height: 6),
              for (final e in _feed.reversed.take(12))
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
                        onTap: () => _watchRaid(context, e),
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
                WarGame.instance.nextWar();
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

  bool get _haveRealData => _verdict != null;

  void _watchRaid(BuildContext context, WarLogEntry e) {
    // your clan's raids hit the ENEMY base; theirs hit yours. The war is
    // DECIDED — there is nothing left to hide, no fog on any replay.
    final base = e.attackerSide == WarSide.you ? _enemyBase : _youBase;
    WarReplayViewer.show(context,
        base: base,
        frames: e.replay!,
        fog: null,
        biome: _biome,
        title:
            '${e.attackerSide == WarSide.you ? '🔵' : '🔴'} ${e.attackerName}\'s raid');
  }

  /// The WAR, twice over: one continuous TIMELAPSE per base — every raid on
  /// it, chronological, start to finish, with title-card beats in between.
  void _watchChronicle(BuildContext context) {
    List<RaidFrame> timelapse(WarSide attacker) {
      final frames = <RaidFrame>[];
      for (final e in _feed) {
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
            base: _enemyBase,
            frames: siege,
            biome: _biome,
            title: '⚔ The siege of $_enemyClanName — the whole war'),
      if (defense.isNotEmpty)
        ReplayEntry(
            base: _youBase,
            frames: defense,
            biome: _biome,
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
  void _viewBase(BuildContext context, WarSide side) {
    final base = side == WarSide.you ? _youBase : _enemyBase;
    final structs = <RaidStruct>[
      for (var r = 0; r < base.rows; r++)
        for (var c = 0; c < base.cols; c++)
          if (base.structAt(r, c) != null && base.structAt(r, c)!.alive)
            RaidStruct(r, c, base.structAt(r, c)!.type,
                base.structAt(r, c)!.hp / base.structAt(r, c)!.maxHp),
    ];
    WarReplayViewer.show(context,
        base: base,
        frames: [RaidFrame(const [], structs, const [], const [], '')],
        biome: _biome,
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
  List<_ReportPlayer> _ranked() {
    final all = [..._youClan, ..._enemyClan];
    all.sort((a, b) => b.destructionDealt.compareTo(a.destructionDealt));
    return all;
  }

  _ReportPlayer? _mvp() {
    final all = _ranked();
    if (all.isEmpty) return null;
    return all.first.destructionDealt > 0 ? all.first : null;
  }

  /// 🥇🥈🥉 + the full TOP RAIDERS table across both clans.
  Widget _topRaiders() {
    final all = _ranked().where((p) => p.destructionDealt > 0).toList();
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

  Widget _clanCard(WarSide side) {
    final you = side == WarSide.you;
    final clan = you ? _youClan : _enemyClan;
    final dealt = you ? _youDestruction : _enemyDestruction;
    final razed = you ? _enemyBaseRazed : _youBaseRazed;
    final lost = clan.fold<int>(0, (a, p) => a + p.troopsLost);
    final spent = clan.fold<double>(0, (a, p) => a + p.resourcesSpent);
    // this clan's OWN defenders that fell — a raider death (above) is only
    // half the casualty picture.
    final defLost = you ? _youGarrisonLost : _enemyGarrisonLost;
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
            Text(you ? '🔵 YOUR CREW' : '🔴 ${_enemyClanName.toUpperCase()}',
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
            _stat('Raiders lost', '$lost'),
            _stat('Points spent', spent.round().toString()),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _stat('Defenders lost', '$defLost'),
            _stat('Total casualties', '${lost + defLost}'),
            const Expanded(child: SizedBox.shrink()),
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

  Widget _mvpCard(_ReportPlayer mvp) {
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
