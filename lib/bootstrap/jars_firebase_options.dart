import 'package:firebase_core/firebase_core.dart';

/// Shared Firebase config (same project as [web/firebase-messaging-sw.js]).
/// Web: do not add Firebase compat `<script>` tags to [web/index.html]; FlutterFire
/// loads the modular SDK. The service worker may still use compat `importScripts`.
/// Initialize in [main.dart] before [runApp].
const jarsFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDI1yg8xMRFK42Nz6n2Tiiwq7_ugIW8RUo',
  authDomain: 'jarsflutter.firebaseapp.com',
  projectId: 'jarsflutter',
  storageBucket: 'jarsflutter.firebasestorage.app',
  messagingSenderId: '93048274469',
  appId: '1:93048274469:web:dfc56256d2aeede1ad49cc',
  measurementId: 'G-X14XTW7GJP',
);
