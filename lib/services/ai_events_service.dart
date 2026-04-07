import 'supabase_service.dart';

/// Server-side AI narrative events (Edge `process-ai-events`).
/// Requires `supabase/functions/process-ai-events` deployed + OPENAI_API_KEY secret.
class AiEventsService {
  static Future<void> processAfterLog(String logId) async {
    try {
      await SupabaseService.client.functions.invoke(
        'process-ai-events',
        body: <String, dynamic>{'log_id': logId},
      );
    } catch (_) {
      // Non-fatal: logging still succeeded if Edge is down or key missing.
    }
  }
}
