#!/usr/bin/env bash
# Build staging APK (debug mode for QA testing)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"

echo "══════════════════════════════════════════════════════"
echo "  Building STAGING APK"
echo "══════════════════════════════════════════════════════"

staging_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-staging-debug.apk"
rm -f "$staging_apk"

# Source env vars from .env if available
if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

"$FLUTTER_BIN" build apk \
  --debug \
  --flavor staging \
  --dart-define=FLAVOR=staging \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  --dart-define=GOOGLE_MAPS_ANDROID_MAP_ID="${GOOGLE_MAPS_ANDROID_MAP_ID:-}" \
  --dart-define=GOOGLE_MAPS_IOS_MAP_ID="${GOOGLE_MAPS_IOS_MAP_ID:-}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}"

if [[ ! -f "$staging_apk" ]]; then
  echo "Staging APK was not generated: $staging_apk" >&2
  exit 1
fi

echo ""
echo "✅ Staging APK: $staging_apk"
