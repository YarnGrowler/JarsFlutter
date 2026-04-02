# Jars - Earn Your Rank

A competitive workout tracker built with Flutter and Supabase.

## Setup

### 1. Supabase Project

1. Create a new project at [supabase.com](https://supabase.com)
2. Go to **SQL Editor** and paste the contents of `supabase_schema.sql` — run it
3. Go to **Authentication > Providers**, ensure **Email** provider is enabled with "Confirm email" **disabled** (for instant signup)
4. Go to **Settings > API**, copy the **Project URL** and **anon key**

### 2. Environment

Supabase settings are read from a **`.env`** file in `jars-flutter/` (loaded at runtime via `flutter_dotenv`, listed as an asset in `pubspec.yaml`).

1. Copy the template: `cp env.example .env` (or create `.env` manually).
2. Fill in real values from Supabase **Settings → API**:

```
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=eyJ...your-anon-key
```

3. Run **`flutter pub get`** (and a **full restart** after changing `.env` so assets rebundle). Hot reload alone does not refresh env assets.

**Alternative (no bundled `.env`):** pass compile-time defines:

```bash
flutter run --dart-define-from-file=.env
```

If both are set, **`--dart-define` values win** over the file.

### 3. Run

```bash
cd jars-flutter
flutter pub get
flutter run -d chrome
# or: flutter run -d emulator-5554
```

## Architecture

```
lib/
  main.dart           — Supabase init, app entry
  app.dart            — MaterialApp with dark theme
  router.dart         — GoRouter with 4-tab navigation
  core/               — Theme, constants, exercise/level data
  models/             — Dart data classes with fromJson/toJson
  services/           — Static Supabase query wrappers
  providers/          — Riverpod state providers
  screens/            — Full-page screen widgets
  widgets/            — Reusable UI components
```

## Features

- Email/password auth (username-based, synthetic email)
- Room creation and join by code
- 52 built-in exercises with points system
- Weight bonus calculation
- Streak tracking
- Real-time activity feed
- Leaderboard with 4 time periods
- Rank progression (32 levels)
- Reactions on feed items
- Group goals
- Custom exercises
- Admin room settings
