import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// Same call path as a raw `<button onclick="...">`: [index.html] defines
/// `window.jarsRequestNotificationPermission` → `Notification.requestPermission()`.
Future<bool> requestDomNotificationPermission() async {
  try {
    if (js_util.hasProperty(html.window, 'jarsRequestNotificationPermission')) {
      final promise = js_util.callMethod<Object?>(
        html.window,
        'jarsRequestNotificationPermission',
        const <Object?>[],
      );
      final result =
          await js_util.promiseToFuture<Object?>(promise as Object);
      return result == 'granted';
    }
    final r = await html.Notification.requestPermission();
    return r == 'granted';
  } catch (e, st) {
    html.window.console
        .log('jarsRequestNotificationPermission failed: $e\n$st');
    return false;
  }
}

bool browserNotificationPermissionIsGranted() =>
    html.Notification.permission == 'granted';
