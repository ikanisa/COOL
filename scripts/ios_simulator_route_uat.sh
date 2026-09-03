#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-$(command -v flutter || true)}"
XCRUN="${XCRUN:-/usr/bin/xcrun}"
DEVICE_ID="${IOS_UAT_SIMULATOR_ID:-}"
CONFIRMED_DISPOSABLE_DEVICE_ID="${IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR:-}"
TEST_TARGET="${IOS_UAT_TEST_TARGET:-integration_test/mobile_route_matrix_device_uat_test.dart}"
DRIVER="${IOS_UAT_DRIVER:-test_driver/integration_test.dart}"
TIMEOUT_SECONDS="${IOS_UAT_TIMEOUT_SECONDS:-900}"
BUNDLE_ID="${IOS_UAT_BUNDLE_ID:-app.cool.mobile}"
MODE="${IOS_UAT_MODE:-route}"
VARIANT_NAME="${IOS_UAT_VARIANT_NAME:-default-dark}"
THEME_MODE="${IOS_UAT_THEME_MODE:-dark}"
TEXT_SCALE="${IOS_UAT_TEXT_SCALE:-1.0}"
HIGH_CONTRAST="${IOS_UAT_HIGH_CONTRAST:-false}"
REDUCED_MOTION="${IOS_UAT_REDUCED_MOTION:-false}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${IOS_UAT_EVIDENCE_DIR:-$ROOT_DIR/.cache/ios_simulator_route_uat/$timestamp}"
LOG_FILE="$EVIDENCE_DIR/ios_simulator_route_uat.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
RUNNER_RESULT_FILE="$EVIDENCE_DIR/runner_result.json"
SCREENSHOT_DIR="$EVIDENCE_DIR/screenshots"
SCREENSHOT_MANIFEST="$SCREENSHOT_DIR/screenshots.jsonl"

fail() {
  printf '[ios-simulator-route-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

simulator_inventory() {
  "$XCRUN" simctl list devices --json
}

resolve_booted_simulator() {
  simulator_inventory |
    ruby -r json -e '
      data = JSON.parse($stdin.read)
      data.fetch("devices", {}).each_value do |devices|
        device = Array(devices).find do |item|
          item["state"] == "Booted" && item.fetch("isAvailable", true)
        end
        if device
          puts device.fetch("udid")
          exit 0
        end
      end
      exit 1
    '
}

simulator_metadata() {
  local simulator_id="$1"
  simulator_inventory |
    ruby -r json -e '
      lookup = ARGV.fetch(0)
      data = JSON.parse($stdin.read)
      data.fetch("devices", {}).each do |runtime, devices|
        device = Array(devices).find { |item| item["udid"] == lookup }
        next unless device
        puts JSON.generate(
          {
            "udid" => device["udid"],
            "name" => device["name"],
            "state" => device["state"],
            "runtime" => runtime,
            "available" => device.fetch("isAvailable", true)
          }
        )
        exit 0
      end
      exit 1
    ' "$simulator_id"
}

write_early_failure_summary() {
  local reason="$1"
  local simulator_json="${2:-}"
  if [[ -z "$simulator_json" ]]; then
    simulator_json='{}'
  fi
  mkdir -p "$EVIDENCE_DIR"
  printf '[ios-simulator-route-uat][FAIL] %s\n' "$reason" >"$LOG_FILE"
  local log_sha256
  log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
  IOS_UAT_REASON="$reason" \
  IOS_UAT_SIMULATOR_JSON="$simulator_json" \
  IOS_UAT_TARGET="$TEST_TARGET" \
  IOS_UAT_MODE="$MODE" \
  IOS_UAT_LOG="${LOG_FILE#$ROOT_DIR/}" \
  IOS_UAT_LOG_SHA256="$log_sha256" \
  IOS_UAT_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
  IOS_UAT_VARIANT_NAME="$VARIANT_NAME" \
  IOS_UAT_THEME_MODE="$THEME_MODE" \
  IOS_UAT_TEXT_SCALE="$TEXT_SCALE" \
  IOS_UAT_HIGH_CONTRAST="$HIGH_CONTRAST" \
  IOS_UAT_REDUCED_MOTION="$REDUCED_MOTION" \
  ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
simulator = JSON.parse(ENV.fetch("IOS_UAT_SIMULATOR_JSON", "{}")) rescue {}
puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => "fail",
    "exit_code" => 1,
    "reason" => ENV.fetch("IOS_UAT_REASON"),
    "simulator" => simulator,
    "target" => ENV.fetch("IOS_UAT_TARGET"),
    "evidence_mode" => ENV.fetch("IOS_UAT_MODE", "route"),
    "runner" => "not_started",
    "log" => ENV.fetch("IOS_UAT_LOG"),
    "log_sha256" => ENV.fetch("IOS_UAT_LOG_SHA256"),
    "timed_out" => false,
    "timeout_seconds" => ENV.fetch("IOS_UAT_TIMEOUT_SECONDS").to_i,
    "variant" => {
      "name" => ENV.fetch("IOS_UAT_VARIANT_NAME"),
      "theme_mode" => ENV.fetch("IOS_UAT_THEME_MODE"),
      "text_scale" => ENV.fetch("IOS_UAT_TEXT_SCALE").to_f,
      "high_contrast" => ENV.fetch("IOS_UAT_HIGH_CONTRAST") == "true",
      "reduced_motion" => ENV.fetch("IOS_UAT_REDUCED_MOTION") == "true"
    },
    "completion_marker" => false,
    "item_expected" => 0,
    "item_passes" => 0,
    "screenshot_count" => 0,
    "secret_handling" => "Synthetic fixture IDs, phone numbers and payment details may appear. Never retain secrets, customer SMS, production/customer phone or payment data, signing keys, service-role keys or provider tokens."
  }
)
RUBY
}

case "${1:-}" in
  "")
    ;;
  --help|-h)
    printf 'usage: %s\n' "$0"
    printf 'Environment: FLUTTER XCRUN IOS_UAT_SIMULATOR_ID IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR IOS_UAT_TEST_TARGET IOS_UAT_DRIVER IOS_UAT_TIMEOUT_SECONDS IOS_UAT_BUNDLE_ID IOS_UAT_EVIDENCE_DIR IOS_UAT_MODE IOS_UAT_VARIANT_NAME IOS_UAT_THEME_MODE IOS_UAT_TEXT_SCALE IOS_UAT_HIGH_CONTRAST IOS_UAT_REDUCED_MOTION\n'
    printf 'This fixture runner uninstalls the app. Confirm only an approved disposable simulator by setting IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR to its exact UDID. Never target an existing signed-in app.\n'
    exit 0
    ;;
  *)
    printf 'usage: %s\n' "$0" >&2
    exit 2
    ;;
esac

case "$THEME_MODE" in
  light|dark|system) ;;
  *) fail "IOS_UAT_THEME_MODE must be light, dark, or system." ;;
esac
case "$MODE" in
  route)
    marker_namespace="collect_route_uat"
    pass_marker="collect_route_uat:pass:"
    variant_marker_prefix="collect_route_uat:variant:"
    spec_token="_RouteSpec("
    screenshot_prefix="mobile_route_"
    ;;
  state)
    marker_namespace="collect_state_uat"
    pass_marker="collect_state_uat:pass:"
    variant_marker_prefix="collect_state_uat:variant:"
    spec_token="_StateSpec("
    screenshot_prefix="mobile_state_"
    ;;
  *) fail "IOS_UAT_MODE must be route or state." ;;
esac
case "$HIGH_CONTRAST" in
  true|false) ;;
  *) fail "IOS_UAT_HIGH_CONTRAST must be true or false." ;;
esac
case "$REDUCED_MOTION" in
  true|false) ;;
  *) fail "IOS_UAT_REDUCED_MOTION must be true or false." ;;
esac
if ! ruby -e 'value = Float(ARGV.fetch(0)); exit(value >= 1.0 && value <= 3.2 ? 0 : 1)' "$TEXT_SCALE"; then
  fail "IOS_UAT_TEXT_SCALE must be a number from 1.0 through 3.2."
fi

if [[ -z "$FLUTTER" || ! -x "$FLUTTER" ]]; then
  reason="Flutter executable is unavailable."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ ! -x "$XCRUN" ]]; then
  reason="xcrun is unavailable."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ ! -f "$TEST_TARGET" ]]; then
  reason="iOS route UAT target is missing: $TEST_TARGET"
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ ! -f "$DRIVER" ]]; then
  reason="iOS route UAT screenshot driver is missing: $DRIVER"
  write_early_failure_summary "$reason"
  fail "$reason"
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(resolve_booted_simulator || true)"
fi
if [[ -z "$DEVICE_ID" ]]; then
  reason="No available booted iOS Simulator was found. Boot the intended simulator or set IOS_UAT_SIMULATOR_ID."
  write_early_failure_summary "$reason"
  fail "$reason"
fi

simulator_before="$(simulator_metadata "$DEVICE_ID" || true)"
if [[ -z "$simulator_before" ]]; then
  reason="iOS Simulator $DEVICE_ID is not present in the current simulator inventory."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ "$(ruby -r json -e 'puts JSON.parse(ARGV.fetch(0))["state"]' "$simulator_before")" != "Booted" ]]; then
  reason="iOS Simulator $DEVICE_ID is not booted."
  write_early_failure_summary "$reason" "$simulator_before"
  fail "$reason"
fi

if [[ "$CONFIRMED_DISPOSABLE_DEVICE_ID" != "$DEVICE_ID" ]]; then
  reason="Refusing app uninstall: IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR must match the exact approved disposable simulator UDID."
  write_early_failure_summary "$reason" "$simulator_before"
  fail "$reason"
fi

mkdir -p "$SCREENSHOT_DIR"
rm -f "$SCREENSHOT_MANIFEST"

# A stale installed evidence build must never be reused after a compile or
# launch failure. The route run is fixture-only and rebuilds the app below.
"$XCRUN" simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
"$XCRUN" simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

cmd=(
  bash
  "$ROOT_DIR/scripts/ios_uat_build_and_drive.sh"
  "$FLUTTER"
  "$DRIVER"
  "$TEST_TARGET"
  "$DEVICE_ID"
  "$BUNDLE_ID"
  "$ROOT_DIR/build/ios/iphonesimulator/Collect.app"
  --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true
  --dart-define="COLLECT_UAT_VARIANT_NAME=$VARIANT_NAME"
  --dart-define="COLLECT_UAT_THEME_MODE=$THEME_MODE"
  --dart-define="COLLECT_UAT_TEXT_SCALE=$TEXT_SCALE"
  --dart-define="COLLECT_UAT_HIGH_CONTRAST=$HIGH_CONTRAST"
  --dart-define="COLLECT_UAT_REDUCED_MOTION=$REDUCED_MOTION"
)

printf '[ios-simulator-route-uat] simulator=%s target=%s evidence=%s timeout_seconds=%s variant=%s theme=%s text_scale=%s high_contrast=%s reduced_motion=%s\n' \
  "$DEVICE_ID" "$TEST_TARGET" "${EVIDENCE_DIR#$ROOT_DIR/}" "$TIMEOUT_SECONDS" \
  "$VARIANT_NAME" "$THEME_MODE" "$TEXT_SCALE" "$HIGH_CONTRAST" "$REDUCED_MOTION" >&2

set +e
IOS_UAT_LOG_FILE="$LOG_FILE" \
IOS_UAT_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
IOS_UAT_RUNNER_RESULT_FILE="$RUNNER_RESULT_FILE" \
INTEGRATION_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
ruby -r json -r pty -e '
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

  log = ENV.fetch("IOS_UAT_LOG_FILE")
  timeout = Integer(ENV.fetch("IOS_UAT_TIMEOUT_SECONDS"))
  result = ENV.fetch("IOS_UAT_RUNNER_RESULT_FILE")
  started_at = Time.now
  reader, writer, pid = PTY.spawn(ENV.to_h, *ARGV)
  writer.close
  log_io = File.open(log, "wb")
  reader_thread = Thread.new do
    begin
      loop do
        log_io.write(reader.readpartial(16_384))
        log_io.flush
      end
    rescue EOFError, Errno::EIO
    ensure
      reader.close unless reader.closed?
      log_io.close unless log_io.closed?
    end
  end
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
  unless reader_thread.join(5)
    reader.close unless reader.closed?
    reader_thread.join(1)
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

timed_out="$(
  ruby -r json -e '
    data = File.exist?(ARGV.fetch(0)) ? JSON.parse(File.read(ARGV.fetch(0))) : {}
    puts(data["timed_out"] ? "1" : "0")
  ' "$RUNNER_RESULT_FILE"
)"
if [[ "$timed_out" == "1" ]]; then
  rc=124
fi

log_failed=0
if grep -Eq 'Some tests failed|Test failed\.|TimeoutException after|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' "$LOG_FILE"; then
  log_failed=1
  [[ "$rc" -eq 0 ]] && rc=1
fi

build_failed=0
if grep -Eq 'Failed to build iOS app|Error \(Xcode\):|\[ios-uat-build\]\[FAIL\]' "$LOG_FILE"; then
  build_failed=1
  [[ "$rc" -eq 0 ]] && rc=1
fi
if ! grep -Fq '[ios-uat-build] fresh-build-ready' "$LOG_FILE"; then
  build_failed=1
  [[ "$rc" -eq 0 ]] && rc=1
fi

completion_marker=0
if grep -Eq 'All tests passed[.!]' "$LOG_FILE"; then
  completion_marker=1
else
  printf '[ios-simulator-route-uat][FAIL] Flutter driver did not emit an All tests passed completion marker.\n' >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi

variant_marker=0
observed_variant_marker="$(
  grep -o "$variant_marker_prefix[^[:space:]]*" "$LOG_FILE" |
    tail -1 ||
    true
)"
if grep -Fq "$variant_marker_prefix$VARIANT_NAME:theme=$THEME_MODE:" "$LOG_FILE"; then
  variant_marker=1
else
  printf '[ios-simulator-route-uat][FAIL] Flutter driver did not emit the expected variant marker.\n' >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi

item_expected="$(awk -v token="$spec_token" 'index($0, token) == 3 { count += 1 } END { print count + 0 }' "$TEST_TARGET")"
item_passes="$(grep -c "$pass_marker" "$LOG_FILE" || true)"
if [[ "$item_expected" -eq 0 || "$item_passes" -ne "$item_expected" ]]; then
  printf '[ios-simulator-route-uat][FAIL] %s completion mismatch: expected=%s passed=%s.\n' \
    "$MODE" "$item_expected" "$item_passes" >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi

screenshot_count="$(find "$SCREENSHOT_DIR" -type f -name "${screenshot_prefix}*.png" | wc -l | tr -d ' ')"
screenshot_manifest_rows=0
if [[ -f "$SCREENSHOT_MANIFEST" ]]; then
  screenshot_manifest_rows="$(wc -l <"$SCREENSHOT_MANIFEST" | tr -d ' ')"
fi
if [[ "$screenshot_count" -ne "$item_expected" || "$screenshot_manifest_rows" -ne "$item_expected" ]]; then
  printf '[ios-simulator-route-uat][FAIL] Screenshot completion mismatch: expected=%s png=%s manifest=%s.\n' \
    "$item_expected" "$screenshot_count" "$screenshot_manifest_rows" >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi

small_screenshot_count="$(
  find "$SCREENSHOT_DIR" -type f -name "${screenshot_prefix}*.png" -size -8001c | wc -l | tr -d ' '
)"
if [[ "$small_screenshot_count" -ne 0 ]]; then
  printf '[ios-simulator-route-uat][FAIL] %s screenshots are smaller than the 8,001-byte evidence floor.\n' \
    "$small_screenshot_count" >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi

unique_screenshot_count="$(
  find "$SCREENSHOT_DIR" -type f -name "${screenshot_prefix}*.png" -print0 |
    xargs -0 shasum -a 256 2>/dev/null |
    awk '{print $1}' |
    sort -u |
    wc -l |
    tr -d ' '
)"
if [[ "$MODE" == "route" ]]; then
  visual_audit="$EVIDENCE_DIR/visual_destinations.json"
  if ! ruby "$ROOT_DIR/scripts/verify_native_route_screenshots.rb" "$SCREENSHOT_DIR" >"$visual_audit"; then
    printf '[ios-simulator-route-uat][FAIL] Unexpected duplicate visual destinations.\n' >>"$LOG_FILE"
    [[ "$rc" -eq 0 ]] && rc=1
  fi
  minimum_unique_screenshots="$(ruby -r json -e 'puts JSON.parse(File.read(ARGV[0])).fetch("minimum_distinct_destinations")' "$visual_audit")"
else
  # Every material state differs visibly; duplicate frames cannot stand in for
  # confirmation dialogs, entered values, validation errors or enabled actions.
  minimum_unique_screenshots="$item_expected"
fi
if [[ "$minimum_unique_screenshots" -lt 1 ]]; then
  minimum_unique_screenshots=1
fi
if [[ "$unique_screenshot_count" -lt "$minimum_unique_screenshots" ]]; then
  printf '[ios-simulator-route-uat][FAIL] Screenshot diversity is too low: minimum=%s unique=%s.\n' \
    "$minimum_unique_screenshots" "$unique_screenshot_count" >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi

simulator_after="$(simulator_metadata "$DEVICE_ID" || true)"
simulator_booted_after=0
if [[ -n "$simulator_after" ]] &&
  [[ "$(ruby -r json -e 'puts JSON.parse(ARGV.fetch(0))["state"]' "$simulator_after")" == "Booted" ]]; then
  simulator_booted_after=1
else
  printf '[ios-simulator-route-uat][FAIL] Simulator was not booted after the route run.\n' >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi
if [[ -z "$simulator_after" ]]; then
  simulator_after='{}'
fi

log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
screenshot_manifest_sha256=""
if [[ -f "$SCREENSHOT_MANIFEST" ]]; then
  screenshot_manifest_sha256="$(shasum -a 256 "$SCREENSHOT_MANIFEST" | awk '{print $1}')"
fi

status="pass"
if [[ "$timed_out" == "1" ]]; then
  status="timeout"
elif [[ "$rc" -ne 0 || "$log_failed" == "1" ]]; then
  status="fail"
fi

IOS_UAT_STATUS="$status" \
IOS_UAT_RC="$rc" \
IOS_UAT_SIMULATOR_BEFORE="$simulator_before" \
IOS_UAT_SIMULATOR_AFTER="$simulator_after" \
IOS_UAT_TARGET="$TEST_TARGET" \
IOS_UAT_MODE="$MODE" \
IOS_UAT_LOG="${LOG_FILE#$ROOT_DIR/}" \
IOS_UAT_LOG_SHA256="$log_sha256" \
IOS_UAT_TIMED_OUT="$timed_out" \
IOS_UAT_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
IOS_UAT_BUILD_FAILED="$build_failed" \
IOS_UAT_LOG_FAILED="$log_failed" \
IOS_UAT_COMPLETION_MARKER="$completion_marker" \
IOS_UAT_VARIANT_MARKER="$variant_marker" \
IOS_UAT_OBSERVED_VARIANT_MARKER="$observed_variant_marker" \
IOS_UAT_VARIANT_NAME="$VARIANT_NAME" \
IOS_UAT_THEME_MODE="$THEME_MODE" \
IOS_UAT_TEXT_SCALE="$TEXT_SCALE" \
IOS_UAT_HIGH_CONTRAST="$HIGH_CONTRAST" \
IOS_UAT_REDUCED_MOTION="$REDUCED_MOTION" \
IOS_UAT_ITEM_EXPECTED="$item_expected" \
IOS_UAT_ITEM_PASSES="$item_passes" \
IOS_UAT_SCREENSHOT_COUNT="$screenshot_count" \
IOS_UAT_SCREENSHOT_MANIFEST="${SCREENSHOT_MANIFEST#$ROOT_DIR/}" \
IOS_UAT_SCREENSHOT_MANIFEST_SHA256="$screenshot_manifest_sha256" \
IOS_UAT_SMALL_SCREENSHOT_COUNT="$small_screenshot_count" \
IOS_UAT_UNIQUE_SCREENSHOT_COUNT="$unique_screenshot_count" \
IOS_UAT_MINIMUM_UNIQUE_SCREENSHOTS="$minimum_unique_screenshots" \
IOS_UAT_SIMULATOR_BOOTED_AFTER="$simulator_booted_after" \
ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
status = ENV.fetch("IOS_UAT_STATUS")
mode = ENV.fetch("IOS_UAT_MODE", "route")
build_failed = ENV.fetch("IOS_UAT_BUILD_FAILED") == "1"
log_failed = ENV.fetch("IOS_UAT_LOG_FAILED") == "1"
completion_marker = ENV.fetch("IOS_UAT_COMPLETION_MARKER") == "1"
variant_marker = ENV.fetch("IOS_UAT_VARIANT_MARKER") == "1"
item_expected = ENV.fetch("IOS_UAT_ITEM_EXPECTED").to_i
item_passes = ENV.fetch("IOS_UAT_ITEM_PASSES").to_i
screenshot_count = ENV.fetch("IOS_UAT_SCREENSHOT_COUNT").to_i
screenshot_manifest_sha256 = ENV.fetch("IOS_UAT_SCREENSHOT_MANIFEST_SHA256")
small_screenshot_count = ENV.fetch("IOS_UAT_SMALL_SCREENSHOT_COUNT").to_i
unique_screenshot_count = ENV.fetch("IOS_UAT_UNIQUE_SCREENSHOT_COUNT").to_i
minimum_unique_screenshots = ENV.fetch("IOS_UAT_MINIMUM_UNIQUE_SCREENSHOTS").to_i
simulator_booted_after = ENV.fetch("IOS_UAT_SIMULATOR_BOOTED_AFTER") == "1"
failure_keys = []
failure_keys << "runner_timeout" if ENV.fetch("IOS_UAT_TIMED_OUT") == "1"
failure_keys << "native_build_failed" if build_failed
failure_keys << "flutter_test_failure" if log_failed
failure_keys << "completion_marker_missing" unless completion_marker
failure_keys << "variant_marker_mismatch" unless variant_marker
failure_keys << "#{mode}_completion_mismatch" unless item_expected.positive? && item_passes == item_expected
failure_keys << "screenshot_completion_mismatch" unless screenshot_count == item_expected && !screenshot_manifest_sha256.empty?
failure_keys << "screenshot_size_floor" if small_screenshot_count.positive?
failure_keys << "screenshot_diversity" if unique_screenshot_count < minimum_unique_screenshots
failure_keys << "simulator_not_booted_after" unless simulator_booted_after
failure_keys << "runner_exit" if ENV.fetch("IOS_UAT_RC").to_i != 0 && failure_keys.empty?

puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => status,
    "exit_code" => ENV.fetch("IOS_UAT_RC").to_i,
    "evidence_accepted" => status == "pass" && failure_keys.empty?,
    "failure_keys" => failure_keys,
    "simulator_before" => JSON.parse(ENV.fetch("IOS_UAT_SIMULATOR_BEFORE")),
    "simulator_after" => JSON.parse(ENV.fetch("IOS_UAT_SIMULATOR_AFTER", "{}")),
    "target" => ENV.fetch("IOS_UAT_TARGET"),
    "evidence_mode" => mode,
    "runner" => "drive",
    "log" => ENV.fetch("IOS_UAT_LOG"),
    "log_sha256" => ENV.fetch("IOS_UAT_LOG_SHA256"),
    "timed_out" => ENV.fetch("IOS_UAT_TIMED_OUT") == "1",
    "timeout_seconds" => ENV.fetch("IOS_UAT_TIMEOUT_SECONDS").to_i,
    "build_failed" => build_failed,
    "log_failed" => log_failed,
    "completion_marker" => completion_marker,
    "variant_marker" => variant_marker,
    "observed_variant_marker" => ENV.fetch("IOS_UAT_OBSERVED_VARIANT_MARKER", ""),
    "variant" => {
      "name" => ENV.fetch("IOS_UAT_VARIANT_NAME"),
      "theme_mode" => ENV.fetch("IOS_UAT_THEME_MODE"),
      "text_scale" => ENV.fetch("IOS_UAT_TEXT_SCALE").to_f,
      "high_contrast" => ENV.fetch("IOS_UAT_HIGH_CONTRAST") == "true",
      "reduced_motion" => ENV.fetch("IOS_UAT_REDUCED_MOTION") == "true"
    },
    "item_expected" => item_expected,
    "item_passes" => item_passes,
    "route_expected" => mode == "route" ? item_expected : nil,
    "route_passes" => mode == "route" ? item_passes : nil,
    "state_expected" => mode == "state" ? item_expected : nil,
    "state_passes" => mode == "state" ? item_passes : nil,
    "screenshot_count" => screenshot_count,
    "screenshot_manifest" => ENV.fetch("IOS_UAT_SCREENSHOT_MANIFEST"),
    "screenshot_manifest_sha256" => screenshot_manifest_sha256,
    "small_screenshot_count" => small_screenshot_count,
    "unique_screenshot_count" => unique_screenshot_count,
    "minimum_unique_screenshots" => minimum_unique_screenshots,
    "simulator_booted_after" => simulator_booted_after,
    "secret_handling" => "Synthetic fixture IDs, phone numbers and payment details may appear. Never retain secrets, customer SMS, production/customer phone or payment data, signing keys, service-role keys or provider tokens."
  }
)
RUBY

printf '[ios-simulator-route-uat] status=%s evidence=%s log=%s screenshots=%s/%s\n' \
  "$status" "${SUMMARY_FILE#$ROOT_DIR/}" "${LOG_FILE#$ROOT_DIR/}" "$screenshot_count" "$item_expected" >&2
cat "$LOG_FILE"
exit "$rc"
