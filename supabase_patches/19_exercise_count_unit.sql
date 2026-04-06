-- Optional: persisted unit for rep vs time exercises (Flutter infers if null).
alter table public.exercises
  add column if not exists count_unit text default 'reps';

comment on column public.exercises.count_unit is
  'reps | seconds | minutes — how count is interpreted for points and UI.';
