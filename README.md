# Jars — Earn Your Rank

**A group fitness app with a scoreboard.** You and your crew share a **room**, log real workouts (reps, time, weight), and earn points that stack into a live leaderboard. It turns "we should work out more" into something visible, competitive, and a little unhinged.

Solo fitness apps feel empty by week two. Group chats devolve into memes. Jars gives a crew one place where effort is **counted, ranked, and celebrated** — or roasted.

> **Stack:** Flutter · Supabase (Postgres, Auth, Realtime, Edge Functions) · Riverpod · GoRouter · FCM + Web Push
> **Scale:** ~157 Dart files · 24 services · 16 providers · 5 Deno edge functions · 40 SQL migrations

---

## What it does

| | |
|---|---|
| **Rooms** | Create or join by invite code (optional password). Admin tools for members, goals, and custom exercises. |
| **Logging** | A hold-to-log flow over a large built-in exercise catalog — rep-based, time-based, and weighted lifts, with bonuses, undo, and idle "wake" prompts. |
| **Ranks** | 32 levels driven by total points, with a full-screen rank-up ceremony and a shareable story card. |
| **Leaderboards** | Today / Week / Month / All-Time, plus a personal breakdown, per-member profile sheets, and room analytics. |
| **Streaks** | Room-configurable daily minimums, tracked per member. |
| **Feed** | Real-time workout logs with reactions — plus synthetic broadcast moments: overtakes, PRs, comebacks, broken silences. The room has memory. |
| **Achievements** | A server-side catalog processed on write, with unlock toasts and per-room read state. |
| **AI events** | An OpenAI-backed edge function that narrates room drama in distinct personas — cold, disappointed, unhinged. |
| **Notifications** | In-app triggers write to `notifications`; edge workers fan out to FCM (native) and Web Push (browser/PWA). |

The product rationale lives in **[docs/WHY_JARS.md](docs/WHY_JARS.md)**.

---

## Architecture

```
Flutter (Riverpod + GoRouter)
    │  thin service wrappers, one per domain
    ▼
Supabase ── Postgres (RLS on every table)
            Auth (email/password)
            Realtime  → live feed + leaderboard
            Edge Functions (Deno)
                ├── process-ai-events      OpenAI room narration
                ├── process-achievements   unlock evaluation
                ├── cron-ai-daily          scheduled drama
                ├── cron-streak-nudge      idle wake nudges
                └── push                   FCM + Web Push (VAPID) fan-out
```

**Notable engineering:**

- **Chicago-anchored day boundaries** (`lib/core/`) so "today" means the same thing for every member regardless of device timezone.
- **Server-authored feed events.** Overtakes and PRs aren't client guesses — `EventService` writes synthetic broadcast rows, so every member sees an identical story.
- **One exercise catalog, two homes.** `lib/core/exercise_data.dart` is the source of truth; `tool/generate_system_exercises_sync_sql.mjs` regenerates the SQL that syncs system rows into Postgres, so client and DB can't drift.
- **Layered config resolution** — `--dart-define` → `.env` → baked public defaults — so the app runs for a contributor with zero setup, while CI and production can point elsewhere.

---

## Quick start

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. In the **SQL Editor**, run `supabase_schema.sql`. For an existing database, apply the incremental scripts in `supabase_patches/` in numeric order.
3. **Authentication → Providers:** enable **Email**. For frictionless local dev, disable *Confirm email*.
4. **Settings → API:** copy the **Project URL** and **anon key**.

> The anon key is a public client credential — it is designed to ship in the app, and **every table is protected by RLS**. Never put a `service_role` key in this repo.

### 2. Configure

Config resolves in this order — **the first hit wins**:

1. `--dart-define` (recommended for CI and production)
2. `.env` in the project root, loaded via `flutter_dotenv`
3. Baked public defaults in `lib/bootstrap/supabase_public_config.dart`

```bash
cp env.example .env
```

```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=eyJ...your-anon-key
```

`.env` is **gitignored and is not bundled as a Flutter asset** — only `env.example` ships. Changing `.env` requires a full restart (hot reload does not re-read it).

Or skip the file entirely:

```bash
flutter run --dart-define-from-file=.env
```

### 3. Firebase (push)

Push uses FCM on Android/iOS/web, with device tokens stored in Supabase. Configure your Firebase targets to match `lib/bootstrap/jars_firebase_options.dart`. Web additionally needs the service worker and the VAPID keys consumed by the `push` edge function.

> The Firebase web `apiKey` is a public project identifier, not a secret — but **restrict it** (HTTP referrer / app restrictions) in the Google Cloud console before shipping.

### 4. Run

```bash
flutter pub get
flutter run -d chrome        # or: flutter run -d <device-id>
```

---

## Repository layout

| Path | Purpose |
|------|---------|
| `lib/main.dart` | Boot: config resolution, Supabase + Firebase init |
| `lib/app.dart` | `MaterialApp`, theme wiring |
| `lib/router.dart` | GoRouter — auth gate, onboarding funnel, tab shell |
| `lib/core/` | Theme, timezone, exercise catalog, level/rank data, achievement catalog |
| `lib/models/` | Data classes (`Exercise`, `ExerciseLog`, `Room`, `Score`, …) |
| `lib/services/` | Thin Supabase wrappers, one per domain (24) |
| `lib/providers/` | Riverpod providers — active room, feed, scores, achievements (16) |
| `lib/screens/` | Onboarding, auth, log flow, ranks, room, profile |
| `lib/widgets/` | Reusable UI — feed cards, log controls, rank visuals |
| `supabase/functions/` | Deno edge functions (AI events, achievements, cron, push) |
| `supabase_schema.sql` | Baseline schema for a fresh project |
| `supabase_patches/` | 40 incremental migrations (RLS, achievements, AI, leagues) |
| `tool/` | Codegen — exercise catalog → SQL sync |
| `docs/` | Deep dives (see below) |

---

## Docs

- **[WHY_JARS.md](docs/WHY_JARS.md)** — what it is and why it exists
- **[NOTIFICATIONS.md](docs/NOTIFICATIONS.md)** — every notification kind, trigger, and delivery path
- **[ACHIEVEMENTS.md](docs/ACHIEVEMENTS.md)** — the achievement catalog and evaluation
- **[AI_EVENTS.md](docs/AI_EVENTS.md)** — how the AI narrator picks its moments and personas

---

## Syncing the exercise catalog

After editing `lib/core/exercise_data.dart`, regenerate the SQL so Postgres system rows stay aligned:

```bash
node tool/generate_system_exercises_sync_sql.mjs > supabase_patches/30_sync_system_exercises_from_exercise_data.sql
npx supabase db query --linked -f supabase_patches/30_sync_system_exercises_from_exercise_data.sql
```

Requires the Supabase CLI linked to your project.

---

## Testing

```bash
flutter test
```

---

## License

`publish_to: 'none'` — private app. Adjust for your distribution model.
