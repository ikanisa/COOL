#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

resolve_adb() {
  local candidate
  for candidate in \
    "${ADB:-}" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf 'adb'
}

ADB="$(resolve_adb)"
DEVICE_ID="${ANDROID_PERMISSION_UAT_DEVICE_ID:-}"
ALLOW_PHYSICAL="${ANDROID_PERMISSION_UAT_ALLOW_PHYSICAL:-false}"
PACKAGE="${ANDROID_PERMISSION_UAT_PACKAGE:-app.cool.mobile.dev}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_PERMISSION_UAT_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_permission_dialog_uat/$timestamp}"
DEVICE_LOG="$EVIDENCE_DIR/android_device_uat.txt"
HARNESS_LOG="$EVIDENCE_DIR/harness.txt"
DIALOG_LOG="$EVIDENCE_DIR/dialog_actions.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"

fail() {
  printf '[android-permission-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

if [[ -z "$DEVICE_ID" ]]; then
  fail "ANDROID_PERMISSION_UAT_DEVICE_ID is required."
fi
if [[ "$DEVICE_ID" != emulator-* && "$ALLOW_PHYSICAL" != "true" ]]; then
  fail "Physical-device mutation is disabled. Use an emulator or explicitly set ANDROID_PERMISSION_UAT_ALLOW_PHYSICAL=true."
fi
if ! "$ADB" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  fail "Android target $DEVICE_ID is not connected and authorized."
fi

mkdir -p "$EVIDENCE_DIR"
: >"$DIALOG_LOG"
"$ADB" -s "$DEVICE_ID" shell pm clear "$PACKAGE" >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE_ID" shell pm revoke "$PACKAGE" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE_ID" shell pm clear-permission-flags "$PACKAGE" android.permission.POST_NOTIFICATIONS user-set >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE_ID" shell pm clear-permission-flags "$PACKAGE" android.permission.POST_NOTIFICATIONS user-fixed >/dev/null 2>&1 || true
if [[ "$PACKAGE" != "app.cool.mobile" ]]; then
  "$ADB" -s "$DEVICE_ID" shell am force-stop app.cool.mobile >/dev/null 2>&1 || true
fi

ADB="$ADB" \
ANDROID_UAT_DEVICE_ID="$DEVICE_ID" \
ANDROID_UAT_FLAVOR=dev \
ANDROID_UAT_TEST_TARGET=integration_test/mobile_permission_device_uat_test.dart \
ANDROID_UAT_TIMEOUT_SECONDS=600 \
ANDROID_UAT_EVIDENCE_DIR="$EVIDENCE_DIR" \
ANDROID_UAT_VARIANT_NAME=permission-dialog-deny-retry-recover \
ANDROID_UAT_THEME_MODE=dark \
ANDROID_UAT_TEXT_SCALE=1.0 \
ANDROID_UAT_HIGH_CONTRAST=false \
ANDROID_UAT_REDUCED_MOTION=false \
/bin/bash scripts/android_device_uat.sh >"$HARNESS_LOG" 2>&1 &
uat_pid=$!

cleanup() {
  if kill -0 "$uat_pid" >/dev/null 2>&1; then
    kill -TERM "$uat_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

wait_for_marker() {
  local marker="$1"
  local timeout_seconds="${2:-90}"
  local waited=0
  while (( waited < timeout_seconds )); do
    if [[ -f "$DEVICE_LOG" ]] && grep -Fq "$marker" "$DEVICE_LOG"; then
      return 0
    fi
    if ! kill -0 "$uat_pid" >/dev/null 2>&1; then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

tap_permission_button() {
  local button_id="$1"
  local expected_state="$2"
  local timeout_seconds="${3:-45}"
  local waited=0
  local xml
  local coordinates
  while (( waited < timeout_seconds )); do
    "$ADB" -s "$DEVICE_ID" shell rm -f /data/local/tmp/collect-permission.xml >/dev/null 2>&1 || true
    # `uiautomator dump` can wait indefinitely while Flutter's integration
    # driver owns accessibility. Android's native timeout still permits the XML
    # file to be consumed when the dump completed but its process did not exit.
    "$ADB" -s "$DEVICE_ID" shell timeout 4 uiautomator dump --compressed \
      /data/local/tmp/collect-permission.xml >/dev/null 2>&1 || true
    xml="$("$ADB" -s "$DEVICE_ID" exec-out cat /data/local/tmp/collect-permission.xml 2>/dev/null || true)"
    if [[ "$xml" != *"permissioncontroller"* ]]; then
      sleep 1
      waited=$((waited + 5))
      continue
    fi
    coordinates="$(
      BUTTON_ID="$button_id" ruby -e '
        xml = STDIN.read
        button_id = ENV.fetch("BUTTON_ID")
        xml.scan(/<node\b[^>]*>/).each do |node|
          resource_id = node[/\bresource-id="([^"]*)"/, 1].to_s
          next unless resource_id.end_with?(":id/#{button_id}")
          match = node.match(/\bbounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/)
          next unless match
          left, top, right, bottom = match.captures.map(&:to_i)
          puts "#{(left + right) / 2} #{(top + bottom) / 2}"
          exit 0
        end
        exit 1
      ' <<<"$xml" 2>/dev/null || true
    )"
    if [[ "$coordinates" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then
      read -r x y <<<"$coordinates"
      # Android ignores taps that land in the short anti-tapjacking window
      # immediately after a runtime-permission dialog appears. Confirm that the
      # permission controller actually closes instead of treating input
      # injection itself as success.
      for tap_attempt in 1 2 3; do
        sleep 1
        "$ADB" -s "$DEVICE_ID" shell input tap "$x" "$y"
        sleep 1
        current_focus="$("$ADB" -s "$DEVICE_ID" shell dumpsys window 2>/dev/null |
          awk -F= '/mCurrentFocus=/ { print $2; exit }' || true)"
        permission_line="$("$ADB" -s "$DEVICE_ID" shell dumpsys package "$PACKAGE" 2>/dev/null |
          awk '/android.permission.POST_NOTIFICATIONS: granted=/ { print; exit }' || true)"
        printf 'action=tap button=%s x=%s y=%s elapsed_seconds=%s attempt=%s focus=%s\n' \
          "$button_id" "$x" "$y" "$waited" "$tap_attempt" \
          "${current_focus//[[:space:]]/}" >>"$DIALOG_LOG"
        if [[ "$expected_state" == "denied" &&
          "$permission_line" == *"granted=false"* &&
          "$permission_line" == *"USER_SET"* ]]; then
          return 0
        fi
        if [[ "$expected_state" == "granted" &&
          "$permission_line" == *"granted=true"* ]]; then
          return 0
        fi
        if [[ "$expected_state" == "granted" && -f "$DEVICE_LOG" ]] &&
          grep -Fq 'collect_permission_uat:notification-recovery-pass' "$DEVICE_LOG"; then
          return 0
        fi
      done
    fi
    if ! kill -0 "$uat_pid" >/dev/null 2>&1; then
      return 1
    fi
    sleep 1
    waited=$((waited + 5))
  done
  printf 'action=timeout button=%s elapsed_seconds=%s\n' \
    "$button_id" "$waited" >>"$DIALOG_LOG"
  return 1
}

wait_for_marker 'collect_permission_uat:notification-deny-prompt-requested' 480 ||
  fail "Notification deny prompt marker was not emitted."
tap_permission_button "permission_deny_button" denied 60 ||
  fail "Notification denial action was not found."
wait_for_marker 'collect_permission_uat:notification-denied-recovery-visible' 60 ||
  fail "Collect did not expose denial recovery."
wait_for_marker 'collect_permission_uat:notification-retry-prompt-requested' 30 ||
  fail "Notification retry marker was not emitted."

if ! tap_permission_button "permission_allow_button" granted 35; then
  wait_for_marker 'collect_permission_uat:notification-settings-recovery-requested' 40 ||
    fail "Neither a retry prompt nor settings recovery became available."
  "$ADB" -s "$DEVICE_ID" shell pm grant "$PACKAGE" android.permission.POST_NOTIFICATIONS
  "$ADB" -s "$DEVICE_ID" shell input keyevent KEYCODE_BACK
fi

set +e
wait "$uat_pid"
rc=$?
set -e
trap - EXIT INT TERM

status="pass"
if [[ "$rc" -ne 0 ]] ||
  [[ ! -f "$DEVICE_LOG" ]] ||
  ! grep -Fq 'collect_permission_uat:notification-recovery-pass' "$DEVICE_LOG" ||
  ! grep -Eq 'All tests passed[.!]' "$DEVICE_LOG"; then
  status="fail"
fi

device_log_sha256=""
harness_log_sha256=""
dialog_log_sha256=""
if [[ -f "$DEVICE_LOG" ]]; then
  device_log_sha256="$(shasum -a 256 "$DEVICE_LOG" | awk '{print $1}')"
fi
if [[ -f "$HARNESS_LOG" ]]; then
  harness_log_sha256="$(shasum -a 256 "$HARNESS_LOG" | awk '{print $1}')"
fi
if [[ -f "$DIALOG_LOG" ]]; then
  dialog_log_sha256="$(shasum -a 256 "$DIALOG_LOG" | awk '{print $1}')"
fi

ANDROID_PERMISSION_UAT_STATUS="$status" \
ANDROID_PERMISSION_UAT_RC="$rc" \
ANDROID_PERMISSION_UAT_DEVICE="$DEVICE_ID" \
ANDROID_PERMISSION_UAT_PACKAGE="$PACKAGE" \
ANDROID_PERMISSION_UAT_DEVICE_LOG="${DEVICE_LOG#$ROOT_DIR/}" \
ANDROID_PERMISSION_UAT_DEVICE_LOG_SHA256="$device_log_sha256" \
ANDROID_PERMISSION_UAT_HARNESS_LOG="${HARNESS_LOG#$ROOT_DIR/}" \
ANDROID_PERMISSION_UAT_HARNESS_LOG_SHA256="$harness_log_sha256" \
ANDROID_PERMISSION_UAT_DIALOG_LOG="${DIALOG_LOG#$ROOT_DIR/}" \
ANDROID_PERMISSION_UAT_DIALOG_LOG_SHA256="$dialog_log_sha256" \
ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => ENV.fetch("ANDROID_PERMISSION_UAT_STATUS"),
    "exit_code" => ENV.fetch("ANDROID_PERMISSION_UAT_RC").to_i,
    "device" => ENV.fetch("ANDROID_PERMISSION_UAT_DEVICE"),
    "package" => ENV.fetch("ANDROID_PERMISSION_UAT_PACKAGE"),
    "scenario" => "notification-deny-retry-settings-recovery",
    "device_log" => ENV.fetch("ANDROID_PERMISSION_UAT_DEVICE_LOG"),
    "device_log_sha256" => ENV.fetch("ANDROID_PERMISSION_UAT_DEVICE_LOG_SHA256"),
    "harness_log" => ENV.fetch("ANDROID_PERMISSION_UAT_HARNESS_LOG"),
    "harness_log_sha256" => ENV.fetch("ANDROID_PERMISSION_UAT_HARNESS_LOG_SHA256"),
    "dialog_log" => ENV.fetch("ANDROID_PERMISSION_UAT_DIALOG_LOG"),
    "dialog_log_sha256" => ENV.fetch("ANDROID_PERMISSION_UAT_DIALOG_LOG_SHA256"),
    "secret_handling" => "Permission evidence records UI state markers and hashes only; it does not retain notification contents, SMS bodies, phone/MoMo numbers, credentials, or production customer data."
  }
)
RUBY

printf '[android-permission-uat] status=%s evidence=%s\n' "$status" "${SUMMARY_FILE#$ROOT_DIR/}" >&2
if [[ "$status" != "pass" ]]; then
  tail -n 120 "$HARNESS_LOG" >&2 || true
  exit 1
fi
