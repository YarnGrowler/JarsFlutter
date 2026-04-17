import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/onboarding_data.dart';

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingAnswers>(
  (ref) => OnboardingNotifier(),
);

class OnboardingNotifier extends StateNotifier<OnboardingAnswers> {
  OnboardingNotifier() : super(const OnboardingAnswers()) {
    _load();
  }

  Future<void> _load() async {
    final saved = await OnboardingAnswers.loadFromPrefs();
    if (saved != null && mounted) state = saved;
  }

  void setGoal(OnboardingGoal goal) {
    state = state.copyWith(goal: goal);
    state.persist();
  }

  void setFrequency(TrainingFrequency frequency) {
    state = state.copyWith(frequency: frequency);
    state.persist();
  }

  void setCrewStatus(CrewStatus status) {
    state = state.copyWith(crewStatus: status);
    state.persist();
  }

  void setExercises(List<String> exercises) {
    state = state.copyWith(exercises: exercises);
    state.persist();
  }

  void markNotifPrimingSeen() {
    state = state.copyWith(notifPrimingSeen: true);
    state.persist();
  }

  Future<void> reset() async {
    state = const OnboardingAnswers();
    await OnboardingAnswers.clear();
  }
}
