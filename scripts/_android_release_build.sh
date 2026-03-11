#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR

readonly BUILD_PRIVACY_POLICY_URL_DEFAULT="https://gen-lang-client-0172279957.web.app/privacy"
readonly BUILD_TERMS_OF_SERVICE_URL_DEFAULT="https://gen-lang-client-0172279957.web.app/terms"
readonly BUILD_ACCOUNT_DELETION_URL_DEFAULT="https://gen-lang-client-0172279957.web.app/account-deletion"
readonly BUILD_FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

build_android_release() {
  local artifact_type="${1:?Pass apk or appbundle.}"
  local build_args=(
    --release
    "--dart-define=SUPABASE_URL=${SUPABASE_URL}"
    "--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
    "--dart-define=COOL_APP_MOMO_NUMBER=${COOL_APP_MOMO_NUMBER:-}"
    "--dart-define=ENABLE_ANDROID_MOMO_SMS_AUTOREAD=${ENABLE_ANDROID_MOMO_SMS_AUTOREAD:-false}"
    "--dart-define=COOL_DEEP_LINK_HOST=${COOL_DEEP_LINK_HOST:-cool.app}"
    "--dart-define=COOL_PRIVACY_POLICY_URL=${COOL_PRIVACY_POLICY_URL:-$BUILD_PRIVACY_POLICY_URL_DEFAULT}"
    "--dart-define=COOL_TERMS_OF_SERVICE_URL=${COOL_TERMS_OF_SERVICE_URL:-$BUILD_TERMS_OF_SERVICE_URL_DEFAULT}"
    "--dart-define=COOL_ACCOUNT_DELETION_URL=${COOL_ACCOUNT_DELETION_URL:-$BUILD_ACCOUNT_DELETION_URL_DEFAULT}"
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
  : "${SUPABASE_URL:?Set SUPABASE_URL before building an Android release artifact.}"
  : "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY before building an Android release artifact.}"

  if [[ -z "${COOL_APP_MOMO_NUMBER:-}" ]]; then
    echo "WARN: COOL_APP_MOMO_NUMBER is not set. Mobility subscription payments" >&2
    echo "will fail and missing-recipient fallbacks will be unavailable." >&2
  fi
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
