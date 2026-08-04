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

/// Call on SIGN-OUT, alongside [WarGame.resetForSignOut]. Without this, a
/// different real user signing in on the same device/browser would find
/// `_syncedRoomId` already matching (if they happen to share a room with the
/// outgoing user) and skip straight to the "already synced" fast path —
/// never re-fetching, never re-subscribing fresh for THEIR session.
void resetWarRoomSync() {
  _syncedRoomId = null;
  _warRealtimeSub?.cancel();
  _warRealtimeSub = null;
}

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
      // Captured BEFORE the fetch: WarGame.load() already applied whatever
      // this device saved LOCALLY (SharedPreferences always gets written
      // regardless of whether the remote push behind it ever landed). If
      // that local save is further along than what the server hands back —
      // a push that silently failed, conflicted against a stale version,
      // or simply hadn't landed yet when this device reloaded — blindly
      // applying the fetched state would REVERT real progress. Exactly the
      // reported bug: NEXT WAR confirmed, then every reload came back
      // showing the old battle report and the old base.
      final localSeason = game.seasonIndex;
      final localWar = game.warIndex;
      final (version, state) =
          await WarSyncService.ensure(room.id, game.toJson());
      final remoteSeason = (state['season'] as num?)?.toInt() ?? 0;
      final remoteWar = (state['war'] as num?)?.toInt() ?? 0;
      final localIsAhead = localSeason > remoteSeason ||
          (localSeason == remoteSeason && localWar > remoteWar);
      if (localIsAhead) {
        // Don't pull the stale remote state — push the local (further
        // along) one to correct the server instead. game's fields already
        // reflect what WarGame.load() set them to; just fix roomVersion
        // so the push's compare-and-swap has the right expected version.
        game.roomVersion = version;
        WarGame.onRoomSave = _pushRoomSave;
        await _pushRoomSave(game);
      } else {
        game.loadFromJson(state);
        // `activePlayerId` is PER-DEVICE identity, never shared state — a
        // remote blob's 'active' field belongs to whoever last saved it,
        // not to us. Reassert immediately, before anything can rebuild and
        // read the wrong one (see the identical guard in applyRoomRoster
        // below).
        game.activePlayerId = myId;
        game.roomVersion = version;
        WarGame.onRoomSave = _pushRoomSave;
      }
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

  List<Map<String, dynamic>> rows;
  try {
    rows = await ref.watch(roomMembersProvider(room.id).future);
  } catch (e) {
    // Members fetch failed — still seat THIS player to the room so a
    // workout log can't silently earn 0 war ⚡ while sync is unhappy.
    if (kDebugMode) debugPrint('WarSync: members load failed: $e');
    game.applyRoomRoster(
      realRoomId: room.id,
      myUserId: myId,
      myUsername: 'You',
      members: const [],
    );
    return;
  }
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
      // A workout credit that lost the CAS race must not vanish — put it
      // back on this device's player and retry once.
      g.reapplyUnsyncedEarn();
      final (v2, s2, c2) =
          await WarSyncService.save(roomId, g.toJson(), g.roomVersion);
      if (c2) {
        g.loadFromJson(s2);
        g.activePlayerId = myId;
        g.roomVersion = v2;
        g.reapplyUnsyncedEarn();
        // Conflicted TWICE in a row — this device's own state (a NEXT WAR
        // transition, a build, whatever) never actually landed; it kept
        // losing to something else. Silently moving on here is exactly
        // what made the room-desync bugs invisible until a reload.
        g.lastSyncError =
            'Your last change didn\'t sync (kept losing to another save) — '
            'try again.';
      } else {
        g.roomVersion = v2;
        g.clearUnsyncedEarn();
        g.lastSyncError = null;
      }
    } else {
      g.roomVersion = version;
      g.clearUnsyncedEarn();
      g.lastSyncError = null;
    }
    g.notifyListeners();
  } catch (e) {
    // Used to be swallowed into a debug-only print — invisible on a real
    // deployed build, so a failed NEXT WAR (or any other save) looked
    // like it worked until the next reload quietly reverted it. The local
    // SharedPreferences mirror still has this save; the next mutating
    // action retries the push naturally, but the CALLER (via
    // flushPendingSave + lastSyncError) can now tell the user it hasn't
    // actually landed yet instead of assuming success.
    g.lastSyncError = e.toString();
    g.notifyListeners();
    if (kDebugMode) debugPrint('WarSync: push failed (will retry later): $e');
  }
}
