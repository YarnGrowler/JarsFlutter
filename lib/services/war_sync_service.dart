import 'dart:async';

import 'supabase_service.dart';

/// Bridges [WarGame]'s serialized state to a REAL room's shared war —
/// `room_wars` in Supabase (see `supabase_patches/48_room_wars.sql`). Every
/// teammate reads and writes the SAME row; a compare-and-swap version stops
/// one player's save from silently erasing another's.
class WarSyncService {
  static final _db = SupabaseService.client;

  /// Confirmed live in production (2026-08-04): the `authenticated` Postgres
  /// role this app runs RPCs as has an 8-second `statement_timeout` (a
  /// Supabase platform default, not something this codebase set). An
  /// actively-played room's `room_wars` row gets written VERY often (one
  /// real room was on save #1623) — under a moment of lock contention on
  /// that one hot row, a single `ensure_room_war`/`save_room_war` call can
  /// occasionally get killed by that timeout and come back as a 500,
  /// exactly matching a live API-log capture of this happening. It's a
  /// transient condition, not a broken query — a short retry is the right
  /// fix, not touching the platform's timeout config, which affects every
  /// other Supabase-backed feature in the app, not just this one.
  static const _retryDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  static Future<T> _withRetry<T>(Future<T> Function() attempt) async {
    for (var i = 0; i <= _retryDelays.length; i++) {
      try {
        return await attempt();
      } catch (e) {
        if (i == _retryDelays.length) rethrow;
        await Future<void>.delayed(_retryDelays[i]);
      }
    }
    throw StateError('unreachable');
  }

  /// Fetch the room's war, creating it (version 0, seeded with
  /// [initialStateIfMissing]) on first-ever use. Always returns a row.
  static Future<(int version, Map<String, dynamic> state)> ensure(
    String roomId,
    Map<String, dynamic> initialStateIfMissing,
  ) {
    return _withRetry(() async {
      final raw = await _db.rpc('ensure_room_war', params: {
        'p_room_id': roomId,
        'p_initial_state': initialStateIfMissing,
      });
      final row = _firstRow(raw);
      return (
        (row['version'] as num).toInt(),
        Map<String, dynamic>.from(row['state'] as Map),
      );
    });
  }

  /// Compare-and-swap save. `conflict == true` means a teammate saved first —
  /// `version`/`state` in the result are the WINNING row, not what was sent;
  /// the caller should apply it (loadFromJson) instead of retrying blindly.
  static Future<(int version, Map<String, dynamic> state, bool conflict)> save(
    String roomId,
    Map<String, dynamic> state,
    int expectedVersion,
  ) {
    return _withRetry(() async {
      final raw = await _db.rpc('save_room_war', params: {
        'p_room_id': roomId,
        'p_state': state,
        'p_expected_version': expectedVersion,
      });
      final row = _firstRow(raw);
      return (
        (row['version'] as num).toInt(),
        Map<String, dynamic>.from(row['state'] as Map),
        row['conflict'] == true,
      );
    });
  }

  /// Every change to the room's war, live — a teammate's move lands here
  /// without polling (same realtime pattern as LogService.streamRoomFeed on
  /// the room feed).
  static Stream<List<Map<String, dynamic>>> stream(String roomId) {
    return _db
        .from('room_wars')
        .stream(primaryKey: ['room_id']).eq('room_id', roomId);
  }

  static Map<String, dynamic> _firstRow(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    throw StateError('WarSyncService: unexpected rpc response shape: $raw');
  }
}
