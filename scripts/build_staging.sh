#!/usr/bin/env bash
# Build staging APK (debug mode for QA testing)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"
readonly LOCAL_BUILD_ROOT="${COOL_LOCAL_BUILD_ROOT:-/tmp/cool-build}"

echo "══════════════════════════════════════════════════════"
echo "  Building STAGING APK"
echo "══════════════════════════════════════════════════════"

staging_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-staging-debug.apk"
rm -f "$staging_apk"

# External volumes without POSIX permissions can break Gradle's asset copy step.
mkdir -p "$LOCAL_BUILD_ROOT"
if [[ ! -L "$ROOT_DIR/build" || "$(readlink "$ROOT_DIR/build" 2>/dev/null || true)" != "$LOCAL_BUILD_ROOT" ]]; then
  rm -rf "$ROOT_DIR/build"
  ln -sfn "$LOCAL_BUILD_ROOT" "$ROOT_DIR/build"
fi

# Source env vars from .env if available
if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

# Stale daemons from earlier builds can keep the workspace locked or starve memory.
if [[ -x "$ROOT_DIR/android/gradlew" ]]; then
  "$ROOT_DIR/android/gradlew" --stop >/dev/null 2>&1 || true
fi

"$FLUTTER_BIN" build apk \
  --debug \
  --flavor staging \
  --dart-define=FLAVOR=staging \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  --dart-define=GOOGLE_MAPS_ANDROID_API_KEY="${GOOGLE_MAPS_ANDROID_API_KEY:-}" \
  --dart-define=GOOGLE_MAPS_IOS_API_KEY="${GOOGLE_MAPS_IOS_API_KEY:-}" \
  --dart-define=GOOGLE_MAPS_ANDROID_MAP_ID="${GOOGLE_MAPS_ANDROID_MAP_ID:-}" \
  --dart-define=GOOGLE_MAPS_IOS_MAP_ID="${GOOGLE_MAPS_IOS_MAP_ID:-}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}"

if [[ ! -f "$staging_apk" ]]; then
  echo "Staging APK was not generated: $staging_apk" >&2
  exit 1
fi

echo ""
echo "✅ Staging APK: $staging_apk"
