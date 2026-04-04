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

# ── CRITICAL BLOCKER: Supabase env vars are mandatory for ANY build ──
: "${SUPABASE_URL:?CRITICAL BLOCKER — Set SUPABASE_URL before building ANY APK, AAB, or IPA. The app will crash or show a config error screen without it.}"
: "${SUPABASE_ANON_KEY:?CRITICAL BLOCKER — Set SUPABASE_ANON_KEY before building ANY APK, AAB, or IPA. The app will crash or show a config error screen without it.}"

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
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}" \
  --dart-define=FIREBASE_IOS_STAGING_API_KEY="${FIREBASE_IOS_STAGING_API_KEY}" \
  --dart-define=FIREBASE_IOS_STAGING_APP_ID="${FIREBASE_IOS_STAGING_APP_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID="${FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_PROJECT_ID="${FIREBASE_IOS_STAGING_PROJECT_ID}" \
  --dart-define=FIREBASE_IOS_STAGING_STORAGE_BUCKET="${FIREBASE_IOS_STAGING_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_IOS_STAGING_BUNDLE_ID="${FIREBASE_IOS_STAGING_BUNDLE_ID}"

echo ""
echo "✅ Staging iOS build: build/ios/iphoneos/Runner.app"
