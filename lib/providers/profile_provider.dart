import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';

/// Row in [profiles] — authoritative for leaderboard / feed; refresh when auth changes.
final currentUserProfileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateProvider);
  final uid = SupabaseService.currentUserId;
  if (uid == null) return null;
  return ProfileService.getByUserId(uid);
});
