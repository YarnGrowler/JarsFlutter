// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';

import 'dart:js_util' as js_util;

import '../bootstrap/web_push_config.dart';

Future<Map<String, dynamic>?> subscribeWebPushWithJs() async {
  if (kWebPushVapidPublicKey.isEmpty) {
    throw StateError(
      'WEB_PUSH_VAPID_PUBLIC_KEY is not set. '
      'Run: npx @pushforge/builder vapid, then flutter build web '
      '--dart-define=WEB_PUSH_VAPID_PUBLIC_KEY=<publicKey>',
    );
  }
  final Object g = js_util.globalThis;
  if (!js_util.hasProperty(g, 'jarsSubscribeWebPush')) {
    throw StateError('jarsSubscribeWebPush missing — load jars-web-push-helper.js');
  }
  final Object? fn = js_util.getProperty<Object?>(g, 'jarsSubscribeWebPush');
  if (fn == null) throw StateError('jarsSubscribeWebPush is null');
  final Object promise = js_util.callMethod<Object>(fn, 'call', [null, kWebPushVapidPublicKey]);
  final Object? out = await js_util.promiseToFuture<Object?>(promise);
  final s = out?.toString();
  if (s == null || s.isEmpty) return null;
  final map = jsonDecode(s);
  if (map is Map<String, dynamic>) return map;
  if (map is Map) return Map<String, dynamic>.from(map);
  return null;
}
