-- Idle wake: the authenticated user who invokes ensure_idle_wake_cards is never
-- assigned a __WAKE__ row on that call. Fixes false "you are idle" pushes when
-- using an older app that does not send p_actor_user_id (25.sql alone cannot).
--
-- Run after 25_idle_wake_actor_skip_and_floor.sql

create or replace function public.ensure_idle_wake_cards(
  p_room_id uuid,
  p_actor_user_id uuid default null
)
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

  idle_interval := greatest(
    (rh::text || ' hours')::interval,
    interval '48 hours'
  );

  for m in
    select rm.user_id, p.username
    from public.room_members rm
    join public.profiles p on p.id = rm.user_id
    where rm.room_id = p_room_id
  loop
    -- You never get an idle card from your own RPC call (PostgREST JWT user).
    if auth.uid() is not null and m.user_id = auth.uid() then
      continue;
    end if;

    if p_actor_user_id is not null and m.user_id = p_actor_user_id then
      continue;
    end if;

    select max(el.created_at) into last_ts
    from public.exercise_logs el
    where el.room_id = p_room_id
      and el.user_id = m.user_id
      and (
        el.exercise_id is not null
        or (
          coalesce(el.points_earned, 0) > 0
          and el.exercise_name is not null
          and el.exercise_name !~ '^__'
        )
      );

    if last_ts is null then
      continue;
    end if;

    if now() - last_ts < idle_interval + interval '15 minutes' then
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
    if days_i > 999 then
      days_i := 999;
    end if;

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

revoke all on function public.ensure_idle_wake_cards(uuid, uuid) from public;
grant execute on function public.ensure_idle_wake_cards(uuid, uuid) to authenticated;
