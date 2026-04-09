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

-- === 12 join by code (RPC) — baseline; 14_room_wake_password.sql upgrades this (safe projection) ===
create or replace function public.get_room_by_code(p_code text)
returns setof public.rooms
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.rooms
  where upper(trim(room_code)) = upper(trim(p_code))
  limit 1;
$$;

revoke all on function public.get_room_by_code(text) from public;
grant execute on function public.get_room_by_code(text) to authenticated;

-- === 13 room admin can delete feed rows (moderation) ===
drop policy if exists "Room admin can delete room logs" on public.exercise_logs;

create policy "Room admin can delete room logs"
  on public.exercise_logs for delete
  to authenticated
  using (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );

-- === 11 user_fcm_tokens (multi-device FCM — fixes REST 404 on /user_fcm_tokens) ===
-- Also in supabase_patches/11_fcm_multi_device.sql (same DDL).
create table if not exists public.user_fcm_tokens (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'web',
  last_seen_at timestamptz not null default now(),
  constraint user_fcm_tokens_token_key unique (token)
);

create index if not exists idx_user_fcm_tokens_user_id on public.user_fcm_tokens(user_id);

alter table public.user_fcm_tokens enable row level security;

drop policy if exists "Users manage own fcm tokens" on public.user_fcm_tokens;
create policy "Users manage own fcm tokens"
  on public.user_fcm_tokens
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on table public.user_fcm_tokens to authenticated;
grant select, insert, update, delete on table public.user_fcm_tokens to service_role;

-- === 14 wake cards + join password: run supabase_patches/14_room_wake_password.sql ===
-- === 15 wake room push + nudge limits + admin wake: run supabase_patches/15_wake_nudge_room_notify.sql ===
-- === 16 Web Push (VAPID): run supabase_patches/16_web_push_subscriptions.sql ===
-- === 17 idle wake last-seen fix: run supabase_patches/17_idle_wake_fix_last_seen.sql ===
-- === 18 idle wake uses real workout logs only: run supabase_patches/18_idle_wake_real_logs_only.sql ===
-- === 19 exercise count_unit column: run supabase_patches/19_exercise_count_unit.sql ===
-- === 20 idle wake: skip never-logged + cap days: run supabase_patches/20_idle_wake_skip_never_logged_cap_days.sql ===
-- === 21 exercise time_points_mode (per min vs per sec): run supabase_patches/21_time_points_mode.sql ===
-- === 22 exercise uses_time + timer_ui + backfill all rows: run supabase_patches/22_exercise_uses_time_and_backfill.sql ===
-- === 23 (5 min) sports → count_unit minutes + null time_points_mode: run supabase_patches/23_sports_blocks_use_minutes.sql ===
-- === 24 idle wake last-activity + 15m grace: run supabase_patches/24_idle_wake_activity_and_grace.sql ===
-- === 25 idle wake: skip actor + 48h floor: run supabase_patches/25_idle_wake_actor_skip_and_floor.sql ===
-- === 26 idle wake: skip auth.uid() caller (old app safe): run supabase_patches/26_idle_wake_skip_rpc_caller_auth_uid.sql ===
-- === 27 idle wake: fresh snapshot before insert (fixes cross-user race): run supabase_patches/27_idle_wake_fresh_snapshot_before_insert.sql ===
-- === 28 block spurious __WAKE__ at INSERT time (no ghost push): run supabase_patches/28_block_spurious_wake_before_insert.sql ===
-- === 29 fix notify trigger: | was regex alternation → idle spam on every log: run supabase_patches/29_fix_wake_regex_pipe_alternation.sql ===
-- === 34 streak at-risk nudge log + RPC (cron-streak-nudge Edge): run supabase_patches/34_streak_nudge.sql ===
-- === 35 AI OpenAI usage log (token counts): run supabase_patches/35_ai_openai_usage_log.sql ===
-- === 36 room achievements + Edge process-achievements: run supabase_patches/36_room_achievements.sql ===
