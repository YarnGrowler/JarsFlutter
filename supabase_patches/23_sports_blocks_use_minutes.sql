-- (5 min) cardio / sports: use minutes + clear time_points_mode (not seconds/per_minute).
-- Safe to re-run.

-- Non-running "(5 min)" blocks (volleyball, swimming, …)
update public.exercises
set
  count_unit = 'minutes',
  time_points_mode = null,
  timer_ui = false,
  uses_time = true
where (lower(name) like '%(5 min)%' or lower(name) like '%(5min)%')
  and not (
    lower(name) like '%running%'
    and (lower(name) like '%5 min%' or lower(name) like '%5min%')
  )
  and name not ilike '%plank%'
  and name not ilike '%l-sit%';

-- Running (5 min) — whole minutes per session
update public.exercises
set
  count_unit = 'minutes',
  time_points_mode = null,
  timer_ui = false,
  uses_time = true
where lower(name) like '%running%'
  and (lower(name) like '%5 min%' or lower(name) like '%5min%')
  and lower(name) not like '%mile%';

update public.exercises
set uses_time = coalesce(nullif(trim(count_unit::text), ''), 'reps')
  in ('seconds', 'minutes');
