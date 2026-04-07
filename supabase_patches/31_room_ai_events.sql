-- AI narrative events: state + per-room config (see supabase/functions/process-ai-events).
-- Apply after baseline schema. Edge uses service role to read/write.

-- Per-room rolling state for cheap detectors (no full-history scans).
create table if not exists public.room_ai_state (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  last_room_log_at timestamptz,
  leader_user_id uuid references public.profiles(id) on delete set null,
  leader_since timestamptz,
  last_leader_user_id uuid references public.profiles(id) on delete set null,
  rivalry_swaps jsonb not null default '[]'::jsonb,
  last_milestone_points double precision default 0,
  last_carry_roll_date date,
  last_retirement_roll_date date,
  last_domination_ai_at timestamptz,
  last_last_stand_date date,
  updated_at timestamptz not null default now()
);

-- Per user per room: spam window, heist window, etc.
create table if not exists public.user_room_ai_state (
  user_id uuid not null references public.profiles(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  spam_window_start timestamptz,
  spam_logs_in_window int not null default 0,
  spam_surge_fired_at timestamptz,
  heist_window_start timestamptz,
  heist_points_in_window double precision default 0,
  heist_fired_at timestamptz,
  last_carry_ai_at timestamptz,
  last_log_at timestamptz,
  primary key (user_id, room_id)
);

-- Overtake → response-gap tracking (victim should log within window).
create table if not exists public.overtake_response_watch (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  victim_user_id uuid not null references public.profiles(id) on delete cascade,
  actor_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  response_gap_fired_at timestamptz,
  unique (room_id, victim_user_id, actor_user_id)
);

-- Feature flags + numeric knobs (defaults applied in Edge if missing).
create table if not exists public.room_ai_config (
  room_id uuid not null references public.rooms(id) on delete cascade,
  event_key text not null,
  enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (room_id, event_key)
);

create index if not exists idx_user_room_ai_state_room on public.user_room_ai_state (room_id);
create index if not exists idx_overtake_watch_room on public.overtake_response_watch (room_id, created_at desc);

alter table public.room_ai_state enable row level security;
alter table public.user_room_ai_state enable row level security;
alter table public.overtake_response_watch enable row level security;
alter table public.room_ai_config enable row level security;

-- Members can read config; writes are service-role only (Edge).
create policy "Room members can view ai config"
  on public.room_ai_config for select
  using (
    exists (
      select 1 from public.room_members m
      where m.room_id = room_ai_config.room_id
        and m.user_id = auth.uid()
    )
  );

create policy "Room members can view room ai state"
  on public.room_ai_state for select
  using (
    exists (
      select 1 from public.room_members m
      where m.room_id = room_ai_state.room_id
        and m.user_id = auth.uid()
    )
  );

-- Deny client writes (Edge uses service role).
create policy "No client insert room_ai_state"
  on public.room_ai_state for insert with check (false);
create policy "No client update room_ai_state"
  on public.room_ai_state for update using (false);

create policy "No client insert user_room_ai_state"
  on public.user_room_ai_state for insert with check (false);
create policy "No client update user_room_ai_state"
  on public.user_room_ai_state for update using (false);

create policy "No client insert overtake_response_watch"
  on public.overtake_response_watch for insert with check (false);
create policy "No client update overtake_response_watch"
  on public.overtake_response_watch for update using (false);

create policy "No client insert room_ai_config"
  on public.room_ai_config for insert with check (false);
create policy "No client update room_ai_config"
  on public.room_ai_config for update using (false);

comment on table public.room_ai_state is 'Rolling AI event detectors; updated by Edge process-ai-events / cron-ai-daily.';
comment on table public.room_ai_config is 'Per-room toggles for AI narrative events (event_key + settings).';
