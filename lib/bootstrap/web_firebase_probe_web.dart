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
