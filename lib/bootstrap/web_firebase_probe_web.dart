// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_util' as js_util;

/// Whether the compat `firebase` global exists before/after Flutter bootstrap.
String describeFirebaseJsGlobal() {
  try {
    final Object g = js_util.globalThis;
    if (!js_util.hasProperty(g, 'firebase')) {
      return 'globalThis.firebase: property missing';
    }
    final Object? fb = js_util.getProperty<Object?>(g, 'firebase');
    if (fb == null) {
      return 'globalThis.firebase: null';
    }
    return 'globalThis.firebase: non-null';
  } catch (e) {
    return 'globalThis.firebase probe error: $e';
  }
}

/// Extra context for iOS PWA / Safari (copy into notification debug panel).
String describeWebEnvForFirebaseDiagnostics() {
  try {
    final Object g = js_util.globalThis;
    final Object? nav = js_util.getProperty<Object?>(g, 'navigator');
    var ua = '(no navigator)';
    var standalone = '(n/a)';
    if (nav != null) {
      final Object? uaVal = js_util.getProperty<Object?>(nav, 'userAgent');
      ua = uaVal?.toString() ?? '(null userAgent)';
      if (js_util.hasProperty(nav, 'standalone')) {
        final Object? s = js_util.getProperty<Object?>(nav, 'standalone');
        standalone = s?.toString() ?? 'null';
      }
    }
    final Object? doc = js_util.getProperty<Object?>(g, 'document');
    var ready = '(no document)';
    if (doc != null) {
      final Object? rs = js_util.getProperty<Object?>(doc, 'readyState');
      ready = rs?.toString() ?? '(null readyState)';
    }
    var ffSdk = '(property missing)';
    if (js_util.hasProperty(g, 'flutterfire_web_sdk_version')) {
      final Object? v =
          js_util.getProperty<Object?>(g, 'flutterfire_web_sdk_version');
      ffSdk = v?.toString() ?? 'null';
    }
    final Object? loc = js_util.getProperty<Object?>(g, 'location');
    var href = '(no location)';
    if (loc != null) {
      final Object? h = js_util.getProperty<Object?>(loc, 'href');
      href = h?.toString() ?? '(null href)';
    }
    return [
      'userAgent: $ua',
      'location.href: $href',
      'document.readyState: $ready',
      'window.flutterfire_web_sdk_version: $ffSdk',
      'navigator.standalone (iOS Home Screen): $standalone',
    ].join('\n');
  } catch (e) {
    return 'Web env probe error: $e';
  }
}
