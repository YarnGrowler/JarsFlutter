import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'bootstrap/config_error_app.dart';
import 'bootstrap/local_env.dart' show readLocalEnvPairs;
import 'bootstrap/supabase_public_config.dart';

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

  runApp(const ProviderScope(child: JarsApp()));
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
