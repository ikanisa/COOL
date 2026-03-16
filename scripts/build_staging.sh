#!/usr/bin/env bash
# Build staging APK (debug mode for QA testing)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"
readonly LOCAL_BUILD_ROOT="${COOL_LOCAL_BUILD_ROOT:-/tmp/cool-build}"
# shellcheck source=scripts/_android_release_build.sh
source "$ROOT_DIR/scripts/_android_release_build.sh"

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

_load_release_env

: "${FIREBASE_ANDROID_STAGING_API_KEY:?Set FIREBASE_ANDROID_STAGING_API_KEY before building the staging APK.}"
: "${FIREBASE_ANDROID_STAGING_APP_ID:?Set FIREBASE_ANDROID_STAGING_APP_ID before building the staging APK.}"
: "${FIREBASE_ANDROID_STAGING_MESSAGING_SENDER_ID:?Set FIREBASE_ANDROID_STAGING_MESSAGING_SENDER_ID before building the staging APK.}"
: "${FIREBASE_ANDROID_STAGING_PROJECT_ID:?Set FIREBASE_ANDROID_STAGING_PROJECT_ID before building the staging APK.}"
: "${FIREBASE_ANDROID_STAGING_STORAGE_BUCKET:?Set FIREBASE_ANDROID_STAGING_STORAGE_BUCKET before building the staging APK.}"

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
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}" \
  --dart-define=FIREBASE_ANDROID_STAGING_API_KEY="${FIREBASE_ANDROID_STAGING_API_KEY}" \
  --dart-define=FIREBASE_ANDROID_STAGING_APP_ID="${FIREBASE_ANDROID_STAGING_APP_ID}" \
  --dart-define=FIREBASE_ANDROID_STAGING_MESSAGING_SENDER_ID="${FIREBASE_ANDROID_STAGING_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_ANDROID_STAGING_PROJECT_ID="${FIREBASE_ANDROID_STAGING_PROJECT_ID}" \
  --dart-define=FIREBASE_ANDROID_STAGING_STORAGE_BUCKET="${FIREBASE_ANDROID_STAGING_STORAGE_BUCKET}"

if [[ ! -f "$staging_apk" ]]; then
  echo "Staging APK was not generated: $staging_apk" >&2
  exit 1
fi

echo ""
echo "✅ Staging APK: $staging_apk"
