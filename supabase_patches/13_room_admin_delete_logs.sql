-- Room admins can delete any exercise_logs row in rooms they own (feed moderation).
drop policy if exists "Room admin can delete room logs" on public.exercise_logs;

create policy "Room admin can delete room logs"
  on public.exercise_logs for delete
  to authenticated
  using (
    room_id in (select id from public.rooms where admin_id = auth.uid())
  );
