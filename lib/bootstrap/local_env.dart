import 'local_env_stub.dart'
    if (dart.library.io) 'local_env_io.dart' as local_env_impl;

/// Key/value pairs from a project-root `.env` (Android/iOS/desktop). Web: empty.
Future<Map<String, String>> readLocalEnvPairs() =>
    local_env_impl.readLocalEnvPairs();
