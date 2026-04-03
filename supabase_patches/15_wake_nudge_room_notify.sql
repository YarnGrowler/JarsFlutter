-- Wake cards: room-wide push (excluding absent), rate-limited nudges (2 per user per card),
-- admin manual wake post RPC.
-- Run in Supabase SQL editor after 14_room_wake_password.sql.

-- ── Nudge taps (max 2 per wake_log_id + from_user_id enforced in RPC) ───────
create table if not exists public.wake_nudge_taps (
  id uuid primary key default gen_random_uuid(),
  wake_log_id uuid not null references public.exercise_logs(id) on delete cascade,
  from_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists idx_wake_nudge_taps_log_from
  on public.wake_nudge_taps (wake_log_id, from_user_id);

alter table public.wake_nudge_taps enable row level security;

-- No policies: only security definer RPC touches this table.

-- ── After each __WAKE__ feed row, notify room members (not the absent person) ─
create or replace function public.notify_room_on_wake_card()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rname text;
  uname text;
begin
  -- Prefix is literal __WAKE__| — use regex (LIKE treats _ as wildcard).
  if new.exercise_name is null or new.exercise_name !~ '^__WAKE__\\|' then
    return new;
  end if;

  select name into rname from public.rooms where id = new.room_id;
  select coalesce(username, 'Teammate') into uname
  from public.profiles where id = new.user_id;

  insert into public.notifications (user_id, body)
  select rm.user_id,
    format(
      '👻 %s is idle in "%s" — open the room feed to send a wake ping (max 2 per person).',
      uname,
      coalesce(rname, 'your room')
    )
  from public.room_members rm
  where rm.room_id = new.room_id
    and rm.user_id is distinct from new.user_id;

  return new;
end;
$$;

drop trigger if exists trg_exercise_logs_notify_wake on public.exercise_logs;
create trigger trg_exercise_logs_notify_wake
  after insert on public.exercise_logs
  for each row
  execute procedure public.notify_room_on_wake_card();

-- ── Member taps "Wake them up" (max 2 per member per wake card) ──────────────
create or replace function public.send_wake_nudge(p_log_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  el public.exercise_logs%rowtype;
  tap_count int;
  tapper_name text;
  body text;
  k int;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select * into el from public.exercise_logs where id = p_log_id;
  if not found then
    raise exception 'log_not_found';
  end if;
  if el.exercise_name is null or el.exercise_name !~ '^__WAKE__\\|' then
    raise exception 'not_wake_card';
  end if;
  if not exists (
    select 1 from public.room_members
    where room_id = el.room_id and user_id = auth.uid()
  ) then
    raise exception 'not_room_member';
  end if;
  if el.user_id = auth.uid() then
    raise exception 'cannot_nudge_self';
  end if;

  select count(*)::int into tap_count
  from public.wake_nudge_taps
  where wake_log_id = p_log_id and from_user_id = auth.uid();

  if tap_count >= 2 then
    raise exception 'wake_nudge_limit';
  end if;

  insert into public.wake_nudge_taps (wake_log_id, from_user_id)
  values (p_log_id, auth.uid());

  select username into tapper_name from public.profiles where id = auth.uid();
  tapper_name := coalesce(nullif(trim(tapper_name), ''), 'Teammate');

  k := 1 + floor(random() * 6)::int;
  body := case k
    when 1 then format('%s: yo — your room wants to see a log from you.', tapper_name)
    when 2 then format('%s tapped "wake you up" in the feed.', tapper_name)
    when 3 then format('%s says the squad is asking where your log is.', tapper_name)
    when 4 then format('%s sent a wake ping (%s/2 from them on this card).', tapper_name, tap_count + 1)
    when 5 then format('%s: time to show the room you''re alive.', tapper_name)
    else format('%s nudged you — streak misses you.', tapper_name)
  end;

  insert into public.notifications (user_id, body)
  values (el.user_id, body);
end;
$$;

revoke all on function public.send_wake_nudge(uuid) from public;
grant execute on function public.send_wake_nudge(uuid) to authenticated;

-- ── Admin: post a wake card for a member (1/hour per target cooldown) ───────
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
    and el.exercise_name !~ '^__';

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

revoke all on function public.admin_post_wake_reminder(uuid, uuid) from public;
grant execute on function public.admin_post_wake_reminder(uuid, uuid) to authenticated;
