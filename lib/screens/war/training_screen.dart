import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/war_providers.dart';
import '../../war/war_types.dart';

/// The Training Grounds — muster your army BEFORE the battle. Training is
/// instant and costs energy; deploying trained troops in battle is free.
class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key});

  static const _leagueNames = [
    'Bronze',
    'Silver',
    'Gold',
    'Platinum',
    'Diamond',
    'Champion',
    'Radiant',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(warRoomSyncProvider);
    final g = ref.watch(warGameProvider);
    final p = g.active;
    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 14, 4),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white70),
                  onPressed: () => context.go('/war'),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TRAINING GROUNDS',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: JarsColors.textPrimary)),
                      Text(
                          '${p.emoji} ${p.name}\'s army · ${p.armyTotal} trained · deploys are free',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 11, color: JarsColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(
                        color: JarsColors.gold.withValues(alpha: 0.5)),
                  ),
                  child: Text('⚡ ${p.resources.round()}',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: JarsColors.textPrimary)),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                children: [
                  for (final type in TroopType.values)
                    if (type != TroopType.general)
                      _troopCard(context, ref, type),
                  const SizedBox(height: 6),
                  Text(
                    'Log a workout to earn energy — then turn sweat into soldiers.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: JarsColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _troopCard(BuildContext context, WidgetRef ref, TroopType type) {
    final g = ref.watch(warGameProvider);
    final spec = kTroopSpecs[type]!;
    final count = g.active.armyCount(type);
    final unlocked = g.troopUnlocked(type);
    final unlockAt = g.troopUnlockDivision(type);
    final lockLabel =
        unlockAt >= 0 ? _leagueNames[unlockAt.clamp(0, 6)] : '';

    Widget stat(String label, String value) => Container(
          margin: const EdgeInsets.only(right: 6, top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: JarsColors.background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: JarsColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: JarsColors.textPrimary)),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 9, color: JarsColors.textTertiary)),
            ],
          ),
        );

    void train(int times) {
      String? err;
      var trained = 0;
      for (var i = 0; i < times; i++) {
        err = g.trainTroop(type);
        if (err != null) break;
        trained++;
      }
      if (trained > 0) HapticFeedback.selectionClick();
      if (err != null && trained == 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }

    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              JarsColors.gold.withValues(alpha: 0.08),
              JarsColors.surface
            ],
          ),
          borderRadius: BorderRadius.circular(JarsRadius.card),
          border: Border.all(
              color: count > 0
                  ? JarsColors.gold.withValues(alpha: 0.5)
                  : JarsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: JarsColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(unlocked ? spec.emoji : '🔒',
                    style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spec.name.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: JarsColors.textPrimary)),
                    Text(
                        unlocked
                            ? spec.blurb
                            : 'Unlocks in $lockLabel League.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 1.3,
                            color: JarsColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(children: [
                Text('×$count',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: count > 0
                            ? JarsColors.gold
                            : JarsColors.textTertiary)),
                Text('trained',
                    style: GoogleFonts.inter(
                        fontSize: 9, color: JarsColors.textTertiary)),
              ]),
            ]),
            Wrap(children: [
              stat('Health', '${spec.hp}'),
              stat('Damage', '${spec.atk}'),
              stat('Speed', '${spec.moveBudget}'),
              stat('Vs buildings', '×${spec.vsStructure}'),
              stat('Max level', 'L${Xp.maxLevel}'),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _btn(
                    unlocked ? 'TRAIN · ⚡${spec.cost}' : 'LOCKED',
                    unlocked && g.active.resources >= spec.cost,
                    () => train(1)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _btn(
                    unlocked ? '×5 · ⚡${spec.cost * 5}' : '—',
                    unlocked && g.active.resources >= spec.cost * 5,
                    () => train(5)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, bool enabled, VoidCallback onTap) => Opacity(
        opacity: enabled ? 1 : 0.45,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: JarsColors.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: JarsColors.gold.withValues(alpha: 0.6)),
            ),
            child: Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: JarsColors.textPrimary)),
          ),
        ),
      );
}
