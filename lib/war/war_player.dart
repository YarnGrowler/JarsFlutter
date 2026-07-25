import 'war_types.dart';

/// A combatant in the war — you, a crewmate, or an enemy. Each carries their
/// OWN resource pool (the single-bank economy is gone): resources fund building,
/// attacking, AND defending, so a broke player's sector stops fighting back.
class WarPlayer {
  final String id;
  String name;
  String emoji;
  int colorValue;
  final WarSide side;
  final bool isYou;

  /// True for AI-controlled players only: the solo/offline crew and every
  /// enemy. Real room teammates (seated via `WarGame.applyRoomRoster`) are
  /// always false — their base sector is theirs to design, never auto-built.
  final bool isBot;
  AiLevel ai;

  /// Continuous difficulty dial: multiplies the tier's competence (the enemy
  /// slider pushes past master toward 1.5 — brutal).
  double skillMul;

  double resources;
  bool ready; // locked in their prep contribution

  /// Total ⚡ this player has had available THIS prep — the starting stipend
  /// plus every workout logged since, whether or not they've spent it yet.
  /// This (summed across the real crew, bots excluded) is what the enemy's
  /// war chest is floored against at `startWar()` — real effort, not a
  /// number picked before anyone logged a single workout.
  double prepEarned = 0;

  /// Effective competence 0..1.5 — ALWAYS use this instead of AiData.skill.
  double get skill => (AiData.skill(ai) * skillMul).clamp(0.0, 1.5);

  /// Effective income multiplier.
  double get incomeMul => (0.7 + skill * 0.8);

  /// Trained, ready-to-deploy troops (Training Grounds). Deploying consumes
  /// from here — the ⚡ was paid at training time.
  Map<TroopType, int> army = {};

  // per-war tallies (reset each war)
  int troopsLost = 0;
  double resourcesSpent = 0;
  double destructionDealt = 0; // % of the enemy base this player razed

  WarPlayer({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    required this.side,
    required this.ai,
    this.isYou = false,
    this.isBot = false,
    this.skillMul = 1.0,
    this.resources = 0,
    this.ready = false,
  });

  bool get isAi => !isYou;

  void resetWarTallies() {
    troopsLost = 0;
    resourcesSpent = 0;
    destructionDealt = 0;
    prepEarned = 0;
  }

  int armyCount(TroopType t) => army[t] ?? 0;
  int get armyTotal => army.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'color': colorValue,
        'side': side.index,
        'isYou': isYou,
        'isBot': isBot,
        'ai': ai.index,
        'mul': skillMul,
        'res': resources,
        'prepEarned': prepEarned,
        'ready': ready,
        'army': {for (final e in army.entries) '${e.key.index}': e.value},
      };

  /// [roomSeated]: for saves from before `isBot` existed, we have to guess —
  /// enemies are always bots, and everyone else is a bot only in solo/offline
  /// saves (no real room). Ignored once the JSON carries an explicit `isBot`.
  factory WarPlayer.fromJson(Map<String, dynamic> j, {bool roomSeated = false}) {
    final side = WarSide.values[(j['side'] as num).toInt()];
    final isYou = j['isYou'] == true;
    final legacyIsBot = side == WarSide.enemy || !roomSeated;
    final p = WarPlayer(
      id: j['id'] as String,
      name: j['name'] as String,
      emoji: j['emoji'] as String? ?? '🧑',
      colorValue: (j['color'] as num?)?.toInt() ?? 0xFF7C6FFF,
      side: side,
      isYou: isYou,
      isBot: j.containsKey('isBot') ? j['isBot'] == true : (!isYou && legacyIsBot),
      ai: AiLevel.values[(j['ai'] as num?)?.toInt() ?? 1],
      skillMul: (j['mul'] as num?)?.toDouble() ?? 1.0,
      resources: (j['res'] as num?)?.toDouble() ?? 0,
      ready: j['ready'] == true,
    );
    p.prepEarned = (j['prepEarned'] as num?)?.toDouble() ?? 0;
    final aj = j['army'] as Map<String, dynamic>? ?? {};
    aj.forEach((k, v) {
      final idx = int.tryParse(k);
      if (idx != null && idx >= 0 && idx < TroopType.values.length) {
        p.army[TroopType.values[idx]] = (v as num).toInt();
      }
    });
    return p;
  }
}
