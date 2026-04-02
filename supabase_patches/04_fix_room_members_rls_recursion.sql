-- Fixes: PostgREST 500 / 42P17 "infinite recursion detected in policy for relation room_members".
-- Policies must NOT subquery room_members directly (self-reference under RLS).
-- Run after 00_apply_all.sql if you already had old policies, or run standalone.

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

drop policy if exists "Members can view reactions" on public.reactions;
drop policy if exists "Members can view group goals" on public.group_goals;
drop policy if exists "Members can view room scores" on public.scores;
drop policy if exists "Members can view room logs" on public.exercise_logs;
drop policy if exists "Members can create exercises" on public.exercises;
drop policy if exists "Members can view room exercises" on public.exercises;
drop policy if exists "Members can view room members" on public.room_members;
drop policy if exists "Creators and members can view rooms" on public.rooms;

create policy "Creators and members can view rooms"
  on public.rooms for select
  to authenticated
  using (
    admin_id = auth.uid()
    or id in (select public.jars_room_ids_for_me())
  );

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
