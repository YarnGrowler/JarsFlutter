import 'package:supabase_flutter/supabase_flutter.dart';

/// DB column is [profiles.username]. Auth metadata uses the same key `username`
/// (set at signup). Some flows use `display_name` / `full_name` — we accept those too.
String? displayNameFromUserMetadata(User? user) {
  final m = user?.userMetadata;
  if (m == null) return null;
  for (final k in ['username', 'display_name', 'full_name', 'name']) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}
