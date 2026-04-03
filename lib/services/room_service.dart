import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'profile_service.dart';
import 'supabase_service.dart';
import '../models/room.dart';
import '../core/constants.dart';
import '../core/exercise_data.dart';

class RoomService {
  static final _db = SupabaseService.client;

  static String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(
      kRoomCodeLength,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
  }

  static void _log(String step, Object? e, [StackTrace? st]) {
    developer.log(
      'RoomService: $step — $e',
      name: 'Jars',
      error: e,
      stackTrace: st,
    );
    if (kDebugMode && st != null) {
      debugPrintStack(stackTrace: st, label: 'RoomService: $step');
    }
  }

  static Future<Room> createRoom({
    required String name,
    required int maxParticipants,
  }) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      throw StateError('Not signed in — cannot create a room.');
    }

    try {
      await ProfileService.ensureProfileRow();
    } catch (e, st) {
      _log('ensureProfileRow', e, st);
      throw StateError(
        'Could not verify your profile. Apply supabase_patches/03_profiles_insert_own_row.sql '
        'in the Supabase SQL editor, then try again. ($e)',
      );
    }

    final roomCode = _generateRoomCode();

    try {
      await _db.from('rooms').insert({
        'name': name,
        'admin_id': userId,
        'room_code': roomCode,
        'max_participants': maxParticipants,
      });
    } catch (e, st) {
      _log('rooms.insert', e, st);
      rethrow;
    }

    // Fetch by code so we don't depend on INSERT ... RETURNING + RLS quirks.
    final Map<String, dynamic>? row = await _db
        .from('rooms')
        .select()
        .eq('room_code', roomCode)
        .maybeSingle();

    if (row == null) {
      throw StateError(
        'Room insert may have succeeded but it is not visible. '
        'Run supabase_patches/01_rooms_select_rls_for_creators.sql (rooms SELECT for creators).',
      );
    }

    late final Room room;
    try {
      room = Room.fromJson(Map<String, dynamic>.from(row));
    } catch (e, st) {
      _log('Room.fromJson', e, st);
      rethrow;
    }

    try {
      await _db.from('room_members').insert({
        'room_id': room.id,
        'user_id': userId,
      });
    } catch (e, st) {
      _log('room_members.insert', e, st);
      rethrow;
    }

    try {
      await _db.from('scores').insert({
        'room_id': room.id,
        'user_id': userId,
        'total_score': 0,
        'daily_points': 0,
        'last_daily_reset': DateTime.now().toIso8601String().split('T')[0],
        'streak_current': 0,
        'streak_highest': 0,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e, st) {
      _log('scores.insert', e, st);
      rethrow;
    }

    try {
      await _seedSystemExercises(room.id);
    } catch (e, st) {
      _log('_seedSystemExercises', e, st);
      rethrow;
    }

    return room;
  }

  static Future<Room?> joinByCode(String code) async {
    final userId = SupabaseService.currentUserId!;
    await ProfileService.ensureProfileRow();

    final rows = await _db
        .from('rooms')
        .select()
        .eq('room_code', code.toUpperCase().trim());

    if (rows.isEmpty) return null;

    final room = Room.fromJson(Map<String, dynamic>.from(rows.first as Map));

    final memberCount = await _db
        .from('room_members')
        .select()
        .eq('room_id', room.id);

    if (memberCount.length >= room.maxParticipants) return null;

    await _db.from('room_members').upsert({
      'room_id': room.id,
      'user_id': userId,
    });

    await _db.from('scores').upsert({
      'room_id': room.id,
      'user_id': userId,
      'total_score': 0,
      'daily_points': 0,
      'last_daily_reset': DateTime.now().toIso8601String().split('T')[0],
      'streak_current': 0,
      'streak_highest': 0,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return room;
  }

  static Future<List<Room>> getUserRooms() async {
    final userId = SupabaseService.currentUserId!;

    final memberRows = await _db
        .from('room_members')
        .select('room_id')
        .eq('user_id', userId);

    if (memberRows.isEmpty) return [];

    final roomIds =
        memberRows.map((r) => r['room_id'] as String).toList();

    final rooms = await _db
        .from('rooms')
        .select()
        .inFilter('id', roomIds)
        .order('created_at', ascending: false);

    return rooms
        .map((r) => Room.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  static Future<void> leaveRoom(String roomId) async {
    final userId = SupabaseService.currentUserId!;
    await _db
        .from('room_members')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', userId);
  }

  static Future<void> deleteRoom(String roomId) async {
    await _db.from('rooms').delete().eq('id', roomId);
  }

  static Future<void> updateRoom(String roomId, Map<String, dynamic> updates) async {
    await _db.from('rooms').update(updates).eq('id', roomId);
  }

  static Future<void> kickMember(String roomId, String userId) async {
    await _db
        .from('room_members')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', userId);
  }

  static Future<List<Map<String, dynamic>>> getRoomMembers(String roomId) async {
    final rows = await _db
        .from('room_members')
        .select('user_id, joined_at, profiles(username)')
        .eq('room_id', roomId);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Zeros all score fields for every member of [roomId], and clears room logs.
  static Future<void> resetRoomScores(String roomId) async {
    await _db.from('exercise_logs').delete().eq('room_id', roomId);
    await _db.from('scores').update({
      'total_score': 0,
      'daily_points': 0,
      'streak_current': 0,
      'streak_highest': 0,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('room_id', roomId);
  }

  static Future<void> _seedSystemExercises(String roomId) async {
    final exercises = kSystemExercises.map((e) {
      final m = <String, dynamic>{
        'room_id': roomId,
        'name': e.name,
        'points': e.points,
        'icon': e.icon,
        'category': e.category,
        'supports_weight': e.supportsWeight,
        'created_by': 'system',
      };
      if (e.weightThreshold != null) {
        m['weight_threshold'] = e.weightThreshold;
      }
      if (e.weightMultiplier != null) {
        m['weight_multiplier'] = e.weightMultiplier;
      }
      return m;
    }).toList();

    await _db.from('exercises').insert(exercises);
  }
}
