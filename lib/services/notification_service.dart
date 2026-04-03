import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'foreground_push_display_stub.dart'
    if (dart.library.html) 'foreground_push_display_web.dart';
import 'web_dom_notification_permission_stub.dart'
    if (dart.library.html) 'web_dom_notification_permission_web.dart'
    as dom_notif;
import '../models/fcm_device.dart';
import 'supabase_service.dart';

// ── VAPID key: Firebase Console → Cloud Messaging → Web Push certificates ──
const _kVapidKey =
    'BObFaztoPMeW_PjcCJGMvRBTUGJ4Z7QvY6GhkiD8qVL5M7LklHmQ2iqDS9j0s4ZOBxVasoSvlCku_n-SHmHVqys';

/// Push icon path on web (same origin as the app, e.g. Vercel).
const kWebPushIconPath = '/icons/jars-notification.svg';

/// Handles FCM token registration and push via Supabase `notifications` table.
/// Tokens are stored in [user_fcm_tokens] so each user can have **multiple devices**.
///
/// **iOS Safari / “Add to Home Screen”:** `requestPermission()` is only honored when
/// triggered from a **direct user gesture** (e.g. a button `onPressed`). Do **not**
/// call [registerToken] from app init, sign-in, or `async` chains after navigation —
/// use [syncTokenIfPermitted] there instead (no prompt; only refreshes token if
/// already allowed). See [registerToken] for the explicit opt-in path.
class NotificationService {
  static final _db = SupabaseService.client;
  static bool _tokenListenersAttached = false;
  static bool _foregroundWebAttached = false;

  /// Last error from [registerToken] (for settings UI). Cleared on success.
  static String? lastRegisterTokenError;

  static const FirebaseOptions _firebaseOptions = FirebaseOptions(
    apiKey: 'AIzaSyDI1yg8xMRFK42Nz6n2Tiiwq7_ugIW8RUo',
    authDomain: 'jarsflutter.firebaseapp.com',
    projectId: 'jarsflutter',
    storageBucket: 'jarsflutter.firebasestorage.app',
    messagingSenderId: '93048274469',
    appId: '1:93048274469:web:dfc56256d2aeede1ad49cc',
    measurementId: 'G-X14XTW7GJP',
  );

  /// Last token obtained from FCM on this install (to mark "this device" in lists).
  static String? _lastKnownLocalToken;

  /// Exposed for settings UI to label the current install in [listMyDevices].
  static String? get cachedLocalFcmToken => _lastKnownLocalToken;

  static Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions);
    }
  }

  /// Safe on session restore / sign-in: **does not** call [requestPermission].
  /// Re-fetches and saves the FCM token only if the user already allowed notifications.
  static Future<bool> syncTokenIfPermitted() async {
    try {
      await _ensureFirebaseInitialized();
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging
          .getNotificationSettings()
          .timeout(const Duration(seconds: 8));
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }
      final token = kIsWeb
          ? await messaging.getToken(vapidKey: _kVapidKey)
          : await messaging.getToken();
      if (token == null || token.isEmpty) return false;
      return _persistTokenAndAttachListeners(token);
    } catch (e, st) {
      developer.log(
        'NotificationService.syncTokenIfPermitted: $e',
        name: 'Jars',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// After sign-in or cold start: Firebase ready + silent token sync if already allowed.
  /// Never shows the permission dialog (unlike [registerToken]).
  static Future<void> init() async {
    try {
      await _ensureFirebaseInitialized();
      await syncTokenIfPermitted();
    } catch (e, st) {
      developer.log('NotificationService.init: $e', name: 'Jars', error: e, stackTrace: st);
    }
  }

  /// Current OS / browser permission (no prompt). Times out so mobile never hangs forever.
  static Future<NotificationSettings?> getNotificationSettings() async {
    try {
      await _ensureFirebaseInitialized().timeout(const Duration(seconds: 8));
      return await FirebaseMessaging.instance
          .getNotificationSettings()
          .timeout(const Duration(seconds: 6));
    } catch (e, st) {
      developer.log(
        'getNotificationSettings timed out or failed (mobile can hang on FCM): $e',
        name: 'Jars',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// FCM token for this install, if permission allows (may be null on web).
  static Future<String?> getCurrentFcmToken() async {
    try {
      await _ensureFirebaseInitialized();
      if (kIsWeb) {
        return FirebaseMessaging.instance.getToken(vapidKey: _kVapidKey);
      }
      return FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  static Future<List<FcmDevice>> listMyDevices() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    try {
      final rows = await (() async {
        return _db
            .from('user_fcm_tokens')
            .select('id, platform, last_seen_at, token')
            .eq('user_id', uid)
            .order('last_seen_at', ascending: false);
      })().timeout(const Duration(seconds: 20));
      return (rows as List)
          .map((r) => FcmDevice.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      final s = e.toString();
      if (s.contains('404') ||
          s.contains('PGRST205') ||
          s.contains('Could not find the table')) {
        developer.log(
          'user_fcm_tokens is missing — in Supabase SQL Editor run the '
          '"11 user_fcm_tokens" block in supabase_patches/00_apply_all.sql '
          '(or 11_fcm_multi_device.sql), then reload the app. ($e)',
          name: 'Jars',
        );
      } else {
        developer.log('NotificationService.listMyDevices: $e', name: 'Jars');
      }
      return [];
    }
  }

  /// Removes a registered device from Supabase. If it matches this install, also calls [FirebaseMessaging.deleteToken].
  static Future<bool> revokeDevice(FcmDevice device) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return false;
    try {
      await _db
          .from('user_fcm_tokens')
          .delete()
          .eq('id', device.id)
          .eq('user_id', uid);

      if (_lastKnownLocalToken == device.token) {
        try {
          await FirebaseMessaging.instance.deleteToken();
        } catch (_) {}
        _lastKnownLocalToken = null;
      }
      await _syncProfileLegacyToken();
      return true;
    } catch (e) {
      final s = e.toString();
      if (s.contains('404') || s.contains('PGRST205')) {
        developer.log(
          'user_fcm_tokens missing — apply SQL patch (see listMyDevices log). $e',
          name: 'Jars',
        );
      } else {
        developer.log('NotificationService.revokeDevice: $e', name: 'Jars');
      }
      return false;
    }
  }

  static Future<void> _syncProfileLegacyToken() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      final rows = await _db
          .from('user_fcm_tokens')
          .select('token')
          .eq('user_id', uid)
          .order('last_seen_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows as List);
      final next = list.isEmpty ? null : list.first['token'] as String?;
      await _db.from('profiles').update({'fcm_token': next}).eq('id', uid);
    } catch (e) {
      developer.log('NotificationService._syncProfileLegacyToken: $e',
          name: 'Jars');
    }
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

  static Future<bool> _persistTokenAndAttachListeners(String token) async {
    final messaging = FirebaseMessaging.instance;
    if (!_tokenListenersAttached) {
      _tokenListenersAttached = true;
      messaging.onTokenRefresh.listen((t) {
        _lastKnownLocalToken = t;
        _saveFcmToken(t);
      });
    }
    if (kIsWeb && !_foregroundWebAttached) {
      _foregroundWebAttached = true;
      attachForegroundWebPushDisplay();
    }
    _lastKnownLocalToken = token;
    final saved = await _saveFcmToken(token);
    if (!saved) {
      developer.log(
        'NotificationService: token not saved (signed in?)',
        name: 'Jars',
      );
    }
    return saved;
  }

  /// Registers this device’s FCM token after **requesting permission**.
  ///
  /// **Must run from a direct user gesture** (e.g. `onPressed` on a button) —
  /// especially on **iPhone Safari / Home Screen web apps**, where calling
  /// [FirebaseMessaging.requestPermission] from init or post-login `async`
  /// code does not show the system prompt and can leave permission denied.
  static Future<bool> registerToken() async {
    lastRegisterTokenError = null;
    try {
      // Web / iOS PWA: the **first** await in this handler must be the browser’s
      // Notification.requestPermission — not Firebase.initializeApp. Otherwise
      // WebKit leaves the user-gesture stack and the prompt never appears.
      if (kIsWeb) {
        final domOk = await dom_notif.requestDomNotificationPermission();
        if (!domOk) {
          developer.log(
            'NotificationService: browser Notification.requestPermission denied',
            name: 'Jars',
          );
          return false;
        }
      }

      await _ensureFirebaseInitialized();

      final messaging = FirebaseMessaging.instance;

      var permissionOk = false;
      try {
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        permissionOk = settings.authorizationStatus ==
                AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      } catch (e, st) {
        developer.log(
          'NotificationService: FCM requestPermission threw: $e',
          name: 'Jars',
          error: e,
          stackTrace: st,
        );
        // Web: if the browser prompt already granted, FCM can still throw; try getToken.
        if (kIsWeb && dom_notif.browserNotificationPermissionIsGranted()) {
          permissionOk = true;
        } else {
          rethrow;
        }
      }

      if (!permissionOk) {
        developer.log(
          'NotificationService: FCM permission not authorized',
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

      final persisted = await _persistTokenAndAttachListeners(token);
      if (!persisted && SupabaseService.currentUserId == null) {
        lastRegisterTokenError =
            'You’re signed out. Sign in, then tap again to save this device for push.';
      }
      return persisted;
    } catch (e, st) {
      lastRegisterTokenError = e.toString();
      developer.log('NotificationService.registerToken: $e\n$st', name: 'Jars');
      return false;
    }
  }

  /// Human-readable status for settings UI.
  static String describeAuthorization(AuthorizationStatus s) {
    switch (s) {
      case AuthorizationStatus.authorized:
        return 'Allowed';
      case AuthorizationStatus.provisional:
        return 'Provisional (quiet)';
      case AuthorizationStatus.denied:
        return 'Denied';
      case AuthorizationStatus.notDetermined:
        return 'Not asked yet';
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

  /// One row per member except [excludeUserId] (typically the actor). Use for
  /// room-visible events (first log, PR, streak, rank-up, etc.).
  static Future<void> notifyRoomMembersExcept({
    required String roomId,
    required String excludeUserId,
    required String body,
  }) async {
    await notifyRoomMembersExceptIds(
      roomId: roomId,
      excludeUserIds: {excludeUserId},
      body: body,
    );
  }

  /// Same as [notifyRoomMembersExcept] but skips multiple users (e.g. overtaker + overtaken).
  static Future<void> notifyRoomMembersExceptIds({
    required String roomId,
    required Set<String> excludeUserIds,
    required String body,
  }) async {
    try {
      final rows = await _db
          .from('room_members')
          .select('user_id')
          .eq('room_id', roomId);
      final targets = <String>[];
      for (final r in rows) {
        final uid = r['user_id'] as String?;
        if (uid != null && !excludeUserIds.contains(uid)) {
          targets.add(uid);
        }
      }
      await Future.wait(
        targets.map(
          (id) => sendNotification(targetUserId: id, body: body),
        ),
      );
    } catch (e, st) {
      developer.log(
        'NotificationService.notifyRoomMembersExceptIds: $e',
        name: 'Jars',
        error: e,
        stackTrace: st,
      );
    }
  }
}
