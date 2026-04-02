#!/usr/bin/env bash
# Vercel build: install Flutter stable, then `flutter build web`.
# Set SUPABASE_URL and SUPABASE_ANON_KEY in Vercel → Project → Environment Variables.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export PATH="${PATH}:${HOME}/flutter/bin"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter stable..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${HOME}/flutter"
fi

flutter config --no-analytics --enable-web
flutter precache --web
flutter pub get

DEFINES=()
if [[ -n "${SUPABASE_URL:-}" ]]; then
  DEFINES+=(--dart-define="SUPABASE_URL=${SUPABASE_URL}")
fi
if [[ -n "${SUPABASE_ANON_KEY:-}" ]]; then
  DEFINES+=(--dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}")
fi

flutter build web --release "${DEFINES[@]}"
