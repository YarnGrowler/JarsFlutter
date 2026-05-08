-- Inserts new rear-delt / shoulder-health accessory lifts as system exercises into every room
-- that does not already have them (safe to re-run). Matches values in lib/core/exercise_data.dart.
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
    'Rear Delt Flies',
    1.2::double precision,
    '🪽',
    'Strength',
    true::boolean,
    5,
    0.6,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'Face Pulls',
    1.3::double precision,
    '🧵',
    'Strength',
    true::boolean,
    10,
    0.5,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'Band Pull-Aparts',
    0.9::double precision,
    '🪢',
    'Strength',
    true::boolean,
    5,
    0.4,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'External Rotations',
    0.8::double precision,
    '🦴',
    'Strength',
    true::boolean,
    5,
    0.4,
    'reps',
    null::text,
    false::boolean,
    false::boolean
  ),
  (
    'Cuban Press',
    1.6::double precision,
    '🧲',
    'Strength',
    true::boolean,
    5,
    0.5,
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

