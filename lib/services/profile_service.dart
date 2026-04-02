import '../core/user_display_name.dart';
import '../models/profile.dart';
import 'supabase_service.dart';

class ProfileService {
  static Future<Profile?> getByUserId(String id) async {
    final row = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromJson(Map<String, dynamic>.from(row));
  }

  /// Ensures a [profiles] row exists (FK targets for rooms, room_members, scores).
  /// Safe if the auth trigger already ran. Requires RLS policy "Users can insert own profile".
  static Future<void> ensureProfileRow() async {
    final client = SupabaseService.client;
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    final existing = await client
        .from('profiles')
        .select('id')
        .eq('id', uid)
        .maybeSingle();
    if (existing != null) return;

    final user = SupabaseService.auth.currentUser;
    var base = displayNameFromUserMetadata(user) ??
        user?.email?.split('@').first ??
        'user';
    base = base.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').toLowerCase();
    if (base.length > 24) base = base.substring(0, 24);
    if (base.isEmpty) base = 'user';
    final username = '${base}_${uid.replaceAll('-', '').substring(0, 8)}';

    try {
      await client.from('profiles').insert({'id': uid, 'username': username});
    } catch (e1) {
      try {
        await client.from('profiles').insert({
          'id': uid,
          'username': 'u_${uid.replaceAll('-', '')}',
        });
      } catch (e2) {
        throw StateError('Could not create profile row: $e1 (fallback: $e2)');
      }
    }
  }
}
