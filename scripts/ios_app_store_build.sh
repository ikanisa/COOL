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
NATIVE_SOURCE_BEFORE="$(ruby scripts/qa/native_build_provenance.rb begin ios)"
readonly EXPECTED_PRODUCTION_PUBLIC_URL="https://collect.ikanisa.com"
readonly EXPECTED_PRODUCTION_ADMIN_URL="https://platform-admin.collect.ikanisa.com"
APP_PUBLIC_URL="${APP_PUBLIC_URL:-$EXPECTED_PRODUCTION_PUBLIC_URL}"
ADMIN_APP_URL="${ADMIN_APP_URL:-$EXPECTED_PRODUCTION_ADMIN_URL}"
export APP_PUBLIC_URL ADMIN_APP_URL

if [[ $# -ne 0 ]]; then
  printf 'This production wrapper accepts no extra Flutter arguments. Update the reviewed script for any build-contract change.\n' >&2
  exit 2
fi

if [[ "$APP_PUBLIC_URL" != "$EXPECTED_PRODUCTION_PUBLIC_URL" || "$ADMIN_APP_URL" != "$EXPECTED_PRODUCTION_ADMIN_URL" ]]; then
  printf 'Public and Admin URLs must match the reviewed HTTPS production targets.\n' >&2
  exit 2
fi

umask 077
DEFINES_FILE="$(mktemp "${TMPDIR:-/tmp}/collect-ios-defines.XXXXXX.json")"
cleanup() {
  rm -f "$DEFINES_FILE"
}
trap cleanup EXIT INT TERM

python3 scripts/qa/native_build_config.py ios --defines-output "$DEFINES_FILE"

"$FLUTTER_BIN" build ipa \
  --release \
  --flavor production \
  --build-name "$BUILD_NAME" \
  --build-number "$BUILD_NUMBER" \
  --dart-define-from-file "$DEFINES_FILE" \
  --export-options-plist ios/ExportOptionsAppStore.plist

if ! unzip -p "$ROOT_DIR/build/ios/ipa/Collect.ipa" \
  'Payload/Collect.app/Frameworks/App.framework/App' | \
  DEFINES_FILE="$DEFINES_FILE" ruby -r json -e '
    values = JSON.parse(File.read(ENV.fetch("DEFINES_FILE")))
    binary = STDIN.read.b
    required = %w[SUPABASE_URL SUPABASE_API_URL SUPABASE_PUBLISHABLE_KEY]
    exit(required.all? { |key| binary.include?(values.fetch(key).b) } ? 0 : 1)
  '
then
  printf 'Packaged iOS release is missing the reviewed Supabase runtime configuration.\n' >&2
  exit 1
fi

ruby scripts/qa/native_build_provenance.rb finish ios \
  "$NATIVE_SOURCE_BEFORE" "${BUILD_NAME}+${BUILD_NUMBER}" "$BUILD_STARTED_EPOCH"
