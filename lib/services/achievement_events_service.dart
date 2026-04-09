import '../models/achievement_unlock_toast.dart';
import 'supabase_service.dart';

class AchievementInvokeResult {
  final List<String> hints;
  final bool hadUnlocks;
  final List<AchievementUnlockToast> unlockToasts;

  const AchievementInvokeResult({
    required this.hints,
    required this.hadUnlocks,
    required this.unlockToasts,
  });
}

/// Server-side achievements (Edge `process-achievements`).
class AchievementEventsService {
  static Future<AchievementInvokeResult?> processAfterLog(String logId) async {
    try {
      final res = await SupabaseService.client.functions.invoke(
        'process-achievements',
        body: <String, dynamic>{'log_id': logId},
      );
      final data = res.data;
      if (data is! Map) return null;
      final ok = data['ok'] == true;
      if (!ok) return null;
      final uid = SupabaseService.currentUserId;
      final hintsRaw = data['progress_hints'];
      final hints = hintsRaw is List
          ? hintsRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : <String>[];
      final unlocksRaw = data['unlocks'];
      final toasts = <AchievementUnlockToast>[];
      if (unlocksRaw is List && uid != null) {
        for (final u in unlocksRaw) {
          if (u is! Map) continue;
          if (u['user_id']?.toString() != uid) continue;
          final line = u['line']?.toString() ?? '';
          if (line.isEmpty) continue;
          final meta = u['meta']?.toString();
          toasts.add(AchievementUnlockToast(
            line: line,
            meta: meta != null && meta.isNotEmpty ? meta : null,
          ));
        }
      }
      final hadUnlocks = toasts.isNotEmpty;
      return AchievementInvokeResult(
        hints: hints,
        hadUnlocks: hadUnlocks,
        unlockToasts: toasts,
      );
    } catch (_) {
      return null;
    }
  }
}
