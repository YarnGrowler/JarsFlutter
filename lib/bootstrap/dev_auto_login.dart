import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/debug_tools.dart';
import '../services/room_service.dart';

/// Dev-only auto-login — gated STRICTLY by --dart-define=DEBUG_TOOLS=true.
///
/// `flutter run -d chrome` launches a FRESH browser profile every run, so the
/// stored session is wiped and you'd otherwise have to log in every single
/// launch. With DEBUG_TOOLS on, startup signs into a dedicated test account
/// (creating it — and a test room — on first ever run). Normal builds are
/// completely unaffected.
///
/// This must NEVER be gated on [kDemoMode] (the Clan War's local-simulation
/// flag): every real user shares this same test account otherwise — nobody
/// gets their own room, nobody's friends are actually their friends. Real
/// users always go through the real sign-up/sign-in flow.
///
/// Override the credentials if you want:
///   --dart-define=DEV_LOGIN_EMAIL=you@x.com --dart-define=DEV_LOGIN_PASSWORD=...
///
/// NOTE: automatic account creation needs "Confirm email" DISABLED in
/// Supabase (Dashboard → Authentication → Providers → Email) — the README's
/// recommended dev setting. If it's enabled, either confirm the dev account's
/// email once, or point DEV_LOGIN_* at any existing account.
// NOTE: modern Supabase rejects non-deliverable domains (example.com etc.)
// with email_address_invalid — use a real-domain address for the dev account.
const String kDevLoginEmail = String.fromEnvironment(
  'DEV_LOGIN_EMAIL',
  defaultValue: 'jars.dev.tester@gmail.com',
);
const String kDevLoginPassword = String.fromEnvironment(
  'DEV_LOGIN_PASSWORD',
  defaultValue: 'jars-dev-123456',
);

Future<void> devAutoLoginIfEnabled() async {
  if (!kDebugTools) return;
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) return; // already signed in

  // 1. Try signing in.
  try {
    await auth.signInWithPassword(
        email: kDevLoginEmail, password: kDevLoginPassword);
    debugPrint('DevAuth: signed in as $kDevLoginEmail');
  } on AuthException catch (e) {
    debugPrint('DevAuth: sign-in failed (${e.message}) — trying signUp');
    // 2. First run: create the dev account.
    try {
      await auth.signUp(
        email: kDevLoginEmail,
        password: kDevLoginPassword,
        data: {'username': 'DevTester', 'display_name': 'DevTester'},
      );
    } catch (e2) {
      debugPrint('DevAuth: signUp failed: $e2');
    }
    if (auth.currentSession == null) {
      // Some projects require email confirmation → signUp returns no session.
      try {
        await auth.signInWithPassword(
            email: kDevLoginEmail, password: kDevLoginPassword);
      } catch (_) {}
    }
    if (auth.currentSession == null) {
      debugPrint(
          'DevAuth: account exists but needs email confirmation. Fixes:\n'
          '  1) Dashboard → Authentication → Users → "$kDevLoginEmail" → '
          'Confirm email (or just DELETE that user); AND/OR\n'
          '  2) Dashboard → Authentication → Providers → Email → turn OFF '
          '"Confirm email" (dev-recommended, also fixes real signups); then '
          'relaunch — a deleted dev user is re-created automatically.\n'
          '  3) Alternative: add DEV_LOGIN_EMAIL / DEV_LOGIN_PASSWORD for an '
          'existing account to .env (loaded via --dart-define-from-file).');
      return;
    }
    debugPrint('DevAuth: created + signed in as $kDevLoginEmail');
  } catch (e) {
    debugPrint('DevAuth: unexpected auth error: $e');
    return;
  }

  // 3. Make sure the tester lands in a room (one-time, persisted server-side).
  try {
    final rooms = await RoomService.getUserRooms();
    if (rooms.isEmpty) {
      final room =
          await RoomService.createRoom(name: 'Dev Room', maxParticipants: 8);
      debugPrint('DevAuth: created test room "${room.name}" (${room.roomCode})');
    }
  } catch (e) {
    debugPrint('DevAuth: room bootstrap failed (non-fatal): $e');
  }
}
