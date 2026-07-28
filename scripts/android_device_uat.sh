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
VARIANT_NAME="${ANDROID_UAT_VARIANT_NAME:-default-dark}"
THEME_MODE="${ANDROID_UAT_THEME_MODE:-dark}"
TEXT_SCALE="${ANDROID_UAT_TEXT_SCALE:-1.0}"
HIGH_CONTRAST="${ANDROID_UAT_HIGH_CONTRAST:-false}"
REDUCED_MOTION="${ANDROID_UAT_REDUCED_MOTION:-false}"
REQUIRE_SCREENSHOTS="${ANDROID_UAT_REQUIRE_SCREENSHOTS:-false}"
export COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY="${COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY:-false}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_UAT_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_device_uat/$timestamp}"
LOG_FILE="$EVIDENCE_DIR/android_device_uat.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
RUNNER_RESULT_FILE="$EVIDENCE_DIR/runner_result.json"
SCREENSHOT_DIR="${ANDROID_UAT_SCREENSHOT_DIR:-$EVIDENCE_DIR/screenshots}"

fail() {
  printf '[android-device-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

write_early_failure_summary() {
  local reason="$1"
  local generated_at
  local log_sha256
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$EVIDENCE_DIR"
  printf '[android-device-uat][FAIL] %s\n' "$reason" >"$LOG_FILE"
  log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
  ANDROID_UAT_GENERATED_AT="$generated_at" \
  ANDROID_UAT_REASON="$reason" \
  ANDROID_UAT_DEVICE_ID="$DEVICE_ID" \
  ANDROID_UAT_FLAVOR="$FLAVOR" \
  ANDROID_UAT_TARGET="$TEST_TARGET" \
  ANDROID_UAT_LOG="${LOG_FILE#$ROOT_DIR/}" \
  ANDROID_UAT_LOG_SHA256="$log_sha256" \
  ANDROID_UAT_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
  ruby -r json <<'RUBY' >"$SUMMARY_FILE"
puts JSON.pretty_generate(
  {
    "generated_at" => ENV.fetch("ANDROID_UAT_GENERATED_AT"),
    "status" => "fail",
    "exit_code" => 1,
    "reason" => ENV.fetch("ANDROID_UAT_REASON"),
    "device" => ENV.fetch("ANDROID_UAT_DEVICE_ID"),
    "device_id" => ENV.fetch("ANDROID_UAT_DEVICE_ID"),
    "device_model" => nil,
    "flavor" => ENV.fetch("ANDROID_UAT_FLAVOR"),
    "target" => ENV.fetch("ANDROID_UAT_TARGET"),
    "runner" => "not_started",
    "log" => ENV.fetch("ANDROID_UAT_LOG"),
    "log_sha256" => ENV.fetch("ANDROID_UAT_LOG_SHA256"),
    "timed_out" => false,
    "timeout_seconds" => ENV.fetch("ANDROID_UAT_TIMEOUT_SECONDS").to_i,
    "secret_handling" => "Device smoke output is retained locally and must not contain raw SMS bodies, phone/MoMo numbers, signing keys, service-role keys, provider tokens, or production customer data."
  }
)
RUBY
}

case "${1:-}" in
  "")
    ;;
  --help|-h)
    printf 'usage: %s\n' "$0"
    printf 'Environment: ADB ANDROID_UAT_DEVICE_ID ANDROID_UAT_FLAVOR ANDROID_UAT_TEST_TARGET ANDROID_UAT_DRIVER ANDROID_UAT_TIMEOUT_SECONDS ANDROID_UAT_EVIDENCE_DIR ANDROID_UAT_SCREENSHOT_DIR ANDROID_UAT_REQUIRE_SCREENSHOTS ANDROID_UAT_VARIANT_NAME ANDROID_UAT_THEME_MODE ANDROID_UAT_TEXT_SCALE ANDROID_UAT_HIGH_CONTRAST ANDROID_UAT_REDUCED_MOTION\n'
    exit 0
    ;;
  *)
    printf 'usage: %s\n' "$0" >&2
    exit 2
    ;;
esac

if ! "$ADB" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  reason="Android device $DEVICE_ID is not connected and authorized over ADB."
  write_early_failure_summary "$reason"
  fail "$reason"
fi

"$ADB" -s "$DEVICE_ID" shell svc power stayon true >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE_ID" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
sleep 1

window_state="$("$ADB" -s "$DEVICE_ID" shell dumpsys window 2>/dev/null || true)"
if grep -q 'mKeyguardShowing=true' <<<"$window_state" ||
  grep -Eiq 'm(CurrentFocus|FocusedApp)=.*(Keyguard|Lockscreen)' <<<"$window_state"; then
  printf '%s\n' "$window_state" |
    rg 'mCurrentFocus|mFocusedApp|mDreamingLockscreen|mKeyguardShowing' >&2 || true
  reason="Android device $DEVICE_ID is locked. Unlock it and keep it awake before running Android UAT."
  write_early_failure_summary "$reason"
  fail "$reason"
fi

mkdir -p "$EVIDENCE_DIR"
if [[ "$REQUIRE_SCREENSHOTS" == "true" ]]; then
  mkdir -p "$SCREENSHOT_DIR"
fi

device_model="$("$ADB" -s "$DEVICE_ID" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
android_release="$("$ADB" -s "$DEVICE_ID" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' || true)"
android_sdk="$("$ADB" -s "$DEVICE_ID" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)"
wm_size="$("$ADB" -s "$DEVICE_ID" shell wm size 2>/dev/null | tr -d '\r' || true)"
wm_density="$("$ADB" -s "$DEVICE_ID" shell wm density 2>/dev/null | tr -d '\r' || true)"
physical_size="$(awk -F': ' '/Physical size:/ { print $2; exit }' <<<"$wm_size")"
override_size="$(awk -F': ' '/Override size:/ { print $2; exit }' <<<"$wm_size")"
physical_density="$(awk -F': ' '/Physical density:/ { print $2; exit }' <<<"$wm_density")"
override_density="$(awk -F': ' '/Override density:/ { print $2; exit }' <<<"$wm_density")"
platform_night_mode="$("$ADB" -s "$DEVICE_ID" shell cmd uimode night 2>/dev/null | tr -d '\r' | sed -E 's/^[^:]+:[[:space:]]*//' || true)"

if [[ -f "$DRIVER" ]]; then
  cmd=(
    "$FLUTTER"
    drive
    --no-pub
    --driver="$DRIVER"
    --target="$TEST_TARGET"
    -d "$DEVICE_ID"
    --flavor "$FLAVOR"
    --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true
    --dart-define="COLLECT_UAT_VARIANT_NAME=$VARIANT_NAME"
    --dart-define="COLLECT_UAT_THEME_MODE=$THEME_MODE"
    --dart-define="COLLECT_UAT_TEXT_SCALE=$TEXT_SCALE"
    --dart-define="COLLECT_UAT_HIGH_CONTRAST=$HIGH_CONTRAST"
    --dart-define="COLLECT_UAT_REDUCED_MOTION=$REDUCED_MOTION"
  )
  runner="drive"
else
  cmd=(
    "$FLUTTER"
    test
    --no-pub
    -d "$DEVICE_ID"
    --flavor "$FLAVOR"
    --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true
    --dart-define="COLLECT_UAT_VARIANT_NAME=$VARIANT_NAME"
    --dart-define="COLLECT_UAT_THEME_MODE=$THEME_MODE"
    --dart-define="COLLECT_UAT_TEXT_SCALE=$TEXT_SCALE"
    --dart-define="COLLECT_UAT_HIGH_CONTRAST=$HIGH_CONTRAST"
    --dart-define="COLLECT_UAT_REDUCED_MOTION=$REDUCED_MOTION"
    "$TEST_TARGET"
  )
  runner="test"
fi

printf '[android-device-uat] adb=%s device=%s flavor=%s target=%s runner=%s variant=%s theme=%s text_scale=%s high_contrast=%s reduced_motion=%s evidence=%s timeout_seconds=%s\n' \
  "$ADB" "$DEVICE_ID" "$FLAVOR" "$TEST_TARGET" "$runner" "$VARIANT_NAME" "$THEME_MODE" "$TEXT_SCALE" "$HIGH_CONTRAST" "$REDUCED_MOTION" "${EVIDENCE_DIR#$ROOT_DIR/}" "$TIMEOUT_SECONDS" >&2

set +e
ANDROID_UAT_LOG_FILE="$LOG_FILE" \
ANDROID_UAT_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
ANDROID_UAT_RUNNER_RESULT_FILE="$RUNNER_RESULT_FILE" \
INTEGRATION_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
ruby -r json -e '
  def kill_process_group_or_pid(signal, pid, errors)
    begin
      Process.kill(signal, -pid)
      return
    rescue Errno::ESRCH
      return
    rescue Errno::EPERM => error
      errors << "#{signal} process-group kill denied: #{error.message}"
    end

    begin
      Process.kill(signal, pid)
    rescue Errno::ESRCH
    rescue Errno::EPERM => error
      errors << "#{signal} direct kill denied: #{error.message}"
    end
  end

  log = ENV.fetch("ANDROID_UAT_LOG_FILE")
  timeout = Integer(ENV.fetch("ANDROID_UAT_TIMEOUT_SECONDS"))
  result = ENV.fetch("ANDROID_UAT_RUNNER_RESULT_FILE")
  started_at = Time.now
  pid = Process.spawn(*ARGV, out: log, err: [:child, :out], pgroup: true)
  timed_out = false
  status = nil
  kill_errors = []

  loop do
    waited_pid, process_status = Process.waitpid2(pid, Process::WNOHANG)
    if waited_pid
      status = process_status
      break
    end

    if Time.now - started_at >= timeout
      timed_out = true
      kill_process_group_or_pid("TERM", pid, kill_errors)
      sleep 2
      kill_process_group_or_pid("KILL", pid, kill_errors)
      begin
        _waited_pid, process_status = Process.waitpid2(pid)
        status = process_status
      rescue Errno::ECHILD
      end
      break
    end

    sleep 5
  end

  exit_code =
    if timed_out
      124
    elsif status
      status.exitstatus || (status.termsig ? 128 + status.termsig : 1)
    else
      1
    end

  File.write(
    result,
    JSON.pretty_generate(
      {
        "exit_code" => exit_code,
        "timed_out" => timed_out,
        "pid" => pid,
        "timeout_seconds" => timeout,
        "kill_errors" => kill_errors
      }
    ) + "\n"
  )
  exit(exit_code)
' -- "${cmd[@]}"
rc=$?
set -e

timed_out="$(ruby -r json -e 'path = ARGV.fetch(0); data = File.exist?(path) ? JSON.parse(File.read(path)) : {}; puts(data["timed_out"] ? "1" : "0")' "$RUNNER_RESULT_FILE")"

if [[ "$timed_out" == "1" ]]; then
  rc=124
fi

log_failed=0
if [[ -f "$LOG_FILE" ]] && grep -Eq 'Some tests failed|Test failed\.|TimeoutException after|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' "$LOG_FILE"; then
  log_failed=1
  if [[ "$rc" -eq 0 ]]; then
    rc=1
  fi
fi

completion_marker=0
if [[ -f "$LOG_FILE" ]] && grep -Eq 'All tests passed[.!]' "$LOG_FILE"; then
  completion_marker=1
else
  printf '[android-device-uat][FAIL] Flutter runner did not emit an All tests passed completion marker.\n' >>"$LOG_FILE"
  if [[ "$rc" -eq 0 ]]; then
    rc=1
  fi
fi

route_expected=0
route_passes=0
screenshot_count=0
screenshot_manifest_sha256=""
if [[ "$TEST_TARGET" == *"mobile_route_matrix_device_uat_test.dart" ]]; then
  route_expected="$(awk '/^  _RouteSpec\(/ { count += 1 } END { print count + 0 }' "$TEST_TARGET")"
  route_passes="$(grep -c 'collect_route_uat:pass:' "$LOG_FILE" || true)"
  if [[ "$route_expected" -eq 0 || "$route_passes" -ne "$route_expected" ]]; then
    printf '[android-device-uat][FAIL] Route completion mismatch: expected=%s passed=%s.\n' \
      "$route_expected" "$route_passes" >>"$LOG_FILE"
    if [[ "$rc" -eq 0 ]]; then
      rc=1
    fi
  fi
  if [[ -d "$SCREENSHOT_DIR" ]]; then
    screenshot_count="$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name 'mobile_route_*.png' | wc -l | tr -d ' ')"
  fi
  if [[ -f "$SCREENSHOT_DIR/screenshots.jsonl" ]]; then
    screenshot_manifest_sha256="$(shasum -a 256 "$SCREENSHOT_DIR/screenshots.jsonl" | awk '{print $1}')"
  fi
  if [[ "$REQUIRE_SCREENSHOTS" == "true" && "$screenshot_count" -ne "$route_expected" ]]; then
    printf '[android-device-uat][FAIL] Screenshot completion mismatch: expected=%s captured=%s.\n' \
      "$route_expected" "$screenshot_count" >>"$LOG_FILE"
    if [[ "$rc" -eq 0 ]]; then
      rc=1
    fi
  fi
fi

device_locked_after_run=0
post_window_state="$("$ADB" -s "$DEVICE_ID" shell dumpsys window 2>/dev/null || true)"
if grep -q 'mKeyguardShowing=true' <<<"$post_window_state" ||
  grep -Eiq 'm(CurrentFocus|FocusedApp)=.*(Keyguard|Lockscreen|NotificationShade)' <<<"$post_window_state" ||
  grep -q 'mDreamingLockscreen=true' <<<"$post_window_state"; then
  device_locked_after_run=1
  printf '[android-device-uat][FAIL] Android device locked or covered by the system shade during UAT.\n' >>"$LOG_FILE"
  if [[ "$rc" -eq 0 ]]; then
    rc=1
  fi
fi

log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
status="pass"
if [[ "$timed_out" == "1" ]]; then
  status="timeout"
elif [[ "$rc" -ne 0 || "$log_failed" == "1" ]]; then
  status="fail"
fi

ANDROID_UAT_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
ANDROID_UAT_STATUS="$status" \
ANDROID_UAT_RC="$rc" \
ANDROID_UAT_DEVICE_ID="$DEVICE_ID" \
ANDROID_UAT_DEVICE_MODEL="$device_model" \
ANDROID_UAT_ANDROID_RELEASE="$android_release" \
ANDROID_UAT_ANDROID_SDK="$android_sdk" \
ANDROID_UAT_PHYSICAL_SIZE="$physical_size" \
ANDROID_UAT_OVERRIDE_SIZE="$override_size" \
ANDROID_UAT_PHYSICAL_DENSITY="$physical_density" \
ANDROID_UAT_OVERRIDE_DENSITY="$override_density" \
ANDROID_UAT_PLATFORM_NIGHT_MODE="$platform_night_mode" \
ANDROID_UAT_FLAVOR="$FLAVOR" \
ANDROID_UAT_TARGET="$TEST_TARGET" \
ANDROID_UAT_RUNNER="$runner" \
ANDROID_UAT_VARIANT_NAME="$VARIANT_NAME" \
ANDROID_UAT_THEME_MODE="$THEME_MODE" \
ANDROID_UAT_TEXT_SCALE="$TEXT_SCALE" \
ANDROID_UAT_HIGH_CONTRAST="$HIGH_CONTRAST" \
ANDROID_UAT_REDUCED_MOTION="$REDUCED_MOTION" \
ANDROID_UAT_LOG="${LOG_FILE#$ROOT_DIR/}" \
ANDROID_UAT_LOG_SHA256="$log_sha256" \
ANDROID_UAT_TIMED_OUT="$timed_out" \
ANDROID_UAT_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
ANDROID_UAT_COMPLETION_MARKER="$completion_marker" \
ANDROID_UAT_ROUTE_EXPECTED="$route_expected" \
ANDROID_UAT_ROUTE_PASSES="$route_passes" \
ANDROID_UAT_REQUIRE_SCREENSHOTS="$REQUIRE_SCREENSHOTS" \
ANDROID_UAT_SCREENSHOT_DIR="${SCREENSHOT_DIR#$ROOT_DIR/}" \
ANDROID_UAT_SCREENSHOT_COUNT="$screenshot_count" \
ANDROID_UAT_SCREENSHOT_MANIFEST_SHA256="$screenshot_manifest_sha256" \
ANDROID_UAT_DEVICE_LOCKED_AFTER_RUN="$device_locked_after_run" \
ruby -r json <<'RUBY' >"$SUMMARY_FILE"
puts JSON.pretty_generate(
  {
    "generated_at" => ENV.fetch("ANDROID_UAT_GENERATED_AT"),
    "status" => ENV.fetch("ANDROID_UAT_STATUS"),
    "exit_code" => ENV.fetch("ANDROID_UAT_RC").to_i,
    "device" => ENV.fetch("ANDROID_UAT_DEVICE_ID"),
    "device_id" => ENV.fetch("ANDROID_UAT_DEVICE_ID"),
    "device_model" => ENV.fetch("ANDROID_UAT_DEVICE_MODEL"),
    "android_release" => ENV.fetch("ANDROID_UAT_ANDROID_RELEASE"),
    "android_sdk" => ENV.fetch("ANDROID_UAT_ANDROID_SDK").to_i,
    "display" => {
      "physical_size" => ENV.fetch("ANDROID_UAT_PHYSICAL_SIZE"),
      "override_size" => ENV.fetch("ANDROID_UAT_OVERRIDE_SIZE"),
      "physical_density" => ENV.fetch("ANDROID_UAT_PHYSICAL_DENSITY").to_i,
      "override_density" => ENV.fetch("ANDROID_UAT_OVERRIDE_DENSITY").to_i,
      "platform_night_mode" => ENV.fetch("ANDROID_UAT_PLATFORM_NIGHT_MODE")
    },
    "flavor" => ENV.fetch("ANDROID_UAT_FLAVOR"),
    "target" => ENV.fetch("ANDROID_UAT_TARGET"),
    "runner" => ENV.fetch("ANDROID_UAT_RUNNER"),
    "variant" => {
      "name" => ENV.fetch("ANDROID_UAT_VARIANT_NAME"),
      "theme_mode" => ENV.fetch("ANDROID_UAT_THEME_MODE"),
      "text_scale" => ENV.fetch("ANDROID_UAT_TEXT_SCALE").to_f,
      "high_contrast" => ENV.fetch("ANDROID_UAT_HIGH_CONTRAST") == "true",
      "reduced_motion" => ENV.fetch("ANDROID_UAT_REDUCED_MOTION") == "true"
    },
    "log" => ENV.fetch("ANDROID_UAT_LOG"),
    "log_sha256" => ENV.fetch("ANDROID_UAT_LOG_SHA256"),
    "timed_out" => ENV.fetch("ANDROID_UAT_TIMED_OUT") == "1",
    "timeout_seconds" => ENV.fetch("ANDROID_UAT_TIMEOUT_SECONDS").to_i,
    "completion_marker" => ENV.fetch("ANDROID_UAT_COMPLETION_MARKER") == "1",
    "route_expected" => ENV.fetch("ANDROID_UAT_ROUTE_EXPECTED").to_i,
    "route_passes" => ENV.fetch("ANDROID_UAT_ROUTE_PASSES").to_i,
    "screenshots" => {
      "required" => ENV.fetch("ANDROID_UAT_REQUIRE_SCREENSHOTS") == "true",
      "directory" => ENV.fetch("ANDROID_UAT_SCREENSHOT_DIR"),
      "count" => ENV.fetch("ANDROID_UAT_SCREENSHOT_COUNT").to_i,
      "manifest_sha256" => ENV.fetch("ANDROID_UAT_SCREENSHOT_MANIFEST_SHA256")
    },
    "device_locked_after_run" => ENV.fetch("ANDROID_UAT_DEVICE_LOCKED_AFTER_RUN") == "1",
    "secret_handling" => "Device smoke output is retained locally and must not contain raw SMS bodies, phone/MoMo numbers, signing keys, service-role keys, provider tokens, or production customer data."
  }
)
RUBY

printf '[android-device-uat] status=%s evidence=%s log=%s\n' \
  "$status" "${SUMMARY_FILE#$ROOT_DIR/}" "${LOG_FILE#$ROOT_DIR/}" >&2
cat "$LOG_FILE"
exit "$rc"
