#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

require_flag_enabled() {
  local name="$1"
  if [[ "${!name:-0}" != "1" ]]; then
    echo "Release-candidate pass requires $name=1." >&2
    exit 1
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_any_env() {
  local label="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ -n "${!candidate:-}" ]]; then
      return 0
    fi
  done

  echo "Release-candidate pass requires one of: $label" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Release-candidate pass requires $name to be set." >&2
    exit 1
  fi
}

require_command bash
require_command deno
require_command python3

require_flag_enabled RUN_ANDROID_MINIFY_CANARY
require_flag_enabled RUN_REMOTE_SMOKE
require_flag_enabled RUN_MOMO_SMS_ROLLOUT_VERIFY
require_any_env "PROJECT_REF or SUPABASE_PROJECT_REF" PROJECT_REF SUPABASE_PROJECT_REF
require_env SUPABASE_ACCESS_TOKEN
require_any_env "SUPABASE_DB_URL or DATABASE_URL" SUPABASE_DB_URL DATABASE_URL
require_any_env "FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT" FIREBASE_SERVICE_ACCOUNT_JSON FIREBASE_SERVICE_ACCOUNT
require_env COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT

export PROJECT_REF="${PROJECT_REF:-${SUPABASE_PROJECT_REF:-}}"
export COOL_SKIP_STAGING_BACKEND_VALIDATION="${COOL_SKIP_STAGING_BACKEND_VALIDATION:-1}"

if [[ ! -f "$ROOT_DIR/android/key.properties" ]]; then
  echo "Release-candidate pass requires android/key.properties for signed Android artifact builds." >&2
  exit 1
fi

echo "==> release metadata verification"
bash "$ROOT_DIR/scripts/qa/verify_release_metadata.sh"

echo "==> Firebase App Check provider verification"
deno run \
  --allow-env=FIREBASE_SERVICE_ACCOUNT_JSON,FIREBASE_SERVICE_ACCOUNT,FIREBASE_PROJECT_NUMBER,FIREBASE_ANDROID_PRODUCTION_APP_ID,FIREBASE_IOS_PRODUCTION_APP_ID,COOL_IOS_RELEASE_ENABLED \
  --allow-net=oauth2.googleapis.com,firebaseappcheck.googleapis.com \
  --allow-read=android/app/src/production/google-services.json,ios/Runner/GoogleService-Info.plist \
  "$ROOT_DIR/scripts/qa/verify_firebase_app_check.ts"

echo "==> release readiness"
bash "$ROOT_DIR/scripts/qa/release_readiness.sh"

echo "==> signed Android release APK"
bash "$ROOT_DIR/scripts/deploy/build_production.sh"

echo "==> signed Android release AAB"
bash "$ROOT_DIR/scripts/deploy/build_play_release.sh"

if [[ "${COOL_IOS_RELEASE_ENABLED:-0}" == "1" ]]; then
  echo "CRITICAL BLOCKER — iOS store release automation is not enabled in this repo yet." >&2
  echo "Either de-scope iOS for this launch or add a signed TestFlight/App Store lane before enabling COOL_IOS_RELEASE_ENABLED=1." >&2
  exit 1
fi

echo "==> iOS store release automation explicitly de-scoped for this pass"
echo "==> release-candidate pass completed"
