-- Paste once into Supabase SQL Editor (existing projects).
-- 1) RLS helper — fixes 42P17 infinite recursion on room_members
-- 2) Rooms SELECT for creators
-- 3) Profile self-insert

-- === jars_room_ids_for_me (must run before policies below) ===
create or replace function public.jars_room_ids_for_me()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select room_id from public.room_members where user_id = auth.uid();
$$;

revoke all on function public.jars_room_ids_for_me() from public;
grant execute on function public.jars_room_ids_for_me() to authenticated;

-- === 01 rooms RLS (uses helper, no direct room_members subquery) ===
drop policy if exists "Members can view their rooms" on public.rooms;
drop policy if exists "Creators and members can view rooms" on public.rooms;

create policy "Creators and members can view rooms"
  on public.rooms for select
  to authenticated
  using (
    admin_id = auth.uid()
    or id in (select public.jars_room_ids_for_me())
  );

-- === 03 profile insert ===
drop policy if exists "Users can insert own profile" on public.profiles;

create policy "Users can insert own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- === 04 replace policies that still use raw room_members subqueries ===
-- (Safe if already applied: drops by name then recreates.)

drop policy if exists "Members can view reactions" on public.reactions;
drop policy if exists "Members can view group goals" on public.group_goals;
drop policy if exists "Members can view room scores" on public.scores;
drop policy if exists "Members can view room logs" on public.exercise_logs;
drop policy if exists "Members can create exercises" on public.exercises;
drop policy if exists "Members can view room exercises" on public.exercises;
drop policy if exists "Members can view room members" on public.room_members;

create policy "Members can view room members"
  on public.room_members for select
  to authenticated
  using (
    user_id = auth.uid()
    or room_id in (select public.jars_room_ids_for_me())
  );

create policy "Members can view room exercises"
  on public.exercises for select
  to authenticated
  using (
    room_id in (select public.jars_room_ids_for_me())
  );

create policy "Members can create exercises"
  on public.exercises for insert
  to authenticated
  with check (
    room_id in (select public.jars_room_ids_for_me())
  );

create policy "Members can view room logs"
  on public.exercise_logs for select
  to authenticated
  using (
    room_id in (select public.jars_room_ids_for_me())
  );

create policy "Members can view room scores"
  on public.scores for select
  to authenticated
  using (
    room_id in (select public.jars_room_ids_for_me())
  );

create policy "Members can view group goals"
  on public.group_goals for select
  to authenticated
  using (
    room_id in (select public.jars_room_ids_for_me())
  );

create policy "Members can view reactions"
  on public.reactions for select
  to authenticated
  using (
    log_id in (
      select id from public.exercise_logs
      where room_id in (select public.jars_room_ids_for_me())
    )
  );
