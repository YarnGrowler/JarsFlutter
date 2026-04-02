-- Run in Supabase SQL Editor if you already applied an older schema.
-- Fixes: room create failed with null / parse errors because SELECT on rooms
-- was only allowed for room_members — the host is not a member until after insert.

drop policy if exists "Members can view their rooms" on public.rooms;
drop policy if exists "Creators and members can view rooms" on public.rooms;

create policy "Creators and members can view rooms"
  on public.rooms for select
  to authenticated
  using (
    admin_id = auth.uid()
    or id in (select room_id from public.room_members where user_id = auth.uid())
  );
