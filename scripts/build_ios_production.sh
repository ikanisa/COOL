#!/usr/bin/env bash
# Build production iOS app without codesigning for release validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"
source "$ROOT_DIR/scripts/_backend_env.sh"

require_build_env() {
  require_resolved_supabase_client_env production
  local native_firebase_config="$ROOT_DIR/ios/Runner/GoogleService-Info.plist"
  if [[ ! -f "$native_firebase_config" ]]; then
    echo "CRITICAL BLOCKER — Missing Firebase iOS config at $native_firebase_config." >&2
    return 1
  fi
}

echo "══════════════════════════════════════════════════════"
echo "  Building PRODUCTION iOS app"
echo "══════════════════════════════════════════════════════"

load_client_env_files "$ROOT_DIR" \
  SUPABASE_URL \
  SUPABASE_ANON_KEY \
  SUPABASE_STAGING_URL \
  SUPABASE_STAGING_ANON_KEY \
  SUPABASE_PRODUCTION_URL \
  SUPABASE_PRODUCTION_ANON_KEY \
  COOL_DEEP_LINK_HOST \
  FIREBASE_IOS_PRODUCTION_API_KEY \
  FIREBASE_IOS_PRODUCTION_APP_ID \
  FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID \
  FIREBASE_IOS_PRODUCTION_PROJECT_ID \
  FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET \
  FIREBASE_IOS_PRODUCTION_BUNDLE_ID
resolve_supabase_client_env production

require_build_env

if [[ -z "${FIREBASE_IOS_PRODUCTION_API_KEY:-}" ]]; then
  echo "⚠️  FIREBASE_IOS_PRODUCTION_* overrides not set; Firebase will use ios/Runner/GoogleService-Info.plist." >&2
fi

"$FLUTTER_BIN" build ios \
  --release \
  --flavor production \
  --no-codesign \
  --dart-define=FLAVOR=production \
  --dart-define=SUPABASE_URL="${RESOLVED_SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${RESOLVED_SUPABASE_ANON_KEY}" \
  --dart-define=SUPABASE_PROJECT_REF="${RESOLVED_SUPABASE_PROJECT_REF}" \
  --dart-define=BACKEND_ENVIRONMENT="${RESOLVED_BACKEND_ENVIRONMENT}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_API_KEY="${FIREBASE_IOS_PRODUCTION_API_KEY}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_APP_ID="${FIREBASE_IOS_PRODUCTION_APP_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID="${FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_PROJECT_ID="${FIREBASE_IOS_PRODUCTION_PROJECT_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET="${FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_BUNDLE_ID="${FIREBASE_IOS_PRODUCTION_BUNDLE_ID}"

echo ""
echo "✅ Production iOS build: build/ios/iphoneos/Cool.app"
