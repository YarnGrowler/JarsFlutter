-- ============================================================
-- Jars Mega Update SQL Patch
-- Run this in the Supabase SQL editor BEFORE deploying the app.
-- ============================================================

-- 1. Reactions: allow multiple distinct emojis per user per log
ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_log_id_user_id_key;
ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_log_id_user_id_emoji_key;
ALTER TABLE reactions
  ADD CONSTRAINT reactions_log_id_user_id_emoji_key
  UNIQUE (log_id, user_id, emoji);

-- 2. FCM token on profiles for web push
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fcm_token text;

-- 3. Notifications table (triggers edge function push via webhook)
CREATE TABLE IF NOT EXISTS public.notifications (
  id         uuid            NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    uuid            REFERENCES auth.users(id) NOT NULL,
  created_at timestamptz     NOT NULL DEFAULT now(),
  body       text            NOT NULL
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can insert notifications" ON public.notifications;
CREATE POLICY "Authenticated can insert notifications"
  ON public.notifications FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Users read own notifications" ON public.notifications;
CREATE POLICY "Users read own notifications"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- 4. Badges table
CREATE TABLE IF NOT EXISTS public.badges (
  id          uuid            NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     uuid            REFERENCES auth.users(id) NOT NULL,
  room_id     text            NOT NULL,
  type        text            NOT NULL,
  awarded_at  timestamptz     NOT NULL DEFAULT now(),
  metadata    jsonb
);

ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own badges" ON public.badges;
CREATE POLICY "Users read own badges"
  ON public.badges FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authenticated can insert badges" ON public.badges;
CREATE POLICY "Authenticated can insert badges"
  ON public.badges FOR INSERT
  TO authenticated
  WITH CHECK (true);

ALTER TABLE public.badges
  DROP CONSTRAINT IF EXISTS badges_user_room_type_key;
ALTER TABLE public.badges
  ADD CONSTRAINT badges_user_room_type_key
  UNIQUE (user_id, room_id, type);
