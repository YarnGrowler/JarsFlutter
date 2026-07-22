-- ============================================================
-- 47_debug_bots.sql — DEV-ONLY: real AI teammate accounts.
--
-- Seeds 3 fixed bot users so the debug "AI teammates" are genuine crew members:
-- real profiles (name + avatar-initial), real room_members (member faces + count),
-- real scores (leaderboard), and real exercise_logs (feed shows "Wade did 20
-- Push-ups"; supply flows to the siege). Everything in the app keys on
-- user_id -> profiles, so once these rows exist the bots render everywhere for
-- free with zero client special-casing.
--
-- Safe/idempotent. This is a TESTING aid — the SECURITY DEFINER RPCs are
-- membership-gated but you may drop this whole patch (and the 3 users) before
-- any real launch. Not required for the shipping app.
-- ============================================================

-- ── 1. Seed the 3 bot auth users (the handle_new_user trigger makes profiles) ──
-- Fixed UUIDs — must match kDebugBotIds in lib/core/debug_bots.dart.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  b.id, 'authenticated', 'authenticated', b.email,
  crypt('jars-debug-bot', gen_salt('bf')),
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', b.username),
  '', '', '', ''
from (values
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'bot.casey@jars.dev', 'Casey'),
  ('b0000000-0000-4000-8000-000000000002'::uuid, 'bot.wade@jars.dev',  'Wade'),
  ('b0000000-0000-4000-8000-000000000003'::uuid, 'bot.finn@jars.dev',  'Finn')
) as b(id, email, username)
on conflict (id) do nothing;

-- Safety net if handle_new_user didn't run (e.g. trigger disabled): ensure profiles.
insert into public.profiles (id, username)
select b.id, b.username
from (values
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'Casey'),
  ('b0000000-0000-4000-8000-000000000002'::uuid, 'Wade'),
  ('b0000000-0000-4000-8000-000000000003'::uuid, 'Finn')
) as b(id, username)
on conflict (id) do nothing;

-- The fixed bot id set, reused by the RPCs below.
create or replace function public._debug_bot_ids()
returns uuid[] language sql immutable as $$
  select array[
    'b0000000-0000-4000-8000-000000000001'::uuid,
    'b0000000-0000-4000-8000-000000000002'::uuid,
    'b0000000-0000-4000-8000-000000000003'::uuid
  ];
$$;

-- ── 2. Add bots to a room as real members + score rows ────────────────────────
create or replace function public.debug_add_bots_to_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = auth.uid()) then
    return; -- only a member may seed bots into their room
  end if;

  insert into public.room_members (room_id, user_id)
  select p_room_id, b from unnest(public._debug_bot_ids()) as b
  on conflict (room_id, user_id) do nothing;

  insert into public.scores (room_id, user_id)
  select p_room_id, b from unnest(public._debug_bot_ids()) as b
  on conflict (room_id, user_id) do nothing;
end;
$$;

-- ── 3. Log a real workout for a bot (feed + supply + leaderboard) ─────────────
create or replace function public.debug_bot_log(
  p_room_id uuid,
  p_bot_id uuid,
  p_exercise_name text,
  p_count int,
  p_points double precision,
  p_created_at timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = auth.uid()) then
    return;
  end if;
  if not (p_bot_id = any(public._debug_bot_ids())) then
    return; -- only ever writes for known bot ids
  end if;

  insert into public.exercise_logs
    (room_id, user_id, exercise_id, exercise_name, count, weight, points_earned, created_at)
  values
    (p_room_id, p_bot_id, null, p_exercise_name, p_count, 0, p_points,
     coalesce(p_created_at, now()));

  insert into public.scores (room_id, user_id, total_score)
  values (p_room_id, p_bot_id, p_points)
  on conflict (room_id, user_id) do update
    set total_score = public.scores.total_score + excluded.total_score,
        updated_at = now();
end;
$$;

-- ── 4. Remove all bot traces from a room ──────────────────────────────────────
create or replace function public.debug_remove_bots(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = auth.uid()) then
    return;
  end if;
  delete from public.exercise_logs
    where room_id = p_room_id and user_id = any(public._debug_bot_ids());
  delete from public.scores
    where room_id = p_room_id and user_id = any(public._debug_bot_ids());
  delete from public.room_members
    where room_id = p_room_id and user_id = any(public._debug_bot_ids());
end;
$$;

revoke all on function public.debug_add_bots_to_room(uuid) from public;
revoke all on function public.debug_bot_log(uuid, uuid, text, int, double precision, timestamptz) from public;
revoke all on function public.debug_remove_bots(uuid) from public;
grant execute on function public.debug_add_bots_to_room(uuid) to authenticated;
grant execute on function public.debug_bot_log(uuid, uuid, text, int, double precision, timestamptz) to authenticated;
grant execute on function public.debug_remove_bots(uuid) to authenticated;
