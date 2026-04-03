import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

/// Notifies [GoRouter] when Supabase session is restored or changes (fixes web
/// cold start showing /auth while session loads).
/// Also initialises FCM push notifications whenever the user signs in.
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier() {
    _sub = AuthService.onAuthStateChange.listen((state) {
      notifyListeners();
      // Init push notifications on sign-in or session restore
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.initialSession) {
        NotificationService.init();
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
