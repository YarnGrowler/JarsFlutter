import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/theme.dart';
import 'bootstrap/config_error_app.dart';
import 'bootstrap/jars_firebase_options.dart';
import 'bootstrap/local_env.dart' show readLocalEnvPairs;
import 'bootstrap/web_firebase_probe_stub.dart'
    if (dart.library.html) 'bootstrap/web_firebase_probe_web.dart'
    as web_firebase_probe;
import 'bootstrap/supabase_public_config.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF08080E),
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  await _loadEnv();
  final url = _resolveUrl();
  final anonKey = _resolveAnonKey();

  if (!_isRealSupabaseConfig(url, anonKey)) {
    runApp(
      ConfigErrorApp(
        details: _configHelpMessage(),
      ),
    );
    return;
  }

  await Supabase.initialize(url: url, anonKey: anonKey);

  // Web/PWA: FlutterFire modular inject + WebKit PWA timing — short settle delay
  // and a few retries before [runApp]. Diagnostics surface on the notification screen.
  if (kIsWeb) {
    NotificationService.webFirebaseStartupError = null;
    final baseDiag = NotificationService.composeWebFirebaseStartupDiagnostics(
      o: jarsFirebaseOptions,
      jsGlobalLine: web_firebase_probe.describeFirebaseJsGlobal(),
      webEnvBlock: web_firebase_probe.describeWebEnvForFirebaseDiagnostics(),
    );
    final initLog = StringBuffer();
    Object? lastErr;
    StackTrace? lastSt;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    initLog.writeln('after settle delay 150ms: apps=${Firebase.apps.length}');
    var ok = false;
    for (var attempt = 1; attempt <= 5; attempt++) {
      if (Firebase.apps.isNotEmpty) {
        initLog.writeln('attempt $attempt: skipped (already initialized)');
        ok = true;
        break;
      }
      try {
        await Firebase.initializeApp(options: jarsFirebaseOptions);
        initLog.writeln('attempt $attempt: Firebase.initializeApp ok');
        ok = true;
        break;
      } catch (e, st) {
        lastErr = e;
        lastSt = st;
        initLog.writeln('attempt $attempt: FAILED → $e');
        debugPrint('Firebase.initializeApp (web) attempt $attempt: $e');
        debugPrint('$st');
        if (attempt < 5) {
          final waitMs = 120 * attempt * attempt;
          initLog.writeln('  backoff ${waitMs}ms');
          await Future<void>.delayed(Duration(milliseconds: waitMs));
        }
      }
    }
    final hint = lastSt
            ?.toString()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .take(10)
            .join('\n') ??
        '';
    if (ok) {
      NotificationService.webFirebaseStartupDiagnostics =
          '$baseDiag\n---\nFirebase init log:\n$initLog\n---\n'
          'Firebase.initializeApp: ok\nFirebase.apps.length: ${Firebase.apps.length}';
    } else {
      NotificationService.webFirebaseStartupError =
          '[startup] ${lastErr.runtimeType}: $lastErr${hint.isEmpty ? '' : '\n$hint'}';
      NotificationService.webFirebaseStartupDiagnostics =
          '$baseDiag\n---\nFirebase init log:\n$initLog\n---\n'
          'Firebase.initializeApp: FAILED\n$lastErr\n$hint';
    }
  }

  runApp(
    const ColoredBox(
      color: JarsColors.background,
      child: ProviderScope(child: JarsApp()),
    ),
  );
}

String _configHelpMessage() {
  return 'Run the app from the jars-flutter folder and add real keys.\n\n'
      'Mobile / desktop:\n'
      '• Copy env.example to .env in jars-flutter/\n'
      '• Set SUPABASE_URL and SUPABASE_ANON_KEY (Dashboard → Settings → API).\n\n'
      'Web (hard refresh has no .env file):\n'
      '• flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co '
      '--dart-define=SUPABASE_ANON_KEY=eyJ...\n'
      '• Or build with the same defines in CI / Vercel.\n\n'
      'CLI (from jars-flutter/):\n'
      '• npx supabase projects api-keys --project-ref YOUR_REF\n';
}

/// Loads [env.example] from assets and merges project [.env] from disk in one pass
/// (flutter_dotenv clears on each load, so we must not call [load] twice).
Future<void> _loadEnv() async {
  final localPairs = await readLocalEnvPairs();
  try {
    await dotenv.load(
      fileName: 'env.example',
      mergeWith: localPairs,
      isOptional: true,
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('flutter_dotenv: failed to load env ($e)');
    }
  }
  if (kDebugMode && localPairs.isNotEmpty) {
    debugPrint('local_env: merged ${localPairs.length} keys from .env');
  }
}

bool _isRealSupabaseConfig(String url, String anonKey) {
  final u = url.trim();
  final k = anonKey.trim();
  if (u.isEmpty || k.isEmpty) return false;
  if (!u.startsWith('https://')) return false;
  final lower = u.toLowerCase();
  if (lower.contains('your-project') ||
      lower.contains('placeholder') ||
      lower.contains('example.invalid')) {
    return false;
  }
  if (k == 'your-anon-key-here' || k.length < 36) return false;
  return true;
}

/// Compile-time defines → `.env` / `env.example` → baked-in Jars project defaults.
String _resolveUrl() {
  const fromDefine = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  if (fromDefine.isNotEmpty) return fromDefine.trim();
  final fromFile = dotenv.env['SUPABASE_URL']?.trim();
  if (fromFile != null && fromFile.isNotEmpty) return fromFile;
  return kDefaultSupabaseUrl;
}

String _resolveAnonKey() {
  const fromDefine =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  if (fromDefine.isNotEmpty) return fromDefine.trim();
  final fromFile = dotenv.env['SUPABASE_ANON_KEY']?.trim();
  if (fromFile != null && fromFile.isNotEmpty) return fromFile;
  return kDefaultSupabaseAnonKey;
}
