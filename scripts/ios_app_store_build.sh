#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
PACKAGE_VERSION="$(awk '/^version:[[:space:]]*/ { print $2; exit }' pubspec.yaml)"
[[ "$PACKAGE_VERSION" == *+* ]] || {
  printf 'pubspec.yaml version must include a build number.\n' >&2
  exit 2
}
DEFAULT_BUILD_NAME="${PACKAGE_VERSION%%+*}"
DEFAULT_BUILD_NUMBER="${PACKAGE_VERSION##*+}"
BUILD_NAME="${COLLECT_IOS_BUILD_NAME:-$DEFAULT_BUILD_NAME}"
BUILD_NUMBER="${COLLECT_IOS_BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"
BUILD_STARTED_EPOCH="$(date +%s)"
DESIGN_SOURCE_BEFORE="$(ruby scripts/qa/mobile_design_build_provenance.rb begin ios)"
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
DEFINES_FILE="$(mktemp "${TMPDIR:-/tmp}/collect-ios-defines.XXXXXX.json")"
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
    "APNS_ENVIRONMENT" => "production",
    "COLLECT_MOBILE_EVIDENCE_MODE" => "false"
  )
)
RUBY

"$FLUTTER_BIN" build ipa \
  --release \
  --flavor production \
  --build-name "$BUILD_NAME" \
  --build-number "$BUILD_NUMBER" \
  --dart-define-from-file "$DEFINES_FILE" \
  --export-options-plist ios/ExportOptionsAppStore.plist

if ! unzip -p "$ROOT_DIR/build/ios/ipa/Collect.ipa" \
  'Payload/Collect.app/Frameworks/App.framework/App' | \
  EXPECTED_SUPABASE_URL="$EXPECTED_PRODUCTION_SUPABASE_URL" ruby -e '
    expected = ENV.fetch("EXPECTED_SUPABASE_URL").b
    exit(STDIN.read.b.include?(expected) ? 0 : 1)
  '
then
  printf 'Packaged iOS release is missing the reviewed Supabase runtime URL.\n' >&2
  exit 1
fi

ruby scripts/qa/mobile_design_build_provenance.rb finish ios \
  "$DESIGN_SOURCE_BEFORE" "${BUILD_NAME}+${BUILD_NUMBER}" "$BUILD_STARTED_EPOCH"
