(function () {
  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; ++i) out[i] = raw.charCodeAt(i);
    return out;
  }

  /** Same bytes (PushSubscription.options.applicationServerKey vs our VAPID public key). */
  function keyEqual(a, b) {
    if (a == null || b == null) return false;
    const ua = a instanceof Uint8Array ? a : new Uint8Array(a);
    const ub = b instanceof Uint8Array ? b : new Uint8Array(b);
    if (ua.byteLength !== ub.byteLength) return false;
    for (let i = 0; i < ua.byteLength; i++) {
      if (ua[i] !== ub[i]) return false;
    }
    return true;
  }

  function subscriptionToPayload(sub) {
    const j = sub.toJSON();
    if (!j.endpoint || !j.keys || !j.keys.p256dh || !j.keys.auth) {
      throw new Error('Invalid PushSubscription');
    }
    return JSON.stringify({
      endpoint: j.endpoint,
      p256dh: j.keys.p256dh,
      auth: j.keys.auth,
    });
  }

  window.jarsSubscribeWebPush = async function (vapidPublicKey) {
    if (!vapidPublicKey || typeof vapidPublicKey !== 'string') {
      throw new Error('Missing VAPID public key');
    }
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      throw new Error('Push not supported');
    }
    if (Notification.permission !== 'granted') {
      throw new Error('Notification permission not granted');
    }

    const reg = await navigator.serviceWorker.register('/jars-web-push-sw.js', {
      scope: '/',
    });
    await navigator.serviceWorker.ready;

    const key = urlBase64ToUint8Array(vapidPublicKey.trim());
    const existing = await reg.pushManager.getSubscription();

    // Reuse current subscription when VAPID key matches (or browser omits options) — do NOT
    // unsubscribe first. Unsubscribing invalidates the endpoint immediately; concurrent
    // server pushes then get HTTP 410.
    if (existing) {
      const optKey = existing.options && existing.options.applicationServerKey;
      if (optKey == null || keyEqual(optKey, key)) {
        return subscriptionToPayload(existing);
      }
      try {
        await existing.unsubscribe();
      } catch (_) {}
    }

    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: key,
    });

    return subscriptionToPayload(sub);
  };
})();
