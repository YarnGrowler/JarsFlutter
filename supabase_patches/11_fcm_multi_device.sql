-- One row per FCM installation; users can have many devices (phone + laptop + tablet).
-- Upsert from the app on token; edge function sends to all tokens for the user.
-- Same DDL is embedded in 00_apply_all.sql (section "11 user_fcm_tokens") for one-shot apply.

CREATE TABLE IF NOT EXISTS public.user_fcm_tokens (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL DEFAULT 'web',
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_fcm_tokens_token_key UNIQUE (token)
);

CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_id ON public.user_fcm_tokens(user_id);

ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own fcm tokens" ON public.user_fcm_tokens;
CREATE POLICY "Users manage own fcm tokens"
  ON public.user_fcm_tokens
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
