#!/usr/bin/env bash
# Build production iOS app without codesigning for release validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"

require_build_env() {
  # ── CRITICAL BLOCKER: Supabase env vars are mandatory for ANY build ──
  : "${SUPABASE_URL:?CRITICAL BLOCKER — Set SUPABASE_URL before building ANY APK, AAB, or IPA. The app will crash or show a config error screen without it.}"
  : "${SUPABASE_ANON_KEY:?CRITICAL BLOCKER — Set SUPABASE_ANON_KEY before building ANY APK, AAB, or IPA. The app will crash or show a config error screen without it.}"
  : "${FIREBASE_IOS_PRODUCTION_API_KEY:?Set FIREBASE_IOS_PRODUCTION_API_KEY before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_APP_ID:?Set FIREBASE_IOS_PRODUCTION_APP_ID before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID:?Set FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_PROJECT_ID:?Set FIREBASE_IOS_PRODUCTION_PROJECT_ID before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET:?Set FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_BUNDLE_ID:?Set FIREBASE_IOS_PRODUCTION_BUNDLE_ID before building the production iOS app.}"
}

echo "══════════════════════════════════════════════════════"
echo "  Building PRODUCTION iOS app"
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
    COOL_DEEP_LINK_HOST \
    FIREBASE_IOS_PRODUCTION_API_KEY \
    FIREBASE_IOS_PRODUCTION_APP_ID \
    FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID \
    FIREBASE_IOS_PRODUCTION_PROJECT_ID \
    FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET \
    FIREBASE_IOS_PRODUCTION_BUNDLE_ID; do
    if [[ -z "${!json_key:-}" ]]; then
      json_value="$(jq -r --arg key "$json_key" '.[$key] // empty' .env.json)"
      if [[ -n "$json_value" ]]; then
        export "$json_key=$json_value"
      fi
    fi
  done
fi

require_build_env

"$FLUTTER_BIN" build ios \
  --release \
  --flavor production \
  --no-codesign \
  --dart-define=FLAVOR=production \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_API_KEY="${FIREBASE_IOS_PRODUCTION_API_KEY}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_APP_ID="${FIREBASE_IOS_PRODUCTION_APP_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID="${FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_PROJECT_ID="${FIREBASE_IOS_PRODUCTION_PROJECT_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET="${FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_BUNDLE_ID="${FIREBASE_IOS_PRODUCTION_BUNDLE_ID}"

echo ""
echo "✅ Production iOS build: build/ios/iphoneos/Cool.app"
