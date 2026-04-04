import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/room.dart';
import '../services/room_service.dart';

const _activeRoomKey = 'active_room_id';

final activeRoomProvider =
    StateNotifierProvider<ActiveRoomNotifier, Room?>((ref) {
  return ActiveRoomNotifier();
});

class ActiveRoomNotifier extends StateNotifier<Room?> {
  ActiveRoomNotifier() : super(null) {
    _loadSavedRoom();
  }

  Future<void> _loadSavedRoom() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_activeRoomKey);
    if (savedId != null) {
      final rooms = await RoomService.getUserRooms();
      final match = rooms.where((r) => r.id == savedId);
      if (match.isNotEmpty) {
        state = match.first;
      } else if (rooms.isNotEmpty) {
        setRoom(rooms.first);
      }
    } else {
      final rooms = await RoomService.getUserRooms();
      if (rooms.isNotEmpty) {
        setRoom(rooms.first);
      }
    }
  }

  Future<void> setRoom(Room room) async {
    state = room;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeRoomKey, room.id);
  }

  void clear() {
    state = null;
    SharedPreferences.getInstance().then((p) => p.remove(_activeRoomKey));
  }

  Future<void> refresh() async {
    if (state != null) {
      final rooms = await RoomService.getUserRooms();
      final match = rooms.where((r) => r.id == state!.id);
      if (match.isNotEmpty) {
        state = match.first;
      }
    }
  }
}
