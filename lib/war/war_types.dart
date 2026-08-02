/// Core vocabulary for the Clan War: terrain, defenses, troops, AI tiers, the
/// XP curve, and action costs. Pure data — no Flutter, fully testable.
library;

/// A grid coordinate (row, col). Immutable so it works as a map key.
class Cell {
  final int r, c;
  const Cell(this.r, this.c);
  @override
  bool operator ==(Object other) => other is Cell && other.r == r && other.c == c;
  @override
  int get hashCode => r * 1000 + c;
  int key(int cols) => r * cols + c;
  @override
  String toString() => '($r,$c)';
}

enum WarSide { you, enemy }

WarSide other(WarSide s) => s == WarSide.you ? WarSide.enemy : WarSide.you;

enum WarPhase { prep, war, results }

/// Combat effect kinds the engine emits for the UI to animate.
enum FxKind { shot, zap, melee, trap, death, levelup, heal }

// ── terrain ───────────────────────────────────────────────────────────────────

enum Terrain { plains, forest, mountain, river, bridge, hill }

class TerrainData {
  static int moveCost(Terrain t) {
    switch (t) {
      case Terrain.plains:
      case Terrain.bridge:
        return 1;
      case Terrain.forest:
      case Terrain.hill:
        return 2;
      case Terrain.mountain:
        return 3;
      case Terrain.river:
        return 999;
    }
  }

  /// Mountains and rivers are HARD walls — no walking over ranges.
  static bool passable(Terrain t) =>
      t != Terrain.river && t != Terrain.mountain;

  /// Buildable ground during Prep (defenses go on open land — and HILLS,
  /// where towers gain +1 range). Bridges are PASSAGES — nothing builds there.
  static bool buildable(Terrain t) => t == Terrain.plains || t == Terrain.hill;

  /// Damage reduction the terrain grants a defender standing on it.
  static double defBonus(Terrain t) {
    switch (t) {
      case Terrain.forest:
      case Terrain.hill:
        return 0.25;
      case Terrain.mountain:
        return 0.5;
      default:
        return 0;
    }
  }

  /// Forest CONCEALS troops: towers and hunting defenders can only spot a
  /// troop standing in forest within this range.
  static const int forestSpotRange = 2;
}

// ── defenses / structures ─────────────────────────────────────────────────────

enum DefCategory { hq, wall, obstacle, trap, tower, garrison }

enum DefType {
  castle,
  wall,
  barbedWire,
  mortar,
  landmine,
  archerTower,
  cannon,
  tesla,
  guardPost,
  gate,
  housing,
  pitchThrower,
  banner,
  ballista,
  watchtower,
  storehouse,
  // league unlocks (appended — never reorder; saves use .index)
  tributeChest,
  commandTent,
  pitchPot,
  citadelCore,
  // economy (appended)
  warGenerator,
}

class DefSpec {
  final DefType type;
  final String name;
  final String emoji;
  final DefCategory category;
  final int cost;
  final int hp;
  final bool blocks; // impassable to troops
  final int extraMoveCost; // slows troops passing through
  final int chipOnEnter; // damage to a troop that steps on it
  final bool hidden; // invisible to the attacker until triggered/revealed
  final bool oneShot; // consumed after triggering (mines)
  final int range; // 0 = not a shooter
  final int minRange; // artillery blind spot — can't hit closer than this
  final int damage; // per shot
  final int fireEveryTicks; // 1 = every tick, 2 = every other…
  final bool zapsMovers; // dynamic defense: fires when a troop moves in range
  final double defBuffAdj; // multiplier bonus to adjacent friendly defenders
  final int upgradeCost; // ⚡ to reach level 2 (0 = not upgradable)
  final int maxLevel; // how far upgrades go (L3 costs upgradeCost × 2)
  final String blurb;

  const DefSpec(
    this.type, {
    required this.name,
    required this.emoji,
    required this.category,
    required this.cost,
    required this.hp,
    this.blocks = false,
    this.extraMoveCost = 0,
    this.chipOnEnter = 0,
    this.hidden = false,
    this.oneShot = false,
    this.range = 0,
    this.minRange = 0,
    this.damage = 0,
    this.fireEveryTicks = 1,
    this.zapsMovers = false,
    this.defBuffAdj = 0,
    this.upgradeCost = 0,
    this.maxLevel = 2,
    this.blurb = '',
  });

  bool get isShooter => range > 0 && damage > 0;
}

const Map<DefType, DefSpec> kDefSpecs = {
  DefType.castle: DefSpec(DefType.castle,
      name: 'Castle',
      emoji: '🏰',
      category: DefCategory.hq,
      cost: 0,
      hp: 360,
      blocks: true,
      defBuffAdj: 0.3,
      blurb:
          'Your heart. It cannot fight — protect it. If every castle falls, the base is razed.'),
  DefType.wall: DefSpec(DefType.wall,
      name: 'Wall',
      emoji: '🧱',
      category: DefCategory.wall,
      cost: 15,
      hp: 140,
      blocks: true,
      defBuffAdj: 0.1,
      upgradeCost: 10,
      maxLevel: 5,
      blurb:
          'Cheap and solid. Levels into spiked ramparts and obsidian bastions.'),
  DefType.barbedWire: DefSpec(DefType.barbedWire,
      name: 'Barbed Wire',
      emoji: '🌵',
      category: DefCategory.obstacle,
      cost: 18,
      hp: 40,
      extraMoveCost: 2,
      chipOnEnter: 10,
      blurb: 'Slows anyone crossing it and shreds them for 10 on the way through.'),
  DefType.mortar: DefSpec(DefType.mortar,
      name: 'Mortar',
      emoji: '💣',
      category: DefCategory.tower,
      cost: 85,
      hp: 110,
      blocks: true,
      upgradeCost: 50,
      maxLevel: 5,
      range: 6,
      minRange: 2,
      damage: 24, // center hit; splash deals half to everything adjacent
      fireEveryTicks: 3,
      blurb:
          'Long-range SPLASH artillery — shells blast the whole impact area. Blind up close: guard its feet.'),
  DefType.landmine: DefSpec(DefType.landmine,
      name: 'Land Mine',
      emoji: '💣',
      category: DefCategory.trap,
      cost: 12,
      hp: 1,
      hidden: true,
      oneShot: true,
      chipOnEnter: 70,
      blurb: 'Invisible until stepped on. One devastating 70-damage blast.'),
  DefType.archerTower: DefSpec(DefType.archerTower,
      name: 'Archer Tower',
      emoji: '🏹',
      category: DefCategory.tower,
      cost: 40,
      hp: 95,
      blocks: true,
      upgradeCost: 25,
      maxLevel: 5,
      range: 3,
      damage: 12,
      fireEveryTicks: 1,
      blurb: 'Steady arrows every volley, range 3. The backbone of a defense.'),
  DefType.cannon: DefSpec(DefType.cannon,
      name: 'Cannon',
      emoji: '💥',
      category: DefCategory.tower,
      cost: 70,
      hp: 150,
      blocks: true,
      upgradeCost: 40,
      maxLevel: 5,
      range: 4,
      damage: 30,
      fireEveryTicks: 2,
      blurb: 'Slow, long-range, and hits like a truck. Range 4, fires every other volley.'),
  DefType.tesla: DefSpec(DefType.tesla,
      name: 'Tesla Coil',
      emoji: '⚡',
      category: DefCategory.tower,
      cost: 90,
      hp: 80,
      blocks: true,
      hidden: true,
      upgradeCost: 45,
      maxLevel: 5,
      range: 2,
      damage: 24, // pool split across up to 4 raiders in range
      fireEveryTicks: 1,
      zapsMovers: true,
      blurb:
          'Hidden chain lightning. Dumps a 24⚡ pool across up to 4 raiders '
          'in range (24 solo, 12 each for two, 6 each for four) — and zaps '
          'again the moment anyone moves nearby.'),
  DefType.guardPost: DefSpec(DefType.guardPost,
      name: 'Guard Post',
      emoji: '⛺',
      category: DefCategory.garrison,
      cost: 35,
      hp: 60,
      upgradeCost: 20,
      maxLevel: 5,
      blurb:
          'Stations a live defender at the start of every raid — upgrades '
          'widen the patrol leash across big boards.'),
  DefType.gate: DefSpec(DefType.gate,
      name: 'Gate',
      emoji: '🚪',
      category: DefCategory.wall,
      cost: 20,
      hp: 110,
      blocks: true,
      defBuffAdj: 0.1,
      upgradeCost: 15,
      maxLevel: 4,
      blurb:
          'The fort\'s doorway: YOUR defenders march through it, attackers cannot. '
          'Weaker than a wall — guard it well.'),
  DefType.housing: DefSpec(DefType.housing,
      name: 'Housing',
      emoji: '🏠',
      category: DefCategory.garrison,
      cost: 45,
      hp: 90,
      blocks: true,
      upgradeCost: 35,
      maxLevel: 3,
      blurb:
          'Barracks quarters: every Guard Post within 2 tiles fields a SECOND '
          'defender each raid.'),
  DefType.pitchThrower: DefSpec(DefType.pitchThrower,
      name: 'Pitch Thrower',
      emoji: '🔥',
      category: DefCategory.tower,
      cost: 55,
      hp: 100,
      blocks: true,
      upgradeCost: 35,
      maxLevel: 4,
      range: 1,
      damage: 9,
      fireEveryTicks: 1,
      blurb:
          'Boiling pitch over the parapet: burns EVERY attacker beside it, '
          'every volley. Swarms melt.'),
  DefType.banner: DefSpec(DefType.banner,
      name: 'War Banner',
      emoji: '🚩',
      category: DefCategory.garrison,
      cost: 40,
      hp: 70,
      blocks: true,
      upgradeCost: 30,
      maxLevel: 3,
      blurb:
          'The colors fly and the guns work FASTER: defenses within 2 tiles '
          'reload quicker while it stands.'),
  DefType.ballista: DefSpec(DefType.ballista,
      name: 'Ballista',
      emoji: '🎯',
      category: DefCategory.tower,
      cost: 95,
      hp: 85,
      blocks: true,
      upgradeCost: 55,
      maxLevel: 5,
      range: 7,
      minRange: 2,
      damage: 55,
      fireEveryTicks: 4,
      blurb:
          'The sniper. A single bolt from across the map DELETES a brute — '
          'it LOBS clean over walls, but is helpless up close.'),
  DefType.watchtower: DefSpec(DefType.watchtower,
      name: 'Watchtower',
      emoji: '👁',
      category: DefCategory.garrison,
      cost: 50,
      hp: 80,
      blocks: true,
      upgradeCost: 40,
      maxLevel: 3,
      blurb:
          'No gun — EYES. Within 3 tiles: forests hide nothing from your '
          'towers, and guards patrol 2 tiles farther.'),
  DefType.storehouse: DefSpec(DefType.storehouse,
      name: 'Storehouse',
      emoji: '💰',
      category: DefCategory.garrison,
      cost: 60,
      hp: 110,
      blocks: true,
      upgradeCost: 40,
      maxLevel: 3,
      blurb:
          'War provisions: guard posts within 3 tiles field VETERAN '
          'defenders — a level stronger, full of stew. Raiders LOVE burning '
          'these.'),
  DefType.tributeChest: DefSpec(DefType.tributeChest,
      name: 'Tribute Chest',
      emoji: '🏆',
      category: DefCategory.garrison,
      cost: 100,
      hp: 160,
      blocks: true,
      blurb:
          'Stash 100⚡. If it survives the war, the crew splits 200⚡. '
          'Raid magnet — hide it well.'),
  DefType.commandTent: DefSpec(DefType.commandTent,
      name: 'Command Tent',
      emoji: '🎖️',
      category: DefCategory.garrison,
      cost: 80,
      hp: 120,
      blocks: true,
      blurb:
          'One per fighter. Fields a General — a strong ranged defender — '
          'each raid. Lose the tent, lose the General.'),
  DefType.pitchPot: DefSpec(DefType.pitchPot,
      name: 'Pitch Pot',
      emoji: '🫙',
      category: DefCategory.trap,
      cost: 28,
      hp: 1,
      hidden: true,
      oneShot: true,
      chipOnEnter: 8,
      blurb:
          'Hidden tar bomb. Triggers underfoot: chips and dumps heavy slow '
          'across a small radius. Elephant-proofing.'),
  DefType.citadelCore: DefSpec(DefType.citadelCore,
      name: 'Citadel Core',
      emoji: '💠',
      category: DefCategory.hq,
      cost: 200,
      hp: 480,
      blocks: true,
      defBuffAdj: 0.35,
      blurb:
          'One per crew. No gun — a landmark aura that toughens nearby walls '
          'and hastens towers. Raiders will come for it.'),
  DefType.warGenerator: DefSpec(DefType.warGenerator,
      name: 'War Generator',
      emoji: '⚗️',
      category: DefCategory.garrison,
      cost: 50,
      hp: 90,
      blocks: true,
      upgradeCost: 30,
      maxLevel: 3,
      blurb:
          'War-day elixir pump. L1 drips 6⚡/hr; L2 pumps 15⚡/hr; L3 floods '
          '28⚡/hr. Accrues whenever anyone in the room opens the war — until '
          'the day ends or the pump is smashed.'),
};

/// The palette a player can place (castle is placed separately, one per player).
const List<DefType> kBuildPalette = [
  DefType.wall,
  DefType.gate,
  DefType.barbedWire,
  DefType.landmine,
  DefType.archerTower,
  DefType.cannon,
  DefType.mortar,
  DefType.tesla,
  DefType.guardPost,
  DefType.housing,
  DefType.pitchThrower,
  DefType.banner,
  DefType.ballista,
  DefType.watchtower,
  DefType.storehouse,
  DefType.tributeChest,
  DefType.commandTent,
  DefType.pitchPot,
  DefType.citadelCore,
  DefType.warGenerator,
];

/// League-gated defenses (everything else in [kBuildPalette] is always free).
const Set<DefType> kLeagueGatedDefs = {
  DefType.tributeChest,
  DefType.commandTent,
  DefType.pitchPot,
  DefType.citadelCore,
};

/// War-day ⚡/hour by generator level (L1 = 6, L2 = 15, L3 = 28).
double warGeneratorRatePerHour(int level) {
  if (level >= 3) return 28.0;
  if (level >= 2) return 15.0;
  return 6.0;
}

String defUnlockKey(DefType t) {
  switch (t) {
    case DefType.tributeChest:
      return 'tributeChest';
    case DefType.commandTent:
      return 'commandTent';
    case DefType.pitchPot:
      return 'pitchPot';
    case DefType.citadelCore:
      return 'citadelCore';
    default:
      return t.name;
  }
}

// ── troops ────────────────────────────────────────────────────────────────────

enum TroopType {
  soldier,
  runner,
  brute,
  sapper,
  archer,
  healer,
  // league unlocks (appended — never reorder; saves use .index)
  javelin,
  fogger,
  elephant,
  general, // defense-only: spawned by Command Tent, not trained
}

/// League-gated troops. Bronze always has the rest of the classic roster.
const Set<TroopType> kLeagueGatedTroops = {
  TroopType.healer,
  TroopType.javelin,
  TroopType.fogger,
  TroopType.elephant,
};

String troopUnlockKey(TroopType t) {
  switch (t) {
    case TroopType.healer:
      return 'healer';
    case TroopType.javelin:
      return 'javelin';
    case TroopType.fogger:
      return 'fogger';
    case TroopType.elephant:
      return 'elephant';
    default:
      return t.name;
  }
}

class TroopSpec {
  final TroopType type;
  final String name;
  final String emoji;
  final int cost;
  final int hp;
  final int atk;
  final int moveBudget;
  final double vsStructure; // damage multiplier against structures
  final int revealRadius; // fog cleared around this troop (scouts see farther)
  /// How big this unit is drawn, relative to a Soldier. A brute towers over
  /// the line infantry and an elephant towers over the brute — you should be
  /// able to read an army's composition at a glance, without squinting at
  /// emoji.
  final double size;
  final String blurb;
  const TroopSpec(this.type,
      {required this.name,
      required this.emoji,
      required this.cost,
      required this.hp,
      required this.atk,
      required this.moveBudget,
      required this.vsStructure,
      this.revealRadius = 1,
      this.size = 1.0,
      this.blurb = ''});

  /// Sprite size for a bare emoji (replay frames only carry the glyph).
  static double sizeForEmoji(String emoji) {
    for (final s in kTroopSpecs.values) {
      if (s.emoji == emoji) return s.size;
    }
    return 1.0;
  }
}

const Map<TroopType, TroopSpec> kTroopSpecs = {
  TroopType.soldier: TroopSpec(TroopType.soldier,
      name: 'Soldier',
      emoji: '⚔️',
      cost: 15,
      hp: 100,
      atk: 22,
      moveBudget: 5,
      vsStructure: 1.0,
      size: 1.0, // the yardstick every other unit is measured against
      blurb: 'The all-rounder. Decent everywhere, weak nowhere.'),
  TroopType.runner: TroopSpec(TroopType.runner,
      name: 'Scout',
      emoji: '🕵️',
      cost: 18,
      hp: 60,
      atk: 14,
      moveBudget: 8,
      vsStructure: 0.8,
      revealRadius: 2,
      size: 0.85, // small and quick
      blurb:
          'Fast, fragile eyes — reveals a 5×5 area as it moves. Send it first.'),
  TroopType.brute: TroopSpec(TroopType.brute,
      name: 'Brute',
      emoji: '🪓',
      cost: 30,
      hp: 260,
      atk: 26,
      moveBudget: 3,
      vsStructure: 1.2,
      size: 1.45, // head and shoulders over the line infantry
      blurb:
          'A lumbering wall of meat. Slow, but it soaks tower fire so the others can work.'),
  TroopType.sapper: TroopSpec(TroopType.sapper,
      name: 'Sapper',
      emoji: '🧨',
      cost: 15,
      hp: 50,
      atk: 12,
      moveBudget: 6,
      vsStructure: 1.0,
      size: 0.8, // a little fellow carrying a very large bomb
      blurb:
          'One boom, one wall. Cheap and fast, sprints at the nearest wall and '
          'blows it sky-high — splash tears at everything beside it.'),
  TroopType.archer: TroopSpec(TroopType.archer,
      name: 'Archer',
      emoji: '🏹',
      cost: 20,
      hp: 55,
      atk: 14,
      moveBudget: 5,
      vsStructure: 0.9,
      size: 0.9,
      blurb:
          'Arrows over the walls from 2 tiles out. Fragile — keep a brute '
          'between her and the guns.'),
  TroopType.healer: TroopSpec(TroopType.healer,
      name: 'Healer',
      emoji: '💚',
      cost: 27,
      hp: 70,
      atk: 0,
      moveBudget: 5,
      vsStructure: 0,
      size: 0.9,
      blurb:
          'Mends the most-wounded ally nearby every beat. Never fights. '
          'Protect her and the push never stops.'),
  TroopType.javelin: TroopSpec(TroopType.javelin,
      name: 'Javelin',
      emoji: '🗡️',
      cost: 25,
      hp: 65,
      atk: 16,
      moveBudget: 5,
      vsStructure: 0.85,
      size: 0.95,
      blurb:
          'Mid-range spears. Bonus damage vs garrison defenders and Generals.'),
  TroopType.fogger: TroopSpec(TroopType.fogger,
      name: 'Fogger',
      emoji: '🌫️',
      cost: 24,
      hp: 55,
      atk: 12,
      moveBudget: 5,
      vsStructure: 0.9,
      size: 0.95,
      blurb:
          'Bleeds smoke: the first hit it takes bursts a cloud (towers spot '
          'like forest — short range only), and it lets one last burst go when '
          'it dies. Higher levels smoke for longer.'),
  TroopType.elephant: TroopSpec(TroopType.elephant,
      name: 'War Elephant',
      emoji: '🐘',
      cost: 60,
      hp: 520,
      atk: 20,
      moveBudget: 2,
      vsStructure: 1.1,
      size: 2.1, // it should DWARF everything else on the field
      blurb:
          'A walking fortress. Slow, enormous, shrugs barbed wire, soaks '
          'tower fire so the crew can work.'),
  TroopType.general: TroopSpec(TroopType.general,
      name: 'General',
      emoji: '🫡',
      cost: 0,
      hp: 180,
      atk: 28,
      moveBudget: 4,
      vsStructure: 0.9,
      size: 1.2, // an officer, visibly a cut above the rank and file
      blurb:
          'Elite ranged defender from a Command Tent. Long reach, tough hide.'),
};

// ── XP / leveling ─────────────────────────────────────────────────────────────

class Xp {
  static const int perDamage = 1;
  static const int perKill = 25;
  static const int perStructure = 15;
  static const int maxLevel = 6;
  static const int perLevel = 300;

  static int levelForXp(double xp) => (1 + xp ~/ perLevel).clamp(1, maxLevel);

  /// Fraction toward the next level (0..1); 1.0 at max level.
  static double progress(double xp) {
    if (levelForXp(xp) >= maxLevel) return 1;
    return (xp % perLevel) / perLevel;
  }

  /// Stat multiplier for a given level (level 1 = ×1.0).
  static double bonus(int level) => 1 + 0.15 * (level - 1);
}

// ── AI difficulty ─────────────────────────────────────────────────────────────

enum AiLevel { rookie, seasoned, elite, master }

class AiData {
  /// 0..1 competence — drives base-design quality and attack decisions.
  static double skill(AiLevel a) {
    switch (a) {
      case AiLevel.rookie:
        return 0.25;
      case AiLevel.seasoned:
        return 0.5;
      case AiLevel.elite:
        return 0.75;
      case AiLevel.master:
        return 1.0;
    }
  }

  static String label(AiLevel a) {
    switch (a) {
      case AiLevel.rookie:
        return 'Rookie';
      case AiLevel.seasoned:
        return 'Seasoned';
      case AiLevel.elite:
        return 'Elite';
      case AiLevel.master:
        return 'Master';
    }
  }

  /// Resource income multiplier — sharper clans out-earn.
  static double income(AiLevel a) => 0.7 + skill(a) * 0.8;
}

// ── action costs (drawn from the acting player's pool) ────────────────────────

class WarCosts {
  static const double move = 1; // per tile stepped
  static const double capture = 2; // flip a tile
  static const double attack = 3; // a troop striking
  static const double defend = 1; // a defender firing a shot / garrison acting
  static const double prepBudget = 300; // starting build ⚡ per player (bots)

  /// Real players get a small headstart, not a free stronghold — the rest
  /// has to come from logged workouts, same as always intended.
  static const double realPlayerPrepStipend = 100;

  /// The enemy's war chest by skill. Below master (1.0) it's the gentle old
  /// curve; past it the treasury EXPLODES — a difficulty-99 clan brings
  /// ~5,000⚡ per castle and spends ALL of it: walls, arsenal, and steel.
  static double prepBudgetFor(double skill) =>
      prepBudget *
      (0.6 + 0.9 * skill + (skill > 1.0 ? (skill - 1.0) * 30 : 0.0));

  /// Share of your real crew's prep earnings mirrored into the enemy build
  /// chest. Full 1:1 made them feel overtuned once the room was grinding.
  static const double enemyPrepMirror = 0.70;

  static const double warStartResources = 120; // per BOT at war start (crew AND enemy)

  /// Real players get a modest raiding stipend at war start too, not the same
  /// bot-sized war chest — the rest of a real war-day budget should come
  /// from raids won and workouts logged, same principle as [realPlayerPrepStipend].
  static const double realPlayerWarStipend = 32;
  static const double clearForest = 20; // 🪓 clear a forest tile in the builder
  static const double upgradeGuardPost = 30; // ⛺ → wider patrol + fresh skin

  /// One-time cost to unlock doctrine [toLevel] for [t] (must already own
  /// toLevel-1). Soldier baseline: L2 250, L3 400, L4 750, L5 1000,
  /// L6 1500. Other troops scale by their training cost, rounded to 25⚡.
  /// Sapper is deliberately exempt: permanent upgrades to its wall-breaching
  /// kit are premium doctrine despite the disposable unit being cheap.
  static double troopDoctrineCost(TroopType t, int toLevel) {
    final lv = toLevel.clamp(2, Xp.maxLevel);
    const soldierCurve = <int, double>{
      2: 250,
      3: 400,
      4: 750,
      5: 1000,
      6: 1500,
    };
    final troopScale = t == TroopType.sapper
        ? 2.5
        : kTroopSpecs[t]!.cost / kTroopSpecs[TroopType.soldier]!.cost;
    return (soldierCurve[lv]! * troopScale / 25).round() * 25.0;
  }
}
