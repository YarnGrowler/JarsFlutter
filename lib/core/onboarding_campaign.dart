import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Intro value-slides campaign: existing users must complete slides once per
/// device. Ends after May 5, 2026 (local time); then no checks apply.
class OnboardingCampaign {
  OnboardingCampaign._();

  /// Campaign is active through May 5, 2026 inclusive; off starting May 6, 2026.
  static final DateTime _campaignEndExclusive = DateTime(2026, 5, 6);

  static bool get isCampaignActive =>
      DateTime.now().isBefore(_campaignEndExclusive);

  static const String _prefsKey = 'intro_value_slides_completed_v1';

  static bool _slidesCompleted = false;

  /// Whether the user finished the value slides (persisted locally).
  static bool get slidesCompleted => _slidesCompleted;

  /// Notifies [GoRouter] after [markSlidesCompleted].
  static final OnboardingCampaignGate gate = OnboardingCampaignGate._();

  /// Call from [main] after [WidgetsFlutterBinding.ensureInitialized].
  static Future<void> init() async {
    if (!isCampaignActive) {
      _slidesCompleted = true;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _slidesCompleted = prefs.getBool(_prefsKey) ?? false;
  }

  /// Persist and broadcast — call when leaving value slides toward questions.
  static Future<void> markSlidesCompleted() async {
    if (!isCampaignActive) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    _slidesCompleted = true;
    gate.notifyListeners();
  }
}

class OnboardingCampaignGate extends ChangeNotifier {
  OnboardingCampaignGate._();
}
