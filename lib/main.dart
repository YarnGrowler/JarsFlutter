import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

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

  if (url.isEmpty || anonKey.isEmpty) {
    throw StateError(
      'Supabase is not configured.\n'
      '• Add jars-flutter/.env with SUPABASE_URL and SUPABASE_ANON_KEY (see env.example), then restart.\n'
      '• Or run: flutter run --dart-define-from-file=.env',
    );
  }

  await Supabase.initialize(url: url, anonKey: anonKey);

  runApp(const ProviderScope(child: JarsApp()));
}

/// Loads [.env] from assets; falls back to [env.example] so fresh clones can build.
Future<void> _loadEnv() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: 'env.example');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('flutter_dotenv: could not load .env or env.example ($e)');
      }
    }
  }
}

/// Compile-time defines (CI / scripts) override bundled env files.
String _resolveUrl() {
  const fromDefine = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  if (fromDefine.isNotEmpty) return fromDefine.trim();
  return dotenv.env['SUPABASE_URL']?.trim() ?? '';
}

String _resolveAnonKey() {
  const fromDefine =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  if (fromDefine.isNotEmpty) return fromDefine.trim();
  return dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
}
