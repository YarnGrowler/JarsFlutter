-- Join-by-code failed: direct SELECT on rooms is hidden by RLS until you're a member.
-- This RPC runs with definer rights so a user who knows the code can fetch the row
-- only for that code (no listing of all rooms).

CREATE OR REPLACE FUNCTION public.get_room_by_code(p_code text)
RETURNS SETOF public.rooms
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.rooms
  WHERE upper(trim(room_code)) = upper(trim(p_code))
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_room_by_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_room_by_code(text) TO authenticated;
