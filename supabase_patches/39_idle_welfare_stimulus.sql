-- Idle ghost card: random "room welfare" stimulus points for absent members (lower rank = more).
-- Inserts __STIMULUS__| row when pts > 0 so Chicago daily / profile can include it; does not count
-- as a real workout (still matches ^__ for last-seen / idle logic).
--
-- Run after 27_idle_wake_fresh_snapshot_before_insert.sql and 37_achievement_bonus_daily_points.sql

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
  last_ts_fresh timestamptz;
  my_score double precision;
  rank_n int;
  days_i int;
  payload jsonb;
  idle_interval interval;
  member_count int;
  welfare_raw int;
  welfare_pts int;
  rf double precision;
  pack_mult double precision;
  chicago_today date;
begin
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = auth.uid()
  ) then
    raise exception 'not_member';
  end if;

  select count(*)::int into member_count
  from public.room_members
  where room_id = p_room_id;

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

  chicago_today := (current_timestamp at time zone 'America/Chicago')::date;

  for m in
    select rm.user_id, p.username
    from public.room_members rm
    join public.profiles p on p.id = rm.user_id
    where rm.room_id = p_room_id
  loop
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

    select max(el.created_at) into last_ts_fresh
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

    if last_ts_fresh is null then
      continue;
    end if;

    if now() - last_ts_fresh < idle_interval + interval '15 minutes' then
      continue;
    end if;

    days_i := greatest(1, floor(extract(epoch from (now() - last_ts_fresh)) / 86400.0)::int);
    if days_i > 999 then
      days_i := 999;
    end if;

    rf := random();
    if rf < 0.14 then
      welfare_raw := 0;
    elsif rf < 0.38 then
      welfare_raw := floor(5 + random() * 10)::int;
    elsif rf < 0.82 then
      welfare_raw := floor(8 + random() * 18)::int;
    elsif rf < 0.96 then
      welfare_raw := floor(15 + random() * 14)::int;
    else
      welfare_raw := floor(40 + random() * 31)::int;
    end if;

    if member_count <= 1 then
      pack_mult := 1.0;
    else
      pack_mult := 0.28 + 0.72 * ((rank_n - 1)::double precision / (member_count - 1)::double precision);
    end if;

    welfare_pts := floor(welfare_raw * pack_mult)::int;
    if welfare_pts < 0 then
      welfare_pts := 0;
    end if;

    payload := jsonb_build_object(
      'days', days_i,
      'rank', rank_n,
      'lastSeen', to_char(last_ts_fresh at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'pick', floor(random() * 6)::int,
      'uname', m.username,
      'welfare', welfare_pts
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

    if welfare_pts > 0 then
      insert into public.scores (room_id, user_id, total_score, daily_points, last_daily_reset, updated_at)
      values (
        p_room_id,
        m.user_id,
        welfare_pts::double precision,
        welfare_pts::double precision,
        chicago_today,
        now()
      )
      on conflict (room_id, user_id) do update
      set
        total_score = coalesce(public.scores.total_score, 0) + welfare_pts::double precision,
        daily_points =
          (
            case
              when public.scores.last_daily_reset is null
                or public.scores.last_daily_reset < chicago_today
              then 0::double precision
              else coalesce(public.scores.daily_points, 0)
            end
          ) + welfare_pts::double precision,
        last_daily_reset = chicago_today,
        updated_at = now();

      insert into public.exercise_logs (
        room_id, user_id, exercise_id, exercise_name, count, weight, points_earned
      )
      values (
        p_room_id,
        m.user_id,
        null,
        '__STIMULUS__|' || jsonb_build_object('pts', welfare_pts, 'kind', 'welfare')::text,
        0,
        0,
        welfare_pts::double precision
      );
    end if;
  end loop;
end;
$$;

revoke all on function public.ensure_idle_wake_cards(uuid, uuid) from public;
grant execute on function public.ensure_idle_wake_cards(uuid, uuid) to authenticated;
