import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/room_analytics_service.dart';
import '../services/supabase_service.dart';
import 'active_room_provider.dart';

/// 7 / 30 / 90-day window for [roomAnalyticsProvider].
final analyticsRangeDaysProvider = StateProvider<int>((ref) => 30);

final roomAnalyticsProvider =
    FutureProvider.autoDispose<RoomAnalyticsSnapshot?>((ref) async {
  final room = ref.watch(activeRoomProvider);
  final uid = SupabaseService.currentUserId;
  final days = ref.watch(analyticsRangeDaysProvider);
  if (room == null || uid == null) return null;
  return RoomAnalyticsService.load(
    roomId: room.id,
    userId: uid,
    rangeDays: days,
  );
});
