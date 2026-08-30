#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ADB="${ADB:-/Volumes/PRO-G40/AppData/android/sdk/platform-tools/adb}"
FLUTTER="${FLUTTER:-/Users/jeanbosco/Developer/flutter/bin/flutter}"
DEVICE_ID="${ANDROID_UAT_DEVICE_ID:-13111JEC215558}"
TARGET="integration_test/mobile_route_matrix_device_uat_test.dart"
CAPTURE_ID="${GOOGLE_PLAY_CAPTURE_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
EVIDENCE_ROOT="${GOOGLE_PLAY_CAPTURE_EVIDENCE_ROOT:-$ROOT_DIR/.cache/android_device_uat/google-play-$CAPTURE_ID}"

fail() {
  printf '[google-play-screenshot-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

[[ -x "$ADB" ]] || fail "adb is unavailable at $ADB"
[[ -x "$FLUTTER" ]] || fail "Flutter is unavailable at $FLUTTER"

if ! "$ADB" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  fail "Android device $DEVICE_ID is not connected and authorized."
fi

original_size="$($ADB -s "$DEVICE_ID" shell wm size | tr -d '\r')"
original_density="$($ADB -s "$DEVICE_ID" shell wm density | tr -d '\r')"
physical_size="$(awk -F': ' '/Physical size:/ { print $2; exit }' <<<"$original_size")"
physical_density="$(awk -F': ' '/Physical density:/ { print $2; exit }' <<<"$original_density")"
[[ -n "$physical_size" ]] || fail "Could not resolve the device physical display size."
[[ -n "$physical_density" ]] || fail "Could not resolve the device physical density."

restore_display() {
  "$ADB" -s "$DEVICE_ID" shell wm size reset >/dev/null 2>&1 || true
  "$ADB" -s "$DEVICE_ID" shell wm density reset >/dev/null 2>&1 || true
}
trap restore_display EXIT INT TERM

run_profile() {
  local profile="$1"
  local size="$2"
  local density="$3"
  local evidence_dir="$EVIDENCE_ROOT/$profile"

  "$ADB" -s "$DEVICE_ID" shell wm size "$size" >/dev/null
  "$ADB" -s "$DEVICE_ID" shell wm density "$density" >/dev/null
  sleep 2

  local active_size
  local active_density
  active_size="$($ADB -s "$DEVICE_ID" shell wm size | tr -d '\r')"
  active_density="$($ADB -s "$DEVICE_ID" shell wm density | tr -d '\r')"
  rg -q "Override size: $size" <<<"$active_size" || fail "$profile size override did not apply."
  if [[ "$density" == "$physical_density" ]]; then
    rg -q "Physical density: $density" <<<"$active_density" || fail "$profile physical density did not match."
  else
    rg -q "Override density: $density" <<<"$active_density" || fail "$profile density override did not apply."
  fi

  printf '[google-play-screenshot-uat] profile=%s size=%s density=%s evidence=%s\n' \
    "$profile" "$size" "$density" "${evidence_dir#$ROOT_DIR/}"

  ADB="$ADB" \
  FLUTTER="$FLUTTER" \
  ANDROID_UAT_DEVICE_ID="$DEVICE_ID" \
  ANDROID_UAT_FLAVOR=dev \
  ANDROID_UAT_TEST_TARGET="$TARGET" \
  ANDROID_UAT_EVIDENCE_DIR="$evidence_dir" \
  ANDROID_UAT_REQUIRE_SCREENSHOTS=true \
  ANDROID_UAT_VARIANT_NAME="google-play-$CAPTURE_ID-$profile" \
  ANDROID_UAT_THEME_MODE=dark \
  "$ROOT_DIR/scripts/android_device_uat.sh"
}

run_profile phone-1080x1920 1080x1920 440
run_profile seven-inch-1080x1920 1080x1920 280
run_profile ten-inch-1080x1920 1080x1920 160

restore_display
trap - EXIT INT TERM

restored_size="$($ADB -s "$DEVICE_ID" shell wm size | tr -d '\r')"
restored_density="$($ADB -s "$DEVICE_ID" shell wm density | tr -d '\r')"
if rg -q 'Override size:' <<<"$restored_size" || rg -q 'Override density:' <<<"$restored_density"; then
  fail "Display overrides remained after capture."
fi
rg -q "Physical size: $physical_size" <<<"$restored_size" || fail "Physical size was not restored."
rg -q "Physical density: $physical_density" <<<"$restored_density" || fail "Physical density was not restored."

printf '[google-play-screenshot-uat] status=pass evidence=%s restored_size=%s restored_density=%s\n' \
  "${EVIDENCE_ROOT#$ROOT_DIR/}" "$physical_size" "$physical_density"
