-- How points apply for time-based exercises (seconds): per minute vs per second.
alter table public.exercises
  add column if not exists time_points_mode text;

comment on column public.exercises.time_points_mode is
  'per_minute | per_second — with count_unit seconds: points × (sec/60) vs points × sec.';

-- Optional: align common sports to ~1 pt per minute of play (adjust points to 1 in app if needed).
update public.exercises
set time_points_mode = 'per_minute'
where count_unit = 'seconds'
  and time_points_mode is null
  and (
    lower(name) like '%volley%'
    or lower(name) like '%basket%'
    or lower(name) like '%soccer%'
    or lower(name) like '%tennis%'
    or lower(name) like '%badminton%'
    or lower(name) like '%pickleball%'
  );

update public.exercises
set time_points_mode = 'per_second'
where count_unit = 'seconds'
  and time_points_mode is null
  and (
    lower(name) like '%plank%'
    or lower(name) like '%wall sit%'
    or lower(name) like '%dead hang%'
  );
