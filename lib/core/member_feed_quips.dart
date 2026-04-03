/// Discord-style variants for join / kick system feed rows.
class MemberFeedQuips {
  MemberFeedQuips._();

  static String joinFeedLine(String username, int pick) {
    final u = username.trim().isEmpty ? 'Someone' : username.trim();
    switch (pick % 8) {
      case 0:
        return '$u slipped into the room.';
      case 1:
        return '$u has entered the chat.';
      case 2:
        return 'New challenger: $u just joined.';
      case 3:
        return ' $u is here now.';
      case 4:
        return '$u spawned in the room.';
      case 5:
        return 'The squad grows — welcome $u.';
      case 6:
        return '$u grabbed a locker in this room.';
      default:
        return 'Look alive — $u joined the party.';
    }
  }

  static String kickFeedLine(String username, int pick) {
    final u = username.trim().isEmpty ? 'Someone' : username.trim();
    switch (pick % 8) {
      case 0:
        return '$u was yeeted from the room.';
      case 1:
        return '$u got the boot 🫣.';
      case 2:
        return 'Poof — $u is no longer in this room.';
      case 3:
        return '$u has left the building (involuntarily).';
      case 4:
        return 'Server said no: $u was removed.';
      case 5:
        return '$u\'s spot got revoked.';
      case 6:
        return 'Admin kick: $u won\'t see this room anymore.';
      default:
        return '$u was removed — they can re-join with the code if you let them.';
    }
  }
}
