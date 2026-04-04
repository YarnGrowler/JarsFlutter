import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

/// Notifies [GoRouter] when Supabase session is restored or changes (fixes web
/// cold start showing /auth while session loads).
/// Also initialises Firebase for messaging (no permission prompt) on sign-in /
/// session restore — see [NotificationService.init].
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier() {
    _sub = AuthService.onAuthStateChange.listen((state) {
      notifyListeners();
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
    });
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
