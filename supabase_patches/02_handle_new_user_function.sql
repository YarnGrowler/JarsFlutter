-- Run only if you need the updated trigger (username / display_name / email fallback).
-- Safe to run on existing DBs; replaces the function only.

create or replace function public.handle_new_user()
returns trigger as $$
declare
  un text;
begin
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
