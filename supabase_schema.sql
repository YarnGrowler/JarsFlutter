-- ============================================================
-- Jars Supabase Schema (fresh project)
-- Paste this entire file into Supabase SQL Editor and run it.
--
-- If you already ran an older version and get "relation already exists",
-- do NOT re-run the full file. Apply incremental scripts in
-- supabase_patches/ instead (see 01_rooms_select_rls_for_creators.sql).
-- ============================================================

-- ==================== TABLES ====================

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null,
  created_at timestamptz default now()
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  admin_id uuid references public.profiles(id) on delete set null,
  room_code text unique not null,
  max_participants int default 20,
  daily_goal_points int,
  daily_goal_set_at timestamptz,
  streak_minimum int default 10,
  created_at timestamptz default now()
);

create table public.room_members (
  room_id uuid references public.rooms(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (room_id, user_id)
);

create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.rooms(id) on delete cascade,
  name text not null,
  points double precision not null,
  icon text not null default '💪',
  category text not null default 'Custom',
  supports_weight boolean default false,
  weight_threshold double precision,
  weight_multiplier double precision,
  created_by text not null default 'system',
  created_at timestamptz default now()
);

create table public.exercise_logs (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.rooms(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  exercise_id uuid references public.exercises(id) on delete set null,
  exercise_name text not null,
  count int not null,
  weight double precision default 0,
  points_earned double precision not null,
  created_at timestamptz default now()
);

create table public.scores (
  room_id uuid references public.rooms(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  total_score double precision default 0,
  daily_points double precision default 0,
  last_daily_reset date default current_date,
  streak_current int default 0,
  streak_highest int default 0,
  streak_last_workout date,
  updated_at timestamptz default now(),
  primary key (room_id, user_id)
);

create table public.group_goals (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.rooms(id) on delete cascade unique,
  target_points int not null,
  duration_days int not null,
  description text,
  start_date timestamptz not null default now(),
  created_at timestamptz default now()
);

create table public.reactions (
  id uuid primary key default gen_random_uuid(),
  log_id uuid references public.exercise_logs(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz default now(),
  unique (log_id, user_id)
);

-- ==================== INDEXES ====================

create index idx_exercise_logs_room on public.exercise_logs(room_id, created_at desc);
create index idx_exercise_logs_user on public.exercise_logs(user_id, created_at desc);
create index idx_scores_room on public.scores(room_id);
create index idx_room_members_user on public.room_members(user_id);
create index idx_rooms_code on public.rooms(room_code);
create index idx_reactions_log on public.reactions(log_id);

-- ==================== TRIGGER: AUTO-CREATE PROFILE ====================

create or replace function public.handle_new_user()
returns trigger as $$
declare
  un text;
begin
  -- App sends [username] and [display_name] in user_metadata; either works.
  un := coalesce(
    nullif(trim(new.raw_user_meta_data->>'username'), ''),
    nullif(trim(new.raw_user_meta_data->>'display_name'), '')
  );
  if un is null then
    un := split_part(new.email, '@', 1);
  end if;
  insert into public.profiles (id, username)
  values (new.id, un);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ==================== TRIGGER: AUTO-UPDATE updated_at ====================

create or replace function public.update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger scores_updated_at
  before update on public.scores
  for each row execute function public.update_updated_at();

-- Lists rooms the current user belongs to. SECURITY DEFINER avoids RLS recursion
-- (42P17) when policies on room_members referenced room_members in a subquery.
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

-- ==================== ROW LEVEL SECURITY ====================

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.exercises enable row level security;
alter table public.exercise_logs enable row level security;
alter table public.scores enable row level security;
alter table public.group_goals enable row level security;
alter table public.reactions enable row level security;

-- Profiles: anyone authenticated can read; users update own
create policy "Profiles are viewable by authenticated users"
  on public.profiles for select
  to authenticated
  using (true);

create policy "Users can update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- Rooms: creator can read immediately after insert (before room_members row);
-- members can read rooms they joined.
create policy "Creators and members can view rooms"
  on public.rooms for select
  to authenticated
  using (
    admin_id = auth.uid()
    or id in (select public.jars_room_ids_for_me())
  );

create policy "Authenticated users can create rooms"
  on public.rooms for insert
  to authenticated
  with check (admin_id = auth.uid());

create policy "Admin can update room"
  on public.rooms for update
  to authenticated
  using (admin_id = auth.uid());

create policy "Admin can delete room"
  on public.rooms for delete
  to authenticated
  using (admin_id = auth.uid());

-- Room Members: members can read co-members; users can join/leave
create policy "Members can view room members"
  on public.room_members for select
  to authenticated
  using (
    user_id = auth.uid()
    or room_id in (select public.jars_room_ids_for_me())
  );

create policy "Users can join rooms"
  on public.room_members for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "Users can leave rooms"
  on public.room_members for delete
  to authenticated
  using (user_id = auth.uid());

create policy "Admin can remove members"
  on public.room_members for delete
  to authenticated
  using (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );

-- Exercises: members can read exercises in their rooms
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

create policy "Admin can update exercises"
  on public.exercises for update
  to authenticated
  using (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );

create policy "Admin can delete exercises"
  on public.exercises for delete
  to authenticated
  using (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );

-- Exercise Logs: members can read logs in their rooms; users insert own
create policy "Members can view room logs"
  on public.exercise_logs for select
  to authenticated
  using (
    room_id in (select public.jars_room_ids_for_me())
  );

create policy "Users can insert own logs"
  on public.exercise_logs for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "Users can delete own logs"
  on public.exercise_logs for delete
  to authenticated
  using (user_id = auth.uid());

create policy "Room admin can delete room logs"
  on public.exercise_logs for delete
  to authenticated
  using (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );

-- Scores: members can read; users update own
create policy "Members can view room scores"
  on public.scores for select
  to authenticated
  using (
    room_id in (select public.jars_room_ids_for_me())
  );

create policy "Users can insert own scores"
  on public.scores for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "Users can update own scores"
  on public.scores for update
  to authenticated
  using (user_id = auth.uid());

-- Group Goals: members can read; admin can manage
create policy "Members can view group goals"
  on public.group_goals for select
  to authenticated
  using (
    room_id in (select public.jars_room_ids_for_me())
  );

create policy "Admin can manage group goals"
  on public.group_goals for insert
  to authenticated
  with check (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );

create policy "Admin can update group goals"
  on public.group_goals for update
  to authenticated
  using (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );

create policy "Admin can delete group goals"
  on public.group_goals for delete
  to authenticated
  using (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );

-- Reactions: members can read; users manage own
create policy "Members can view reactions"
  on public.reactions for select
  to authenticated
  using (
    log_id in (
      select id from public.exercise_logs
      where room_id in (select public.jars_room_ids_for_me())
    )
  );

create policy "Users can add reactions"
  on public.reactions for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "Users can remove own reactions"
  on public.reactions for delete
  to authenticated
  using (user_id = auth.uid());

-- ==================== REALTIME ====================
-- Enable realtime on tables that need live updates.
-- Run these in Supabase Dashboard > Database > Replication if the below doesn't work.

alter publication supabase_realtime add table public.exercise_logs;
alter publication supabase_realtime add table public.scores;
alter publication supabase_realtime add table public.reactions;

-- ==================== DAILY RESET FUNCTION (optional pg_cron) ====================
-- If you have pg_cron enabled, schedule this to run at midnight:
--
-- select cron.schedule(
--   'daily-score-reset',
--   '0 0 * * *',
--   $$
--     update public.scores
--     set daily_points = 0,
--         last_daily_reset = current_date
--     where last_daily_reset < current_date;
--   $$
-- );
--
-- Otherwise, the client handles daily reset checks on app open.
