-- Lets the app create a missing profile row (e.g. trigger failed or user created in Dashboard).
-- Run after 01_rooms_select_rls_for_creators.sql if you still see FK / null errors.

drop policy if exists "Users can insert own profile" on public.profiles;

create policy "Users can insert own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);
