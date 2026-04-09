import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../bootstrap/jars_firebase_options.dart';
import '../models/fcm_device.dart';
import 'supabase_service.dart';
import 'web_dom_notification_permission_stub.dart'
    if (dart.library.html) 'web_dom_notification_permission_web.dart'
    as dom_notif;
import 'web_push_js_stub.dart'
    if (dart.library.html) 'web_push_js_web.dart' as web_push_js;

// ── In-app / push notification inventory (rows → Supabase `notifications` → Edge → FCM/Web Push)
//
// • Idle wake card (SQL `notify_room_on_wake_card` on __WAKE__| insert): “👻 {user} is idle…”
//   to all room members except the absent user. (Fix spurious wakes: patch 18 + feed throttle.)
// • Wake nudge (`send_wake_nudge` RPC): random body to the absent user only (max 2 taps/card).
// • Every real workout log (log_sheet): `notifyRoomMembersExcept` — room activity one-liner for mates.
// • EventService: overtaken victim DM, close-gap target, PR/streak/first-log feed cards (pushes merged into per-log).
//   Rank-up push stays in log_sheet.
// • “Same time yesterday” workout reminder: not implemented — see [kJarsNotificationInventory].
//
// Full matrix: lib/core/notifications_catalog.dart
//
// Push icon path on web (same origin as the app, e.g. Vercel).
const kWebPushIconPath = '/icons/jars-notification.svg';

/// **Web:** standard Web Push (VAPID) → `user_web_push_subscriptions` + Edge `web-push`.
/// **Native:** FCM → `user_fcm_tokens` + Edge FCM v1.
class NotificationService {
  static final _db = SupabaseService.client;
  static bool _tokenListenersAttached = false;

  static bool _syncTokenIfPermittedRunning = false;
  static DateTime? _lastInitAt;
  static Future<void> _persistTail = Future.value();

  static String? lastRegisterTokenError;
  static String? lastRegisterTokenStep;
  static String? lastRegisterTokenStackHint;

  static String? _lastKnownLocalToken;
  static String? get cachedLocalFcmToken => _lastKnownLocalToken;

  static Future<void> _ensureFirebaseInitialized() async {
    if (kIsWeb) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: jarsFirebaseOptions);
    }
  }

  static Future<String?> _fetchMessagingToken(FirebaseMessaging messaging) async {
    return messaging.getToken();
  }

  static Future<String?> getMessagingTokenWithRetries(
    FirebaseMessaging messaging, {
    int maxAttempts = 6,
    Duration delayBetween = const Duration(milliseconds: 450),
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final t = await _fetchMessagingToken(messaging);
        if (t != null && t.isNotEmpty) return t;
      } catch (e, st) {
        developer.log(
          'NotificationService: getToken attempt ${i + 1}/$maxAttempts failed: $e',
          name: 'Jars',
          error: e,
          stackTrace: st,
        );
      }
      if (i < maxAttempts - 1) {
        await Future<void>.delayed(delayBetween);
      }
    }
    return null;
  }

  static Future<bool> syncTokenIfPermitted() async {
    if (kIsWeb) return false;
    if (_syncTokenIfPermittedRunning) return false;
    _syncTokenIfPermittedRunning = true;
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
      final token = await getMessagingTokenWithRetries(
        messaging,
        maxAttempts: 2,
        delayBetween: const Duration(milliseconds: 200),
      );
      if (token == null || token.isEmpty) return false;
      return await _persistTokenAndAttachListeners(token);
    } catch (e, st) {
      developer.log(
        'NotificationService.syncTokenIfPermitted: $e',
        name: 'Jars',
        error: e,
        stackTrace: st,
      );
      return false;
    } finally {
      _syncTokenIfPermittedRunning = false;
    }
  }

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final now = DateTime.now();
      if (_lastInitAt != null &&
          now.difference(_lastInitAt!) < const Duration(seconds: 10)) {
        return;
      }
      _lastInitAt = now;
      await _ensureFirebaseInitialized();
      await syncTokenIfPermitted();
    } catch (e, st) {
      developer.log('NotificationService.init: $e', name: 'Jars', error: e, stackTrace: st);
    }
  }

  static Future<NotificationSettings?> getNotificationSettings() async {
    if (kIsWeb) return null;
    try {
      await _ensureFirebaseInitialized().timeout(const Duration(seconds: 8));
      return await FirebaseMessaging.instance
          .getNotificationSettings()
          .timeout(const Duration(seconds: 6));
    } catch (e, st) {
      developer.log(
        'getNotificationSettings failed: $e',
        name: 'Jars',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  static Future<String?> getCurrentFcmToken() async {
    if (kIsWeb) return _lastKnownLocalToken;
    try {
      await _ensureFirebaseInitialized();
      return getMessagingTokenWithRetries(
        FirebaseMessaging.instance,
        maxAttempts: 2,
        delayBetween: const Duration(milliseconds: 150),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<FcmDevice>> listMyDevices() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final out = <FcmDevice>[];
    try {
      final rows = await _db
          .from('user_fcm_tokens')
          .select('id, platform, last_seen_at, token')
          .eq('user_id', uid)
          .order('last_seen_at', ascending: false)
          .timeout(const Duration(seconds: 20));
      for (final r in rows as List) {
        try {
          if (r is! Map) continue;
          out.add(FcmDevice.fromJson(Map<String, dynamic>.from(r)));
        } catch (e) {
          developer.log('listMyDevices fcm skip: $e', name: 'Jars');
        }
      }
    } catch (e) {
      developer.log('listMyDevices user_fcm_tokens: $e', name: 'Jars');
    }
    try {
      final webRows = await _db
          .from('user_web_push_subscriptions')
          .select('id, endpoint, last_seen_at')
          .eq('user_id', uid)
          .eq('enabled', true)
          .order('last_seen_at', ascending: false)
          .timeout(const Duration(seconds: 15));
      for (final r in webRows as List) {
        try {
          if (r is! Map) continue;
          final m = Map<String, dynamic>.from(r);
          final seen = m['last_seen_at'];
          out.add(FcmDevice(
            id: m['id'] as String,
            platform: 'web_push',
            lastSeenAt: seen is String ? DateTime.tryParse(seen) : null,
            token: m['endpoint'] as String,
          ));
        } catch (e) {
          developer.log('listMyDevices web skip: $e', name: 'Jars');
        }
      }
    } catch (e) {
      developer.log('listMyDevices user_web_push_subscriptions: $e', name: 'Jars');
    }
    out.sort((a, b) {
      final ta = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return out;
  }

  static Future<bool> revokeDevice(FcmDevice device) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return false;
    try {
      if (device.platform == 'web_push') {
        await _db
            .from('user_web_push_subscriptions')
            .delete()
            .eq('id', device.id)
            .eq('user_id', uid);
        if (_lastKnownLocalToken == device.token) {
          _lastKnownLocalToken = null;
        }
        return true;
      }
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
      developer.log('NotificationService.revokeDevice: $e', name: 'Jars');
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
      developer.log('NotificationService._syncProfileLegacyToken: $e', name: 'Jars');
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

  static Future<T> _enqueuePersistTail<T>(Future<T> Function() work) {
    final c = Completer<T>();
    _persistTail = _persistTail.then((_) async {
      try {
        final v = await work();
        if (!c.isCompleted) c.complete(v);
      } catch (e, st) {
        developer.log(
          'NotificationService._enqueuePersistTail: $e',
          name: 'Jars',
          error: e,
          stackTrace: st,
        );
        if (!c.isCompleted) c.completeError(e, st);
      }
    });
    return c.future;
  }

  static Future<bool> _persistTokenAndAttachListeners(String token) {
    return _enqueuePersistTail<bool>(
      () => _persistTokenAndAttachListenersSerial(token),
    );
  }

  static Future<bool> _persistTokenAndAttachListenersSerial(String token) async {
    final messaging = FirebaseMessaging.instance;
    if (!_tokenListenersAttached) {
      _tokenListenersAttached = true;
      messaging.onTokenRefresh.listen((t) {
        unawaited(
          _enqueuePersistTail<void>(() async {
            _lastKnownLocalToken = t;
            await _saveFcmToken(t);
          }),
        );
      });
    }
    _lastKnownLocalToken = token;
    return _saveFcmToken(token);
  }

  static void _traceRegisterStep(String step) {
    lastRegisterTokenStep = step;
    developer.log('registerToken ▶ $step', name: 'Jars');
  }

  static Future<bool> registerToken() async {
    lastRegisterTokenError = null;
    lastRegisterTokenStep = null;
    lastRegisterTokenStackHint = null;
    try {
      if (kIsWeb) {
        return await _registerTokenWeb();
      }
      return await _registerTokenNative();
    } catch (e, st) {
      lastRegisterTokenStackHint = st
          .toString()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .take(5)
          .join('\n');
      lastRegisterTokenError =
          '[${lastRegisterTokenStep ?? 'unknown'}] ${e.runtimeType}: $e';
      developer.log(
        'NotificationService.registerToken FAILED at ${lastRegisterTokenStep ?? '?'}: $e\n$st',
        name: 'Jars',
      );
      return false;
    }
  }

  static Future<bool> _registerTokenWeb() async {
    _traceRegisterStep('web_dom_notification_permission');
    final domOk = await dom_notif.requestDomNotificationPermission();
    if (!domOk) return false;

    _traceRegisterStep('web_push_subscribe_js');
    final sub = await web_push_js.subscribeWebPushWithJs();
    if (sub == null) {
      lastRegisterTokenError = 'Could not create Web Push subscription.';
      return false;
    }
    final endpoint = sub['endpoint'] as String?;
    final p256dh = sub['p256dh'] as String?;
    final auth = sub['auth'] as String?;
    if (endpoint == null || p256dh == null || auth == null) {
      lastRegisterTokenError = 'Invalid subscription payload from browser.';
      return false;
    }

    _traceRegisterStep('persist_web_push');
    final ok = await _saveWebPushSubscription(
      endpoint: endpoint,
      p256dh: p256dh,
      auth: auth,
    );
    if (!ok && SupabaseService.currentUserId == null) {
      lastRegisterTokenError =
          'You’re signed out. Sign in, then tap again to save this device for push.';
    }
    if (ok) {
      _lastKnownLocalToken = endpoint;
      lastRegisterTokenStep = 'ok';
    }
    return ok;
  }

  static Future<bool> _registerTokenNative() async {
    await _ensureFirebaseInitialized();
    final messaging = FirebaseMessaging.instance;
    var permissionOk = false;
    _traceRegisterStep('firebase_messaging_request_permission');
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      permissionOk = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e, st) {
      developer.log(
        'NotificationService: FCM requestPermission threw: $e',
        name: 'Jars',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
    if (!permissionOk) return false;

    _traceRegisterStep('firebase_get_token');
    final token = await getMessagingTokenWithRetries(
      messaging,
      maxAttempts: 3,
      delayBetween: const Duration(milliseconds: 200),
    );
    if (token == null || token.isEmpty) {
      lastRegisterTokenError = 'Could not get a push token on this device.';
      return false;
    }
    _traceRegisterStep('persist_token_and_listeners');
    final persisted = await _persistTokenAndAttachListeners(token);
    if (!persisted && SupabaseService.currentUserId == null) {
      lastRegisterTokenError =
          'You’re signed out. Sign in, then tap again to save this device for push.';
    }
    if (persisted) lastRegisterTokenStep = 'ok';
    return persisted;
  }

  static Future<bool> _saveWebPushSubscription({
    required String endpoint,
    required String p256dh,
    required String auth,
  }) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return false;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _db.from('user_web_push_subscriptions').upsert(
        {
          'user_id': userId,
          'endpoint': endpoint,
          'p256dh': p256dh,
          'auth': auth,
          'last_seen_at': now,
          'enabled': true,
        },
        onConflict: 'endpoint',
      );
      // Do not delete other rows: Chrome + iPhone PWA are different endpoints;
      // the Edge `push` function sends to every enabled row for this user.
      if (kDebugMode) {
        developer.log('Web push subscription saved', name: 'Jars');
      }
      return true;
    } catch (e) {
      developer.log('_saveWebPushSubscription: $e', name: 'Jars');
      lastRegisterTokenError =
          'Save failed. Run SQL patch 16_web_push_subscriptions.sql in Supabase. ($e)';
      return false;
    }
  }

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

  static Future<bool> _saveFcmToken(String token) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return false;
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
      await _db.from('profiles').update({'fcm_token': token}).eq('id', userId);
      if (kDebugMode) {
        developer.log(
          'NotificationService: FCM token registered ($platform)',
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
