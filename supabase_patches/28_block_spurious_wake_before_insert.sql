-- Last line of defense: cancel __WAKE__ inserts when the target still has a recent
-- real workout. Runs BEFORE INSERT in the same statement as the insert, so it sees
-- all commits from other transactions — fixes races that survive ensure_idle_wake_cards
-- (e.g. push notification fired but you do not see a ghost card because the row should
-- never have committed, or the card scrolled off under the 50-item cap).
--
-- If this trigger returns NULL, the row is not inserted → notify_room_on_wake_card
-- (AFTER INSERT) never runs → no "👻 … is idle …" push.
--
-- Run after 27_idle_wake_fresh_snapshot_before_insert.sql

create or replace function public.trg_block_spurious_wake_card()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rh int;
  idle_interval interval;
  last_ts timestamptz;
begin
  -- Do NOT use regex here: in POSIX `|` is alternation, so patterns like `^__WAKE__|`
  -- can match incorrectly and this trigger will cancel *normal* workout inserts →
  -- PostgREST `.single()` returns PGRST116 (0 rows).
  if new.exercise_name is null
     or not starts_with(new.exercise_name, '__WAKE__|') then
    return new;
  end if;

  select coalesce(idle_nudge_hours, 48) into rh
  from public.rooms
  where id = new.room_id;

  -- Idle nudge off: do not apply automatic blocking (manual/admin wake rows may still exist).
  if rh is null or rh <= 0 then
    return new;
  end if;

  idle_interval := greatest(
    (rh::text || ' hours')::interval,
    interval '48 hours'
  );

  select max(el.created_at) into last_ts
  from public.exercise_logs el
  where el.room_id = new.room_id
    and el.user_id = new.user_id
    and (
      el.exercise_id is not null
      or (
        coalesce(el.points_earned, 0) > 0
        and el.exercise_name is not null
        and el.exercise_name !~ '^__'
      )
    );

  if last_ts is not null
     and now() - last_ts < idle_interval + interval '15 minutes' then
    return null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_block_spurious_wake_card on public.exercise_logs;

create trigger trg_block_spurious_wake_card
  before insert on public.exercise_logs
  for each row
  execute procedure public.trg_block_spurious_wake_card();
