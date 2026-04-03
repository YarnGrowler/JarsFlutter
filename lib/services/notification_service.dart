import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'foreground_push_display_stub.dart'
    if (dart.library.html) 'foreground_push_display_web.dart';
import 'supabase_service.dart';

// ── VAPID key: Firebase Console → Cloud Messaging → Web Push certificates ──
const _kVapidKey =
    'BObFaztoPMeW_PjcCJGMvRBTUGJ4Z7QvY6GhkiD8qVL5M7LklHmQ2iqDS9j0s4ZOBxVasoSvlCku_n-SHmHVqys';

/// Push icon path on web (same origin as the app, e.g. Vercel).
const kWebPushIconPath = '/icons/jars-notification.svg';

/// Handles FCM token registration and push via Supabase `notifications` table.
/// Tokens are stored in [user_fcm_tokens] so each user can have **multiple devices**.
class NotificationService {
  static final _db = SupabaseService.client;
  static bool _tokenListenersAttached = false;
  static bool _foregroundWebAttached = false;

  static Future<void> init() async {
    await registerToken();
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  /// Registers this device’s FCM token (upsert). Safe after every sign-in / new browser.
  static Future<bool> registerToken() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'AIzaSyDI1yg8xMRFK42Nz6n2Tiiwq7_ugIW8RUo',
            authDomain: 'jarsflutter.firebaseapp.com',
            projectId: 'jarsflutter',
            storageBucket: 'jarsflutter.firebasestorage.app',
            messagingSenderId: '93048274469',
            appId: '1:93048274469:web:dfc56256d2aeede1ad49cc',
            measurementId: 'G-X14XTW7GJP',
          ),
        );
      }

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        developer.log(
          'NotificationService: permission ${settings.authorizationStatus}',
          name: 'Jars',
        );
        return false;
      }

      final token = kIsWeb
          ? await messaging.getToken(vapidKey: _kVapidKey)
          : await messaging.getToken();

      if (token == null || token.isEmpty) {
        developer.log(
          'NotificationService: getToken returned null (web: check firebase-messaging-sw.js)',
          name: 'Jars',
        );
        return false;
      }

      if (!_tokenListenersAttached) {
        _tokenListenersAttached = true;
        messaging.onTokenRefresh.listen((t) => _saveFcmToken(t));
      }

      if (kIsWeb && !_foregroundWebAttached) {
        _foregroundWebAttached = true;
        attachForegroundWebPushDisplay();
      }

      final saved = await _saveFcmToken(token);
      if (!saved) {
        developer.log(
          'NotificationService: token not saved (signed in?)',
          name: 'Jars',
        );
      }
      return saved;
    } catch (e, st) {
      developer.log('NotificationService.registerToken: $e\n$st', name: 'Jars');
      return false;
    }
  }

  /// Saves to [user_fcm_tokens] (multi-device) and mirrors last token on [profiles] for legacy tools.
  static Future<bool> _saveFcmToken(String token) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      developer.log(
        'NotificationService._saveFcmToken: no Supabase user',
        name: 'Jars',
      );
      return false;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final platform = _platformLabel();
    try {
      await _db.from('user_fcm_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': platform,
          'last_seen_at': now,
        },
        onConflict: 'token',
      );
      await _db
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
      if (kDebugMode) {
        developer.log(
          'NotificationService: token registered ($platform, ${token.length} chars)',
          name: 'Jars',
        );
      }
      return true;
    } catch (e) {
      developer.log('NotificationService._saveFcmToken: $e', name: 'Jars');
      try {
        await _db
            .from('profiles')
            .update({'fcm_token': token})
            .eq('id', userId);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static Future<bool> sendNotification({
    required String targetUserId,
    required String body,
  }) async {
    try {
      await _db.from('notifications').insert({
        'user_id': targetUserId,
        'body': body,
      });
      return true;
    } catch (e) {
      developer.log('NotificationService.sendNotification: $e', name: 'Jars');
      return false;
    }
  }
}
