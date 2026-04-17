import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum OnboardingGoal { competition, accountability, tracking }

enum TrainingFrequency { low, moderate, high, varies }

enum CrewStatus { hasCode, startingFresh }

class OnboardingAnswers {
  final OnboardingGoal? goal;
  final TrainingFrequency? frequency;
  final CrewStatus? crewStatus;
  final List<String> exercises;
  final bool notifPrimingSeen;

  const OnboardingAnswers({
    this.goal,
    this.frequency,
    this.crewStatus,
    this.exercises = const [],
    this.notifPrimingSeen = false,
  });

  OnboardingAnswers copyWith({
    OnboardingGoal? goal,
    TrainingFrequency? frequency,
    CrewStatus? crewStatus,
    List<String>? exercises,
    bool? notifPrimingSeen,
  }) =>
      OnboardingAnswers(
        goal: goal ?? this.goal,
        frequency: frequency ?? this.frequency,
        crewStatus: crewStatus ?? this.crewStatus,
        exercises: exercises ?? this.exercises,
        notifPrimingSeen: notifPrimingSeen ?? this.notifPrimingSeen,
      );

  static const _kPrefsKey = 'onboarding_answers_v1';

  Map<String, dynamic> toJson() => {
        'goal': goal?.name,
        'frequency': frequency?.name,
        'crewStatus': crewStatus?.name,
        'exercises': exercises,
        'notifPrimingSeen': notifPrimingSeen,
      };

  static OnboardingAnswers fromJson(Map<String, dynamic> map) =>
      OnboardingAnswers(
        goal: map['goal'] == null
            ? null
            : OnboardingGoal.values.asNameMap()[map['goal'] as String],
        frequency: map['frequency'] == null
            ? null
            : TrainingFrequency.values.asNameMap()[map['frequency'] as String],
        crewStatus: map['crewStatus'] == null
            ? null
            : CrewStatus.values.asNameMap()[map['crewStatus'] as String],
        exercises: (map['exercises'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        notifPrimingSeen: map['notifPrimingSeen'] as bool? ?? false,
      );

  static Future<OnboardingAnswers?> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsKey);
  }
}

/// Human-readable processing copy per goal.
extension OnboardingGoalCopy on OnboardingGoal {
  String get processingLine {
    switch (this) {
      case OnboardingGoal.competition:
        return 'Calibrating your competitive setup...';
      case OnboardingGoal.accountability:
        return 'Setting up your accountability system...';
      case OnboardingGoal.tracking:
        return 'Building your personal stats engine...';
    }
  }
}

/// Processing copy per crew status.
extension CrewStatusCopy on CrewStatus {
  String get processingLine {
    switch (this) {
      case CrewStatus.hasCode:
        return 'Connecting you to your crew...';
      case CrewStatus.startingFresh:
        return 'Preparing your room...';
    }
  }
}
