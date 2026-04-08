-- Token / usage logging for process-ai-events OpenAI calls (cost tracking, debugging).
-- Run in Supabase SQL Editor after deploy. Edge inserts via service role.

create table if not exists public.ai_openai_usage_log (
  id uuid primary key default gen_random_uuid(),
  trigger_log_id uuid not null,
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  model_requested text,
  model_returned text,
  prompt_tokens int,
  completion_tokens int,
  total_tokens int,
  openai_response_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_openai_usage_log_room on public.ai_openai_usage_log (room_id, created_at desc);
create index if not exists idx_ai_openai_usage_log_created on public.ai_openai_usage_log (created_at desc);

alter table public.ai_openai_usage_log enable row level security;

comment on table public.ai_openai_usage_log is
  'Per OpenAI completion from process-ai-events; service role inserts only.';

grant insert on public.ai_openai_usage_log to service_role;

-- No client SELECT by default; use SQL editor or service role for analytics.
