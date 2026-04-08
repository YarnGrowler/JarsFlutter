# Jars — Notifications & events

This document describes **what notifications exist**, **what triggers them**, and how they relate to **feed events**. Code references are under `lib/` unless noted.

---

## Delivery pipeline (high level)

1. **Flutter** calls `NotificationService.sendNotification` / `notifyRoomMembersExcept` / `notifyRoomMembersExceptIds`, which **insert rows** into Supabase `public.notifications` (target `user_id` + `body` text).
2. Your **backend** (typically a Supabase **Database Webhook** and/or **Edge Function**) picks up those rows and sends:
   - **Native:** Firebase **FCM** using tokens in `user_fcm_tokens` (and legacy `profiles.fcm_token` where used).
   - **Web / PWA:** **Web Push** (VAPID) via `user_web_push_subscriptions` and your Edge `web-push` handler.

Exact Edge/webhook configuration lives outside this repo; the app assumes inserts to `notifications` result in a push when the user has registered a device.

**In-app catalog enum:** `lib/core/notifications_catalog.dart` (`JarsNotificationKind`, `kJarsNotificationInventory`) — keep aligned when adding kinds.

---

## A. Server-driven (Postgres / RPC)

### Idle wake — room members (`idleWakeRoom`)

- **Trigger:** A synthetic feed row is inserted into `exercise_logs` whose `exercise_name` starts with `__WAKE__|` (idle card). SQL triggers / functions (see `supabase_patches/`, e.g. wake/idle pipelines) notify the room.
- **Audience:** Other members in the room (not the absent user), per your `notify_room_on_wake_card`-style logic.
- **Notes:** Patches exist to avoid spurious wakes (never-logged users, regex, activity grace). Feed throttling is documented in patch comments.

### Wake nudge — absent user only (`wakeNudgeToAbsent`)

- **Trigger:** Client calls RPC `send_wake_nudge` via `LogService.sendWakeNudge` → `WakeNudgeService.nudgeAbsentMember`.
- **Audience:** The user the wake card is **about** (the “absent” member).
- **Rules:** Max **2** nudges per tapper per wake card (enforced in SQL); you cannot nudge yourself.

---

## B. Client `EventService` (after a real exercise log)

`EventService.checkAndBroadcast` runs **after** `ScoreService.addPoints` from the log flow (`log_sheet.dart`). It evaluates several conditions in parallel and may:

- insert **broadcast** rows into `exercise_logs` (special `exercise_name` prefixes — see `ExerciseLog` / `EventService`), and  
- enqueue **push** via `NotificationService`.

| Kind (catalog) | Trigger | Feed broadcast | Push |
|----------------|---------|----------------|------|
| **Overtake** (`overtakeVictim` / `overtakeSpectators`) | After this log, your **total** crosses someone who was strictly ahead of you before | Overtake line for the room | **Victim:** DM — “X just passed you…” **Others:** room minus logger + victim — “X overtook Y…” |
| **Personal record** (`personalRecordRoom`) | Same `exerciseName`, non-broadcast history exists; this log’s **count** beats previous best for that name | PR line | Everyone in room **except** logger |
| **First log of day** (`firstLogOfDayRoom`) | First **non-broadcast** log for you today (**Chicago** calendar day) | First-log line with time | Room except you |
| **Streak milestone** (`streakMilestoneRoom`) | Streak crosses **3, 7, 14, 30, 60, or 100** days | Streak line | Room except you |
| **Dead streak** (`deadStreakRoom`) | Streak **dropped** from ≥3 to **1** (broken streak) | Dead streak line | Room except you |
| **Close gap** (`closeGapRoom`) | Someone **ahead** of you exists; gap ≤ **50** pts | **Targeted** broadcast row visible to the person ahead (`kCloseGapPrefix`) | **Only** the person ahead — “Watch out — someone is only N pts behind you.” |

**Timezone:** “Day” boundaries for first-log-of-day use `JarsTimezone` / Chicago.

---

## C. Other Flutter-triggered pushes (not all in `notifications_catalog` enum)

These also insert into `notifications` the same way; consider extending the catalog if you want one enum per kind.

### Rank up

- **Trigger:** After logging, total points cross the next **level** threshold (`getLevelForScore`).
- **Code:** `log_sheet.dart` — `LogService.insertRankUpBroadcast` for feed, then `NotificationService.notifyRoomMembersExcept` so **others** get “X leveled up to {title}!”

### Room member joined

- **Trigger:** `EventService.roomMemberJoined` (after join succeeds).
- **Push:** Room members **except** the joiner — “{username} joined {roomName}”.

### Room member kicked

- **Trigger:** `EventService.roomMemberKicked`.
- **Push:** Remaining members (excluding removed user) + **direct** message to removed user — “You were removed from {roomName}.”

### Reaction on your log

- **Trigger:** `ReactionService.addReaction` when someone adds an emoji to **your** log (not on your own reaction toggle to self).
- **Push:** Log owner — “{username} reacted {emoji} on your log.”

---

## D. Streak at-risk cron (before midnight Chicago)

**Goal:** Push the user (not the room) if they still need points to hit the room’s `streak_minimum` today and they have an active streak to lose.

1. **SQL:** Run `supabase_patches/34_streak_nudge.sql` in the Supabase SQL editor (creates `streak_nudge_log` + `cron_streak_nudge_execute`).
2. **Deploy function:** From the repo root:

   ```bash
   npx supabase functions deploy cron-streak-nudge --no-verify-jwt
   ```

3. **Secrets:** Reuse `CRON_SECRET` (same Bearer as `cron-ai-daily`). `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided in hosted projects.
4. **Schedule:** In Supabase **Scheduled Functions** (or any cron), `POST` your project URL every 30–60 minutes during the evening window, for example:

   `https://<PROJECT_REF>.supabase.co/functions/v1/cron-streak-nudge`  
   Header: `Authorization: Bearer <CRON_SECRET>`

   The function only inserts rows when **America/Chicago** hour is between **18 and 23** (6 PM–11 PM) by default, so runs near midnight but not after the day rolls. Override with `STREAK_NUDGE_CHICAGO_START_HOUR` / `STREAK_NUDGE_CHICAGO_END_HOUR`. Set `STREAK_NUDGE_SKIP_HOUR_CHECK=true` only for manual testing.

5. **Behavior:** `cron_streak_nudge_execute` selects users where `streak_current >= STREAK_NUDGE_MIN_STREAK` (default **2**), today’s effective `daily_points` is still below `rooms.streak_minimum`, and `streak_last_workout` is not already **today** (Chicago). One notification per user per room per Chicago day (`streak_nudge_log` dedupes). Rows go to `notifications` → your existing DB webhook → `push` Edge → FCM / Web Push.

---

## E. Planned / not fully wired (catalog)

From `kJarsNotificationInventory`:

| Kind | Status | Notes |
|------|--------|--------|
| **Same time yesterday reminder** | Not implemented | Would need stored first-log time + scheduler. |

---

## F. Foreground & web behavior

- **Native:** OS handles background pushes; foreground behavior depends on platform and FCM setup.
- **Web:** When the tab is focused, FCM may not show a system banner; `foreground_push_display_web.dart` can show a **browser** `Notification` for visibility (see comments in that file).
- **Permissions:** `NotificationSettingsScreen`, `NotificationService.registerToken`, web DOM permission helpers — users must grant permission for tokens to register.

---

## G. Testing the pipeline

- **Profile → Test push notification** (`profile_screen.dart`): inserts a test row / triggers your webhook path so you can verify FCM/Web Push end-to-end.

---

## H. Related files (quick index)

| Area | Files |
|------|--------|
| Insert notifications | `lib/services/notification_service.dart` |
| Event matrix | `lib/services/event_service.dart` |
| Catalog | `lib/core/notifications_catalog.dart` |
| Log pipeline | `lib/screens/log/log_sheet.dart` |
| Reactions | `lib/services/reaction_service.dart` |
| Wake nudge UI path | `lib/services/wake_nudge_service.dart`, `lib/services/log_service.dart` |
| Comments / inventory | Top of `notification_service.dart` |

SQL behavior for idle wake, nudge limits, and RLS is under `supabase_patches/` and `supabase_schema.sql`.
