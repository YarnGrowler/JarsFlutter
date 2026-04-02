import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room.dart';
import '../services/room_service.dart';

final userRoomsProvider = FutureProvider<List<Room>>((ref) async {
  return RoomService.getUserRooms();
});

final roomMembersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, roomId) async {
  return RoomService.getRoomMembers(roomId);
});
