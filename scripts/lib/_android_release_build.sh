#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
readonly ROOT_DIR
source "$ROOT_DIR/scripts/lib/_backend_env.sh"

readonly BUILD_PRIVACY_POLICY_URL_DEFAULT="https://cool.ikanisa.com/privacy"
readonly BUILD_TERMS_OF_SERVICE_URL_DEFAULT="https://cool.ikanisa.com/terms"
readonly BUILD_ACCOUNT_DELETION_URL_DEFAULT="https://cool.ikanisa.com/account-deletion"
readonly BUILD_FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/dev/flutterw}"

build_android_release() {
  local artifact_type="${1:?Pass apk or appbundle.}"
  _load_release_env
  resolve_supabase_client_env production
  local build_args=(
    --release
    --flavor
    production
    "--dart-define=FLAVOR=production"
    "--dart-define=SUPABASE_URL=${RESOLVED_SUPABASE_URL}"
    "--dart-define=SUPABASE_ANON_KEY=${RESOLVED_SUPABASE_ANON_KEY}"
    "--dart-define=SUPABASE_PROJECT_REF=${RESOLVED_SUPABASE_PROJECT_REF}"
    "--dart-define=BACKEND_ENVIRONMENT=${RESOLVED_BACKEND_ENVIRONMENT}"
    "--dart-define=ENABLE_ANDROID_MOMO_SMS_AUTOREAD=${ENABLE_ANDROID_MOMO_SMS_AUTOREAD:-true}"
    "--dart-define=COOL_DEEP_LINK_HOST=${COOL_DEEP_LINK_HOST:-cool.app}"
    "--dart-define=COOL_PRIVACY_POLICY_URL=${COOL_PRIVACY_POLICY_URL:-$BUILD_PRIVACY_POLICY_URL_DEFAULT}"
    "--dart-define=COOL_TERMS_OF_SERVICE_URL=${COOL_TERMS_OF_SERVICE_URL:-$BUILD_TERMS_OF_SERVICE_URL_DEFAULT}"
    "--dart-define=COOL_ACCOUNT_DELETION_URL=${COOL_ACCOUNT_DELETION_URL:-$BUILD_ACCOUNT_DELETION_URL_DEFAULT}"
    "--dart-define=FIREBASE_ANDROID_PRODUCTION_API_KEY=${FIREBASE_ANDROID_PRODUCTION_API_KEY:-}"
    "--dart-define=FIREBASE_ANDROID_PRODUCTION_APP_ID=${FIREBASE_ANDROID_PRODUCTION_APP_ID:-}"
    "--dart-define=FIREBASE_ANDROID_PRODUCTION_MESSAGING_SENDER_ID=${FIREBASE_ANDROID_PRODUCTION_MESSAGING_SENDER_ID:-}"
    "--dart-define=FIREBASE_ANDROID_PRODUCTION_PROJECT_ID=${FIREBASE_ANDROID_PRODUCTION_PROJECT_ID:-}"
    "--dart-define=FIREBASE_ANDROID_PRODUCTION_STORAGE_BUCKET=${FIREBASE_ANDROID_PRODUCTION_STORAGE_BUCKET:-}"
  )

  cd "$ROOT_DIR"
  _assert_pinned_flutter_version
  _require_build_env

  case "$artifact_type" in
    apk)
      "$BUILD_FLUTTER_BIN" build apk "${build_args[@]}"
      ;;
    appbundle)
      "$BUILD_FLUTTER_BIN" build appbundle "${build_args[@]}"
      ;;
    *)
      echo "Unsupported Android artifact: $artifact_type" >&2
      return 1
      ;;
  esac
}

_require_build_env() {
  require_resolved_supabase_client_env production
  local native_firebase_config="$ROOT_DIR/android/app/src/production/google-services.json"
  if [[ ! -f "$native_firebase_config" ]]; then
    echo "CRITICAL BLOCKER — Missing Firebase Android config at $native_firebase_config." >&2
    return 1
  fi
  # Firebase keys are optional build-time overrides (google-services.json is the runtime source).
  if [[ -z "${FIREBASE_ANDROID_PRODUCTION_API_KEY:-}" ]]; then
    echo "⚠️  FIREBASE_ANDROID_PRODUCTION_* overrides not set; Firebase will use $native_firebase_config." >&2
  fi
}

_load_release_env() {
  load_client_env_files "$ROOT_DIR" \
    SUPABASE_URL \
    SUPABASE_ANON_KEY \
    SUPABASE_STAGING_URL \
    SUPABASE_STAGING_ANON_KEY \
    SUPABASE_PRODUCTION_URL \
    SUPABASE_PRODUCTION_ANON_KEY \
    COOL_DEEP_LINK_HOST \
    COOL_PRIVACY_POLICY_URL \
    COOL_TERMS_OF_SERVICE_URL \
    COOL_ACCOUNT_DELETION_URL \
    ENABLE_ANDROID_MOMO_SMS_AUTOREAD \
    FIREBASE_ANDROID_STAGING_API_KEY \
    FIREBASE_ANDROID_STAGING_APP_ID \
    FIREBASE_ANDROID_STAGING_MESSAGING_SENDER_ID \
    FIREBASE_ANDROID_STAGING_PROJECT_ID \
    FIREBASE_ANDROID_STAGING_STORAGE_BUCKET \
    FIREBASE_ANDROID_PRODUCTION_API_KEY \
    FIREBASE_ANDROID_PRODUCTION_APP_ID \
    FIREBASE_ANDROID_PRODUCTION_MESSAGING_SENDER_ID \
    FIREBASE_ANDROID_PRODUCTION_PROJECT_ID \
    FIREBASE_ANDROID_PRODUCTION_STORAGE_BUCKET
}

_assert_pinned_flutter_version() {
  local fvmrc_path="$ROOT_DIR/.fvmrc"
  if [[ ! -f "$fvmrc_path" ]]; then
    return 0
  fi

  local expected_version
  expected_version="$(
    sed -nE 's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$fvmrc_path"
  )"

  if [[ -z "$expected_version" ]]; then
    echo "Unable to parse Flutter version from $fvmrc_path." >&2
    return 1
  fi

  local current_version
  current_version="$(
    "$BUILD_FLUTTER_BIN" --version --machine 2>/dev/null |
      sed -nE 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p'
  )"

  if [[ -z "$current_version" ]]; then
    echo "Unable to determine the current Flutter SDK version." >&2
    return 1
  fi

  if [[ "$current_version" != "$expected_version" ]]; then
    echo "Flutter $expected_version is required by $fvmrc_path, but $current_version is active." >&2
    echo "Switch to the pinned SDK before building release artifacts." >&2
    return 1
  fi
}
