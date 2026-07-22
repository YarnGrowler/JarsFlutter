import 'supabase_service.dart';

/// Bridges [WarGame]'s serialized state to a REAL room's shared war —
/// `room_wars` in Supabase (see `supabase_patches/48_room_wars.sql`). Every
/// teammate reads and writes the SAME row; a compare-and-swap version stops
/// one player's save from silently erasing another's.
class WarSyncService {
  static final _db = SupabaseService.client;

  /// Fetch the room's war, creating it (version 0, seeded with
  /// [initialStateIfMissing]) on first-ever use. Always returns a row.
  static Future<(int version, Map<String, dynamic> state)> ensure(
    String roomId,
    Map<String, dynamic> initialStateIfMissing,
  ) async {
    final raw = await _db.rpc('ensure_room_war', params: {
      'p_room_id': roomId,
      'p_initial_state': initialStateIfMissing,
    });
    final row = _firstRow(raw);
    return (
      (row['version'] as num).toInt(),
      Map<String, dynamic>.from(row['state'] as Map),
    );
  }

  /// Compare-and-swap save. `conflict == true` means a teammate saved first —
  /// `version`/`state` in the result are the WINNING row, not what was sent;
  /// the caller should apply it (loadFromJson) instead of retrying blindly.
  static Future<(int version, Map<String, dynamic> state, bool conflict)> save(
    String roomId,
    Map<String, dynamic> state,
    int expectedVersion,
  ) async {
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
