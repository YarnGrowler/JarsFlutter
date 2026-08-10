import '../core/seeded_rng.dart';
import 'war_ai.dart';
import 'war_base.dart';
import 'war_engine.dart';
import 'war_player.dart';
import 'war_types.dart';

/// One AI raid, summarised for the war feed + battle report.
class WarLogEntry {
  final int minute;
  final WarSide attackerSide;
  final String attackerName;
  final double gained; // destruction added this raid
  final double defenderDestruction; // defender base destruction after
  final int troopsLost;
  final int troopsSent;
  final double resourcesSpent;
  final bool razed; // defender base fully razed after this raid
  List<RaidFrame>? replay; // watchable playback (stripped on old entries)

  WarLogEntry({
    required this.minute,
    required this.attackerSide,
    required this.attackerName,
    required this.gained,
    required this.defenderDestruction,
    required this.troopsLost,
    this.troopsSent = 0,
    required this.resourcesSpent,
    required this.razed,
    this.replay,
  });

  String get line =>
      '$attackerName raided with $troopsSent — +${gained.round()}% · lost $troopsLost';
}

/// Advances the war timeline. For each simulated hour, every AI player earns
/// income and may launch a raid on the opposing clan's base. Fully seeded, so a
/// given (warSeed, hour, player) always resolves the same — fast-forward is
/// reproducible and re-runnable.
class WarSim {
  /// Runs a single sim-hour. Mutates bases + pools; returns the raids that
  /// happened (newest actions appended). Skips [activePlayerId] (the human plays
  /// their own raids live).
  ///
  /// [raidChance] is per bot, per hour (typically difficulty/100 — so a dial
  /// of 29 means each living enemy has a 29% shot to launch, not a guarantee).
  static List<WarLogEntry> runHour({
    required int hour,
    required int minute,
    required Base youBase,
    required Base enemyBase,
    required List<WarPlayer> players,
    required WarPools pools,
    required int warSeed,
    required String activePlayerId,
    required Set<int> youIntel, // your clan's scouting of the ENEMY base
    required Set<int> enemyIntel, // their clan's scouting of YOURS
    Set<TroopType> unlockTroops = const {},
    /// Level of the troops the ENEMY fields — a function of the league you
    /// have climbed to, never of the difficulty dial.
    int troopLevel = 1,
    double raidChance = 0.5,
  }) {
    final out = <WarLogEntry>[];
    final chance = raidChance.clamp(0.0, 1.0);
    for (final p in players) {
      if (p.id == activePlayerId) continue; // human raids are hands-on
      // Real teammates are never auto-played: no free hourly income, no
      // AI-piloted raids on their behalf. Only actual bots (solo/offline
      // crew, and the always-bot enemy clan) get simulated here — a real
      // friend who isn't at the wheel right now simply doesn't raid until
      // they show up and play their own raid live.
      if (!p.isBot) continue;
      final rng = SeededRng(seedFromParts([warSeed, 'hour', hour, p.id]));
      // income (variable per team/hour)
      final ownBase = p.side == WarSide.you ? youBase : enemyBase;
      pools.add(p.id, WarAi.hourlyIncome(p, rng));

      // a fighter whose CASTLE has fallen is OUT of the war (spectator)
      final myCastle = ownBase.castles[p.id];
      if (myCastle != null) {
        final cs = ownBase.structAt(myCastle.r, myCastle.c);
        if (cs == null || cs.hp <= 0) continue;
      }

      // Decide whether to raid — must be banked up, then pass the dial roll.
      // The bar scales with skill because the army it has to pay for does
      // too (see WarAi.runAttack's cap): a sharper clan saves for a bigger
      // punch rather than trickling the same ten bodies in forever.
      final skill = p.skill;
      if (pools.of(p.id) < WarAi.raidBudget(skill) || rng.unit() > chance) {
        continue;
      }

      final target = p.side == WarSide.you ? enemyBase : youBase;
      final intel = p.side == WarSide.you ? youIntel : enemyIntel;
      // the DEFENSE fights as smart as the clan that built it
      final defenders =
          players.where((d) => d.side != p.side && d.id != activePlayerId);
      final defenderIq = defenders.isEmpty
          ? 0.5
          : defenders.map((d) => d.skill).reduce((a, b) => a + b) /
              defenders.length;
      final before = target.destructionPercent;
      final res = WarAi.runAttack(
          base: target,
          attacker: p,
          pools: pools,
          rng: rng,
          intel: intel,
          defenderIq: defenderIq,
          unlockTroops: unlockTroops,
          troopLevel: troopLevel);
      intel.addAll(res.revealed); // the clan shares everything it scouts
      if (res.frames.isEmpty) continue; // nothing to raid — no still-frame junk
      final gained = (target.destructionPercent - before).clamp(0.0, 100.0);

      p.troopsLost += res.troopsLost;
      p.resourcesSpent += res.resourcesSpent;
      p.destructionDealt = (p.destructionDealt + gained).clamp(0.0, 100.0);

      out.add(WarLogEntry(
        minute: minute,
        attackerSide: p.side,
        attackerName: p.name,
        gained: gained,
        defenderDestruction: target.destructionPercent,
        troopsLost: res.troopsLost,
        troopsSent: res.troopsSent,
        resourcesSpent: res.resourcesSpent,
        razed: target.allCastlesRazed,
        // every raid is watchable (report ▶ + defense board)
        replay: res.frames,
      ));
    }
    return out;
  }
}
