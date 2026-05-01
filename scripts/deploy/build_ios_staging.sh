#!/usr/bin/env bash
# Build staging iOS app without codesigning for QA or CI validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/dev/flutterw}"
source "$ROOT_DIR/scripts/lib/_backend_env.sh"

echo "══════════════════════════════════════════════════════"
echo "  Building STAGING iOS app"
echo "══════════════════════════════════════════════════════"

load_client_env_files "$ROOT_DIR" \
  SUPABASE_URL \
  SUPABASE_ANON_KEY \
  SUPABASE_STAGING_URL \
  SUPABASE_STAGING_ANON_KEY \
  SUPABASE_PRODUCTION_URL \
  SUPABASE_PRODUCTION_ANON_KEY \
  COOL_DEEP_LINK_HOST \
  FIREBASE_IOS_STAGING_API_KEY \
  FIREBASE_IOS_STAGING_APP_ID \
  FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID \
  FIREBASE_IOS_STAGING_PROJECT_ID \
  FIREBASE_IOS_STAGING_STORAGE_BUCKET \
  FIREBASE_IOS_STAGING_BUNDLE_ID
resolve_supabase_client_env staging
require_resolved_supabase_client_env staging

native_firebase_config="$ROOT_DIR/ios/Runner/GoogleService-Info-staging.plist"
if [[ ! -f "$native_firebase_config" ]]; then
  echo "CRITICAL BLOCKER — Missing Firebase iOS config at $native_firebase_config." >&2
  exit 1
fi

if [[ -z "${FIREBASE_IOS_STAGING_API_KEY:-}" ]]; then
  echo "⚠️  FIREBASE_IOS_STAGING_* overrides not set; Firebase will use $native_firebase_config." >&2
fi

"$FLUTTER_BIN" build ios \
  --debug \
  --flavor staging \
  --no-codesign \
  --dart-define=FLAVOR=staging \
  --dart-define=SUPABASE_URL="${RESOLVED_SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${RESOLVED_SUPABASE_ANON_KEY}" \
  --dart-define=SUPABASE_PROJECT_REF="${RESOLVED_SUPABASE_PROJECT_REF}" \
  --dart-define=BACKEND_ENVIRONMENT="${RESOLVED_BACKEND_ENVIRONMENT}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}" \
  --dart-define=FIREBASE_IOS_STAGING_API_KEY="${FIREBASE_IOS_STAGING_API_KEY}" \
  --dart-define=FIREBASE_IOS_STAGING_APP_ID="${FIREBASE_IOS_STAGING_APP_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID="${FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_PROJECT_ID="${FIREBASE_IOS_STAGING_PROJECT_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_STORAGE_BUCKET="${FIREBASE_IOS_STAGING_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_IOS_STAGING_BUNDLE_ID="${FIREBASE_IOS_STAGING_BUNDLE_ID}"

echo ""
echo "✅ Staging iOS build: build/ios/iphoneos/Runner.app"
