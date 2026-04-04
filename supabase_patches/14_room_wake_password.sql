-- Room: idle ghost/wake cards, optional join password, safe room discovery.
-- Requires pgcrypto (Supabase: Database → Extensions → pgcrypto).

create extension if not exists pgcrypto with schema extensions;

alter table public.rooms
  add column if not exists idle_nudge_hours int default 48;

alter table public.rooms
  add column if not exists join_password_hash text;

alter table public.rooms
  add column if not exists join_password_required boolean
  generated always as (join_password_hash is not null) stored;

comment on column public.rooms.idle_nudge_hours is
  'Hours without a real log before a "__WAKE__" feed card is generated. 0 = disabled.';

-- Was SETOF rooms; must drop before changing return type (42P13).
drop function if exists public.get_room_by_code(text);

-- Safe projection (never exposes join_password_hash)
create or replace function public.get_room_by_code(p_code text)
returns table (
  id uuid,
  name text,
  admin_id uuid,
  room_code text,
  max_participants int,
  daily_goal_points int,
  daily_goal_set_at timestamptz,
  streak_minimum int,
  created_at timestamptz,
  idle_nudge_hours int,
  join_password_required boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.name,
    r.admin_id,
    r.room_code,
    r.max_participants,
    r.daily_goal_points,
    r.daily_goal_set_at,
    r.streak_minimum,
    r.created_at,
    coalesce(r.idle_nudge_hours, 48),
    coalesce(r.join_password_required, false)
  from public.rooms r
  where upper(trim(r.room_code)) = upper(trim(p_code))
  limit 1;
$$;

revoke all on function public.get_room_by_code(text) from public;
grant execute on function public.get_room_by_code(text) to authenticated;

-- Admin sets or clears join password (stored as SHA-256 hex of utf8(password || room_id))
create or replace function public.set_room_join_password(
  p_room_id uuid,
  p_password text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.rooms
    where id = p_room_id and admin_id = auth.uid()
  ) then
    raise exception 'not_room_admin';
  end if;

  if p_password is null or length(trim(p_password)) = 0 then
    update public.rooms
    set join_password_hash = null
    where id = p_room_id;
  else
    update public.rooms
    set join_password_hash = encode(
      extensions.digest(
        convert_to(trim(p_password) || p_room_id::text, 'UTF8'),
        'sha256'
      ),
      'hex'
    )
    where id = p_room_id;
  end if;
end;
$$;

revoke all on function public.set_room_join_password(uuid, text) from public;
grant execute on function public.set_room_join_password(uuid, text) to authenticated;

-- Atomic join with password verification + membership + score row
create or replace function public.join_room_with_code(
  p_code text,
  p_password text default null
)
returns table (
  id uuid,
  name text,
  admin_id uuid,
  room_code text,
  max_participants int,
  daily_goal_points int,
  daily_goal_set_at timestamptz,
  streak_minimum int,
  created_at timestamptz,
  idle_nudge_hours int,
  join_password_required boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.rooms%rowtype;
  mcount int;
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;

  -- Qualify column: `room_code` is also an OUT param name from RETURNS TABLE (ambiguous otherwise).
  select * into r from public.rooms rm
  where upper(trim(rm.room_code)) = upper(trim(p_code))
  limit 1;

  if not found then
    return;
  end if;

  if r.join_password_hash is not null then
    if encode(
      extensions.digest(
        convert_to(trim(coalesce(p_password, '')) || r.id::text, 'UTF8'),
        'sha256'
      ),
      'hex'
    ) is distinct from r.join_password_hash then
      raise exception 'invalid_password';
    end if;
  end if;

  select count(*)::int into mcount from public.room_members where room_id = r.id;

  if not exists (
    select 1 from public.room_members where room_id = r.id and user_id = uid
  ) then
    if mcount >= r.max_participants then
      return;
    end if;
  end if;

  insert into public.room_members (room_id, user_id)
  values (r.id, uid)
  on conflict do nothing;

  insert into public.scores (
    room_id, user_id, total_score, daily_points, last_daily_reset,
    streak_current, streak_highest, updated_at
  )
  values (
    r.id, uid, 0, 0,
    (timezone('utc', now()))::date,
    0, 0, now()
  )
  on conflict (room_id, user_id) do nothing;

  return query
  select
    r2.id,
    r2.name,
    r2.admin_id,
    r2.room_code,
    r2.max_participants,
    r2.daily_goal_points,
    r2.daily_goal_set_at,
    r2.streak_minimum,
    r2.created_at,
    coalesce(r2.idle_nudge_hours, 48),
    coalesce(r2.join_password_required, false)
  from public.rooms r2
  where r2.id = r.id;
end;
$$;

revoke all on function public.join_room_with_code(text, text) from public;
grant execute on function public.join_room_with_code(text, text) to authenticated;

-- Insert idle "wake" feed rows for members who crossed idle_nudge_hours (once per ~24h per user)
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
    -- Count any feed row except idle ghost cards. Old filter !~ '^__' wrongly ignored
    -- __RANKUP__, __PR__, __STREAK__, __JOIN__, etc., so "active" users still looked idle.
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

revoke all on function public.ensure_idle_wake_cards(uuid) from public;
grant execute on function public.ensure_idle_wake_cards(uuid) to authenticated;

-- Room admin: clear one member's logs + scores in this room (moderation)
create or replace function public.admin_reset_room_member(
  p_room_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.rooms
    where id = p_room_id and admin_id = auth.uid()
  ) then
    raise exception 'not_room_admin';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'cannot_reset_self';
  end if;

  delete from public.exercise_logs
  where room_id = p_room_id and user_id = p_user_id;

  update public.scores
  set
    total_score = 0,
    daily_points = 0,
    streak_current = 0,
    streak_highest = 0,
    updated_at = now()
  where room_id = p_room_id and user_id = p_user_id;
end;
$$;

revoke all on function public.admin_reset_room_member(uuid, uuid) from public;
grant execute on function public.admin_reset_room_member(uuid, uuid) to authenticated;
