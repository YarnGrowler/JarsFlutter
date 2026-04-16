-- One-row “dashboard export” for a room: room row, members, leaderboard, recent logs, stats, group goal.
-- Change log_limit in CTE "p" (default 150). Change room in CTE "rid" if needed.
--
-- Requires columns on exercise_logs: count_unit, reply_to_log_id (see supabase_patches 32–33). Drop those keys from jsonb_build_object if your DB is older.
--
-- Room: 76d53f7d-f1fb-494f-a469-e5f336f06bde

WITH
  rid AS (
    SELECT '76d53f7d-f1fb-494f-a469-e5f336f06bde'::uuid AS room_id
  ),
  p AS (
    SELECT 150::int AS log_limit -- <<< change X here
  ),
  members_json AS (
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'user_id', rm.user_id,
            'username', pr.username,
            'joined_at', rm.joined_at
          )
          ORDER BY rm.joined_at
        ),
        '[]'::jsonb
      ) AS data
    FROM public.room_members rm
    JOIN public.profiles pr ON pr.id = rm.user_id
    CROSS JOIN rid
    WHERE rm.room_id = rid.room_id
  ),
  leaderboard_json AS (
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'rank', t.rank,
            'user_id', t.user_id,
            'username', t.username,
            'total_score', t.total_score,
            'daily_points', t.daily_points,
            'last_daily_reset', t.last_daily_reset,
            'streak_current', t.streak_current,
            'streak_highest', t.streak_highest,
            'streak_last_workout', t.streak_last_workout,
            'scores_updated_at', t.scores_updated_at
          )
          ORDER BY t.rank
        ),
        '[]'::jsonb
      ) AS data
    FROM (
      SELECT
        row_number() OVER (
          ORDER BY coalesce(s.total_score, 0) DESC, s.user_id
        ) AS rank,
        s.user_id,
        pr.username,
        coalesce(s.total_score, 0) AS total_score,
        coalesce(s.daily_points, 0) AS daily_points,
        s.last_daily_reset,
        coalesce(s.streak_current, 0) AS streak_current,
        coalesce(s.streak_highest, 0) AS streak_highest,
        s.streak_last_workout,
        s.updated_at AS scores_updated_at
      FROM public.scores s
      JOIN public.profiles pr ON pr.id = s.user_id
      CROSS JOIN rid
      WHERE s.room_id = rid.room_id
    ) t
  ),
  recent_logs_json AS (
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', x.id,
            'created_at', x.created_at,
            'user_id', x.user_id,
            'username', x.username,
            'exercise_id', x.exercise_id,
            'exercise_name', x.exercise_name,
            'count', x.count,
            'weight', x.weight,
            'points_earned', x.points_earned,
            'count_unit', x.count_unit,
            'reply_to_log_id', x.reply_to_log_id
          )
          ORDER BY x.created_at DESC
        ),
        '[]'::jsonb
      ) AS data
    FROM (
      SELECT
        el.id,
        el.created_at,
        el.user_id,
        pr.username,
        el.exercise_id,
        el.exercise_name,
        el.count,
        el.weight,
        el.points_earned,
        el.count_unit,
        el.reply_to_log_id
      FROM public.exercise_logs el
      LEFT JOIN public.profiles pr ON pr.id = el.user_id
      CROSS JOIN rid
      CROSS JOIN p
      WHERE el.room_id = rid.room_id
      ORDER BY el.created_at DESC
      LIMIT (SELECT log_limit FROM p)
    ) x
  ),
  stats_json AS (
    SELECT
      jsonb_build_object(
        'member_count', (SELECT count(*) FROM public.room_members rm CROSS JOIN rid WHERE rm.room_id = rid.room_id),
        'scores_rows', (SELECT count(*) FROM public.scores s CROSS JOIN rid WHERE s.room_id = rid.room_id),
        'total_exercise_log_rows', (SELECT count(*) FROM public.exercise_logs el CROSS JOIN rid WHERE el.room_id = rid.room_id),
        'exercise_catalog_rows', (SELECT count(*) FROM public.exercises e CROSS JOIN rid WHERE e.room_id = rid.room_id),
        'reactions_total_room', (
          SELECT count(*)::bigint
          FROM public.reactions r
          JOIN public.exercise_logs el ON el.id = r.log_id
          CROSS JOIN rid
          WHERE el.room_id = rid.room_id
        )
      ) AS data
  )
SELECT
  (SELECT to_jsonb(r.*) FROM public.rooms r CROSS JOIN rid WHERE r.id = rid.room_id) AS room,
  (SELECT data FROM members_json) AS members,
  (SELECT data FROM leaderboard_json) AS leaderboard,
  (SELECT data FROM recent_logs_json) AS recent_logs,
  (SELECT data FROM stats_json) AS stats,
  (
    SELECT to_jsonb(g.*)
    FROM public.group_goals g
    CROSS JOIN rid
    WHERE g.room_id = rid.room_id
    LIMIT 1
  ) AS group_goal;
