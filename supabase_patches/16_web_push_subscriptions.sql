-- Standard Web Push (VAPID). Edge function push/index.ts sends via @pushforge/builder + fetch.

CREATE TABLE IF NOT EXISTS public.user_web_push_subscriptions (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  enabled boolean NOT NULL DEFAULT true,
  CONSTRAINT user_web_push_subscriptions_endpoint_key UNIQUE (endpoint)
);

CREATE INDEX IF NOT EXISTS idx_user_web_push_user_id ON public.user_web_push_subscriptions(user_id);

ALTER TABLE public.user_web_push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own web push subs" ON public.user_web_push_subscriptions;
CREATE POLICY "Users manage own web push subs"
  ON public.user_web_push_subscriptions
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_web_push_subscriptions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_web_push_subscriptions TO service_role;
