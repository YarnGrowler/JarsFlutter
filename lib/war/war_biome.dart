import 'dart:ui' show Color;

/// Visual + light generation dials for a league division's battlefield.
enum WarBiomeId {
  meadow,
  autumn,
  sunscrub,
  coast,
  tundra,
  nightglass,
  ashfall,
}

WarBiomeId warBiomeFromString(String? s) {
  switch (s) {
    case 'autumn':
      return WarBiomeId.autumn;
    case 'sunscrub':
      return WarBiomeId.sunscrub;
    case 'coast':
      return WarBiomeId.coast;
    case 'tundra':
      return WarBiomeId.tundra;
    case 'nightglass':
      return WarBiomeId.nightglass;
    case 'ashfall':
      return WarBiomeId.ashfall;
    default:
      return WarBiomeId.meadow;
  }
}

/// Seeded water abundance for a single war's terrain roll.
enum WaterRoll { dry, light, wet }

class WaterWeights {
  final double dry;
  final double light;
  final double wet;
  const WaterWeights(
      {this.dry = 0.25, this.light = 0.50, this.wet = 0.25});

  WaterRoll roll(double u) {
    final t = u.clamp(0.0, 0.999999);
    if (t < dry) return WaterRoll.dry;
    if (t < dry + light) return WaterRoll.light;
    return WaterRoll.wet;
  }
}

/// Absolutely stunning per-biome color kit for the board painter.
class WarBiome {
  final WarBiomeId id;
  final String name;
  final Color plains;
  final Color plainsAlt;
  final Color hill;
  final Color forestCanopy;
  final Color forestTrunk;
  final Color forestDeep;
  final Color mountain;
  final Color mountainSnow;
  final Color mountainShade;
  final Color water;
  final Color waterDeep;
  final Color waterFoam;
  final Color bridge;
  final Color skirt;
  final Color skirtLeaf;
  final Color skirtLeafDeep;
  final Color ringGlow;

  const WarBiome({
    required this.id,
    required this.name,
    required this.plains,
    required this.plainsAlt,
    required this.hill,
    required this.forestCanopy,
    required this.forestTrunk,
    required this.forestDeep,
    required this.mountain,
    required this.mountainSnow,
    required this.mountainShade,
    required this.water,
    required this.waterDeep,
    required this.waterFoam,
    required this.bridge,
    required this.skirt,
    required this.skirtLeaf,
    required this.skirtLeafDeep,
    required this.ringGlow,
  });

  static const meadow = WarBiome(
    id: WarBiomeId.meadow,
    name: 'Meadow',
    plains: Color(0xFF3D5C3A),
    plainsAlt: Color(0xFF355434),
    hill: Color(0xFF4A6B42),
    forestCanopy: Color(0xFF1F4A28),
    forestTrunk: Color(0xFF3A2A18),
    forestDeep: Color(0xFF163820),
    mountain: Color(0xFF6B7280),
    mountainSnow: Color(0xFFE8EEF5),
    mountainShade: Color(0xFF4B5563),
    water: Color(0xFF2B6CB0),
    waterDeep: Color(0xFF1A4A7A),
    waterFoam: Color(0xFFA0D2FF),
    bridge: Color(0xFF8B6914),
    skirt: Color(0xFF141D14),
    skirtLeaf: Color(0xFF1D3323),
    skirtLeafDeep: Color(0xFF17291C),
    ringGlow: Color(0xFF7C6BF0),
  );

  static const autumn = WarBiome(
    id: WarBiomeId.autumn,
    name: 'Autumn Heath',
    plains: Color(0xFF6B4E2E),
    plainsAlt: Color(0xFF5C4228),
    hill: Color(0xFF7A5A34),
    forestCanopy: Color(0xFFB85A1A),
    forestTrunk: Color(0xFF3D2410),
    forestDeep: Color(0xFF8A3A12),
    mountain: Color(0xFF7A828C),
    mountainSnow: Color(0xFFE5D5C0),
    mountainShade: Color(0xFF555C66),
    water: Color(0xFF3A6E8C),
    waterDeep: Color(0xFF244A60),
    waterFoam: Color(0xFFC8DDE8),
    bridge: Color(0xFF9A6B2E),
    skirt: Color(0xFF1A1410),
    skirtLeaf: Color(0xFF3A2414),
    skirtLeafDeep: Color(0xFF2A1A10),
    ringGlow: Color(0xFFD4A017),
  );

  static const sunscrub = WarBiome(
    id: WarBiomeId.sunscrub,
    name: 'Sunscrub',
    plains: Color(0xFFC2A36B),
    plainsAlt: Color(0xFFB8955C),
    hill: Color(0xFFD4B87A),
    forestCanopy: Color(0xFF6B7A3A),
    forestTrunk: Color(0xFF5A4020),
    forestDeep: Color(0xFF4A5A28),
    mountain: Color(0xFFA09078),
    mountainSnow: Color(0xFFE8DCC8),
    mountainShade: Color(0xFF6E6048),
    water: Color(0xFF5A9EAE),
    waterDeep: Color(0xFF2E6A78),
    waterFoam: Color(0xFFE0F0F4),
    bridge: Color(0xFF8B6914),
    skirt: Color(0xFF2A2218),
    skirtLeaf: Color(0xFF4A3A20),
    skirtLeafDeep: Color(0xFF3A2C18),
    ringGlow: Color(0xFFE8B923),
  );

  static const coast = WarBiome(
    id: WarBiomeId.coast,
    name: 'Coast',
    plains: Color(0xFFC8B896),
    plainsAlt: Color(0xFFB8A888),
    hill: Color(0xFFD0C0A0),
    forestCanopy: Color(0xFF2E6B4A),
    forestTrunk: Color(0xFF3A2A18),
    forestDeep: Color(0xFF1E4A34),
    mountain: Color(0xFF4A5560),
    mountainSnow: Color(0xFFD0D8E0),
    mountainShade: Color(0xFF2E3840),
    water: Color(0xFF1FA8A0),
    waterDeep: Color(0xFF0E6E6A),
    waterFoam: Color(0xFFB8FFF8),
    bridge: Color(0xFF8A7A5A),
    skirt: Color(0xFF0E1A1C),
    skirtLeaf: Color(0xFF1A3A34),
    skirtLeafDeep: Color(0xFF122A28),
    ringGlow: Color(0xFF6EE7D6),
  );

  static const tundra = WarBiome(
    id: WarBiomeId.tundra,
    name: 'Tundra',
    plains: Color(0xFFD8E4F0),
    plainsAlt: Color(0xFFC8D4E4),
    hill: Color(0xFFE4EEF8),
    forestCanopy: Color(0xFF2A4A3A),
    forestTrunk: Color(0xFF2A2018),
    forestDeep: Color(0xFF1A3028),
    mountain: Color(0xFF8A96A4),
    mountainSnow: Color(0xFFF5FAFF),
    mountainShade: Color(0xFF5A6674),
    water: Color(0xFF6AB0D4),
    waterDeep: Color(0xFF3A7098),
    waterFoam: Color(0xFFE8F8FF),
    bridge: Color(0xFF6A5A48),
    skirt: Color(0xFF121820),
    skirtLeaf: Color(0xFF1A2A24),
    skirtLeafDeep: Color(0xFF142018),
    ringGlow: Color(0xFF67C7FF),
  );

  static const nightglass = WarBiome(
    id: WarBiomeId.nightglass,
    name: 'Nightglass',
    plains: Color(0xFF2A2438),
    plainsAlt: Color(0xFF221E30),
    hill: Color(0xFF3A3250),
    forestCanopy: Color(0xFF6B4AC8),
    forestTrunk: Color(0xFF1A1028),
    forestDeep: Color(0xFF4A2A9A),
    mountain: Color(0xFF5A4A78),
    mountainSnow: Color(0xFFC8B8F0),
    mountainShade: Color(0xFF3A2A58),
    water: Color(0xFF1A1840),
    waterDeep: Color(0xFF0C0A28),
    waterFoam: Color(0xFFA090E8),
    bridge: Color(0xFF6A5080),
    skirt: Color(0xFF0A0814),
    skirtLeaf: Color(0xFF1A1430),
    skirtLeafDeep: Color(0xFF120E24),
    ringGlow: Color(0xFFB06BF0),
  );

  static const ashfall = WarBiome(
    id: WarBiomeId.ashfall,
    name: 'Ashfall',
    plains: Color(0xFF3A3430),
    plainsAlt: Color(0xFF2E2A28),
    hill: Color(0xFF4A4038),
    forestCanopy: Color(0xFFB04018),
    forestTrunk: Color(0xFF1A1010),
    forestDeep: Color(0xFF802010),
    mountain: Color(0xFF1A1414),
    mountainSnow: Color(0xFF6A4040),
    mountainShade: Color(0xFF0A0808),
    water: Color(0xFFC04010),
    waterDeep: Color(0xFF801808),
    waterFoam: Color(0xFFFFA040),
    bridge: Color(0xFF5A4030),
    skirt: Color(0xFF0C0808),
    skirtLeaf: Color(0xFF2A1410),
    skirtLeafDeep: Color(0xFF1A0C0C),
    ringGlow: Color(0xFFFF7DB0),
  );

  static WarBiome of(WarBiomeId id) {
    switch (id) {
      case WarBiomeId.autumn:
        return autumn;
      case WarBiomeId.sunscrub:
        return sunscrub;
      case WarBiomeId.coast:
        return coast;
      case WarBiomeId.tundra:
        return tundra;
      case WarBiomeId.nightglass:
        return nightglass;
      case WarBiomeId.ashfall:
        return ashfall;
      case WarBiomeId.meadow:
        return meadow;
    }
  }
}
