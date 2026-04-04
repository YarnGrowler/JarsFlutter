// FCM web push — served at /firebase-messaging-sw.js
// Must show notifications here; FCM accepting the message is not enough on web.
// Worker scope only: compat importScripts here does NOT set window.firebase on
// the page. Main document must NOT load compat scripts — FlutterFire uses modular.
// Keep this Firebase JS version aligned with firebase_core_web (see pub.dev changelog).
/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDI1yg8xMRFK42Nz6n2Tiiwq7_ugIW8RUo',
  authDomain: 'jarsflutter.firebaseapp.com',
  projectId: 'jarsflutter',
  storageBucket: 'jarsflutter.firebasestorage.app',
  messagingSenderId: '93048274469',
  appId: '1:93048274469:web:dfc56256d2aeede1ad49cc',
  measurementId: 'G-X14XTW7GJP',
});

const messaging = firebase.messaging();

function showFromPayload(payload) {
  const n = payload.notification || {};
  const title = n.title || payload.data?.title || 'Jars';
  const body = n.body || payload.data?.body || '';
  const icon = n.icon || '/icons/jars-notification.svg';
  const options = {
    body,
    icon,
    badge: '/icons/jars-notification.svg',
    tag: payload.fcmMessageId || payload.data?.tag || 'jars-' + Date.now(),
    renotify: true,
    requireInteraction: false,
  };
  return self.registration.showNotification(title, options);
}

// Background / collapsed tab — required for browser/OS notifications from FCM v1
if (typeof messaging.onBackgroundMessage === 'function') {
  messaging.onBackgroundMessage((payload) => showFromPayload(payload));
} else if (typeof messaging.setBackgroundMessageHandler === 'function') {
  messaging.setBackgroundMessageHandler((payload) => showFromPayload(payload));
}
