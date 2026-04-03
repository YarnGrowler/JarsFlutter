import 'dart:html' as html;

import 'package:firebase_messaging/firebase_messaging.dart';

/// Same path as [NotificationService.kWebPushIconPath] (avoid importing notification_service — circular).
const _kIcon = '/icons/jars-notification.svg';

/// Web: FCM does not auto-show a system banner while the tab is focused.
/// Uses the browser [Notification] API (OS notification tray), not Flutter widgets.
void attachForegroundWebPushDisplay() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (html.Notification.permission != 'granted') return;
    final n = message.notification;
    final title = n?.title ?? 'Jars';
    final body = n?.body ?? '';
    try {
      html.Notification(title, body: body, icon: _kIcon);
    } catch (_) {
      // ignore
    }
  });
}
