import 'package:firebase_core/firebase_core.dart';

/// Shared Firebase config (same project as [web/firebase-messaging-sw.js]).
/// Web: initialize in [main.dart] before [runApp] so Dart init is not the first
/// touch on a user gesture (avoids FlutterFire web interop null crashes in PWA).
const jarsFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDI1yg8xMRFK42Nz6n2Tiiwq7_ugIW8RUo',
  authDomain: 'jarsflutter.firebaseapp.com',
  projectId: 'jarsflutter',
  storageBucket: 'jarsflutter.firebasestorage.app',
  messagingSenderId: '93048274469',
  appId: '1:93048274469:web:dfc56256d2aeede1ad49cc',
  measurementId: 'G-X14XTW7GJP',
);
