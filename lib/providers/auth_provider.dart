import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return AuthService.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  return AuthService.currentUser;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return AuthService.currentUser != null;
});
