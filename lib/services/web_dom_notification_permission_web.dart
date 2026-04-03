import 'dart:html' as html;

/// iOS Safari / Home Screen: call the browser's [Notification.requestPermission]
/// from the same user gesture before FCM's wrapper (some WebKit builds need this).
Future<bool> requestDomNotificationPermission() async {
  try {
    final r = await html.Notification.requestPermission();
    return r == 'granted';
  } catch (_) {
    return false;
  }
}
