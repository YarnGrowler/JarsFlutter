import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AuthService {
  static final _auth = SupabaseService.auth;

  /// Uses a real email address (Supabase Auth). [username] is stored in user metadata for the leaderboard.
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final name = username.trim();
    return _auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      // DB trigger + RLS use [profiles.username]; duplicate display_name for Auth UI/tools.
      data: {'username': name, 'display_name': name},
    );
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  static Session? get currentSession => _auth.currentSession;
  static User? get currentUser => _auth.currentUser;

  static Stream<AuthState> get onAuthStateChange =>
      _auth.onAuthStateChange;
}
