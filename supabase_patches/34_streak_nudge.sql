-- Streak-at-risk nudges: dedupe log + RPC used by Edge cron `cron-streak-nudge`.
-- Run in Supabase SQL Editor, then deploy: supabase functions deploy cron-streak-nudge --no-verify-jwt

create table if not exists public.streak_nudge_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  nudge_date date not null,
  created_at timestamptz not null default now(),
  unique (user_id, room_id, nudge_date)
);

create index if not exists idx_streak_nudge_log_nudge_date on public.streak_nudge_log (nudge_date desc);

alter table public.streak_nudge_log enable row level security;

-- No client policies; Edge uses service role.

comment on table public.streak_nudge_log is
  'One row per (user, room, Chicago calendar day) when a streak-at-risk push was sent.';

create or replace function public.cron_streak_nudge_execute(p_min_streak int default 2)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  with today_cte as (
    select (now() at time zone 'America/Chicago')::date as d
  ),
  scored as (
    select
      s.room_id,
      s.user_id,
      s.streak_current,
      r.name as room_name,
      r.streak_minimum,
      case
        when s.last_daily_reset is null or s.last_daily_reset < t.d then 0::double precision
        else s.daily_points
      end as effective_daily
    from scores s
    inner join rooms r on r.id = s.room_id
    cross join today_cte t
    where r.streak_minimum > 0
      and s.streak_current >= p_min_streak
      and s.streak_last_workout is distinct from t.d
      and (
        case
          when s.last_daily_reset is null or s.last_daily_reset < t.d then 0::double precision
          else s.daily_points
        end
      ) < r.streak_minimum::double precision
  ),
  claimed as (
    insert into public.streak_nudge_log (user_id, room_id, nudge_date)
    select user_id, room_id, (select d from today_cte)
    from scored
    on conflict (user_id, room_id, nudge_date) do nothing
    returning user_id, room_id
  )
  insert into public.notifications (user_id, body)
  select
    c.user_id,
    format(
      '🔥 Your %s-day streak in "%s" needs %s more pts (min %s/day, Chicago) before midnight — log now!',
      sc.streak_current,
      sc.room_name,
      greatest(0, ceil(sc.streak_minimum::numeric - sc.effective_daily::numeric))::int,
      sc.streak_minimum
    )
  from claimed c
  inner join scored sc on sc.room_id = c.room_id and sc.user_id = c.user_id;

  get diagnostics n = row_count;
  return coalesce(n, 0);
end;
$$;

comment on function public.cron_streak_nudge_execute(int) is
  'Inserts streak-at-risk notifications for users below room streak_minimum today (Chicago), idempotent per day via streak_nudge_log.';

revoke all on function public.cron_streak_nudge_execute(int) from public;
grant execute on function public.cron_streak_nudge_execute(int) to service_role;
