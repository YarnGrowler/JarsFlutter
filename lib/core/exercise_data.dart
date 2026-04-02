class ExerciseDefinition {
  final String id;
  final String name;
  final double points;
  final String icon;
  final String category;
  final bool supportsWeight;
  final double? weightThreshold;
  final double? weightMultiplier;

  const ExerciseDefinition({
    required this.id,
    required this.name,
    required this.points,
    required this.icon,
    required this.category,
    this.supportsWeight = false,
    this.weightThreshold,
    this.weightMultiplier,
  });
}

const kSystemExercises = <ExerciseDefinition>[
  // Upper Body
  ExerciseDefinition(id: 'pushups', name: 'Push-ups', points: 2, icon: '💪', category: 'Upper Body', supportsWeight: true, weightThreshold: 7, weightMultiplier: 1),
  ExerciseDefinition(id: 'explosive_pushups', name: 'Explosive Push-ups', points: 3, icon: '⚡', category: 'Upper Body', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'diamond_pushups', name: 'Diamond Push-ups', points: 3.6, icon: '💎', category: 'Upper Body', supportsWeight: true, weightThreshold: 7, weightMultiplier: 1),
  ExerciseDefinition(id: 'pullups', name: 'Pull-ups', points: 4, icon: '🏋️', category: 'Upper Body', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'wide_grip_pullups', name: 'Wide Grip Pull-ups', points: 4, icon: '📏', category: 'Upper Body', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'one_arm_pullups', name: 'One-Arm Pull-ups', points: 6, icon: '💪💪', category: 'Upper Body', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'dips', name: 'Dips', points: 3.8, icon: '🔽', category: 'Upper Body', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'chair_dips', name: 'Chair Dips', points: 2, icon: '🪑', category: 'Upper Body', supportsWeight: true, weightThreshold: 6, weightMultiplier: 1),
  ExerciseDefinition(id: 'handstand_pushups', name: 'Handstand Push-ups', points: 6, icon: '🤸', category: 'Upper Body'),
  ExerciseDefinition(id: 'incline_pushups', name: 'Incline Push-ups', points: 1.5, icon: '⬆️', category: 'Upper Body', supportsWeight: true, weightThreshold: 7.5, weightMultiplier: 1),
  ExerciseDefinition(id: 'clap_pushups', name: 'Clap Push-ups', points: 3.5, icon: '👏', category: 'Upper Body', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'decline_pushups', name: 'Decline Push-ups', points: 3.2, icon: '🔻', category: 'Upper Body', supportsWeight: true, weightThreshold: 10, weightMultiplier: 1),
  ExerciseDefinition(id: 'archer_pushups', name: 'Archer Pushups', points: 4, icon: '🏹', category: 'Upper Body', supportsWeight: true, weightThreshold: 7.5, weightMultiplier: 1),
  ExerciseDefinition(id: 'chin_ups', name: 'Chin Ups', points: 3.5, icon: '🏋️‍♂️', category: 'Upper Body', supportsWeight: true, weightThreshold: 7.5, weightMultiplier: 1),

  // Core
  ExerciseDefinition(id: 'situps', name: 'Sit-ups', points: 1.2, icon: '🔄', category: 'Core', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'plank', name: 'Plank(5s)', points: 1, icon: '⚰️', category: 'Core'),
  ExerciseDefinition(id: 'crunches', name: 'Crunches', points: 1, icon: '🌟', category: 'Core'),
  ExerciseDefinition(id: 'lsit_hold', name: 'L-Sit Hold(5s)', points: 3, icon: '📏', category: 'Core'),
  ExerciseDefinition(id: 'abwheel_knees', name: 'Ab Wheel (Knees)', points: 2.5, icon: '⚙️', category: 'Core', supportsWeight: true, weightThreshold: 7, weightMultiplier: 1),
  ExerciseDefinition(id: 'abwheel_full', name: 'Ab Wheel (Full)', points: 4, icon: '⚙️', category: 'Core', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'bicycle_crunch', name: 'Bicycle Crunch', points: 1.4, icon: '🚴', category: 'Core'),
  ExerciseDefinition(id: 'russian_twist', name: 'Russian Twist', points: 1, icon: '🔄', category: 'Core', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'leg_raises', name: 'Leg Raises', points: 2, icon: '🍗', category: 'Core'),

  // Lower Body
  ExerciseDefinition(id: 'squats', name: 'Squats', points: 1, icon: '🦵', category: 'Lower Body', supportsWeight: true, weightThreshold: 7.5, weightMultiplier: 1),
  ExerciseDefinition(id: 'jump_squats', name: 'Jump Squats', points: 3, icon: '⬆️', category: 'Lower Body', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'bulgarian_split_squats', name: 'Bulgarian Split Squats', points: 2, icon: '🇧🇬', category: 'Lower Body', supportsWeight: true, weightThreshold: 7.5, weightMultiplier: 1),
  ExerciseDefinition(id: 'lunges', name: 'Lunges', points: 1, icon: '🚶', category: 'Lower Body', supportsWeight: true, weightThreshold: 7.5, weightMultiplier: 1),
  ExerciseDefinition(id: 'glute_bridges', name: 'Glute Bridges', points: 1.4, icon: '🌉', category: 'Lower Body'),
  ExerciseDefinition(id: 'pistol_squats', name: 'Pistol Squats', points: 4, icon: '🔫', category: 'Lower Body', supportsWeight: true, weightThreshold: 10, weightMultiplier: 1),

  // Full Body
  ExerciseDefinition(id: 'burpees', name: 'Burpees', points: 4, icon: '⚡', category: 'Full Body'),
  ExerciseDefinition(id: 'mountain_climbers', name: 'Mountain Climbers', points: 1, icon: '⛰️', category: 'Full Body'),

  // Cardio
  ExerciseDefinition(id: 'jumping_jacks', name: 'Jumping Jacks', points: 0.5, icon: '🦘', category: 'Cardio'),
  ExerciseDefinition(id: 'high_knees', name: 'High Knees', points: 0.5, icon: '🏃', category: 'Cardio'),
  ExerciseDefinition(id: 'skaters', name: 'Skaters', points: 0.5, icon: '⛸️', category: 'Cardio'),
  ExerciseDefinition(id: 'jump_rope', name: 'Jump Rope', points: 0.5, icon: '🤾', category: 'Cardio'),
  ExerciseDefinition(id: 'box_jumps', name: 'Box Jumps', points: 3, icon: '📦', category: 'Cardio'),
  ExerciseDefinition(id: 'running1', name: 'Running(5 min)', points: 10, icon: '🏃🏿', category: 'Cardio'),
  ExerciseDefinition(id: 'running2', name: 'Running(1 mile)', points: 40, icon: '🏃‍♂️', category: 'Cardio'),
  ExerciseDefinition(id: 'soccer', name: 'Futbol/Soccer (5 min)', points: 15, icon: '⚽', category: 'Cardio'),
  ExerciseDefinition(id: 'basketball', name: 'Basketball (5 min)', points: 16, icon: '🏀', category: 'Cardio'),
  ExerciseDefinition(id: 'swimming', name: 'Swimming (5 min)', points: 22, icon: '🏊', category: 'Cardio'),
  ExerciseDefinition(id: 'cycling', name: 'Cycling (5 min)', points: 12, icon: '🚴', category: 'Cardio'),
  ExerciseDefinition(id: 'tennis', name: 'Tennis (5 min)', points: 5, icon: '🎾', category: 'Cardio'),
  ExerciseDefinition(id: 'golf', name: 'Golf (5 min)', points: 4, icon: '⛳', category: 'Cardio'),
  ExerciseDefinition(id: 'volleyball', name: 'Volleyball (5 min)', points: 10, icon: '🏐', category: 'Cardio'),
  ExerciseDefinition(id: 'baseball', name: 'Baseball (5 min)', points: 7, icon: '⚾', category: 'Cardio'),
  ExerciseDefinition(id: 'football', name: 'American Football (5 min)', points: 16, icon: '🏈', category: 'Cardio'),

  // Strength
  ExerciseDefinition(id: 'bicep_curls', name: 'Bicep Curls', points: 2.5, icon: '💪', category: 'Strength', supportsWeight: true, weightThreshold: 5, weightMultiplier: 1),
  ExerciseDefinition(id: 'overhead_press', name: 'Overhead Press', points: 3.5, icon: '🏋️‍♂️', category: 'Strength', supportsWeight: true, weightThreshold: 7.5, weightMultiplier: 1),
  ExerciseDefinition(id: 'tricep_extensions', name: 'Tricep Extensions', points: 3, icon: '💪', category: 'Strength', supportsWeight: true, weightThreshold: 6, weightMultiplier: 1),
  ExerciseDefinition(id: 'lat_pulldown', name: 'Lat Pulldown', points: 4, icon: '🏋️', category: 'Strength', supportsWeight: true, weightThreshold: 10, weightMultiplier: 1),
  ExerciseDefinition(id: 'bench_press', name: 'Bench Press', points: 5, icon: '🏋️‍♂️', category: 'Strength', supportsWeight: true, weightThreshold: 10, weightMultiplier: 1),
  ExerciseDefinition(id: 'deadlift', name: 'Deadlift', points: 6, icon: '🏋️‍♂️', category: 'Strength', supportsWeight: true, weightThreshold: 15, weightMultiplier: 1),
];

const kExerciseCategories = [
  'Upper Body',
  'Core',
  'Lower Body',
  'Full Body',
  'Cardio',
  'Strength',
  'Custom',
];
