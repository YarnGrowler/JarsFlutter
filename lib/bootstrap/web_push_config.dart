/// URL-safe VAPID **public** key (pair with `VAPID_PRIVATE_KEY` in Supabase).
///
/// Default is the Jars dev key so `flutter run -d chrome` works without
/// `--dart-define`. Override: `--dart-define=WEB_PUSH_VAPID_PUBLIC_KEY=...`
/// or Vercel `WEB_PUSH_VAPID_PUBLIC_KEY` (see scripts/vercel-build.sh).
const kWebPushVapidPublicKey = String.fromEnvironment(
  'WEB_PUSH_VAPID_PUBLIC_KEY',
  defaultValue:
      'BJfq_JW_AhdQ28bXU0uenuy2TeL3kQrRUH97RVjthR1qsVbmNyr9H-tqcqV7wVW5EsIqcxAPpWbPhHJp6LT4PvY',
);
