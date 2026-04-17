import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

/// Notifies [GoRouter] when Supabase session is restored or changes (fixes web
/// cold start showing /auth while session loads).
///
/// [notifyListeners] is **not** called on every auth stream event: skipping
/// [AuthChangeEvent.tokenRefreshed] avoids full GoRouter refresh on JWT refresh,
/// which was a major source of UI jank. Other events only refresh when routing
/// state may have changed (sign-in/out, initial session, or user identity).
/// Also initialises Firebase for messaging (no permission prompt) on sign-in /
/// session restore — see [NotificationService.init].
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier() {
    _sub = AuthService.onAuthStateChange.listen(_onAuthState);
  }

  late final StreamSubscription<AuthState> _sub;

  /// Last session user id we notified for; null means last notified state was
  /// signed-out. Used to avoid redundant refreshes on [AuthChangeEvent.userUpdated]
  /// when nothing routing-relevant changed.
  String? _lastNotifiedUserId;

  void _onAuthState(AuthState state) {
    if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.initialSession) {
      // Web / home-screen PWA: defer FCM init slightly so the first frames and
      // taps aren’t competing with Firebase + service worker on the main isolate.
      if (kIsWeb) {
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          NotificationService.init();
        });
      } else {
        NotificationService.init();
      }
    }

    if (!_shouldNotifyRouter(state)) return;

    _lastNotifiedUserId = state.session?.user.id;
    notifyListeners();
  }

  bool _shouldNotifyRouter(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.tokenRefreshed:
        return false;
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.signedOut:
      case AuthChangeEvent.initialSession:
        return true;
      case AuthChangeEvent.userUpdated:
      case AuthChangeEvent.passwordRecovery:
      case AuthChangeEvent.mfaChallengeVerified:
        final uid = state.session?.user.id;
        return uid != _lastNotifiedUserId;
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
