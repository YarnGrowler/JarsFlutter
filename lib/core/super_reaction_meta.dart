/// Premium reaction keys stored as [Reaction.emoji]: `sr:<id>`.
const String kSuperReactionPrefix = 'sr:';

class SuperReactionDef {
  final String id;
  final String label;
  final String displayEmoji;
  final int cost;

  const SuperReactionDef({
    required this.id,
    required this.label,
    required this.displayEmoji,
    required this.cost,
  });

  String get storageKey => '$kSuperReactionPrefix$id';
}

/// Twelve super reactions (point cost per use).
const List<SuperReactionDef> kSuperReactions = [
  SuperReactionDef(
    id: 'nova',
    label: 'Nova',
    displayEmoji: '🔥',
    cost: 12,
  ),
  SuperReactionDef(
    id: 'galaxy',
    label: 'Galaxy',
    displayEmoji: '🌌',
    cost: 14,
  ),
  SuperReactionDef(
    id: 'thunder',
    label: 'Thunder',
    displayEmoji: '⚡',
    cost: 10,
  ),
  SuperReactionDef(
    id: 'heartbeat',
    label: 'Heartbeat',
    displayEmoji: '💗',
    cost: 11,
  ),
  SuperReactionDef(
    id: 'rainbow',
    label: 'Rainbow',
    displayEmoji: '🌈',
    cost: 13,
  ),
  SuperReactionDef(
    id: 'confetti',
    label: 'Confetti',
    displayEmoji: '🎊',
    cost: 15,
  ),
  SuperReactionDef(
    id: 'laser',
    label: 'Laser',
    displayEmoji: '✴️',
    cost: 16,
  ),
  SuperReactionDef(
    id: 'orbit',
    label: 'Orbit',
    displayEmoji: '🛸',
    cost: 14,
  ),
  SuperReactionDef(
    id: 'bloom',
    label: 'Bloom',
    displayEmoji: '🌸',
    cost: 12,
  ),
  SuperReactionDef(
    id: 'meteor',
    label: 'Meteor',
    displayEmoji: '☄️',
    cost: 18,
  ),
  SuperReactionDef(
    id: 'bubble',
    label: 'Bubble',
    displayEmoji: '🫧',
    cost: 10,
  ),
  SuperReactionDef(
    id: 'crown',
    label: 'Crown',
    displayEmoji: '👑',
    cost: 20,
  ),
];

bool isSuperReactionKey(String emoji) =>
    emoji.startsWith(kSuperReactionPrefix);

SuperReactionDef? tryParseSuperReaction(String emoji) {
  if (!isSuperReactionKey(emoji)) return null;
  final id = emoji.substring(kSuperReactionPrefix.length);
  for (final d in kSuperReactions) {
    if (d.id == id) return d;
  }
  return null;
}

String superReactionNotificationLabel(String storageKey) {
  final d = tryParseSuperReaction(storageKey);
  if (d == null) return storageKey;
  return '${d.displayEmoji} ${d.label}';
}
