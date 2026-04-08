# AI narrative events

## What it does

After each **real** workout log, the app calls the Edge Function `process-ai-events` with `{ log_id }`. The function:

1. Runs cheap detectors (heist, ghost return, rivalry, uno reverse, domination, room milestone, silence break, spam surge, carry, near tie, …).
2. Batches all fired events into **one** OpenAI call.
3. Inserts a feed row: `exercise_name = '__AI__|' || json` (see `ExerciseLog.kAiPrefix`).

Optional push to all room members: set Edge secret `AI_EVENTS_SEND_PUSH=true` (off by default).

Daily cron function `cron-ai-daily` (Bearer `CRON_SECRET`): last stand batch, response gap, random retirement / carry lore.

## Supabase setup

1. **SQL:** run `supabase_patches/31_room_ai_events.sql` in the SQL editor. For **per-call token logging** (dashboard cost rollups), also run `supabase_patches/35_ai_openai_usage_log.sql` (table `ai_openai_usage_log`). Inserts are best-effort if the table is missing.

2. **Secrets** (Dashboard → Edge Functions → Secrets):

   - `OPENAI_API_KEY` — required for AI text.
   - `OPENAI_MODEL` — optional (default `gpt-4o-mini`; set to your preferred nano/small model when available).
   - `OPENAI_MAX_COMPLETION_TOKENS` — optional cap for **both** Edge functions (defaults: `220` in `process-ai-events`, `240` in `cron-ai-daily` when unset). Only `max_completion_tokens` is sent to OpenAI.
   - `CRON_SECRET` — long random string; use as `Authorization: Bearer …` for `cron-ai-daily`.
   - `AI_EVENTS_SEND_PUSH` — optional `true` to mirror AI lines into `notifications` (same pipeline as existing pushes).
   - `AI_LOG_FULL_IO` — optional `true` to log **full** system/user prompts and completion text in Edge logs (noisy; use when debugging).
   - `AI_NARRATIVE_MAX_CHARS` — optional cap on the `recent_room_narrative` block sent to the model (default **14000**). Raises prompt size; increase only if your model budget allows.

**Model context:** `process-ai-events` builds a **compact narrative** from the latest **50** room logs (workouts + parsed broadcast lines + recent `__AI__` text), full **leaderboard with streaks and today-vs-minimum**, **rank before/after**, **Chicago time** of the trigger log, **room age**, and **spam_surge** session detail (exercises + points in the window). It is **not** 50 raw JSON rows — it is summarized sections so personas (Snitch, Historian, Conspiracy, etc.) can reference patterns without drowning in tokens.

**API note:** Newer models require `max_completion_tokens` (not `max_tokens`). Functions use `max_completion_tokens` only.

**Cost / usage:** Every successful call logs JSON lines `openai_request` and `openai_response` with `usage` (`prompt_tokens`, `completion_tokens`, `total_tokens`) and `cost_hint`. Multiply by your model’s **USD per 1M tokens** on [OpenAI pricing](https://openai.com/api/pricing/) (or your dashboard usage export).

3. **Deploy functions**

   ```bash
   cd jars-flutter
   npx supabase functions deploy process-ai-events --no-verify-jwt
   npx supabase functions deploy cron-ai-daily --no-verify-jwt
   ```

4. **Schedule** `cron-ai-daily` (e.g. Supabase Scheduled Functions or external cron) once per day near end of Chicago day for “last stand” feel, or your preferred time.

**Important:** Nothing runs until this schedule exists. If you have not configured a daily trigger in the Supabase dashboard (or an external cron hitting the function with `Authorization: Bearer CRON_SECRET`), the cron **never** fires—there is no built-in “every hour” or automatic midnight job.

**Streak reminders:** `cron-ai-daily` handles AI narrative batches (last stand, response gap, retirement/carry lore). It does **not** notify users that a streak is about to expire. That would be a separate feature; see `docs/NOTIFICATIONS.md` (“Streak minimum at risk” — not implemented as push).

## Per-room toggles

Table `room_ai_config` (`room_id`, `event_key`, `enabled`, `settings`). If a row is missing, the event defaults to **enabled**. Keys match detector names: `heist`, `ghost_return`, `rivalry`, `uno_reverse`, `domination`, `room_milestone`, `silence_break`, `spam_surge`, `carry`, `near_tie`, `response_gap` (cron), etc.

## Flutter

`lib/services/ai_events_service.dart` invokes `process-ai-events` after each successful log. Failures are ignored so logging never breaks.
