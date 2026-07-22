-- Inserts Goblet Squat, Dumbbell Lunges, Dead Bug, Dumbbell Romanian Deadlift,
-- Dumbbell Shoulder Press, Dumbbell Chest Press as system exercises into every
-- room that does not already have them (safe to re-run). Matches values in
-- lib/core/exercise_data.dart.
--
BEGIN;

INSERT INTO public.exercises (
  room_id,
  name,
  points,
  icon,
  category,
  supports_weight,
  weight_threshold,
  weight_multiplier,
  created_by,
  count_unit,
  time_points_mode,
  uses_time,
  timer_ui
)
SELECT
  r.id,
  v.name,
  v.points,
  v.icon,
  v.category,
  v.supports_weight,
  v.weight_threshold,
  v.weight_multiplier,
  'system',
  v.count_unit,
  v.time_points_mode,
  v.uses_time,
  v.timer_ui
FROM public.rooms AS r
CROSS JOIN (
  VALUES
  (
    'Goblet Squat',
    1.5::double precision,
    '🏆',
    'Lower Body',
    true::boolean,
    15,
    1,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'Dumbbell Lunges',
    1.3::double precision,
    '🚶',
    'Lower Body',
    true::boolean,
    12.5,
    1,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'Dumbbell Romanian Deadlift',
    4::double precision,
    '🏋️‍♀️',
    'Strength',
    true::boolean,
    12.5,
    1.2,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'Dumbbell Shoulder Press',
    3.5::double precision,
    '🏋️‍♂️',
    'Strength',
    true::boolean,
    10,
    1.1,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'Dumbbell Chest Press',
    4::double precision,
    '🏋️',
    'Strength',
    true::boolean,
    12.5,
    1.15,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'Dead Bug',
    1.2::double precision,
    '🐛',
    'Core',
    false::boolean,
    null::double precision,
    null::double precision,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  )
) AS v(
  name,
  points,
  icon,
  category,
  supports_weight,
  weight_threshold,
  weight_multiplier,
  count_unit,
  time_points_mode,
  uses_time,
  timer_ui
)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.exercises AS e
  WHERE e.room_id = r.id
    AND e.created_by = 'system'
    AND e.name = v.name
);

COMMIT;
