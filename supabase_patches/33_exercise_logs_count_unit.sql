-- How [count] is interpreted for this log row (matches exercises.count_unit).
alter table public.exercise_logs
  add column if not exists count_unit text default 'reps';

comment on column public.exercise_logs.count_unit is
  'reps | seconds | minutes — same meaning as public.exercises.count_unit.';
