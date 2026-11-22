#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-$(command -v flutter || true)}"
XCRUN="${XCRUN:-/usr/bin/xcrun}"
XCODEBUILD="${XCODEBUILD:-/usr/bin/xcodebuild}"
DEVICE_ID="${IOS_CAMERA_UAT_SIMULATOR_ID:-}"
CONFIRMED_DISPOSABLE_DEVICE_ID="${IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR:-}"
FLAVOR="${IOS_CAMERA_UAT_FLAVOR:-staging}"
BUNDLE_ID="${IOS_CAMERA_UAT_BUNDLE_ID:-app.cool.mobile.staging}"
TEST_TARGET="${IOS_CAMERA_UAT_TEST_TARGET:-integration_test/mobile_camera_permission_device_uat_test.dart}"
DRIVER="${IOS_CAMERA_UAT_DRIVER:-test_driver/integration_test.dart}"
TIMEOUT_SECONDS="${IOS_CAMERA_UAT_TIMEOUT_SECONDS:-900}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${IOS_CAMERA_UAT_EVIDENCE_DIR:-$ROOT_DIR/.cache/ios_simulator_camera_permission_uat/$timestamp}"
LOG_FILE="$EVIDENCE_DIR/ios_simulator_camera_permission_uat.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
ACTION_LOG="$EVIDENCE_DIR/privacy_actions.jsonl"
SCREENSHOT_DIR="$EVIDENCE_DIR/screenshots"
SCREENSHOT_MANIFEST="$SCREENSHOT_DIR/screenshots.jsonl"
APP_BINARY="$ROOT_DIR/build/ios/iphonesimulator/Collect.app"

fail() {
  printf '[ios-simulator-camera-permission-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

simulator_inventory() {
  "$XCRUN" simctl list devices --json
}

simulator_metadata() {
  local simulator_id="$1"
  simulator_inventory |
    ruby -r json -r digest -e '
      lookup = ARGV.fetch(0)
      data = JSON.parse($stdin.read)
      data.fetch("devices", {}).each do |runtime, devices|
        device = Array(devices).find { |item| item["udid"] == lookup }
        next unless device
        puts JSON.generate(
          {
            "device_id_sha256" => Digest::SHA256.hexdigest(lookup),
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
  local simulator_json="${2:-{}}"
  mkdir -p "$EVIDENCE_DIR"
  printf '[ios-simulator-camera-permission-uat][FAIL] %s\n' "$reason" >"$LOG_FILE"
  local log_sha256
  log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
  IOS_CAMERA_REASON="$reason" \
  IOS_CAMERA_SIMULATOR_JSON="$simulator_json" \
  IOS_CAMERA_LOG="${LOG_FILE#$ROOT_DIR/}" \
  IOS_CAMERA_LOG_SHA256="$log_sha256" \
  ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
simulator = JSON.parse(ENV.fetch("IOS_CAMERA_SIMULATOR_JSON", "{}")) rescue {}
puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => "fail",
    "evidence_accepted" => false,
    "failure_keys" => ["preflight"],
    "reason" => ENV.fetch("IOS_CAMERA_REASON"),
    "simulator" => simulator,
    "log" => ENV.fetch("IOS_CAMERA_LOG"),
    "log_sha256" => ENV.fetch("IOS_CAMERA_LOG_SHA256"),
    "scope" => {
      "ios_simulator_tcc_state" => false,
      "native_permission_dialog_interaction" => false,
      "physical_iphone" => false,
      "voiceover" => false
    }
  }
)
RUBY
}

cleanup_exact_fixture() {
  if [[ -n "$DEVICE_ID" && -x "$XCRUN" ]]; then
    "$XCRUN" simctl privacy "$DEVICE_ID" reset camera "$BUNDLE_ID" >/dev/null 2>&1 || true
    "$XCRUN" simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    "$XCRUN" simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${CAPTURE_TMP_DIR:-}" && -d "$CAPTURE_TMP_DIR" ]]; then
    rm -f "$CAPTURE_TMP_DIR/ios_camera_permission_denied_recovery.png"
    rmdir "$CAPTURE_TMP_DIR" >/dev/null 2>&1 || true
  fi
}

case "${1:-}" in
  "") ;;
  --help|-h)
    printf 'usage: %s\n' "$0"
    printf 'Required: IOS_CAMERA_UAT_SIMULATOR_ID and matching IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR (approved disposable simulator only).\n'
    printf 'This runner uninstalls its staging fixture and changes its camera permission; never target an existing signed-in app.\n'
    printf 'Optional: FLUTTER XCRUN XCODEBUILD IOS_CAMERA_UAT_TIMEOUT_SECONDS IOS_CAMERA_UAT_EVIDENCE_DIR.\n'
    exit 0
    ;;
  *)
    printf 'usage: %s\n' "$0" >&2
    exit 2
    ;;
esac

if [[ -z "$FLUTTER" || ! -x "$FLUTTER" ]]; then
  reason="Flutter executable is unavailable."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ ! -x "$XCRUN" || ! -x "$XCODEBUILD" ]]; then
  reason="xcrun or xcodebuild is unavailable."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ -z "$DEVICE_ID" ]]; then
  reason="IOS_CAMERA_UAT_SIMULATOR_ID is required; the harness never auto-selects a simulator."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ "$CONFIRMED_DISPOSABLE_DEVICE_ID" != "$DEVICE_ID" ]]; then
  reason="Refusing fixture or camera permission changes without exact disposable-simulator confirmation."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ ! -f "$TEST_TARGET" || ! -f "$DRIVER" ]]; then
  reason="The Camera permission target or integration driver is missing."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ "$FLAVOR" != "staging" || "$BUNDLE_ID" != "app.cool.mobile.staging" ]]; then
  reason="Camera permission UAT requires the staging flavor and app.cool.mobile.staging bundle identity."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
resolved_bundle_id="$("$XCODEBUILD" \
  -project ios/Runner.xcodeproj \
  -scheme "$FLAVOR" \
  -configuration Debug-staging \
  -showBuildSettings 2>/dev/null | awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }')"
if [[ "$resolved_bundle_id" != "$BUNDLE_ID" ]]; then
  reason="The staging Xcode build settings do not resolve to the guarded bundle identity."
  write_early_failure_summary "$reason"
  fail "$reason"
fi

simulator_before="$(simulator_metadata "$DEVICE_ID" || true)"
if [[ -z "$simulator_before" ]]; then
  reason="The exact iOS Simulator is not present in the current inventory."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if ! ruby -r json -e '
  d = JSON.parse(ARGV.fetch(0))
  exit(d["state"] == "Booted" && d["available"] == true ? 0 : 1)
' "$simulator_before"; then
  reason="The exact iOS Simulator is not booted and available."
  write_early_failure_summary "$reason" "$simulator_before"
  fail "$reason"
fi

flutter_device="$("$FLUTTER" devices --machine | ruby -r json -e '
  lookup = ARGV.fetch(0)
  device = JSON.parse($stdin.read).find { |item| item["id"] == lookup }
  exit 1 unless device
  puts JSON.generate(
    {
      "name" => device["name"],
      "target_platform" => device["targetPlatform"],
      "emulator" => device["emulator"],
      "supported" => device["isSupported"]
    }
  )
' "$DEVICE_ID" || true)"
if [[ -z "$flutter_device" ]] || ! ruby -r json -e '
  d = JSON.parse(ARGV.fetch(0))
  exit(d["target_platform"] == "ios" && d["emulator"] == true && d["supported"] == true ? 0 : 1)
' "$flutter_device"; then
  reason="The exact target is not a supported iOS Simulator visible to Flutter."
  write_early_failure_summary "$reason" "$simulator_before"
  fail "$reason"
fi

mkdir -p "$SCREENSHOT_DIR"
rm -f "$SCREENSHOT_MANIFEST" "$ACTION_LOG"
CAPTURE_TMP_DIR="$(mktemp -d)"
CAPTURE_TMP_PATH="$CAPTURE_TMP_DIR/ios_camera_permission_denied_recovery.png"
trap cleanup_exact_fixture EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BUILD_DENIED_LOG="$EVIDENCE_DIR/build_denied.txt"
BUILD_GRANTED_LOG="$EVIDENCE_DIR/build_granted.txt"
DENIED_LOG="$EVIDENCE_DIR/denied_phase.txt"
GRANTED_LOG="$EVIDENCE_DIR/granted_phase.txt"
BUILD_DENIED_RESULT="$EVIDENCE_DIR/build_denied_result.json"
BUILD_GRANTED_RESULT="$EVIDENCE_DIR/build_granted_result.json"
DENIED_RESULT="$EVIDENCE_DIR/denied_phase_result.json"
GRANTED_RESULT="$EVIDENCE_DIR/granted_phase_result.json"

run_guarded() {
  local phase_log="$1"
  local phase_result="$2"
  shift 2
  IOS_CAMERA_PHASE_LOG="$phase_log" \
  IOS_CAMERA_PHASE_RESULT="$phase_result" \
  IOS_CAMERA_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
  ruby -r json -r open3 -r pty -e '
    def terminate(signal, pid, errors)
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

    log_path = ENV.fetch("IOS_CAMERA_PHASE_LOG")
    result_path = ENV.fetch("IOS_CAMERA_PHASE_RESULT")
    timeout = Integer(
      ENV.fetch(
        "IOS_CAMERA_COMMAND_TIMEOUT_SECONDS",
        ENV.fetch("IOS_CAMERA_TIMEOUT_SECONDS")
      )
    )
    capture_marker = ENV["IOS_CAMERA_CAPTURE_MARKER"].to_s
    capture_path = ENV["IOS_CAMERA_CAPTURE_PATH"].to_s
    capture_device = ENV["IOS_CAMERA_CAPTURE_DEVICE"].to_s
    capture_xcrun = ENV["IOS_CAMERA_CAPTURE_XCRUN"].to_s
    started_at = Time.now
    reader, writer, pid = PTY.spawn(ENV.to_h, *ARGV)
    writer.close
    log_io = File.open(log_path, "wb")
    capture_result = nil
    reader_thread = Thread.new do
      aggregate = +""
      begin
        loop do
          chunk = reader.readpartial(16_384)
          log_io.write(chunk)
          log_io.flush
          $stdout.write(chunk)
          $stdout.flush
          aggregate << chunk
          aggregate = aggregate.byteslice(-131_072, 131_072) if aggregate.bytesize > 131_072
          if capture_result.nil? && !capture_marker.empty? && aggregate.include?(capture_marker)
            capture_status = nil
            capture_attempts = 0
            5.times do
              capture_attempts += 1
              _stdout, _stderr, capture_status = Open3.capture3(
                capture_xcrun,
                "simctl",
                "io",
                capture_device,
                "screenshot",
                capture_path
              )
              break if capture_status.success? && File.size?(capture_path)
              sleep 1
            end
            capture_result = {
              "marker" => capture_marker,
              "attempts" => capture_attempts,
              "exit_code" => capture_status.exitstatus,
              "success" => capture_status.success? && !!File.size?(capture_path)
            }
          end
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
        terminate("TERM", pid, kill_errors)
        sleep 2
        terminate("KILL", pid, kill_errors)
        begin
          _waited_pid, process_status = Process.waitpid2(pid)
          status = process_status
        rescue Errno::ECHILD
        end
        break
      end
      sleep 1
    end
    unless reader_thread.join(10)
      reader.close unless reader.closed?
      reader_thread.join(2)
    end
    exit_code = timed_out ? 124 : (status&.exitstatus || (status&.termsig ? 128 + status.termsig : 1))
    File.write(
      result_path,
      JSON.pretty_generate(
        {
          "exit_code" => exit_code,
          "timed_out" => timed_out,
          "timeout_seconds" => timeout,
          "kill_errors" => kill_errors,
          "host_screenshot" => capture_result
        }
      ) + "\n"
    )
    exit(exit_code)
  ' -- "$@"
}

record_privacy_action() {
  local phase="$1"
  local action="$2"
  local action_rc
  set +e
  "$XCRUN" simctl privacy "$DEVICE_ID" "$action" camera "$BUNDLE_ID" >/dev/null 2>&1
  action_rc=$?
  set -e
  IOS_CAMERA_ACTION_PHASE="$phase" \
  IOS_CAMERA_ACTION="$action" \
  IOS_CAMERA_ACTION_RC="$action_rc" \
  ruby -r json -r time -e '
    puts JSON.generate(
      {
        "at" => Time.now.utc.iso8601,
        "phase" => ENV.fetch("IOS_CAMERA_ACTION_PHASE"),
        "action" => ENV.fetch("IOS_CAMERA_ACTION"),
        "exit_code" => ENV.fetch("IOS_CAMERA_ACTION_RC").to_i,
        "success" => ENV.fetch("IOS_CAMERA_ACTION_RC") == "0",
        "application_state" => "stopped"
      }
    )
  ' >>"$ACTION_LOG"
  return "$action_rc"
}

build_phase() {
  local phase="$1"
  local phase_log="$2"
  local phase_result="$3"
  run_guarded "$phase_log" "$phase_result" \
    "$FLUTTER" build ios \
    --simulator \
    --debug \
    --no-pub \
    --flavor "$FLAVOR" \
    --target="$TEST_TARGET" \
    --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=false \
    --dart-define="COLLECT_CAMERA_PERMISSION_UAT_PHASE=$phase"
}

run_phase() {
  local phase="$1"
  local phase_log="$2"
  local phase_result="$3"
  if [[ "$phase" == "denied" ]]; then
    IOS_CAMERA_COMMAND_TIMEOUT_SECONDS=180 \
    IOS_CAMERA_CAPTURE_MARKER='collect_camera_permission_uat:camera-denied-recovery-visible' \
    IOS_CAMERA_CAPTURE_PATH="$CAPTURE_TMP_PATH" \
    IOS_CAMERA_CAPTURE_DEVICE="$DEVICE_ID" \
    IOS_CAMERA_CAPTURE_XCRUN="$XCRUN" \
    run_guarded "$phase_log" "$phase_result" \
      "$FLUTTER" drive \
      --no-pub \
      --driver="$DRIVER" \
      --target="$TEST_TARGET" \
      -d "$DEVICE_ID" \
      --use-application-binary="$APP_BINARY" \
      --flavor "$FLAVOR" \
      --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=false \
      --dart-define="COLLECT_CAMERA_PERMISSION_UAT_PHASE=$phase"
    return
  fi
  IOS_CAMERA_COMMAND_TIMEOUT_SECONDS=180 \
  run_guarded "$phase_log" "$phase_result" \
    "$FLUTTER" drive \
    --no-pub \
    --driver="$DRIVER" \
    --target="$TEST_TARGET" \
    -d "$DEVICE_ID" \
    --use-application-binary="$APP_BINARY" \
    --flavor "$FLAVOR" \
    --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=false \
    --dart-define="COLLECT_CAMERA_PERMISSION_UAT_PHASE=$phase"
}

validate_binary() {
  [[ -d "$APP_BINARY" ]] || return 1
  local binary_bundle_id
  binary_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BINARY/Info.plist" 2>/dev/null || true)"
  [[ "$binary_bundle_id" == "$BUNDLE_ID" ]]
}

printf '[ios-simulator-camera-permission-uat] simulator=%s flavor=%s bundle=%s evidence=%s timeout_seconds=%s\n' \
  "$(ruby -r json -e 'print JSON.parse(ARGV[0])["name"]' "$simulator_before")" \
  "$FLAVOR" "$BUNDLE_ID" "${EVIDENCE_DIR#$ROOT_DIR/}" "$TIMEOUT_SECONDS" >&2

# Only the exact staging fixture is replaced. TCC is mutated exclusively while
# that application is stopped because simctl privacy terminates running apps.
"$XCRUN" simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
"$XCRUN" simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

rc=0
set +e
build_phase denied "$BUILD_DENIED_LOG" "$BUILD_DENIED_RESULT"
build_denied_rc=$?
set -e
if [[ "$build_denied_rc" -ne 0 ]] || ! validate_binary; then
  rc=1
else
  "$XCRUN" simctl install "$DEVICE_ID" "$APP_BINARY" || rc=1
  if [[ "$rc" -eq 0 ]] && ! record_privacy_action denied revoke; then rc=1; fi
  if [[ "$rc" -eq 0 ]]; then
    set +e
    run_phase denied "$DENIED_LOG" "$DENIED_RESULT"
    denied_rc=$?
    set -e
    [[ "$denied_rc" -ne 0 ]] && rc=1
  fi
fi

"$XCRUN" simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
set +e
build_phase granted "$BUILD_GRANTED_LOG" "$BUILD_GRANTED_RESULT"
build_granted_rc=$?
set -e
granted_rc=1
if [[ "$build_granted_rc" -eq 0 ]] && validate_binary; then
  if "$XCRUN" simctl install "$DEVICE_ID" "$APP_BINARY" && record_privacy_action granted grant; then
    set +e
    run_phase granted "$GRANTED_LOG" "$GRANTED_RESULT"
    granted_rc=$?
    set -e
  fi
else
  rc=1
fi
if [[ "$granted_rc" -ne 0 && -f "$GRANTED_LOG" ]] &&
  ! grep -Fq 'collect_camera_permission_uat:camera-granted-phase-requested' "$GRANTED_LOG"; then
  # One bounded retry is allowed only when the driver never reached the test
  # phase (for example, an intermittent Simulator VM-service attach failure).
  # Assertion failures are never retried or hidden.
  cp "$GRANTED_LOG" "$EVIDENCE_DIR/granted_phase_attach_attempt_1.txt"
  cp "$GRANTED_RESULT" "$EVIDENCE_DIR/granted_phase_attach_attempt_1_result.json"
  "$XCRUN" simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  set +e
  run_phase granted "$GRANTED_LOG" "$GRANTED_RESULT"
  granted_rc=$?
  set -e
fi
[[ "$granted_rc" -ne 0 ]] && rc=1

if [[ -s "$CAPTURE_TMP_PATH" ]]; then
  cp "$CAPTURE_TMP_PATH" "$SCREENSHOT_DIR/ios_camera_permission_denied_recovery.png"
fi

{
  printf '=== build denied ===\n'
  [[ -f "$BUILD_DENIED_LOG" ]] && cat "$BUILD_DENIED_LOG"
  printf '\n=== denied phase ===\n'
  [[ -f "$DENIED_LOG" ]] && cat "$DENIED_LOG"
  printf '\n=== build granted ===\n'
  [[ -f "$BUILD_GRANTED_LOG" ]] && cat "$BUILD_GRANTED_LOG"
  printf '\n=== granted phase ===\n'
  if [[ -f "$EVIDENCE_DIR/granted_phase_attach_attempt_1.txt" ]]; then
    printf '%s\n' '[bounded attach attempt 1 rejected]'
    cat "$EVIDENCE_DIR/granted_phase_attach_attempt_1.txt"
    printf '%s\n' '[bounded attach retry follows]'
  fi
  [[ -f "$GRANTED_LOG" ]] && cat "$GRANTED_LOG"
} >"$LOG_FILE"

denied_phase_pass=0
if [[ -f "$DENIED_LOG" ]] &&
  grep -Fq 'collect_camera_permission_uat:camera-denied-phase-pass' "$DENIED_LOG" &&
  grep -Eq 'All tests passed[.!]' "$DENIED_LOG"; then
  denied_phase_pass=1
else
  rc=1
fi
granted_phase_pass=0
if [[ -f "$GRANTED_LOG" ]] &&
  grep -Fq 'collect_camera_permission_uat:camera-granted-phase-pass' "$GRANTED_LOG" &&
  grep -Eq 'All tests passed[.!]' "$GRANTED_LOG"; then
  granted_phase_pass=1
else
  rc=1
fi

build_failed=0
if grep -Eq 'Failed to build iOS app|Error \(Xcode\):|Could not build the precompiled application' "$LOG_FILE"; then
  build_failed=1
  rc=1
fi
log_failed=0
if grep -Eq 'Some tests failed|Test failed\.|TimeoutException after|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|Service has disappeared' "$LOG_FILE"; then
  log_failed=1
  rc=1
fi

privacy_actions_ok=0
if [[ -f "$ACTION_LOG" ]] && ruby -r json -e '
  rows = File.readlines(ARGV.fetch(0), chomp: true).map { |line| JSON.parse(line) }
  actual = rows.map { |row| [row["phase"], row["action"], row["success"], row["application_state"]] }
  expected = [["denied", "revoke", true, "stopped"], ["granted", "grant", true, "stopped"]]
  exit(actual == expected ? 0 : 1)
' "$ACTION_LOG"; then
  privacy_actions_ok=1
else
  rc=1
fi

expected_screenshot="$SCREENSHOT_DIR/ios_camera_permission_denied_recovery.png"
if [[ -f "$expected_screenshot" ]]; then
  IOS_CAMERA_SCREENSHOT_PATH="$(basename "$expected_screenshot")" \
  IOS_CAMERA_SCREENSHOT_BYTES="$(stat -f '%z' "$expected_screenshot")" \
  ruby -r json -e '
    puts JSON.generate(
      {
        "status" => "pass",
        "name" => "ios_camera_permission_denied_recovery",
        "path" => ENV.fetch("IOS_CAMERA_SCREENSHOT_PATH"),
        "bytes" => ENV.fetch("IOS_CAMERA_SCREENSHOT_BYTES").to_i,
        "capture" => "xcrun-simctl-io"
      }
    )
  ' >"$SCREENSHOT_MANIFEST"
fi
screenshot_count="$(find "$SCREENSHOT_DIR" -type f -name '*.png' | wc -l | tr -d ' ')"
screenshot_manifest_rows=0
[[ -f "$SCREENSHOT_MANIFEST" ]] && screenshot_manifest_rows="$(wc -l <"$SCREENSHOT_MANIFEST" | tr -d ' ')"
screenshot_size=0
[[ -f "$expected_screenshot" ]] && screenshot_size="$(stat -f '%z' "$expected_screenshot")"
if [[ "$screenshot_count" -ne 1 || "$screenshot_manifest_rows" -ne 1 || "$screenshot_size" -le 8000 ]]; then
  rc=1
fi

simulator_after="$(simulator_metadata "$DEVICE_ID" || true)"
simulator_booted_after=0
if [[ -n "$simulator_after" ]] && ruby -r json -e 'exit(JSON.parse(ARGV[0])["state"] == "Booted" ? 0 : 1)' "$simulator_after"; then
  simulator_booted_after=1
else
  simulator_after='{}'
  rc=1
fi

timed_out=0
for result_file in "$BUILD_DENIED_RESULT" "$BUILD_GRANTED_RESULT" "$DENIED_RESULT" "$GRANTED_RESULT"; do
  if [[ -f "$result_file" ]] && ruby -r json -e 'exit(JSON.parse(File.read(ARGV[0]))["timed_out"] ? 0 : 1)' "$result_file"; then
    timed_out=1
    rc=124
  fi
done

log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
action_log_sha256=""
[[ -f "$ACTION_LOG" ]] && action_log_sha256="$(shasum -a 256 "$ACTION_LOG" | awk '{print $1}')"
screenshot_manifest_sha256=""
[[ -f "$SCREENSHOT_MANIFEST" ]] && screenshot_manifest_sha256="$(shasum -a 256 "$SCREENSHOT_MANIFEST" | awk '{print $1}')"
status="pass"
[[ "$timed_out" == "1" ]] && status="timeout"
[[ "$rc" -ne 0 && "$rc" -ne 124 ]] && status="fail"

IOS_CAMERA_STATUS="$status" \
IOS_CAMERA_RC="$rc" \
IOS_CAMERA_SIMULATOR_BEFORE="$simulator_before" \
IOS_CAMERA_SIMULATOR_AFTER="$simulator_after" \
IOS_CAMERA_LOG="${LOG_FILE#$ROOT_DIR/}" \
IOS_CAMERA_LOG_SHA256="$log_sha256" \
IOS_CAMERA_ACTION_LOG="${ACTION_LOG#$ROOT_DIR/}" \
IOS_CAMERA_ACTION_LOG_SHA256="$action_log_sha256" \
IOS_CAMERA_TIMED_OUT="$timed_out" \
IOS_CAMERA_BUILD_FAILED="$build_failed" \
IOS_CAMERA_LOG_FAILED="$log_failed" \
IOS_CAMERA_DENIED_PHASE_PASS="$denied_phase_pass" \
IOS_CAMERA_GRANTED_PHASE_PASS="$granted_phase_pass" \
IOS_CAMERA_PRIVACY_ACTIONS_OK="$privacy_actions_ok" \
IOS_CAMERA_SCREENSHOT_COUNT="$screenshot_count" \
IOS_CAMERA_SCREENSHOT_SIZE="$screenshot_size" \
IOS_CAMERA_SCREENSHOT_MANIFEST="${SCREENSHOT_MANIFEST#$ROOT_DIR/}" \
IOS_CAMERA_SCREENSHOT_MANIFEST_SHA256="$screenshot_manifest_sha256" \
IOS_CAMERA_SIMULATOR_BOOTED_AFTER="$simulator_booted_after" \
ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
status = ENV.fetch("IOS_CAMERA_STATUS")
failure_keys = []
failure_keys << "runner_timeout" if ENV.fetch("IOS_CAMERA_TIMED_OUT") == "1"
failure_keys << "native_build_failed" if ENV.fetch("IOS_CAMERA_BUILD_FAILED") == "1"
failure_keys << "flutter_test_failure" if ENV.fetch("IOS_CAMERA_LOG_FAILED") == "1"
failure_keys << "denied_phase" unless ENV.fetch("IOS_CAMERA_DENIED_PHASE_PASS") == "1"
failure_keys << "granted_phase" unless ENV.fetch("IOS_CAMERA_GRANTED_PHASE_PASS") == "1"
failure_keys << "stopped_app_tcc_actions" unless ENV.fetch("IOS_CAMERA_PRIVACY_ACTIONS_OK") == "1"
failure_keys << "screenshot_evidence" unless ENV.fetch("IOS_CAMERA_SCREENSHOT_COUNT").to_i == 1 && ENV.fetch("IOS_CAMERA_SCREENSHOT_SIZE").to_i > 8000
failure_keys << "simulator_not_booted_after" unless ENV.fetch("IOS_CAMERA_SIMULATOR_BOOTED_AFTER") == "1"
failure_keys << "runner_exit" if ENV.fetch("IOS_CAMERA_RC").to_i != 0 && failure_keys.empty?
action_rows = if File.exist?(File.expand_path(ENV.fetch("IOS_CAMERA_ACTION_LOG"), Dir.pwd))
  File.readlines(File.expand_path(ENV.fetch("IOS_CAMERA_ACTION_LOG"), Dir.pwd), chomp: true).map { |line| JSON.parse(line) }
else
  []
end

puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => status,
    "exit_code" => ENV.fetch("IOS_CAMERA_RC").to_i,
    "evidence_accepted" => status == "pass" && failure_keys.empty?,
    "failure_keys" => failure_keys,
    "scenario" => "camera-denied-recovery-and-granted-state-across-controlled-relaunch",
    "simulator_before" => JSON.parse(ENV.fetch("IOS_CAMERA_SIMULATOR_BEFORE")),
    "simulator_after" => JSON.parse(ENV.fetch("IOS_CAMERA_SIMULATOR_AFTER")),
    "simulator_booted_after" => ENV.fetch("IOS_CAMERA_SIMULATOR_BOOTED_AFTER") == "1",
    "runner" => "two-phase-flutter-drive",
    "timed_out" => ENV.fetch("IOS_CAMERA_TIMED_OUT") == "1",
    "phases" => {
      "denied_recovery" => ENV.fetch("IOS_CAMERA_DENIED_PHASE_PASS") == "1",
      "granted_state" => ENV.fetch("IOS_CAMERA_GRANTED_PHASE_PASS") == "1"
    },
    "privacy_actions" => action_rows,
    "log" => ENV.fetch("IOS_CAMERA_LOG"),
    "log_sha256" => ENV.fetch("IOS_CAMERA_LOG_SHA256"),
    "privacy_action_log" => ENV.fetch("IOS_CAMERA_ACTION_LOG"),
    "privacy_action_log_sha256" => ENV.fetch("IOS_CAMERA_ACTION_LOG_SHA256"),
    "screenshot_count" => ENV.fetch("IOS_CAMERA_SCREENSHOT_COUNT").to_i,
    "screenshot_bytes" => ENV.fetch("IOS_CAMERA_SCREENSHOT_SIZE").to_i,
    "screenshot_manifest" => ENV.fetch("IOS_CAMERA_SCREENSHOT_MANIFEST"),
    "screenshot_manifest_sha256" => ENV.fetch("IOS_CAMERA_SCREENSHOT_MANIFEST_SHA256"),
    "scope" => {
      "ios_simulator_tcc_state" => true,
      "controlled_relaunch_boundary" => true,
      "continuous_in_session_retry" => false,
      "native_permission_dialog_interaction" => false,
      "physical_iphone" => false,
      "voiceover" => false,
      "claim" => status == "pass" && failure_keys.empty? ?
        "This proves iOS Simulator TCC denial, in-app denial recovery UI, and the host-granted Camera path across two controlled staging launches. It does not prove a continuous in-session retry, native permission-dialog interaction, physical-iPhone behavior, or VoiceOver operation." :
        "This run is not accepted. Consult failure_keys and individual phases; no complete camera-denial/recovery acceptance is established."
    },
    "secret_handling" => "The retained screenshot contains fixture-only denial recovery UI. No camera frame, photo, gallery image, SMS or OTP content, phone or payment data, credential, signing material, or production customer data is retained."
  }
)
RUBY

printf '[ios-simulator-camera-permission-uat] status=%s evidence=%s screenshot=%s bytes\n' \
  "$status" "${SUMMARY_FILE#$ROOT_DIR/}" "$screenshot_size" >&2
trap - EXIT INT TERM
cleanup_exact_fixture
exit "$rc"
