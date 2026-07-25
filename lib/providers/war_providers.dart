import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';
import '../services/war_sync_service.dart';
import '../war/war_game.dart';
import 'active_room_provider.dart';
import 'room_provider.dart';

/// The Clan War master. Widgets watch this to rebuild on any state change
/// (resources, base edits, the war timeline, results).
final warGameProvider =
    ChangeNotifierProvider<WarGame>((ref) => WarGame.instance);

// Which room we've already done the (expensive, one-time-per-room) remote
// load + realtime subscribe for THIS app session. Module-level, matching
// WarGame's own top-level-singleton style — re-running this on every widget
// rebuild would be wasteful and, worse, could stomp an in-progress local
// edit by re-applying a now-stale snapshot over it.
String? _syncedRoomId;
StreamSubscription<List<Map<String, dynamic>>>? _warRealtimeSub;

/// Keeps [WarGame] true to your REAL room: your teammates are whoever's
/// actually in the room (no fake AI crew), the enemy clan is sized to match,
/// and — once, per room, per session — the shared war state is pulled from
/// Supabase and kept in sync (a teammate's raid or build lands on your
/// screen without you touching anything).
///
/// `ref.watch`ing this from the war hub is the "catch up on open" moment,
/// same as [WarGame.syncToWallClock] is for time.
///
/// Solo/offline play (no active room, e.g. pre-onboarding, or the network is
/// simply unavailable) leaves [WarGame] on its local SharedPreferences
/// mirror — nothing here ever blocks the game from working offline.
final warRoomSyncProvider = FutureProvider<void>((ref) async {
  final room = ref.watch(activeRoomProvider);
  if (room == null) return;
  final myId = SupabaseService.currentUserId;
  if (myId == null) return;

  final game = WarGame.instance;
  // re-derived every time the provider fires, never persisted/trusted from a
  // shared blob — if the room's admin changes, this device finds out on its
  // very next rebuild.
  game.isRoomAdmin = room.adminId == myId;

  if (_syncedRoomId != room.id) {
    try {
      final (version, state) =
          await WarSyncService.ensure(room.id, game.toJson());
      game.loadFromJson(state);
      // `activePlayerId` is PER-DEVICE identity, never shared state — a
      // remote blob's 'active' field belongs to whoever last saved it, not
      // to us. Reassert immediately, before anything can rebuild and read
      // the wrong one (see the identical guard in applyRoomRoster below).
      game.activePlayerId = myId;
      game.roomVersion = version;
      WarGame.onRoomSave = _pushRoomSave;
      _warRealtimeSub?.cancel();
      _warRealtimeSub = WarSyncService.stream(room.id).listen(
        (rows) => _applyRemote(game, rows, myId),
        onError: (Object e) {
          if (kDebugMode) debugPrint('WarSync: realtime stream error: $e');
        },
      );
      game.notifyListeners();
      _syncedRoomId = room.id; // only mark done once everything succeeded
    } catch (e) {
      // offline, RLS not yet migrated, or a transient error — local play
      // keeps working untouched; we'll simply retry next time this fires
      if (kDebugMode) debugPrint('WarSync: initial room load failed: $e');
    }
  }

  final rows = await ref.watch(roomMembersProvider(room.id).future);
  String usernameOf(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map<String, dynamic>?;
    return profile?['username'] as String? ?? 'Player';
  }

  final mine = rows.where((r) => r['user_id'] == myId);
  final myUsername = mine.isNotEmpty ? usernameOf(mine.first) : 'You';
  final others = [
    for (final r in rows)
      if (r['user_id'] != myId)
        RosterMember(r['user_id'] as String, usernameOf(r)),
  ];

  game.applyRoomRoster(
    realRoomId: room.id,
    myUserId: myId,
    myUsername: myUsername,
    members: others,
  );
});

void _applyRemote(
    WarGame game, List<Map<String, dynamic>> rows, String myId) {
  if (rows.isEmpty) return;
  final row = rows.first;
  final remoteVersion = (row['version'] as num?)?.toInt() ?? -1;
  if (remoteVersion <= game.roomVersion) return; // our own echo, or stale
  final state = row['state'];
  if (state is! Map) return;
  game.loadFromJson(Map<String, dynamic>.from(state));
  // same identity guard as the initial load — a teammate's realtime save
  // carries THEIR activePlayerId; it must never leak onto this device.
  game.activePlayerId = myId;
  game.roomVersion = remoteVersion;
  game.notifyListeners();
}

/// Wired to [WarGame.onRoomSave]: push the latest state with a
/// compare-and-swap. A conflict means a teammate saved first — their version
/// wins, and we adopt it rather than silently overwriting it.
Future<void> _pushRoomSave(WarGame g) async {
  final roomId = g.roomId;
  if (roomId == null) return;
  // captured BEFORE the round-trip: this device's own identity, which the
  // conflict branch below must restore — a teammate's winning save carries
  // THEIR activePlayerId, and it must never leak onto this device.
  final myId = g.activePlayerId;
  try {
    final (version, state, conflict) =
        await WarSyncService.save(roomId, g.toJson(), g.roomVersion);
    if (conflict) {
      g.loadFromJson(state);
      g.activePlayerId = myId;
      g.roomVersion = version;
      g.syncConflicts++;
    } else {
      g.roomVersion = version;
    }
    g.notifyListeners();
  } catch (e) {
    // offline / transient — the local SharedPreferences mirror already has
    // this save; the next mutating action retries the push naturally
    if (kDebugMode) debugPrint('WarSync: push failed (will retry later): $e');
  }
}
