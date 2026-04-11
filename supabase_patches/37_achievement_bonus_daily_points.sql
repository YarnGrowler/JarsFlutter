-- Achievement bonuses must bump daily_points (Chicago day) so Today leaderboard matches total_score
-- and "+N today" includes achievement rewards, same as workout points.

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
declare
  chicago_today date;
begin
  if p_points is null or p_points <= 0 then
    return;
  end if;

  chicago_today := (current_timestamp at time zone 'America/Chicago')::date;

  update public.scores
  set
    total_score = coalesce(total_score, 0) + p_points,
    daily_points =
      (
        case
          when last_daily_reset is null
            or last_daily_reset < chicago_today
          then 0::double precision
          else coalesce(daily_points, 0)
        end
      ) + p_points,
    last_daily_reset = chicago_today,
    updated_at = now()
  where room_id = p_room_id and user_id = p_user_id;
end;
$$;

revoke all on function public.achievement_apply_bonus(uuid, uuid, double precision) from public;
grant execute on function public.achievement_apply_bonus(uuid, uuid, double precision) to service_role;
