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

ADB_BIN="$(resolve_adb)"
FLUTTER="${FLUTTER:-/Users/jeanbosco/Developer/flutter/bin/flutter}"
DEVICE_ID="${ANDROID_NETWORK_UAT_DEVICE_ID:-emulator-5554}"
FLAVOR="${ANDROID_NETWORK_UAT_FLAVOR:-dev}"
PROBE_HOST="${ANDROID_NETWORK_UAT_PROBE_HOST:-10.0.2.2}"
PROBE_PORT="${ANDROID_NETWORK_UAT_PROBE_PORT:-54331}"
TIMEOUT_SECONDS="${ANDROID_NETWORK_UAT_TIMEOUT_SECONDS:-900}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_NETWORK_UAT_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_network_restoration_uat/$timestamp}"
DEVICE_LOG="$EVIDENCE_DIR/android_network_restoration_uat.txt"
HARNESS_LOG="$EVIDENCE_DIR/harness.txt"
RADIO_LOG="$EVIDENCE_DIR/radio_state.txt"
SCREENSHOT_DIR="$EVIDENCE_DIR/screenshots"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
TEST_TARGET="integration_test/mobile_network_restoration_device_uat_test.dart"
export COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY="${COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY:-false}"

fail() {
  printf '[android-network-restoration-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

adb_shell() {
  "$ADB_BIN" -s "$DEVICE_ID" shell "$@" 2>/dev/null | tr -d '\r' || true
}

wait_for_marker() {
  local marker="$1"
  local timeout_seconds="${2:-90}"
  local waited=0
  while (( waited < timeout_seconds )); do
    if [[ -f "$DEVICE_LOG" ]] && grep -Fq "$marker" "$DEVICE_LOG"; then
      return 0
    fi
    if [[ "${uat_pid:-}" != "" ]] && ! kill -0 "$uat_pid" >/dev/null 2>&1; then
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
  "$ADB_BIN" -s "$DEVICE_ID" exec-out screencap -p >"$target" || true
  if [[ ! -s "$target" ]]; then
    printf '[android-network-restoration-uat][WARN] Screenshot capture empty: %s\n' "$name" >&2
  fi
}

set_airplane_mode() {
  local enabled="$1"
  if [[ "$enabled" == "1" ]]; then
    adb_shell cmd connectivity airplane-mode enable >/dev/null
    adb_shell settings put global airplane_mode_on 1 >/dev/null
    adb_shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true >/dev/null
  else
    adb_shell cmd connectivity airplane-mode disable >/dev/null
    adb_shell settings put global airplane_mode_on 0 >/dev/null
    adb_shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false >/dev/null
  fi
}

set_wifi_enabled() {
  local enabled="$1"
  if [[ "$enabled" == "1" ]]; then
    adb_shell svc wifi enable >/dev/null
  else
    adb_shell svc wifi disable >/dev/null
  fi
}

set_data_enabled() {
  local enabled="$1"
  if [[ "$enabled" == "1" ]]; then
    adb_shell svc data enable >/dev/null
  else
    adb_shell svc data disable >/dev/null
  fi
}

current_wifi_enabled() {
  local status
  status="$(adb_shell cmd wifi status)"
  if grep -Eiq 'enabled|is on' <<<"$status"; then
    printf '1\n'
  elif grep -Eiq 'disabled|is off' <<<"$status"; then
    printf '0\n'
  else
    printf 'unknown\n'
  fi
}

restore_radio_state() {
  local rc="${1:-0}"
  {
    printf 'restore_started_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'restore_reason_exit_code=%s\n' "$rc"
  } >>"$RADIO_LOG" 2>/dev/null || true

  if [[ "${original_airplane:-unknown}" == "1" ]]; then
    set_airplane_mode 1
  else
    set_airplane_mode 0
  fi

  if [[ "${original_wifi:-unknown}" == "1" ]]; then
    set_wifi_enabled 1
  elif [[ "${original_wifi:-unknown}" == "0" ]]; then
    set_wifi_enabled 0
  fi

  if [[ "${original_mobile_data:-unknown}" == "1" ]]; then
    set_data_enabled 1
  elif [[ "${original_mobile_data:-unknown}" == "0" ]]; then
    set_data_enabled 0
  fi

  {
    printf 'restore_completed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'restored_airplane=%s\n' "$(adb_shell settings get global airplane_mode_on)"
    printf 'restored_wifi=%s\n' "$(current_wifi_enabled)"
    printf 'restored_mobile_data=%s\n' "$(adb_shell settings get global mobile_data)"
  } >>"$RADIO_LOG" 2>/dev/null || true
}

on_exit() {
  local rc=$?
  trap - EXIT INT TERM
  restore_radio_state "$rc"
  if [[ "${uat_pid:-}" != "" ]] && kill -0 "$uat_pid" >/dev/null 2>&1; then
    kill -TERM "$uat_pid" >/dev/null 2>&1 || true
  fi
  exit "$rc"
}

if [[ "$DEVICE_ID" != emulator-* ]]; then
  fail "This UAT mutates Android radio state and is restricted to emulators. Got $DEVICE_ID."
fi
if ! "$ADB_BIN" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  fail "Android emulator $DEVICE_ID is not connected and authorized."
fi

mkdir -p "$SCREENSHOT_DIR"
: >"$RADIO_LOG"
: >"$HARNESS_LOG"

original_airplane="$(adb_shell settings get global airplane_mode_on)"
original_wifi="$(current_wifi_enabled)"
original_mobile_data="$(adb_shell settings get global mobile_data)"
{
  printf 'device_id=%s\n' "$DEVICE_ID"
  printf 'model=%s\n' "$(adb_shell getprop ro.product.model)"
  printf 'android_release=%s\n' "$(adb_shell getprop ro.build.version.release)"
  printf 'android_sdk=%s\n' "$(adb_shell getprop ro.build.version.sdk)"
  printf 'probe_host=%s\n' "$PROBE_HOST"
  printf 'probe_port=%s\n' "$PROBE_PORT"
  printf 'original_airplane=%s\n' "$original_airplane"
  printf 'original_wifi=%s\n' "$original_wifi"
  printf 'original_mobile_data=%s\n' "$original_mobile_data"
} >>"$RADIO_LOG"

trap on_exit EXIT INT TERM

set_airplane_mode 0
set_wifi_enabled 1
set_data_enabled 1
sleep 4

"$FLUTTER" test \
  --no-pub \
  -d "$DEVICE_ID" \
  --flavor "$FLAVOR" \
  --dart-define="COLLECT_NETWORK_UAT_HOST=$PROBE_HOST" \
  --dart-define="COLLECT_NETWORK_UAT_PORT=$PROBE_PORT" \
  "$TEST_TARGET" >"$DEVICE_LOG" 2>&1 &
uat_pid=$!

wait_for_marker 'collect_network_uat:ready-for-radio-loss' "$TIMEOUT_SECONDS" ||
  fail "Network UAT did not reach the ready-for-radio-loss marker."
capture_screenshot "01-online-contribution-route.png"

{
  printf 'loss_started_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'action=disable_airplane_wifi_data\n'
} >>"$RADIO_LOG"
set_wifi_enabled 0
set_data_enabled 0
set_airplane_mode 1
sleep 5

wait_for_marker 'collect_network_uat:radio-loss-observed' 140 ||
  fail "Flutter test did not observe controlled radio loss."
wait_for_marker 'collect_network_uat:stale-cache-offline-ui-visible' 140 ||
  fail "Flutter test did not expose stale-cache/offline UI."
capture_screenshot "02-stale-cache-contribution-route.png"
wait_for_marker 'collect_network_uat:ready-for-radio-restoration' 30 ||
  fail "Flutter test did not request radio restoration."

{
  printf 'restore_for_test_started_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'action=restore_online_for_test\n'
} >>"$RADIO_LOG"
set_airplane_mode 0
set_wifi_enabled 1
set_data_enabled 1
sleep 8

wait_for_marker 'collect_network_uat:authoritative-online-resync-pass' 180 ||
  fail "Flutter test did not confirm authoritative online resync."
capture_screenshot "03-online-resynced-contribution-route.png"

set +e
wait "$uat_pid"
rc=$?
set -e
uat_pid=""

status="pass"
if [[ "$rc" -ne 0 ]] ||
  ! grep -Fq 'collect_network_uat:authoritative-online-resync-pass' "$DEVICE_LOG" ||
  ! grep -Eq 'All tests passed[.!]' "$DEVICE_LOG"; then
  status="fail"
fi

(
  cd "$SCREENSHOT_DIR"
  shasum -a 256 ./*.png 2>/dev/null || true
) >"$SCREENSHOT_DIR/SCREENSHOT_MANIFEST.sha256"

device_log_sha256="$(shasum -a 256 "$DEVICE_LOG" | awk '{print $1}')"
radio_log_sha256="$(shasum -a 256 "$RADIO_LOG" | awk '{print $1}')"
screenshot_manifest_sha256="$(shasum -a 256 "$SCREENSHOT_DIR/SCREENSHOT_MANIFEST.sha256" | awk '{print $1}')"

ANDROID_NETWORK_UAT_STATUS="$status" \
ANDROID_NETWORK_UAT_RC="$rc" \
ANDROID_NETWORK_UAT_DEVICE="$DEVICE_ID" \
ANDROID_NETWORK_UAT_FLAVOR="$FLAVOR" \
ANDROID_NETWORK_UAT_TARGET="$TEST_TARGET" \
ANDROID_NETWORK_UAT_PROBE_HOST="$PROBE_HOST" \
ANDROID_NETWORK_UAT_PROBE_PORT="$PROBE_PORT" \
ANDROID_NETWORK_UAT_DEVICE_LOG="${DEVICE_LOG#$ROOT_DIR/}" \
ANDROID_NETWORK_UAT_DEVICE_LOG_SHA256="$device_log_sha256" \
ANDROID_NETWORK_UAT_RADIO_LOG="${RADIO_LOG#$ROOT_DIR/}" \
ANDROID_NETWORK_UAT_RADIO_LOG_SHA256="$radio_log_sha256" \
ANDROID_NETWORK_UAT_SCREENSHOT_MANIFEST="${SCREENSHOT_DIR#$ROOT_DIR/}/SCREENSHOT_MANIFEST.sha256" \
ANDROID_NETWORK_UAT_SCREENSHOT_MANIFEST_SHA256="$screenshot_manifest_sha256" \
ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => ENV.fetch("ANDROID_NETWORK_UAT_STATUS"),
    "exit_code" => ENV.fetch("ANDROID_NETWORK_UAT_RC").to_i,
    "device" => ENV.fetch("ANDROID_NETWORK_UAT_DEVICE"),
    "flavor" => ENV.fetch("ANDROID_NETWORK_UAT_FLAVOR"),
    "target" => ENV.fetch("ANDROID_NETWORK_UAT_TARGET"),
    "probe" => {
      "host" => ENV.fetch("ANDROID_NETWORK_UAT_PROBE_HOST"),
      "port" => ENV.fetch("ANDROID_NETWORK_UAT_PROBE_PORT").to_i,
      "purpose" => "non-production local reachability probe only"
    },
    "markers" => [
      "collect_network_uat:ready-for-radio-loss",
      "collect_network_uat:radio-loss-observed",
      "collect_network_uat:stale-cache-offline-ui-visible",
      "collect_network_uat:ready-for-radio-restoration",
      "collect_network_uat:authoritative-online-resync-pass"
    ],
    "device_log" => ENV.fetch("ANDROID_NETWORK_UAT_DEVICE_LOG"),
    "device_log_sha256" => ENV.fetch("ANDROID_NETWORK_UAT_DEVICE_LOG_SHA256"),
    "radio_log" => ENV.fetch("ANDROID_NETWORK_UAT_RADIO_LOG"),
    "radio_log_sha256" => ENV.fetch("ANDROID_NETWORK_UAT_RADIO_LOG_SHA256"),
    "screenshot_manifest" => ENV.fetch("ANDROID_NETWORK_UAT_SCREENSHOT_MANIFEST"),
    "screenshot_manifest_sha256" => ENV.fetch("ANDROID_NETWORK_UAT_SCREENSHOT_MANIFEST_SHA256"),
    "secret_handling" => "Uses synthetic fixture/local-cache state and a local non-production TCP reachability probe. No production Supabase mutation, provider payment, real SMS body, OTP, credentials, or customer data is used."
  }
)
RUBY

trap - EXIT INT TERM
restore_radio_state "$rc"

printf '[android-network-restoration-uat] status=%s evidence=%s\n' \
  "$status" "${SUMMARY_FILE#$ROOT_DIR/}" >&2
if [[ "$status" != "pass" ]]; then
  tail -n 160 "$DEVICE_LOG" >&2 || true
  exit 1
fi
