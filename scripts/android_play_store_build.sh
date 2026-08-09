#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUILD_NAME="${COLLECT_ANDROID_BUILD_NAME:-1.2.2}"
BUILD_NUMBER="${COLLECT_ANDROID_BUILD_NUMBER:-14}"
readonly EXPECTED_PRODUCTION_SUPABASE_URL="https://lhbowpbcpwoiparwnwgt.supabase.co"
SUPABASE_URL_VALUE="${SUPABASE_PRODUCTION_URL:-}"
SUPABASE_ANON_KEY_VALUE="${SUPABASE_PRODUCTION_ANON_KEY:-}"

if [[ $# -ne 0 ]]; then
  printf 'This production wrapper accepts no extra Flutter arguments. Update the reviewed script for any build-contract change.\n' >&2
  exit 2
fi

if [[ -z "$SUPABASE_URL_VALUE" || -z "$SUPABASE_ANON_KEY_VALUE" ]]; then
  printf 'SUPABASE_PRODUCTION_URL and SUPABASE_PRODUCTION_ANON_KEY are required.\n' >&2
  exit 2
fi

if [[ "$SUPABASE_URL_VALUE" != "$EXPECTED_PRODUCTION_SUPABASE_URL" ]]; then
  printf 'SUPABASE_PRODUCTION_URL does not match the reviewed Collect production project.\n' >&2
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

verify_public_runtime_config() {
  local archive="$1"
  local app_binary="$2"

  if ! unzip -p "$archive" "$app_binary" | \
    EXPECTED_SUPABASE_URL="$EXPECTED_PRODUCTION_SUPABASE_URL" ruby -e '
      expected = ENV.fetch("EXPECTED_SUPABASE_URL").b
      exit(STDIN.read.b.include?(expected) ? 0 : 1)
    '
  then
    printf 'Packaged release is missing the reviewed Supabase runtime URL: %s\n' "$archive" >&2
    exit 1
  fi
}

# Flutter recompiles its AOT binary when dart defines change, but Gradle can
# otherwise restore an older packaged APK/AAB whose stripped libapp.so does not
# contain those values. A clean, cache-disabled production build plus a binary
# assertion prevents that store-blocking failure from being published again.
export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.caching=false"
export COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false
"$ROOT_DIR/android/gradlew" --no-build-cache -p "$ROOT_DIR/android" :app:clean

"$FLUTTER_BIN" build apk "${common_args[@]}"
verify_public_runtime_config \
  "$ROOT_DIR/build/app/outputs/flutter-apk/app-production-release.apk" \
  'lib/arm64-v8a/libapp.so'

"$FLUTTER_BIN" build appbundle "${common_args[@]}"
verify_public_runtime_config \
  "$ROOT_DIR/build/app/outputs/bundle/productionRelease/app-production-release.aab" \
  'base/lib/arm64-v8a/libapp.so'
