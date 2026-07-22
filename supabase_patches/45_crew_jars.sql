-- ============================================================
-- 45_crew_jars.sql — Co-op redesign: the shared weekly "jar".
--
-- The live jar (fill %, target, contributor slices) is computed client-side
-- from exercise_logs + room config, so the home works WITHOUT this patch.
-- This patch only adds cross-cycle persistence for the **crew streak**
-- (consecutive weeks the crew filled its jar). Safe to run on an existing DB.
-- ============================================================

create table if not exists public.crew_jars (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  base_per_person int not null default 70,
  cycle_length_days int not null default 7,
  crew_streak int not null default 0,
  best_crew_streak int not null default 0,
  last_filled_cycle_start date,
  last_evaluated_cycle_start date,
  updated_at timestamptz not null default now()
);

alter table public.crew_jars enable row level security;

drop policy if exists "Members can view crew jar" on public.crew_jars;
create policy "Members can view crew jar"
  on public.crew_jars for select
  to authenticated
  using (room_id in (select public.jars_room_ids_for_me()));

-- Evaluate the just-finished cycle and update the crew streak.
-- Idempotent per cycle via last_evaluated_cycle_start. SECURITY DEFINER so any
-- member can trigger the roll (they have no direct write access to the table).
create or replace function public.roll_crew_jar(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_min        int;
  v_cycle_len  int;
  v_base       int;
  v_streak     int;
  v_best       int;
  v_last_eval  date;
  v_today      date;
  v_cur_start  date;
  v_prev_start date;
  v_prev_end   date;
  v_active     int;
  v_filled     double precision;
  v_target     double precision;
begin
  select coalesce(streak_minimum, 10) into v_min
  from public.rooms where id = p_room_id;
  if v_min is null then
    return; -- no such room
  end if;

  insert into public.crew_jars (room_id, base_per_person)
  values (p_room_id, greatest(7 * v_min, 1))
  on conflict (room_id) do nothing;

  select cycle_length_days, base_per_person, crew_streak,
         best_crew_streak, last_evaluated_cycle_start
    into v_cycle_len, v_base, v_streak, v_best, v_last_eval
  from public.crew_jars where room_id = p_room_id;

  v_cycle_len := coalesce(v_cycle_len, 7);
  v_base      := coalesce(v_base, greatest(7 * v_min, 1));

  v_today     := (now() at time zone 'America/Chicago')::date;
  v_cur_start := v_today - (extract(isodow from v_today)::int - 1); -- Monday
  v_prev_start := v_cur_start - v_cycle_len;
  v_prev_end   := v_cur_start;

  -- Already rolled for the current cycle? Nothing to do.
  if v_last_eval is not null and v_last_eval >= v_cur_start then
    return;
  end if;

  -- Active members = distinct real loggers in the 14 days before cycle end.
  select count(distinct user_id) into v_active
  from public.exercise_logs
  where room_id = p_room_id
    and exercise_name !~ '^__'
    and (created_at at time zone 'America/Chicago')::date >= (v_prev_end - 14)
    and (created_at at time zone 'America/Chicago')::date <  v_prev_end;
  if v_active is null or v_active < 1 then
    v_active := 1;
  end if;

  -- Filled = real-workout points poured in during the previous cycle.
  select coalesce(sum(points_earned), 0) into v_filled
  from public.exercise_logs
  where room_id = p_room_id
    and exercise_name !~ '^__'
    and (created_at at time zone 'America/Chicago')::date >= v_prev_start
    and (created_at at time zone 'America/Chicago')::date <  v_prev_end;

  v_target := v_base::double precision * v_active;

  if v_target > 0 and v_filled >= v_target then
    v_streak := coalesce(v_streak, 0) + 1;
    update public.crew_jars
      set crew_streak = v_streak,
          best_crew_streak = greatest(coalesce(v_best, 0), v_streak),
          last_filled_cycle_start = v_prev_start,
          last_evaluated_cycle_start = v_cur_start,
          updated_at = now()
      where room_id = p_room_id;
  else
    update public.crew_jars
      set crew_streak = 0,
          last_evaluated_cycle_start = v_cur_start,
          updated_at = now()
      where room_id = p_room_id;
  end if;
end;
$$;

revoke all on function public.roll_crew_jar(uuid) from public;
grant execute on function public.roll_crew_jar(uuid) to authenticated;
