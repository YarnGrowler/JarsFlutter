-- ============================================================
-- 46_room_leagues.sql — Co-op Leagues.
--
-- The live table + AI opponents are computed CLIENT-SIDE (deterministic seed),
-- so the app works WITHOUT this patch (rooms just sit in the lowest division).
-- This patch only persists the tiny promotion/relegation state and enforces
-- once-only league notifications, both with DB-level idempotency.
-- Safe to run on an existing database.
-- ============================================================

-- Current division + season for a room (one row per room).
create table if not exists public.room_leagues (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  division_index int not null default 0,
  season_index int not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.room_leagues enable row level security;

drop policy if exists "Members can view room league" on public.room_leagues;
create policy "Members can view room league"
  on public.room_leagues for select
  to authenticated
  using (room_id in (select public.jars_room_ids_for_me()));

-- Advance a room's division for a new season. Idempotent: the UPDATE fires only
-- when the incoming season is strictly newer than what's stored, so multiple
-- devices computing the same deterministic result converge (first writer wins).
create or replace function public.advance_room_league(
  p_room_id uuid,
  p_division_index int,
  p_season_index int
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = auth.uid()
  ) then
    return; -- only members can touch their room's league
  end if;

  insert into public.room_leagues (room_id, division_index, season_index, updated_at)
  values (p_room_id, greatest(coalesce(p_division_index, 0), 0), p_season_index, now())
  on conflict (room_id) do update
    set division_index = excluded.division_index,
        season_index = excluded.season_index,
        updated_at = now()
    where public.room_leagues.season_index < excluded.season_index;
end;
$$;

revoke all on function public.advance_room_league(uuid, int, int) from public;
grant execute on function public.advance_room_league(uuid, int, int) to authenticated;

-- Dedupe table: exactly one notification per (room, matchweek, kind).
create table if not exists public.league_notifications (
  room_id uuid not null references public.rooms(id) on delete cascade,
  week_index int not null,
  kind text not null,
  created_at timestamptz not null default now(),
  primary key (room_id, week_index, kind)
);

alter table public.league_notifications enable row level security;
-- No direct client access; the SECURITY DEFINER RPC below manages it.

-- Fire a league notification to the room's members exactly once per
-- (room, week, kind). Returns true only for the call that actually created it,
-- so whichever device resolves the week first sends a single push.
create or replace function public.notify_league_event(
  p_room_id uuid,
  p_week_index int,
  p_kind text,
  p_body text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows int := 0;
begin
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = auth.uid()
  ) then
    return false;
  end if;

  insert into public.league_notifications (room_id, week_index, kind)
  values (p_room_id, p_week_index, p_kind)
  on conflict (room_id, week_index, kind) do nothing;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return false; -- already sent for this (room, week, kind)
  end if;

  -- Notify everyone except the caller (they're looking at the app already).
  insert into public.notifications (user_id, body)
    select rm.user_id, p_body
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id is distinct from auth.uid();

  return true;
end;
$$;

revoke all on function public.notify_league_event(uuid, int, text, text) from public;
grant execute on function public.notify_league_event(uuid, int, text, text) to authenticated;
