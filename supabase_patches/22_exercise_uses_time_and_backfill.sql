-- Time metadata + backfill every exercise row to match lib/core/exercise_data.dart.
-- Requires: 19_exercise_count_unit.sql, 21_time_points_mode.sql (columns exist).

alter table public.exercises
  add column if not exists uses_time boolean not null default false;

alter table public.exercises
  add column if not exists timer_ui boolean not null default false;

comment on column public.exercises.uses_time is
  'True when count_unit is seconds or minutes (logging time, not rep count).';

comment on column public.exercises.timer_ui is
  'True = stopwatch tap UI for seconds-based holds (plank, L-sit).';

-- ── Order matters: specific rows before broad (5 min) rules. ──────────────────

-- 1) Plank / L-Sit holds: seconds, per-second points, stopwatch UI
update public.exercises
set
  count_unit = 'seconds',
  time_points_mode = 'per_second',
  timer_ui = true,
  uses_time = true
where name ilike '%plank%'
   or name ilike '%l-sit%';

-- 2) Running (5 min) block: log minutes, not seconds of a 5-minute session
update public.exercises
set
  count_unit = 'minutes',
  time_points_mode = null,
  timer_ui = false,
  uses_time = true
where lower(name) like '%running%'
  and (lower(name) like '%5 min%' or lower(name) like '%5min%')
  and lower(name) not like '%mile%';

-- 3) Other “(5 min)” sports / cardio: seconds of play, points scale per minute
update public.exercises
set
  count_unit = 'seconds',
  time_points_mode = 'per_minute',
  timer_ui = false,
  uses_time = true
where (lower(name) like '%(5 min)%' or lower(name) like '%(5min)%')
  and not (
    lower(name) like '%running%'
    and (lower(name) like '%5 min%' or lower(name) like '%5min%')
  );

-- 4) Mile runs: distance-style rep count
update public.exercises
set
  count_unit = 'reps',
  time_points_mode = null,
  timer_ui = false,
  uses_time = false
where lower(name) like '%mile%';

-- 5) Keep uses_time consistent with count_unit (covers manual SQL / drift)
update public.exercises
set uses_time = coalesce(nullif(trim(count_unit::text), ''), 'reps')
  in ('seconds', 'minutes');
