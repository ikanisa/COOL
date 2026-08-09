#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUILD_NAME="${COLLECT_ANDROID_BUILD_NAME:-1.2.2}"
BUILD_NUMBER="${COLLECT_ANDROID_BUILD_NUMBER:-13}"
SUPABASE_URL_VALUE="${SUPABASE_PRODUCTION_URL:-${SUPABASE_URL:-}}"
SUPABASE_ANON_KEY_VALUE="${SUPABASE_PRODUCTION_ANON_KEY:-${SUPABASE_ANON_KEY:-}}"

if [[ $# -ne 0 ]]; then
  printf 'This production wrapper accepts no extra Flutter arguments. Update the reviewed script for any build-contract change.\n' >&2
  exit 2
fi

if [[ -z "$SUPABASE_URL_VALUE" || -z "$SUPABASE_ANON_KEY_VALUE" ]]; then
  printf 'SUPABASE_PRODUCTION_URL and SUPABASE_PRODUCTION_ANON_KEY are required.\n' >&2
  exit 2
fi

umask 077
DEFINES_FILE="$(mktemp "${TMPDIR:-/tmp}/collect-android-defines.XXXXXX.json")"
cleanup() {
  rm -f "$DEFINES_FILE"
}
trap cleanup EXIT INT TERM

SUPABASE_URL_VALUE="$SUPABASE_URL_VALUE" \
SUPABASE_ANON_KEY_VALUE="$SUPABASE_ANON_KEY_VALUE" \
DEFINES_FILE="$DEFINES_FILE" \
ruby -r json <<'RUBY'
File.write(
  ENV.fetch("DEFINES_FILE"),
  JSON.generate(
    "SUPABASE_URL" => ENV.fetch("SUPABASE_URL_VALUE"),
    "SUPABASE_ANON_KEY" => ENV.fetch("SUPABASE_ANON_KEY_VALUE"),
    "APP_PUBLIC_URL" => ENV.fetch("APP_PUBLIC_URL", "https://collect.ikanisa.com"),
    "APP_ENVIRONMENT" => "production",
    "COLLECT_MOBILE_EVIDENCE_MODE" => "false"
  )
)
RUBY

common_args=(
  --release
  --flavor production
  --build-name "$BUILD_NAME"
  --build-number "$BUILD_NUMBER"
  --dart-define-from-file "$DEFINES_FILE"
)

"$FLUTTER_BIN" build apk "${common_args[@]}"
"$FLUTTER_BIN" build appbundle "${common_args[@]}"
