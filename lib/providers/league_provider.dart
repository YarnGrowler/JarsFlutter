import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/demo_mode.dart';
import '../models/league.dart';
import '../services/league_service.dart';
import 'active_room_provider.dart';
import 'war_providers.dart';

/// The current ladder snapshot. Demo Mode: computed locally from the Clan War
/// ([WarGame]) — no Supabase. Real mode: the Supabase-backed weekly model.
final leagueProvider = FutureProvider<LeagueTable?>((ref) async {
  if (kDemoMode) {
    final game = ref.watch(warGameProvider);
    return game.buildTable();
  }
  final room = ref.watch(activeRoomProvider);
  if (room == null) return null;
  return LeagueService.getLeague(room);
});
