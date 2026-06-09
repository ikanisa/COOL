#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

resolve_adb() {
  local candidate
  if [[ "${ADB:-}" != "" ]]; then
    printf '%s\n' "$ADB"
    return 0
  fi
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi
  for candidate in \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$ROOT_DIR/../AppData/android/sdk/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf 'adb'
}

ADB="$(resolve_adb)"
FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
DEVICE_ID="${ANDROID_UAT_DEVICE_ID:-13111JEC215558}"
FLAVOR="${ANDROID_UAT_FLAVOR:-production}"
TEST_TARGET="${ANDROID_UAT_TEST_TARGET:-integration_test/app_uat_smoke_test.dart}"
DRIVER="${ANDROID_UAT_DRIVER:-test_driver/integration_test.dart}"
TIMEOUT_SECONDS="${ANDROID_UAT_TIMEOUT_SECONDS:-900}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_UAT_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_device_uat/$timestamp}"
LOG_FILE="$EVIDENCE_DIR/android_device_uat.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"

fail() {
  printf '[android-device-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

case "${1:-}" in
  "")
    ;;
  --help|-h)
    printf 'usage: %s\n' "$0"
    printf 'Environment: ADB ANDROID_UAT_DEVICE_ID ANDROID_UAT_FLAVOR ANDROID_UAT_TEST_TARGET ANDROID_UAT_DRIVER ANDROID_UAT_TIMEOUT_SECONDS ANDROID_UAT_EVIDENCE_DIR\n'
    exit 0
    ;;
  *)
    printf 'usage: %s\n' "$0" >&2
    exit 2
    ;;
esac

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

mkdir -p "$EVIDENCE_DIR"

if [[ -f "$DRIVER" ]]; then
  cmd=(
    "$FLUTTER"
    drive
    --no-pub
    --driver="$DRIVER"
    --target="$TEST_TARGET"
    -d "$DEVICE_ID"
    --flavor "$FLAVOR"
  )
  runner="drive"
else
  cmd=("$FLUTTER" test --no-pub -d "$DEVICE_ID" --flavor "$FLAVOR" "$TEST_TARGET")
  runner="test"
fi

printf '[android-device-uat] adb=%s device=%s flavor=%s target=%s runner=%s evidence=%s timeout_seconds=%s\n' \
  "$ADB" "$DEVICE_ID" "$FLAVOR" "$TEST_TARGET" "$runner" "${EVIDENCE_DIR#$ROOT_DIR/}" "$TIMEOUT_SECONDS" >&2

set +e
"${cmd[@]}" >"$LOG_FILE" 2>&1 &
uat_pid=$!
deadline=$((SECONDS + TIMEOUT_SECONDS))
timed_out=0
while kill -0 "$uat_pid" >/dev/null 2>&1; do
  if ((SECONDS >= deadline)); then
    timed_out=1
    kill "$uat_pid" >/dev/null 2>&1 || true
    sleep 2
    kill -9 "$uat_pid" >/dev/null 2>&1 || true
    break
  fi
  sleep 5
done
wait "$uat_pid" >/dev/null 2>&1
rc=$?
set -e

if [[ "$timed_out" == "1" ]]; then
  rc=124
fi

log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
status="pass"
if [[ "$timed_out" == "1" ]]; then
  status="timeout"
elif [[ "$rc" -ne 0 ]]; then
  status="fail"
fi

ANDROID_UAT_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
ANDROID_UAT_STATUS="$status" \
ANDROID_UAT_RC="$rc" \
ANDROID_UAT_DEVICE_ID="$DEVICE_ID" \
ANDROID_UAT_FLAVOR="$FLAVOR" \
ANDROID_UAT_TARGET="$TEST_TARGET" \
ANDROID_UAT_RUNNER="$runner" \
ANDROID_UAT_LOG="${LOG_FILE#$ROOT_DIR/}" \
ANDROID_UAT_LOG_SHA256="$log_sha256" \
ANDROID_UAT_TIMED_OUT="$timed_out" \
ANDROID_UAT_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
ruby -r json <<'RUBY' >"$SUMMARY_FILE"
puts JSON.pretty_generate(
  {
    "generated_at" => ENV.fetch("ANDROID_UAT_GENERATED_AT"),
    "status" => ENV.fetch("ANDROID_UAT_STATUS"),
    "exit_code" => ENV.fetch("ANDROID_UAT_RC").to_i,
    "device" => ENV.fetch("ANDROID_UAT_DEVICE_ID"),
    "flavor" => ENV.fetch("ANDROID_UAT_FLAVOR"),
    "target" => ENV.fetch("ANDROID_UAT_TARGET"),
    "runner" => ENV.fetch("ANDROID_UAT_RUNNER"),
    "log" => ENV.fetch("ANDROID_UAT_LOG"),
    "log_sha256" => ENV.fetch("ANDROID_UAT_LOG_SHA256"),
    "timed_out" => ENV.fetch("ANDROID_UAT_TIMED_OUT") == "1",
    "timeout_seconds" => ENV.fetch("ANDROID_UAT_TIMEOUT_SECONDS").to_i,
    "secret_handling" => "Device smoke output is retained locally and must not contain raw SMS bodies, phone/MoMo numbers, signing keys, service-role keys, provider tokens, or production customer data."
  }
)
RUBY

printf '[android-device-uat] status=%s evidence=%s log=%s\n' \
  "$status" "${SUMMARY_FILE#$ROOT_DIR/}" "${LOG_FILE#$ROOT_DIR/}" >&2
cat "$LOG_FILE"
exit "$rc"
