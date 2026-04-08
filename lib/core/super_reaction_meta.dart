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
    label: 'Feral',
    displayEmoji: '🔥',
    cost: 12,
  ),
 
  SuperReactionDef(
    id: 'meteor',
    label: 'Skill issue',
    displayEmoji: '💀',
    cost: 18,
  ),
  SuperReactionDef(
    id: 'bubble',
    label: 'Gremlin',
    displayEmoji: '🧌',
    cost: 10,
  ),
  SuperReactionDef(
    id: 'crown',
    label: 'Rent free',
    displayEmoji: '🧠',
    cost: 20,
  ),
  SuperReactionDef(
    id: 'thunder',
    label: 'Main character',
    displayEmoji: '🎬',
    cost: 10,
  ),
  SuperReactionDef(
    id: 'heartbeat',
    label: 'Unhinged',
    displayEmoji: '😵‍💫',
    cost: 11,
  ),
  SuperReactionDef(
    id: 'rainbow',
    label: 'Chaos',
    displayEmoji: '🌈',
    cost: 13,
  ),
  SuperReactionDef(
    id: 'confetti',
    label: 'Touch grass',
    displayEmoji: '🌿',
    cost: 15,
  ),
  SuperReactionDef(
    id: 'laser',
    label: 'Doom scroll',
    displayEmoji: '📱',
    cost: 16,
  ),
  SuperReactionDef(
    id: 'orbit',
    label: 'UFO',
    displayEmoji: '🛸',
    cost: 14,
  ),
  SuperReactionDef(
    id: 'bloom',
    label: 'Delulu',
    displayEmoji: '🫧',
    cost: 12,
  ),
   SuperReactionDef(
    id: 'galaxy',
    label: 'Void spiral',
    displayEmoji: '🌀',
    cost: 14,
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

/// Emoji (or fallback) for UI / celebration rain — never show raw `sr:*` strings.
String displayEmojiForStoredReaction(String stored) {
  final d = tryParseSuperReaction(stored);
  if (d != null) return d.displayEmoji;
  if (isSuperReactionKey(stored)) return '✨';
  return stored;
}

bool storedReactionIsSuper(String stored) => isSuperReactionKey(stored);
