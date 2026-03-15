#!/usr/bin/env bash
# Build staging iOS app without codesigning for QA or CI validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"

echo "══════════════════════════════════════════════════════"
echo "  Building STAGING iOS app"
echo "══════════════════════════════════════════════════════"

if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

if [[ -f .env.json ]]; then
  for json_key in \
    SUPABASE_URL \
    SUPABASE_ANON_KEY \
    GOOGLE_MAPS_ANDROID_API_KEY \
    GOOGLE_MAPS_IOS_API_KEY \
    GOOGLE_MAPS_ANDROID_MAP_ID \
    GOOGLE_MAPS_IOS_MAP_ID \
    COOL_DEEP_LINK_HOST \
    FIREBASE_IOS_STAGING_API_KEY \
    FIREBASE_IOS_STAGING_APP_ID \
    FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID \
    FIREBASE_IOS_STAGING_PROJECT_ID \
    FIREBASE_IOS_STAGING_STORAGE_BUCKET \
    FIREBASE_IOS_STAGING_BUNDLE_ID; do
    if [[ -z "${!json_key:-}" ]]; then
      json_value="$(jq -r --arg key "$json_key" '.[$key] // empty' .env.json)"
      if [[ -n "$json_value" ]]; then
        export "$json_key=$json_value"
      fi
    fi
  done
fi

: "${FIREBASE_IOS_STAGING_API_KEY:?Set FIREBASE_IOS_STAGING_API_KEY before building the staging iOS app.}"
: "${FIREBASE_IOS_STAGING_APP_ID:?Set FIREBASE_IOS_STAGING_APP_ID before building the staging iOS app.}"
: "${FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID:?Set FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID before building the staging iOS app.}"
: "${FIREBASE_IOS_STAGING_PROJECT_ID:?Set FIREBASE_IOS_STAGING_PROJECT_ID before building the staging iOS app.}"
: "${FIREBASE_IOS_STAGING_STORAGE_BUCKET:?Set FIREBASE_IOS_STAGING_STORAGE_BUCKET before building the staging iOS app.}"
: "${FIREBASE_IOS_STAGING_BUNDLE_ID:?Set FIREBASE_IOS_STAGING_BUNDLE_ID before building the staging iOS app.}"

"$FLUTTER_BIN" build ios \
  --debug \
  --flavor staging \
  --no-codesign \
  --dart-define=FLAVOR=staging \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  --dart-define=GOOGLE_MAPS_ANDROID_API_KEY="${GOOGLE_MAPS_ANDROID_API_KEY:-}" \
  --dart-define=GOOGLE_MAPS_IOS_API_KEY="${GOOGLE_MAPS_IOS_API_KEY:-}" \
  --dart-define=GOOGLE_MAPS_ANDROID_MAP_ID="${GOOGLE_MAPS_ANDROID_MAP_ID:-}" \
  --dart-define=GOOGLE_MAPS_IOS_MAP_ID="${GOOGLE_MAPS_IOS_MAP_ID:-}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}" \
  --dart-define=FIREBASE_IOS_STAGING_API_KEY="${FIREBASE_IOS_STAGING_API_KEY}" \
  --dart-define=FIREBASE_IOS_STAGING_APP_ID="${FIREBASE_IOS_STAGING_APP_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID="${FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_PROJECT_ID="${FIREBASE_IOS_STAGING_PROJECT_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_STORAGE_BUCKET="${FIREBASE_IOS_STAGING_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_IOS_STAGING_BUNDLE_ID="${FIREBASE_IOS_STAGING_BUNDLE_ID}"

echo ""
echo "✅ Staging iOS build: build/ios/iphoneos/Runner.app"
