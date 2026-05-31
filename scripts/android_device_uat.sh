#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ADB="${ADB:-adb}"
FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
DEVICE_ID="${ANDROID_UAT_DEVICE_ID:-13111JEC215558}"
FLAVOR="${ANDROID_UAT_FLAVOR:-production}"
TEST_TARGET="${ANDROID_UAT_TEST_TARGET:-integration_test/app_uat_smoke_test.dart}"

fail() {
  printf '[android-device-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

if ! "$ADB" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  fail "Android device $DEVICE_ID is not connected and authorized over ADB."
fi

window_state="$("$ADB" -s "$DEVICE_ID" shell dumpsys window 2>/dev/null || true)"
if grep -q 'mDreamingLockscreen=true' <<<"$window_state" ||
  grep -q 'mKeyguardShowing=true' <<<"$window_state"; then
  printf '%s\n' "$window_state" |
    rg 'mCurrentFocus|mFocusedApp|mDreamingLockscreen|mKeyguardShowing' >&2 || true
  fail "Pixel 4a $DEVICE_ID is locked. Unlock it manually and keep it awake before running Android UAT."
fi

printf '[android-device-uat] device=%s flavor=%s target=%s\n' "$DEVICE_ID" "$FLAVOR" "$TEST_TARGET" >&2
exec "$FLUTTER" test --no-pub -d "$DEVICE_ID" --flavor "$FLAVOR" "$TEST_TARGET"
