-- Fix false "idle" wake cards: last activity must include rank-up / PR / streak / join
-- broadcast rows — only __WAKE__ ghost cards are excluded from "last seen".
-- Also fix recent-wake check: LIKE '__WAKE__|%' treated _ as wildcards; use regex.
--
-- Run in Supabase SQL editor (linked project) once.

create or replace function public.ensure_idle_wake_cards(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rh int;
  m record;
  last_ts timestamptz;
  my_score double precision;
  rank_n int;
  days_i int;
  payload jsonb;
  idle_interval interval;
begin
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = auth.uid()
  ) then
    raise exception 'not_member';
  end if;

  select coalesce(idle_nudge_hours, 48) into rh
  from public.rooms
  where id = p_room_id;

  if rh is null or rh <= 0 then
    return;
  end if;

  idle_interval := (rh::text || ' hours')::interval;

  for m in
    select rm.user_id, p.username
    from public.room_members rm
    join public.profiles p on p.id = rm.user_id
    where rm.room_id = p_room_id
  loop
    select max(el.created_at) into last_ts
    from public.exercise_logs el
    where el.room_id = p_room_id
      and el.user_id = m.user_id
      and el.exercise_name !~ '^__WAKE__\\|';

    if last_ts is null then
      last_ts := timestamp 'epoch';
    end if;

    if now() - last_ts < idle_interval then
      continue;
    end if;

    if exists (
      select 1 from public.exercise_logs el
      where el.room_id = p_room_id
        and el.user_id = m.user_id
        and el.exercise_name ~ '^__WAKE__\\|'
        and el.created_at > now() - interval '20 hours'
    ) then
      continue;
    end if;

    select coalesce(s.total_score, 0) into my_score
    from public.scores s
    where s.room_id = p_room_id and s.user_id = m.user_id;

    select count(*)::int + 1 into rank_n
    from public.scores s
    where s.room_id = p_room_id
      and coalesce(s.total_score, 0) > my_score;

    days_i := greatest(1, floor(extract(epoch from (now() - last_ts)) / 86400.0)::int);

    payload := jsonb_build_object(
      'days', days_i,
      'rank', rank_n,
      'lastSeen', to_char(last_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'pick', floor(random() * 6)::int,
      'uname', m.username
    );

    insert into public.exercise_logs (
      room_id, user_id, exercise_id, exercise_name, count, weight, points_earned
    )
    values (
      p_room_id,
      m.user_id,
      null,
      '__WAKE__|' || payload::text,
      0,
      0,
      0
    );
  end loop;
end;
$$;

create or replace function public.admin_post_wake_reminder(
  p_room_id uuid,
  p_target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  last_ts timestamptz;
  my_score double precision;
  rank_n int;
  days_i int;
  payload jsonb;
  uname text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (
    select 1 from public.rooms
    where id = p_room_id and admin_id = auth.uid()
  ) then
    raise exception 'not_room_admin';
  end if;
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_target_user_id
  ) then
    raise exception 'not_room_member';
  end if;

  if exists (
    select 1 from public.exercise_logs el
    where el.room_id = p_room_id
      and el.user_id = p_target_user_id
      and el.exercise_name ~ '^__WAKE__\\|'
      and el.created_at > now() - interval '1 hour'
  ) then
    raise exception 'wake_recently_posted';
  end if;

  select max(el.created_at) into last_ts
  from public.exercise_logs el
  where el.room_id = p_room_id
    and el.user_id = p_target_user_id
    and el.exercise_name !~ '^__WAKE__\\|';

  if last_ts is null then
    last_ts := timestamp 'epoch';
  end if;

  select coalesce(s.total_score, 0) into my_score
  from public.scores s
  where s.room_id = p_room_id and s.user_id = p_target_user_id;

  select count(*)::int + 1 into rank_n
  from public.scores s
  where s.room_id = p_room_id
    and coalesce(s.total_score, 0) > my_score;

  days_i := greatest(1, floor(extract(epoch from (now() - last_ts)) / 86400.0)::int);

  select username into uname
  from public.profiles
  where id = p_target_user_id;

  payload := jsonb_build_object(
    'days', days_i,
    'rank', rank_n,
    'lastSeen', to_char(last_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'pick', floor(random() * 6)::int,
    'uname', uname
  );

  insert into public.exercise_logs (
    room_id, user_id, exercise_id, exercise_name, count, weight, points_earned
  )
  values (
    p_room_id,
    p_target_user_id,
    null,
    '__WAKE__|' || payload::text,
    0,
    0,
    0
  );
end;
$$;

revoke all on function public.ensure_idle_wake_cards(uuid) from public;
grant execute on function public.ensure_idle_wake_cards(uuid) to authenticated;

revoke all on function public.admin_post_wake_reminder(uuid, uuid) from public;
grant execute on function public.admin_post_wake_reminder(uuid, uuid) to authenticated;
