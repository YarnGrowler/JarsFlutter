# Jars — Earn Your Rank

Jars is a **competitive workout tracker** for groups: members join **rooms** (invite codes), log exercises with a points system, climb **ranks** (32 levels), and compete on **leaderboards** with streaks, daily goals, and a real-time **activity feed** (including special broadcast events like overtakes and PRs).

**Stack:** Flutter (Dart), **Supabase** (Postgres, Auth, Realtime), **Firebase Cloud Messaging** on native apps, **Web Push** on browsers/PWA. State: **Riverpod**. Navigation: **GoRouter**.

---

## Quick start

### 1. Supabase project

1. Create a project at [supabase.com](https://supabase.com).
2. In **SQL Editor**, run `supabase_schema.sql` (see repo root). If you already have schema, apply incremental scripts from `supabase_patches/` as documented there.
3. **Authentication → Providers:** enable **Email**; for frictionless dev you can disable “Confirm email”.
4. **Settings → API:** copy **Project URL** and **anon key**.

### 2. Environment

Config is read from a **`.env`** file in this folder (via `flutter_dotenv`, listed under `flutter.assets` in `pubspec.yaml`).

1. Copy `env.example` to `.env`.
2. Set:

   ```env
   SUPABASE_URL=https://your-project-id.supabase.co
   SUPABASE_ANON_KEY=eyJ...your-anon-key
   ```

3. Run `flutter pub get`, then do a **full restart** after changing `.env` (hot reload does not reload asset bundles).

**Alternative:** pass secrets at compile time:

```bash
flutter run --dart-define-from-file=.env
```

If both file and `--dart-define` are present, **defines override** the file.

### 3. Firebase (push notifications, native & web)

Push delivery uses FCM (Android/iOS/web) with tokens stored in Supabase. Configure Firebase for your app targets and align with `lib/bootstrap/jars_firebase_options.dart` / your deployment docs. Web deployments need the service worker and VAPID setup used by your Edge pipeline.

### 4. Run the app

```bash
cd jars-flutter
flutter pub get
flutter run -d chrome
# or: flutter run -d <device-id>
```

---

## Repository layout

| Path | Purpose |
|------|---------|
| `lib/main.dart` | Entry: Supabase init, Firebase where applicable |
| `lib/app.dart` | `MaterialApp`, theme |
| `lib/router.dart` | **GoRouter**: auth gate, shell with main tabs |
| `lib/core/` | Theme, timezone (Chicago day boundaries), exercise catalog, level data, notification catalog reference |
| `lib/models/` | Data classes (`Exercise`, `ExerciseLog`, `Room`, `Score`, …) |
| `lib/services/` | Thin Supabase wrappers: auth, rooms, logs, scores, goals, reactions, notifications, events |
| `lib/providers/` | Riverpod providers (active room, feed, scores, …) |
| `lib/screens/` | Full screens: room hub, log flow, ranks, profile, auth |
| `lib/widgets/` | Reusable UI (feed cards, log controls, rank UI) |
| `supabase_schema.sql` | Baseline DB schema for a fresh project |
| `supabase_patches/` | Incremental SQL (RLS, idle wake, exercise columns, …) |
| `supabase/` | Local Supabase CLI config when using `supabase` CLI |
| `tool/` | e.g. `generate_system_exercises_sync_sql.mjs` — regenerates SQL to sync `public.exercises` system rows from `lib/core/exercise_data.dart` |

---

## Product overview

- **Auth:** Email/password (username-centric flows in UI).
- **Rooms:** Create/join by code; optional join password; room admin actions (members, goals, custom exercises).
- **Exercises:** Large built-in catalog in `exercise_data.dart` (reps, time-based, weighted); per-room **custom** exercises; points and metadata stored per room in `exercises`.
- **Logging:** Per-exercise count/time, optional weight bonuses; undo; idle **wake** cards driven by server logic.
- **Scores & streaks:** Total score, daily points, streaks with room-configurable minimum; rank from total points.
- **Feed:** Real-time `exercise_logs`; reactions; synthetic **broadcast** rows (prefixes like overtakes, PRs) from `EventService`.
- **Ranks screen:** Leaderboard (Today / Week / Month / All Time) + personal breakdown; member profile sheets; **all exercises** stats sheet.
- **Goals:** Group goals per room.
- **Notifications:** In-app triggers insert rows into `notifications`; infrastructure delivers FCM/Web Push. See **[docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md)** for a full list of kinds, triggers, and delivery.

---

## Syncing exercise catalog to the database

When you change `lib/core/exercise_data.dart`, system rows in Postgres should stay aligned:

```bash
node tool/generate_system_exercises_sync_sql.mjs > supabase_patches/30_sync_system_exercises_from_exercise_data.sql
npx supabase db query --linked -f supabase_patches/30_sync_system_exercises_from_exercise_data.sql
```

(Adjust filename/numbering as you prefer; requires Supabase CLI linked to the project.)

---

## Testing

```bash
flutter test
```

---

## License / publishing

`publish_to: 'none'` in `pubspec.yaml` — private app; adjust for your distribution model.
