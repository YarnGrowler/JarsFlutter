#!/usr/bin/env bash
# Runs on Vercel (Linux). Installs Flutter stable, then builds web.
# Match flutter/scripts/vercel_build.sh. Set SUPABASE_* in Vercel env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

export FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter_vercel}"
export PATH="$FLUTTER_ROOT/bin:$PATH"

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  echo ">>> Cloning Flutter (stable, shallow) into $FLUTTER_ROOT ..."
  rm -rf "$FLUTTER_ROOT"
  mkdir -p "$(dirname "$FLUTTER_ROOT")"
  git clone https://github.com/flutter/flutter.git "$FLUTTER_ROOT" --branch stable --depth 1
fi

echo ">>> flutter --version"
flutter --version

echo ">>> flutter config (web, no analytics)"
flutter config --no-analytics
flutter config --enable-web

# Project must include web/ (index.html). If missing, generate platform files.
if [[ ! -f web/index.html ]]; then
  echo ">>> web/ missing — flutter create . --platforms web"
  flutter create . --platforms web
fi

echo ">>> flutter pub get"
flutter pub get

DEFINES=()
if [[ -n "${SUPABASE_URL:-}" ]]; then
  DEFINES+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
fi
if [[ -n "${SUPABASE_ANON_KEY:-}" ]]; then
  DEFINES+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi
if [[ -n "${WEB_PUSH_VAPID_PUBLIC_KEY:-}" ]]; then
  DEFINES+=(--dart-define=WEB_PUSH_VAPID_PUBLIC_KEY="$WEB_PUSH_VAPID_PUBLIC_KEY")
fi

# --no-web-resources-cdn: ship CanvasKit from this origin so Vercel Cache-Control
#   applies on repeat opens (iOS “Add to Home Screen” uses a separate cache profile).
# --pwa-strategy=none: avoid aggressive default Flutter SW body; rely on HTTP cache
#   + your firebase-messaging-sw.js / jars-web-push flows.
echo ">>> flutter build web --release (self-hosted web assets, minimal PWA SW)"
flutter build web --release --no-web-resources-cdn --pwa-strategy=none "${DEFINES[@]}"

echo ">>> build/web ready"
ls -la build/web | head -20
