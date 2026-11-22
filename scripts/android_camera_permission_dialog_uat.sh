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
DEVICE_ID="${ANDROID_CAMERA_UAT_DEVICE_ID:-}"
ALLOW_PHYSICAL="${ANDROID_CAMERA_UAT_ALLOW_PHYSICAL:-false}"
PACKAGE="${ANDROID_CAMERA_UAT_PACKAGE:-app.cool.mobile.dev}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_CAMERA_UAT_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_camera_permission_dialog_uat/$timestamp}"
DEVICE_LOG="$EVIDENCE_DIR/android_device_uat.txt"
HARNESS_LOG="$EVIDENCE_DIR/harness.txt"
DIALOG_LOG="$EVIDENCE_DIR/dialog_actions.txt"
SCREENSHOT_DIR="$EVIDENCE_DIR/screenshots"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"

fail() {
  printf '[android-camera-permission-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

if [[ -z "$DEVICE_ID" ]]; then
  fail "ANDROID_CAMERA_UAT_DEVICE_ID is required."
fi
if [[ "$DEVICE_ID" != emulator-* && "$ALLOW_PHYSICAL" != "true" ]]; then
  fail "Physical-device mutation is disabled. Use an emulator or explicitly set ANDROID_CAMERA_UAT_ALLOW_PHYSICAL=true."
fi
if ! "$ADB" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  fail "Android target $DEVICE_ID is not connected and authorized."
fi

mkdir -p "$SCREENSHOT_DIR"
: >"$DIALOG_LOG"
"$ADB" -s "$DEVICE_ID" shell pm clear "$PACKAGE" >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE_ID" shell pm revoke "$PACKAGE" android.permission.CAMERA >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE_ID" shell pm clear-permission-flags "$PACKAGE" android.permission.CAMERA user-set >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE_ID" shell pm clear-permission-flags "$PACKAGE" android.permission.CAMERA user-fixed >/dev/null 2>&1 || true
if [[ "$PACKAGE" != "app.cool.mobile" ]]; then
  "$ADB" -s "$DEVICE_ID" shell am force-stop app.cool.mobile >/dev/null 2>&1 || true
fi

ADB="$ADB" \
ANDROID_UAT_DEVICE_ID="$DEVICE_ID" \
ANDROID_UAT_FLAVOR=dev \
ANDROID_UAT_TEST_TARGET=integration_test/mobile_camera_permission_device_uat_test.dart \
ANDROID_UAT_TIMEOUT_SECONDS=600 \
ANDROID_UAT_EVIDENCE_DIR="$EVIDENCE_DIR" \
ANDROID_UAT_VARIANT_NAME=camera-permission-deny-retry-recover \
ANDROID_UAT_THEME_MODE=dark \
ANDROID_UAT_TEXT_SCALE=1.0 \
ANDROID_UAT_HIGH_CONTRAST=false \
ANDROID_UAT_REDUCED_MOTION=false \
ANDROID_UAT_MOBILE_EVIDENCE_MODE=false \
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

capture_screenshot() {
  local name="$1"
  local target="$SCREENSHOT_DIR/$name"
  "$ADB" -s "$DEVICE_ID" exec-out screencap -p >"$target"
  if [[ ! -s "$target" ]]; then
    fail "Screenshot capture was empty: $name"
  fi
}

tap_permission_button() {
  local candidate_ids="$1"
  local screenshot_name="$2"
  local expected_state="$3"
  local timeout_seconds="${4:-60}"
  local waited=0
  local xml
  local match
  while (( waited < timeout_seconds )); do
    "$ADB" -s "$DEVICE_ID" shell rm -f /data/local/tmp/collect-camera-permission.xml >/dev/null 2>&1 || true
    "$ADB" -s "$DEVICE_ID" shell timeout 4 uiautomator dump --compressed \
      /data/local/tmp/collect-camera-permission.xml >/dev/null 2>&1 || true
    xml="$("$ADB" -s "$DEVICE_ID" exec-out cat /data/local/tmp/collect-camera-permission.xml 2>/dev/null || true)"
    match="$(
      CANDIDATE_IDS="$candidate_ids" ruby -e '
        xml = STDIN.read
        candidates = ENV.fetch("CANDIDATE_IDS").split("|")
        xml.scan(/<node\b[^>]*>/).each do |node|
          resource_id = node[/\bresource-id="([^"]*)"/, 1].to_s
          candidate = candidates.find { |id| resource_id.end_with?(":id/#{id}") }
          next unless candidate
          bounds = node.match(/\bbounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/)
          next unless bounds
          left, top, right, bottom = bounds.captures.map(&:to_i)
          puts "#{candidate} #{(left + right) / 2} #{(top + bottom) / 2}"
          exit 0
        end
        exit 1
      ' <<<"$xml" 2>/dev/null || true
    )"
    if [[ "$match" =~ ^[^[:space:]]+[[:space:]][0-9]+[[:space:]][0-9]+$ ]]; then
      local button_id
      local x
      local y
      read -r button_id x y <<<"$match"
      capture_screenshot "$screenshot_name"
      for tap_attempt in 1 2 3; do
        sleep 1
        "$ADB" -s "$DEVICE_ID" shell input tap "$x" "$y"
        sleep 1
        current_focus="$("$ADB" -s "$DEVICE_ID" shell dumpsys window 2>/dev/null |
          awk -F= '/mCurrentFocus=/ { print $2; exit }' || true)"
        permission_line="$("$ADB" -s "$DEVICE_ID" shell dumpsys package "$PACKAGE" 2>/dev/null |
          awk '/android.permission.CAMERA: granted=/ { print; exit }' || true)"
        printf 'action=tap button=%s x=%s y=%s elapsed_seconds=%s attempt=%s focus=%s screenshot=%s\n' \
          "$button_id" "$x" "$y" "$waited" "$tap_attempt" \
          "${current_focus//[[:space:]]/}" "$screenshot_name" >>"$DIALOG_LOG"
        if [[ "$expected_state" == "denied" &&
          "$permission_line" == *"granted=false"* &&
          "$permission_line" == *"USER_SET"* &&
          "$current_focus" == *"$PACKAGE/"* ]]; then
          return 0
        fi
        if [[ "$expected_state" == "granted" &&
          "$permission_line" == *"granted=true"* &&
          "$current_focus" == *"$PACKAGE/"* ]]; then
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
  printf 'action=timeout candidates=%s elapsed_seconds=%s\n' \
    "$candidate_ids" "$waited" >>"$DIALOG_LOG"
  return 1
}

wait_for_marker 'collect_camera_permission_uat:camera-deny-prompt-requested' 480 ||
  fail "Camera deny prompt marker was not emitted."
tap_permission_button \
  "permission_deny_button|permission_deny_and_dont_ask_again_button" \
  "01-camera-native-deny-prompt.png" denied 75 ||
  fail "Camera denial action was not found."
wait_for_marker 'collect_camera_permission_uat:camera-denied-recovery-visible' 75 ||
  fail "Collect did not expose Camera denial recovery."
capture_screenshot "02-collect-camera-recovery.png"
wait_for_marker 'collect_camera_permission_uat:camera-retry-prompt-requested' 30 ||
  fail "Camera retry marker was not emitted."
tap_permission_button \
  "permission_allow_foreground_only_button|permission_allow_one_time_button|permission_allow_button" \
  "03-camera-native-allow-prompt.png" granted 75 ||
  fail "Camera allow action was not found."
wait_for_marker 'collect_camera_permission_uat:camera-recovery-pass' 75 ||
  fail "Collect did not confirm Camera recovery."
capture_screenshot "04-camera-recovered.png"

set +e
wait "$uat_pid"
rc=$?
set -e
trap - EXIT INT TERM

status="pass"
if [[ "$rc" -ne 0 ]] ||
  [[ ! -f "$DEVICE_LOG" ]] ||
  ! grep -Fq 'collect_camera_permission_uat:camera-recovery-pass' "$DEVICE_LOG" ||
  ! grep -Eq 'All tests passed[.!]' "$DEVICE_LOG"; then
  status="fail"
fi

device_log_sha256="$(shasum -a 256 "$DEVICE_LOG" | awk '{print $1}')"
harness_log_sha256="$(shasum -a 256 "$HARNESS_LOG" | awk '{print $1}')"
dialog_log_sha256="$(shasum -a 256 "$DIALOG_LOG" | awk '{print $1}')"
(
  cd "$SCREENSHOT_DIR"
  shasum -a 256 ./*.png
) >"$SCREENSHOT_DIR/SCREENSHOT_MANIFEST.sha256"
screenshot_manifest_sha256="$(shasum -a 256 "$SCREENSHOT_DIR/SCREENSHOT_MANIFEST.sha256" | awk '{print $1}')"

ANDROID_CAMERA_UAT_STATUS="$status" \
ANDROID_CAMERA_UAT_RC="$rc" \
ANDROID_CAMERA_UAT_DEVICE="$DEVICE_ID" \
ANDROID_CAMERA_UAT_PACKAGE="$PACKAGE" \
ANDROID_CAMERA_UAT_DEVICE_LOG="${DEVICE_LOG#$ROOT_DIR/}" \
ANDROID_CAMERA_UAT_DEVICE_LOG_SHA256="$device_log_sha256" \
ANDROID_CAMERA_UAT_HARNESS_LOG="${HARNESS_LOG#$ROOT_DIR/}" \
ANDROID_CAMERA_UAT_HARNESS_LOG_SHA256="$harness_log_sha256" \
ANDROID_CAMERA_UAT_DIALOG_LOG="${DIALOG_LOG#$ROOT_DIR/}" \
ANDROID_CAMERA_UAT_DIALOG_LOG_SHA256="$dialog_log_sha256" \
ANDROID_CAMERA_UAT_SCREENSHOT_MANIFEST="${SCREENSHOT_DIR#$ROOT_DIR/}/SCREENSHOT_MANIFEST.sha256" \
ANDROID_CAMERA_UAT_SCREENSHOT_MANIFEST_SHA256="$screenshot_manifest_sha256" \
ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => ENV.fetch("ANDROID_CAMERA_UAT_STATUS"),
    "exit_code" => ENV.fetch("ANDROID_CAMERA_UAT_RC").to_i,
    "device" => ENV.fetch("ANDROID_CAMERA_UAT_DEVICE"),
    "package" => ENV.fetch("ANDROID_CAMERA_UAT_PACKAGE"),
    "scenario" => "camera-deny-education-retry-grant-recovery",
    "device_log" => ENV.fetch("ANDROID_CAMERA_UAT_DEVICE_LOG"),
    "device_log_sha256" => ENV.fetch("ANDROID_CAMERA_UAT_DEVICE_LOG_SHA256"),
    "harness_log" => ENV.fetch("ANDROID_CAMERA_UAT_HARNESS_LOG"),
    "harness_log_sha256" => ENV.fetch("ANDROID_CAMERA_UAT_HARNESS_LOG_SHA256"),
    "dialog_log" => ENV.fetch("ANDROID_CAMERA_UAT_DIALOG_LOG"),
    "dialog_log_sha256" => ENV.fetch("ANDROID_CAMERA_UAT_DIALOG_LOG_SHA256"),
    "screenshot_manifest" => ENV.fetch("ANDROID_CAMERA_UAT_SCREENSHOT_MANIFEST"),
    "screenshot_manifest_sha256" => ENV.fetch("ANDROID_CAMERA_UAT_SCREENSHOT_MANIFEST_SHA256"),
    "screenshot_count" => 4,
    "secret_handling" => "Camera evidence retains permission and recovery UI only. It does not retain camera frames, photos, gallery images, SMS bodies, phone or MoMo numbers, credentials, or production customer data."
  }
)
RUBY

printf '[android-camera-permission-uat] status=%s evidence=%s\n' \
  "$status" "${SUMMARY_FILE#$ROOT_DIR/}" >&2
if [[ "$status" != "pass" ]]; then
  tail -n 140 "$HARNESS_LOG" >&2 || true
  exit 1
fi
