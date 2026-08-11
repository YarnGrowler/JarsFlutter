import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../war/war_types.dart';

/// Clash-style stat cards: long-press any troop or defense chip to see exactly
/// what it does before you spend on it. v3: aligned ROWS, not chip soup.
void showTroopCard(BuildContext context, TroopType type) {
  final spec = kTroopSpecs[type]!;
  _showCard(
    context,
    emoji: spec.emoji,
    name: spec.name,
    cost: spec.cost,
    blurb: spec.blurb,
    accent: JarsColors.gold,
    stats: [
      _Stat('❤️ Health', '${spec.hp}'),
      if (spec.atk > 0) _Stat('⚔️ Damage', '${spec.atk}'),
      _Stat('👟 Speed', '${spec.moveBudget} tiles'),
      if (spec.atk > 0) _Stat('🏚 Vs buildings', '×${spec.vsStructure}'),
      if (type == TroopType.archer)
        const _Stat('🏹 Ranged', 'strikes from 2 tiles — arrows clear walls'),
      if (type == TroopType.healer)
        const _Stat('💚 Mends', '+14 to the worst-hurt ally within 2 tiles'),
      _Stat('📈 Levels', 'up to L${Xp.maxLevel} (+15%/level)'),
    ],
  );
}

void showDefenseCard(BuildContext context, DefType type, {int level = 1}) {
  final spec = kDefSpecs[type]!;
  int hpAt(int l) => (spec.hp * (1 + 0.3 * (l - 1))).round();
  int dmgAt(int l) => (spec.damage * (1 + 0.25 * (l - 1))).round();
  int patrolAt(int l) => 4 + (l - 1) * 2;
  int baselineAt(int l) => l.clamp(1, 4);
  // Mirrors AttackState._reinforceCooldownSeconds (war_engine.dart) — kept
  // as a literal here since this is presentational, not simulated, but the
  // two MUST be changed together.
  const cooldownSecondsByLevel = [15, 12, 10, 8, 5];
  int cooldownAt(int l) => cooldownSecondsByLevel[
      (l - 1).clamp(0, cooldownSecondsByLevel.length - 1)];

  final stats = <_Stat>[
    _Stat('❤️ Health', '${hpAt(level)}'),
    if (spec.isShooter) _Stat('⚔️ Damage', '${dmgAt(level)}'),
    if (spec.isShooter) _Stat('🎯 Range', '${spec.range} tiles'),
    if (spec.isShooter && spec.minRange > 0)
      _Stat('🚫 Blind spot', 'under ${spec.minRange} tiles'),
    if (spec.isShooter)
      _Stat(
          '⏱ Rate',
          spec.fireEveryTicks == 1
              ? 'every volley'
              : 'every ${spec.fireEveryTicks} volleys'),
    if (type == DefType.cannon)
      const _Stat('📏 Flat shot', 'walls / gates / blockers stop the shot'),
    if (type == DefType.archerTower)
      const _Stat('🏹 Lobbed', 'arrows clear walls — height does the work'),
    if (type == DefType.ballista)
      const _Stat('🪁 Lobbed bolt', 'arcs clean over walls'),
    if (type == DefType.mortar)
      _Stat('💥 Splash', level >= 3 ? '~2.2 tiles' : '~1.5 tiles'),
    if (type == DefType.tesla) ...[
      const _Stat('🪁 Lobbed arc', 'zaps clear walls — short range only'),
      _Stat(
          '⛓ Chain',
          'splits ${dmgAt(level)} pool across up to 4 '
          '(${dmgAt(level)} / ${dmgAt(level) ~/ 2} / ${dmgAt(level) ~/ 4} each)'),
    ],
    if (type == DefType.pitchThrower) ...[
      const _Stat('🔥 Boiling pitch', 'burns EVERY attacker beside it'),
      const _Stat('🕯 Clings', '+3/beat for 3 beats — and SLOWS them'),
    ],
    if (spec.zapsMovers)
      const _Stat('⚡ Dynamic', 'arcs again when a troop MOVES in range'),
    if (spec.chipOnEnter > 0) _Stat('🩸 On contact', '${spec.chipOnEnter} dmg'),
    if (spec.extraMoveCost > 0)
      _Stat('🐌 Slows', '+${spec.extraMoveCost} move cost'),
    if (spec.hidden) const _Stat('🫥 Hidden', 'invisible until it acts'),
    if (spec.blocks) const _Stat('🧱 Blocks', 'troops must destroy it'),
    if (spec.defBuffAdj > 0)
      _Stat('🛡 Aura', '+${spec.defBuffAdj} multiplier to neighbours'),
    if (type == DefType.guardPost) ...[
      const _Stat('🪖 Garrison', 'fields a live defender every raid'),
      _Stat('👥 Fields alone',
          '${baselineAt(level)} of a 4-guard solo cap (Housing pushes past '
          'it, up to 8 total)'),
      _Stat('⏱ Reinforce', '${cooldownAt(level)}s after a slot falls'),
      if (level >= 3)
        const _Stat('🏹 Recruits', '50/50 chance each is an ARCHER'),
      _Stat('📍 Patrol', '${patrolAt(level)} tiles, then returns home'),
    ],
    if (type == DefType.housing)
      _Stat('🏠 Quarters',
          'posts within 2 tiles gain +$level to their reinforcement pool'),
    if (type == DefType.banner)
      const _Stat('🚩 Rally', 'defenses within 2 reload FASTER (no stacking)'),
    if (type == DefType.watchtower) ...[
      const _Stat('👁 Eyes', 'forests hide nothing within 5 tiles'),
      const _Stat('🪖 Rally', 'guards within 5 tiles patrol +2 farther'),
      const _Stat('🚨 Alert', 'posts whose patrol reaches this tower\'s '
          'vision charge in at anything it spots'),
    ],
    if (type == DefType.storehouse) ...[
      const _Stat('🍖 Provisions', 'tents within 3 field VETERAN guards'),
      _Stat('💰 Loot', '${WarCosts.plunderAmount(type, level).round()}⚡ if smashed'),
    ],
    if (type == DefType.tributeChest) ...[
      _Stat('💰 Loot',
          '${WarCosts.plunderAmount(type, level).round()}⚡ if smashed mid-raid'),
      _Stat('🏆 Survives to war\'s end',
          '${(2 * WarCosts.plunderAmount(type, level)).round()}⚡ split with the crew'),
    ],
    if (type == DefType.gate)
      const _Stat('🚪 Doorway', 'YOUR garrison passes; attackers cannot'),
    if (type == DefType.warGenerator) ...[
      _Stat('⚗️ Pump rate',
          '${warGeneratorRatePerHour(level).round()}⚡/hr on war day'),
      _Stat('💰 Loot',
          '${WarCosts.plunderAmount(type, level).round()}⚡ if smashed '
          '(~${level + 1}h tank — deeper the more it\'s upgraded)'),
    ],
  ];

  // what the NEXT level buys — shown until you're maxed
  final next = level + 1;
  final upgrade = <_Stat>[
    if (spec.upgradeCost > 0 && level < spec.maxLevel) ...[
      _Stat('❤️ Health', '${hpAt(level)} → ${hpAt(next)}'),
      if (spec.isShooter) _Stat('⚔️ Damage', '${dmgAt(level)} → ${dmgAt(next)}'),
      if (type == DefType.guardPost)
        _Stat('📍 Patrol', '${patrolAt(level)} → ${patrolAt(next)} tiles'),
      if (type == DefType.mortar && next >= 3)
        const _Stat('💥 Splash', '~1.5 → ~2.2 tiles'),
      if (type == DefType.warGenerator)
        _Stat(
            '⚗️ Pump rate',
            '${warGeneratorRatePerHour(level).round()} → '
            '${warGeneratorRatePerHour(next).round()}⚡/hr'),
      const _Stat('✨ Look', 'reforged, reinforced, grander'),
    ],
  ];

  _showCard(
    context,
    emoji: spec.emoji,
    name: level >= 2 ? '${spec.name} · LVL $level' : spec.name,
    cost: spec.cost,
    blurb: spec.blurb,
    accent: level >= 2 ? JarsColors.gold : JarsColors.primary,
    stats: stats,
    upgradeStats: upgrade,
    upgradeCost: spec.upgradeCost * level,
    upgradeLabel: level < spec.maxLevel ? '⬆ LEVEL $next' : '',
  );
}

class _Stat {
  final String label, value;
  const _Stat(this.label, this.value);
}

Widget _statRow(_Stat s, {bool gold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(s.label,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: gold ? JarsColors.gold : JarsColors.textTertiary)),
          ),
          Expanded(
            child: Text(s.value,
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: JarsColors.textPrimary)),
          ),
        ],
      ),
    );

Widget _divider() =>
    Container(height: 1, color: JarsColors.border.withValues(alpha: 0.55));

void _showCard(
  BuildContext context, {
  required String emoji,
  required String name,
  required int cost,
  required String blurb,
  required Color accent,
  required List<_Stat> stats,
  List<_Stat> upgradeStats = const [],
  int upgradeCost = 0,
  String upgradeLabel = '⬆ UPGRADE',
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.16), JarsColors.surfaceRaised],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.5)),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 30)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toUpperCase(),
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: JarsColors.textPrimary)),
                      Text(cost == 0 ? 'free' : '⚡ $cost to place',
                          style: GoogleFonts.spaceMono(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: JarsColors.gold)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(blurb,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: JarsColors.textSecondary)),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: JarsColors.background.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: JarsColors.border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) _divider(),
                      _statRow(stats[i]),
                    ],
                  ],
                ),
              ),
              if (upgradeStats.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Text(upgradeLabel,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: JarsColors.gold)),
                  const SizedBox(width: 8),
                  Text('⚡ $upgradeCost',
                      style: GoogleFonts.spaceMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: JarsColors.gold)),
                ]),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: JarsColors.gold.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: JarsColors.gold.withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < upgradeStats.length; i++) ...[
                        if (i > 0) _divider(),
                        _statRow(upgradeStats[i], gold: true),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
