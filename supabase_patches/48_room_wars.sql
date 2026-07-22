-- ============================================================
-- Patch 48: Clan War shared room state (real multiplayer wars)
-- ============================================================
-- One row per room holds the ENTIRE serialized Clan War (the exact same JSON
-- shape the client already writes to local SharedPreferences for solo play —
-- see WarGame.toJson/loadFromJson). Your crew is real room members now, not
-- fake local AI teammates, and this table is what lets every one of them see
-- the same base, the same army, the same war on their own device.
--
-- `version` is optimistic concurrency: a save only lands if it still matches
-- the version the client last read. If a teammate saved in between, the
-- later write is REJECTED (not silently merged/overwritten) and the caller
-- reloads the winner's state instead — nobody's build or raid gets quietly
-- erased by a race.

create table if not exists public.room_wars (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  state jsonb not null,
  version bigint not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

alter table public.room_wars enable row level security;

-- ==================== ROW LEVEL SECURITY ====================
-- Reads: any co-member, straight off the table (mirrors room_members' own
-- read policy) — the client polls/streams this directly, same pattern as
-- LogService.streamRoomFeed on exercise_logs.
create policy "room_wars_select_co_members" on public.room_wars
  for select using (room_id in (select public.jars_room_ids_for_me()));

-- Writes ONLY through the RPCs below (security definer, explicit membership
-- check in the function body) — no direct insert/update policy, matching
-- join_room_with_code's convention for anything that needs an atomic
-- check-then-mutate.

-- ==================== RPCs ====================

-- Fetch the room's war, creating it (version 0) on first-ever use. Returns
-- exactly one row either way, so the caller never has to branch on "does
-- this room have a war yet."
create or replace function public.ensure_room_war(
  p_room_id uuid,
  p_initial_state jsonb
)
returns table (version bigint, state jsonb)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (
    select 1 from public.room_members where room_id = p_room_id and user_id = uid
  ) then
    raise exception 'not_a_member';
  end if;

  insert into public.room_wars (room_id, state, version, updated_by)
  values (p_room_id, p_initial_state, 0, uid)
  on conflict (room_id) do nothing;

  return query
    select rw.version, rw.state from public.room_wars rw where rw.room_id = p_room_id;
end;
$$;

revoke all on function public.ensure_room_war(uuid, jsonb) from public;
grant execute on function public.ensure_room_war(uuid, jsonb) to authenticated;

-- Compare-and-swap save. `conflict = true` means someone else saved first —
-- `state`/`version` in the result are the CURRENT (winning) row, not what the
-- caller sent; the client should loadFromJson(state) and try again from there.
create or replace function public.save_room_war(
  p_room_id uuid,
  p_state jsonb,
  p_expected_version bigint
)
returns table (version bigint, state jsonb, conflict boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_new_version bigint;
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (
    select 1 from public.room_members where room_id = p_room_id and user_id = uid
  ) then
    raise exception 'not_a_member';
  end if;

  update public.room_wars rw
    set state = p_state,
        version = rw.version + 1,
        updated_at = now(),
        updated_by = uid
    where rw.room_id = p_room_id and rw.version = p_expected_version
    returning rw.version into v_new_version;

  if found then
    return query select v_new_version, p_state, false;
  else
    return query
      select rw.version, rw.state, true
      from public.room_wars rw
      where rw.room_id = p_room_id;
  end if;
end;
$$;

revoke all on function public.save_room_war(uuid, jsonb, bigint) from public;
grant execute on function public.save_room_war(uuid, jsonb, bigint) to authenticated;

-- ==================== REALTIME ====================
-- Teammates see each other's moves without polling (same mechanism as the
-- room feed).
alter publication supabase_realtime add table public.room_wars;
