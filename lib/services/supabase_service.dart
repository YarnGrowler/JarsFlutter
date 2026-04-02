import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
  static SupabaseStorageClient get storage => client.storage;

  static String? get currentUserId => auth.currentUser?.id;

  static Stream<AuthState> get onAuthStateChange =>
      auth.onAuthStateChange;
}
