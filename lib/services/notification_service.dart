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

/// Handles FCM token registration and push via Supabase `notifications` table.
class NotificationService {
  static final _db = SupabaseService.client;
  static bool _tokenListenersAttached = false;
  static bool _foregroundWebAttached = false;

  /// Idempotent: call after cold start / login. Uses [registerToken] when signed in.
  static Future<void> init() async {
    await registerToken();
  }

  /// Get FCM token, save to [profiles.fcm_token] for the **current** Supabase user.
  /// Call after sign-in (and after browser notification permission). Safe to call often.
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
          'NotificationService: getToken returned null (web: ensure web/firebase-messaging-sw.js exists and matches Firebase config)',
          name: 'Jars',
        );
        return false;
      }

      if (!_tokenListenersAttached) {
        _tokenListenersAttached = true;
        messaging.onTokenRefresh.listen((t) => _saveFcmToken(t));
      }

      // Web: while tab is focused, FCM delivers here — still show OS notification (not in-app UI).
      if (kIsWeb && !_foregroundWebAttached) {
        _foregroundWebAttached = true;
        attachForegroundWebPushDisplay();
      }

      final saved = await _saveFcmToken(token);
      if (!saved) {
        developer.log(
          'NotificationService: token received but not saved (signed in?)',
          name: 'Jars',
        );
      }
      return saved;
    } catch (e, st) {
      developer.log('NotificationService.registerToken: $e\n$st', name: 'Jars');
      return false;
    }
  }

  /// Returns true if Supabase update applied to at least one row.
  static Future<bool> _saveFcmToken(String token) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      developer.log(
        'NotificationService._saveFcmToken: no Supabase user; token not saved',
        name: 'Jars',
      );
      return false;
    }
    try {
      await _db
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
      if (kDebugMode) {
        developer.log(
          'NotificationService: fcm_token saved (${token.length} chars)',
          name: 'Jars',
        );
      }
      return true;
    } catch (e) {
      developer.log('NotificationService._saveFcmToken: $e', name: 'Jars');
      return false;
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
