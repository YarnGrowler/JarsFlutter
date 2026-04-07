# AI narrative events

## What it does

After each **real** workout log, the app calls the Edge Function `process-ai-events` with `{ log_id }`. The function:

1. Runs cheap detectors (heist, ghost return, rivalry, uno reverse, domination, room milestone, silence break, spam surge, carry, near tie, …).
2. Batches all fired events into **one** OpenAI call.
3. Inserts a feed row: `exercise_name = '__AI__|' || json` (see `ExerciseLog.kAiPrefix`).

Optional push to all room members: set Edge secret `AI_EVENTS_SEND_PUSH=true` (off by default).

Daily cron function `cron-ai-daily` (Bearer `CRON_SECRET`): last stand batch, response gap, random retirement / carry lore.

## Supabase setup

1. **SQL:** run `supabase_patches/31_room_ai_events.sql` in the SQL editor.

2. **Secrets** (Dashboard → Edge Functions → Secrets):

   - `OPENAI_API_KEY` — required for AI text.
   - `OPENAI_MODEL` — optional (default `gpt-4o-mini`; set to your preferred nano/small model when available).
   - `OPENAI_MAX_COMPLETION_TOKENS` — optional cap (default `220` for `process-ai-events`, `240` for cron default in code).
   - `CRON_SECRET` — long random string; use as `Authorization: Bearer …` for `cron-ai-daily`.
   - `AI_EVENTS_SEND_PUSH` — optional `true` to mirror AI lines into `notifications` (same pipeline as existing pushes).
   - `AI_LOG_FULL_IO` — optional `true` to log **full** system/user prompts and completion text in Edge logs (noisy; use when debugging).

**API note:** Newer models require `max_completion_tokens` (not `max_tokens`). Functions use `max_completion_tokens` only.

**Cost / usage:** Every successful call logs JSON lines `openai_request` and `openai_response` with `usage` (`prompt_tokens`, `completion_tokens`, `total_tokens`) and `cost_hint`. Multiply by your model’s **USD per 1M tokens** on [OpenAI pricing](https://openai.com/api/pricing/) (or your dashboard usage export).

3. **Deploy functions**

   ```bash
   cd jars-flutter
   npx supabase functions deploy process-ai-events --no-verify-jwt
   npx supabase functions deploy cron-ai-daily --no-verify-jwt
   ```

4. **Schedule** `cron-ai-daily` (e.g. Supabase Scheduled Functions or external cron) once per day near end of Chicago day for “last stand” feel, or your preferred time.

## Per-room toggles

Table `room_ai_config` (`room_id`, `event_key`, `enabled`, `settings`). If a row is missing, the event defaults to **enabled**. Keys match detector names: `heist`, `ghost_return`, `rivalry`, `uno_reverse`, `domination`, `room_milestone`, `silence_break`, `spam_surge`, `carry`, `near_tie`, `response_gap` (cron), etc.

## Flutter

`lib/services/ai_events_service.dart` invokes `process-ai-events` after each successful log. Failures are ignored so logging never breaks.
