import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/onboarding_redo.dart';
import 'supabase_service.dart';

class AuthService {
  static final _auth = SupabaseService.auth;

  /// After sign-up when email confirmation sends a 6-digit code ([OtpType.signup]).
  static Future<AuthResponse> verifySignupOtp({
    required String email,
    required String token,
  }) {
    return _auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: token.trim(),
      type: OtpType.signup,
    );
  }

  static Future<void> resendSignupOtp({required String email}) {
    return _auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
    );
  }

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
    OnboardingRedoSession.end();
    await _auth.signOut();
  }

  static Session? get currentSession => _auth.currentSession;
  static User? get currentUser => _auth.currentUser;

  static Stream<AuthState> get onAuthStateChange =>
      _auth.onAuthStateChange;
}
