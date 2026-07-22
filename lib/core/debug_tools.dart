/// Dev-tools gate. Build with `--dart-define=DEBUG_TOOLS=true` to enable the
/// siege debug screen, AI teammate bots, and the time simulator. Off by
/// default in every normal build.
const bool kDebugTools = bool.fromEnvironment('DEBUG_TOOLS');
