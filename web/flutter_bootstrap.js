{{flutter_js}}
{{flutter_build_config}}

// iOS Safari / Chrome (WKWebView): skip Flutter's service worker entirely.
// With --pwa-strategy=none the generated flutter_service_worker.js is empty but
// the default bootstrap still registers it — that can hang or break startup.
// Push uses jars-web-push-sw.js only when the user subscribes.
//
// Prefer full CanvasKit (works on all browsers; avoids chromium-only APIs).
(function () {
  var ua = navigator.userAgent || '';
  // iPhone/iPad/iPod — includes Chrome on iOS (CriOS), which still uses WKWebView.
  var isAppleMobile = /iP(hone|od|ad)/.test(ua);
  var isIPadOS = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;

  var config = {
    canvasKitVariant: 'full',
  };

  // If WebGL is unavailable, CPU CanvasKit avoids a blank/black GL-backed surface.
  if (isAppleMobile || isIPadOS) {
    try {
      var c = document.createElement('canvas');
      var gl = c.getContext('webgl2') || c.getContext('webgl');
      if (!gl) {
        config.canvasKitForceCpuOnly = true;
      }
    } catch (_) {
      config.canvasKitForceCpuOnly = true;
    }
  }

  _flutter.loader.load({ config: config });
})();
