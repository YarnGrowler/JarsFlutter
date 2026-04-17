/// When [active] is true, logged-in users can open the full `/onboarding` funnel
/// (e.g. from Profile → Replay onboarding). Cleared when the flow finishes at
/// [ProcessingScreen] or when the user closes from the welcome screen.
class OnboardingRedoSession {
  OnboardingRedoSession._();

  static bool _active = false;

  static bool get active => _active;

  static void start() => _active = true;

  static void end() => _active = false;
}
