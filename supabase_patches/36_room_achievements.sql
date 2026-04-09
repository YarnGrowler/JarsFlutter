-- Room achievements: progress, read state, admin reset, bonus points RPC.
-- Edge function process-achievements uses service_role; clients read progress only.

create table if not exists public.room_achievement_room_meta (
  room_id uuid primary key references public.rooms (id) on delete cascade,
  achievements_reset_at timestamptz not null default now(),
  generation int not null default 0
);

insert into public.room_achievement_room_meta (room_id, achievements_reset_at, generation)
select r.id, now(), 0
from public.rooms r
where not exists (
  select 1 from public.room_achievement_room_meta m where m.room_id = r.id
);

create table if not exists public.room_achievement_progress (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  achievement_key text not null,
  tier_reached int not null default 0,
  progress jsonb not null default '{}'::jsonb,
  last_unlock_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (room_id, user_id, achievement_key)
);

create index if not exists idx_room_achievement_progress_room on public.room_achievement_progress (room_id);
create index if not exists idx_room_achievement_progress_user_room on public.room_achievement_progress (room_id, user_id);

create table if not exists public.user_room_achievement_read_state (
  user_id uuid not null references public.profiles (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  last_opened_at timestamptz,
  primary key (user_id, room_id)
);

alter table public.room_achievement_room_meta enable row level security;
alter table public.room_achievement_progress enable row level security;
alter table public.user_room_achievement_read_state enable row level security;

-- Members can read room meta
create policy "Members read achievement room meta"
  on public.room_achievement_room_meta for select
  to authenticated
  using (
    exists (
      select 1 from public.room_members m
      where m.room_id = room_achievement_room_meta.room_id
        and m.user_id = auth.uid()
    )
  );

create policy "No client write achievement room meta"
  on public.room_achievement_room_meta for insert with check (false);
create policy "No client update achievement room meta"
  on public.room_achievement_room_meta for update using (false);

-- Members can read all progress in their rooms (feed context / gallery)
create policy "Members read achievement progress in room"
  on public.room_achievement_progress for select
  to authenticated
  using (
    exists (
      select 1 from public.room_members m
      where m.room_id = room_achievement_progress.room_id
        and m.user_id = auth.uid()
    )
  );

create policy "No client insert achievement progress"
  on public.room_achievement_progress for insert with check (false);
create policy "No client update achievement progress"
  on public.room_achievement_progress for update using (false);
create policy "No client delete achievement progress"
  on public.room_achievement_progress for delete using (false);

-- Own read state
create policy "User read own achievement read state"
  on public.user_room_achievement_read_state for select
  to authenticated
  using (user_id = auth.uid());

create policy "User upsert own achievement read state"
  on public.user_room_achievement_read_state for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "User update own achievement read state"
  on public.user_room_achievement_read_state for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Bonus points (service role / Edge only)
create or replace function public.achievement_apply_bonus(
  p_room_id uuid,
  p_user_id uuid,
  p_points double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_points is null or p_points <= 0 then
    return;
  end if;
  update public.scores
  set
    total_score = coalesce(total_score, 0) + p_points,
    updated_at = now()
  where room_id = p_room_id and user_id = p_user_id;
end;
$$;

revoke all on function public.achievement_apply_bonus(uuid, uuid, double precision) from public;
grant execute on function public.achievement_apply_bonus(uuid, uuid, double precision) to service_role;

-- Room admin: wipe progress + bump generation
create or replace function public.admin_reset_room_achievements(p_room_id uuid)
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

  delete from public.room_achievement_progress
  where room_id = p_room_id;

  insert into public.room_achievement_room_meta (room_id, achievements_reset_at, generation)
  values (p_room_id, now(), 1)
  on conflict (room_id) do update
  set
    achievements_reset_at = now(),
    generation = public.room_achievement_room_meta.generation + 1;
end;
$$;

revoke all on function public.admin_reset_room_achievements(uuid) from public;
grant execute on function public.admin_reset_room_achievements(uuid) to authenticated;

comment on table public.room_achievement_progress is 'Per-user achievement state per room; written by Edge process-achievements.';
comment on table public.user_room_achievement_read_state is 'Last time user opened achievements UI; for red-dot unread.';

-- Idempotency: one successful process-achievements pass per workout log.
create table if not exists public.achievement_processed_logs (
  log_id uuid primary key references public.exercise_logs (id) on delete cascade,
  processed_at timestamptz not null default now()
);

alter table public.achievement_processed_logs enable row level security;

grant select, insert, delete on public.achievement_processed_logs to service_role;

grant select, insert, update, delete on public.room_achievement_progress to service_role;
grant select, insert, update, delete on public.room_achievement_room_meta to service_role;
grant select, insert, update, delete on public.user_room_achievement_read_state to service_role;
