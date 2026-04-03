import 'supabase_service.dart';
import 'log_service.dart';
import '../models/exercise_log.dart';

class WakeNudgeService {
  /// Sends push to the absent member via [send_wake_nudge] (max 2 per tapper per card).
  /// Returns `null` on success, or a short error for the UI.
  static Future<String?> nudgeAbsentMember(ExerciseLog log) async {
    final me = SupabaseService.currentUserId;
    if (me == null || !log.isWakeCard) return 'Not signed in.';
    if (me == log.userId) return 'That card is about you — others can wake you.';

    try {
      await LogService.sendWakeNudge(log.id);
      return null;
    } catch (e) {
      final s = e.toString();
      if (s.contains('wake_nudge_limit')) {
        return 'You already sent 2 wake pings for this card.';
      }
      if (s.contains('cannot_nudge_self')) {
        return 'You can\'t nudge yourself on this card.';
      }
      if (s.contains('not_wake_card')) {
        return 'That feed row isn’t a wake card anymore.';
      }
      return 'Could not send: $e';
    }
  }
}
