#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-$(command -v flutter || true)}"
XCRUN="${XCRUN:-/usr/bin/xcrun}"
XCODEBUILD="${XCODEBUILD:-/usr/bin/xcodebuild}"
DEVICE_ID="${IOS_PHYSICAL_UAT_DEVICE_ID:-}"
EXPECTED_NAME="${IOS_PHYSICAL_UAT_EXPECTED_NAME:-}"
EXPECTED_MODEL="${IOS_PHYSICAL_UAT_EXPECTED_MODEL:-}"
FLAVOR="${IOS_PHYSICAL_UAT_FLAVOR:-staging}"
BUNDLE_ID="${IOS_PHYSICAL_UAT_BUNDLE_ID:-app.cool.mobile.staging}"
TEST_TARGET="${IOS_PHYSICAL_UAT_TEST_TARGET:-integration_test/mobile_route_matrix_device_uat_test.dart}"
DRIVER="${IOS_PHYSICAL_UAT_DRIVER:-test_driver/integration_test.dart}"
TIMEOUT_SECONDS="${IOS_PHYSICAL_UAT_TIMEOUT_SECONDS:-1200}"
UAT_MODE="${IOS_PHYSICAL_UAT_MODE:-route}"
MOBILE_EVIDENCE_MODE="${IOS_PHYSICAL_UAT_MOBILE_EVIDENCE_MODE:-true}"
CAMERA_PHASE="${IOS_PHYSICAL_UAT_CAMERA_PHASE:-continuous}"
RESET_STAGING_APP="${IOS_PHYSICAL_UAT_RESET_STAGING_APP:-false}"
PREBUILD="${IOS_PHYSICAL_UAT_PREBUILD:-false}"
UNLOCK_WAIT_SECONDS="${IOS_PHYSICAL_UAT_UNLOCK_WAIT_SECONDS:-0}"
VARIANT_NAME="${IOS_PHYSICAL_UAT_VARIANT_NAME:-physical-default-dark}"
THEME_MODE="${IOS_PHYSICAL_UAT_THEME_MODE:-dark}"
TEXT_SCALE="${IOS_PHYSICAL_UAT_TEXT_SCALE:-1.0}"
HIGH_CONTRAST="${IOS_PHYSICAL_UAT_HIGH_CONTRAST:-false}"
REDUCED_MOTION="${IOS_PHYSICAL_UAT_REDUCED_MOTION:-false}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${IOS_PHYSICAL_UAT_EVIDENCE_DIR:-$ROOT_DIR/.cache/ios_physical_route_uat/$timestamp}"
LOG_FILE="$EVIDENCE_DIR/ios_physical_route_uat.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
RUNNER_RESULT_FILE="$EVIDENCE_DIR/runner_result.json"
HOST_ACTION_FILE="$EVIDENCE_DIR/host_actions.json"
PREBUILD_LOG="$EVIDENCE_DIR/prebuild.txt"
APP_BINARY="$ROOT_DIR/build/ios/iphoneos/Collect.app"
DEVICE_JSON_FILE="$(mktemp /tmp/collect-ios-physical-device.XXXXXX.json)"
LOCK_JSON_FILE="$(mktemp /tmp/collect-ios-physical-lock.XXXXXX.json)"
APP_JSON_FILE="$(mktemp /tmp/collect-ios-physical-apps.XXXXXX.json)"
UNINSTALL_JSON_FILE="$(mktemp /tmp/collect-ios-physical-uninstall.XXXXXX.json)"
trap 'rm -f "$DEVICE_JSON_FILE" "$LOCK_JSON_FILE" "$APP_JSON_FILE" "$UNINSTALL_JSON_FILE"' EXIT

fail() {
  printf '[ios-physical-route-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

write_early_failure_summary() {
  local reason="$1"
  local device_json="${2:-}"
  [[ -n "$device_json" ]] || device_json='{}'
  mkdir -p "$EVIDENCE_DIR"
  printf '[ios-physical-route-uat][FAIL] %s\n' "$reason" >"$LOG_FILE"
  local log_sha256
  log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
  IOS_PHYSICAL_REASON="$reason" \
  IOS_PHYSICAL_DEVICE_JSON="$device_json" \
  IOS_PHYSICAL_TARGET="$TEST_TARGET" \
  IOS_PHYSICAL_MODE="$UAT_MODE" \
  IOS_PHYSICAL_LOG="${LOG_FILE#$ROOT_DIR/}" \
  IOS_PHYSICAL_LOG_SHA256="$log_sha256" \
  IOS_PHYSICAL_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
  IOS_PHYSICAL_FLAVOR="$FLAVOR" \
  IOS_PHYSICAL_BUNDLE_ID="$BUNDLE_ID" \
  IOS_PHYSICAL_VARIANT_NAME="$VARIANT_NAME" \
  IOS_PHYSICAL_THEME_MODE="$THEME_MODE" \
  IOS_PHYSICAL_TEXT_SCALE="$TEXT_SCALE" \
  IOS_PHYSICAL_HIGH_CONTRAST="$HIGH_CONTRAST" \
  IOS_PHYSICAL_REDUCED_MOTION="$REDUCED_MOTION" \
  ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
device = JSON.parse(ENV.fetch("IOS_PHYSICAL_DEVICE_JSON", "{}")) rescue {}
puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => "fail",
    "evidence_accepted" => false,
    "exit_code" => 1,
    "reason" => ENV.fetch("IOS_PHYSICAL_REASON"),
    "failure_keys" => ["preflight"],
    "device" => device,
    "target" => ENV.fetch("IOS_PHYSICAL_TARGET"),
    "mode" => ENV.fetch("IOS_PHYSICAL_MODE", "route"),
    "runner" => "not_started",
    "log" => ENV.fetch("IOS_PHYSICAL_LOG"),
    "log_sha256" => ENV.fetch("IOS_PHYSICAL_LOG_SHA256"),
    "timed_out" => false,
    "timeout_seconds" => ENV.fetch("IOS_PHYSICAL_TIMEOUT_SECONDS").to_i,
    "flavor" => ENV.fetch("IOS_PHYSICAL_FLAVOR"),
    "bundle_id" => ENV.fetch("IOS_PHYSICAL_BUNDLE_ID"),
    "variant" => {
      "name" => ENV.fetch("IOS_PHYSICAL_VARIANT_NAME"),
      "theme_mode" => ENV.fetch("IOS_PHYSICAL_THEME_MODE"),
      "text_scale" => ENV.fetch("IOS_PHYSICAL_TEXT_SCALE").to_f,
      "high_contrast" => ENV.fetch("IOS_PHYSICAL_HIGH_CONTRAST") == "true",
      "reduced_motion" => ENV.fetch("IOS_PHYSICAL_REDUCED_MOTION") == "true"
    },
    "completion_marker" => false,
    "route_expected" => 0,
    "route_passes" => 0,
    "screenshots_required" => false,
    "secret_handling" => "The physical run uses fixture-only app state. Evidence excludes screenshots, signing material, raw device inventory, serial/ECID values, raw SMS, OTPs, phone/MoMo receiver data, provider tokens, and production customer data."
  }
)
RUBY
}

case "${1:-}" in
  "") ;;
  --help|-h)
    printf 'usage: %s\n' "$0"
    printf 'Required: IOS_PHYSICAL_UAT_DEVICE_ID\n'
    printf 'Optional identity guards: IOS_PHYSICAL_UAT_EXPECTED_NAME IOS_PHYSICAL_UAT_EXPECTED_MODEL\n'
    printf 'Optional mode: IOS_PHYSICAL_UAT_MODE=route|lifecycle|camera-settings\n'
    printf 'Camera Settings mode uninstalls only app.cool.mobile.staging to reset its Camera permission.\n'
    printf 'The harness refuses production flavor and app.cool.mobile bundle identity.\n'
    exit 0
    ;;
  *)
    printf 'usage: %s\n' "$0" >&2
    exit 2
    ;;
esac

case "$THEME_MODE" in
  light|dark|system) ;;
  *) fail "IOS_PHYSICAL_UAT_THEME_MODE must be light, dark, or system." ;;
esac
case "$UAT_MODE" in
  route|lifecycle|camera-settings) ;;
  *) fail "IOS_PHYSICAL_UAT_MODE must be route, lifecycle, or camera-settings." ;;
esac
case "$MOBILE_EVIDENCE_MODE" in
  true|false) ;;
  *) fail "IOS_PHYSICAL_UAT_MOBILE_EVIDENCE_MODE must be true or false." ;;
esac
case "$RESET_STAGING_APP" in
  true|false) ;;
  *) fail "IOS_PHYSICAL_UAT_RESET_STAGING_APP must be true or false." ;;
esac
case "$PREBUILD" in
  true|false) ;;
  *) fail "IOS_PHYSICAL_UAT_PREBUILD must be true or false." ;;
esac
if ! [[ "$UNLOCK_WAIT_SECONDS" =~ ^[0-9]+$ ]] || (( UNLOCK_WAIT_SECONDS > 300 )); then
  fail "IOS_PHYSICAL_UAT_UNLOCK_WAIT_SECONDS must be an integer from 0 through 300."
fi
if [[ "$UAT_MODE" == "camera-settings" && ( "$MOBILE_EVIDENCE_MODE" != "false" || "$CAMERA_PHASE" != "physical-settings" || "$RESET_STAGING_APP" != "true" ) ]]; then
  fail "Physical Camera Settings UAT requires real scanner mode, the physical-settings phase, and an explicit staging-app reset."
fi
case "$HIGH_CONTRAST" in
  true|false) ;;
  *) fail "IOS_PHYSICAL_UAT_HIGH_CONTRAST must be true or false." ;;
esac
case "$REDUCED_MOTION" in
  true|false) ;;
  *) fail "IOS_PHYSICAL_UAT_REDUCED_MOTION must be true or false." ;;
esac
if ! ruby -e 'value = Float(ARGV.fetch(0)); exit(value >= 1.0 && value <= 3.2 ? 0 : 1)' "$TEXT_SCALE"; then
  fail "IOS_PHYSICAL_UAT_TEXT_SCALE must be a number from 1.0 through 3.2."
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
if [[ ! -x "$XCODEBUILD" ]]; then
  reason="xcodebuild is unavailable."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ -z "$DEVICE_ID" ]]; then
  reason="IOS_PHYSICAL_UAT_DEVICE_ID is required; the harness never auto-selects a physical device."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ ! -f "$TEST_TARGET" || ! -f "$DRIVER" ]]; then
  reason="The physical route target or integration driver is missing."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if [[ "$FLAVOR" != "staging" || "$BUNDLE_ID" != "app.cool.mobile.staging" ]]; then
  reason="Physical UAT requires the staging flavor and app.cool.mobile.staging bundle identity."
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

prebuild_rc=0
prebuild_sha256=""
if [[ "$PREBUILD" == "true" ]]; then
  mkdir -p "$EVIDENCE_DIR"
  set +e
  "$FLUTTER" build ios \
    --debug \
    --no-pub \
    --flavor "$FLAVOR" \
    --target="$TEST_TARGET" \
    --dart-define="COLLECT_MOBILE_EVIDENCE_MODE=$MOBILE_EVIDENCE_MODE" \
    --dart-define="COLLECT_CAMERA_PERMISSION_UAT_PHASE=$CAMERA_PHASE" \
    --dart-define="COLLECT_UAT_VARIANT_NAME=$VARIANT_NAME" \
    --dart-define="COLLECT_UAT_THEME_MODE=$THEME_MODE" \
    --dart-define="COLLECT_UAT_TEXT_SCALE=$TEXT_SCALE" \
    --dart-define="COLLECT_UAT_HIGH_CONTRAST=$HIGH_CONTRAST" \
    --dart-define="COLLECT_UAT_REDUCED_MOTION=$REDUCED_MOTION" \
    2>&1 | tee "$PREBUILD_LOG"
  prebuild_rc="${PIPESTATUS[0]}"
  set -e
  if [[ "$prebuild_rc" -ne 0 || ! -d "$APP_BINARY" ]]; then
    reason="The guarded physical-iOS UAT prebuild failed."
    write_early_failure_summary "$reason"
    fail "$reason"
  fi
  binary_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BINARY/Info.plist" 2>/dev/null || true)"
  if [[ "$binary_bundle_id" != "$BUNDLE_ID" ]]; then
    reason="The physical-iOS UAT prebuild does not contain the guarded staging bundle identity."
    write_early_failure_summary "$reason"
    fail "$reason"
  fi
  prebuild_sha256="$(shasum -a 256 "$PREBUILD_LOG" | awk '{print $1}')"
fi

flutter_device="$("$FLUTTER" devices --machine | ruby -r json -e '
  lookup = ARGV.fetch(0)
  devices = JSON.parse($stdin.read)
  device = devices.find { |item| item["id"] == lookup }
  exit 1 unless device
  puts JSON.generate(
    {
      "id" => device["id"],
      "name" => device["name"],
      "target_platform" => device["targetPlatform"],
      "emulator" => device["emulator"],
      "supported" => device["isSupported"],
      "sdk" => device["sdk"]
    }
  )
' "$DEVICE_ID" || true)"
if [[ -z "$flutter_device" ]]; then
  reason="The exact physical iOS device is not currently visible to Flutter."
  write_early_failure_summary "$reason"
  fail "$reason"
fi
if ! ruby -r json -e '
  d = JSON.parse(ARGV.fetch(0))
  exit(d["target_platform"] == "ios" && d["emulator"] == false && d["supported"] == true ? 0 : 1)
' "$flutter_device"; then
  reason="The exact Flutter target is not a supported physical iOS device."
  write_early_failure_summary "$reason" "$flutter_device"
  fail "$reason"
fi

"$XCRUN" devicectl list devices --json-output "$DEVICE_JSON_FILE" --quiet
core_device="$(ruby -r json -r digest -e '
  lookup = ARGV.fetch(0)
  data = JSON.parse(File.read(ARGV.fetch(1)))
  device = data.fetch("result", {}).fetch("devices", []).find do |item|
    item.dig("hardwareProperties", "udid") == lookup
  end
  exit 1 unless device
  puts JSON.generate(
    {
      "udid_sha256" => Digest::SHA256.hexdigest(lookup),
      "name" => device.dig("deviceProperties", "name"),
      "model" => device.dig("hardwareProperties", "marketingName"),
      "platform" => device.dig("hardwareProperties", "platform"),
      "reality" => device.dig("hardwareProperties", "reality"),
      "developer_mode" => device.dig("deviceProperties", "developerModeStatus"),
      "pairing_state" => device.dig("connectionProperties", "pairingState")
    }
  )
' "$DEVICE_ID" "$DEVICE_JSON_FILE" || true)"
if [[ -z "$core_device" ]]; then
  reason="The exact physical iOS device is not present in the CoreDevice inventory."
  write_early_failure_summary "$reason" "$flutter_device"
  fail "$reason"
fi

lock_state=""
unlock_deadline="$(( $(date +%s) + UNLOCK_WAIT_SECONDS ))"
unlock_wait_announced=0
while true; do
  if "$XCRUN" devicectl device info lockState \
    --device "$DEVICE_ID" \
    --json-output "$LOCK_JSON_FILE" \
    --quiet; then
    lock_state="$(ruby -r json -e '
      data = JSON.parse(File.read(ARGV.fetch(0)))
      result = data.fetch("result", {})
      exit 1 unless [true, false].include?(result["passcodeRequired"])
      puts JSON.generate(
        {
          "passcode_required" => result["passcodeRequired"],
          "unlocked_since_boot" => result["unlockedSinceBoot"]
        }
      )
    ' "$LOCK_JSON_FILE" || true)"
  else
    lock_state=""
  fi
  if [[ -n "$lock_state" ]] && ruby -r json -e 'exit(JSON.parse(ARGV.fetch(0))["passcode_required"] == false ? 0 : 1)' "$lock_state"; then
    break
  fi
  if [[ "$UNLOCK_WAIT_SECONDS" -eq 0 || "$(date +%s)" -ge "$unlock_deadline" ]]; then
    break
  fi
  if [[ "$unlock_wait_announced" == "0" ]]; then
    printf '[ios-physical-route-uat][WAIT] Unlock the exact physical iPhone and keep its screen awake; waiting up to %s seconds.\n' "$UNLOCK_WAIT_SECONDS" >&2
    unlock_wait_announced=1
  fi
  sleep 5
done
if [[ -z "$lock_state" ]]; then
  reason="The exact physical iOS device returned no usable current lock state."
  write_early_failure_summary "$reason" "$core_device"
  fail "$reason"
fi
core_device="$(ruby -r json -e '
  device = JSON.parse(ARGV.fetch(0))
  lock = JSON.parse(ARGV.fetch(1))
  puts JSON.generate(device.merge(lock))
' "$core_device" "$lock_state")"
if ! ruby -r json -e 'exit(JSON.parse(ARGV.fetch(0))["passcode_required"] == false ? 0 : 1)' "$core_device"; then
  reason="The exact physical iOS device is locked; unlock it before starting UAT."
  write_early_failure_summary "$reason" "$core_device"
  fail "$reason"
fi

if ! ruby -r json -e '
  d = JSON.parse(ARGV.fetch(0))
  exit(d["platform"] == "iOS" && d["reality"] == "physical" && d["developer_mode"] == "enabled" && d["pairing_state"] == "paired" ? 0 : 1)
' "$core_device"; then
  reason="The exact target is not a paired physical iOS device with Developer Mode enabled."
  write_early_failure_summary "$reason" "$core_device"
  fail "$reason"
fi
if [[ -n "$EXPECTED_NAME" ]] && ! ruby -r json -e 'exit(JSON.parse(ARGV[0])["name"] == ARGV[1] ? 0 : 1)' "$core_device" "$EXPECTED_NAME"; then
  reason="Physical iOS device name does not match IOS_PHYSICAL_UAT_EXPECTED_NAME."
  write_early_failure_summary "$reason" "$core_device"
  fail "$reason"
fi
if [[ -n "$EXPECTED_MODEL" ]] && ! ruby -r json -e 'exit(JSON.parse(ARGV[0])["model"] == ARGV[1] ? 0 : 1)' "$core_device" "$EXPECTED_MODEL"; then
  reason="Physical iOS device model does not match IOS_PHYSICAL_UAT_EXPECTED_MODEL."
  write_early_failure_summary "$reason" "$core_device"
  fail "$reason"
fi

staging_app_reset=0
if [[ "$UAT_MODE" == "camera-settings" ]]; then
  if ! "$XCRUN" devicectl device info apps \
    --device "$DEVICE_ID" \
    --json-output "$APP_JSON_FILE" \
    --quiet; then
    reason="The staging-app inventory could not be queried before Camera permission reset."
    write_early_failure_summary "$reason" "$core_device"
    fail "$reason"
  fi
  staging_app_installed=0
  if ruby -r json -e '
    apps = JSON.parse(File.read(ARGV.fetch(0))).fetch("result", {}).fetch("apps", [])
    exit(apps.any? { |app| app["bundleIdentifier"] == ARGV.fetch(1) } ? 0 : 1)
  ' "$APP_JSON_FILE" "$BUNDLE_ID"; then
    staging_app_installed=1
  fi
  if [[ "$staging_app_installed" == "1" ]]; then
    if ! "$XCRUN" devicectl device uninstall app \
      --device "$DEVICE_ID" \
      --json-output "$UNINSTALL_JSON_FILE" \
      --quiet \
      "$BUNDLE_ID"; then
      reason="The staging app could not be reset before physical Camera permission UAT."
      write_early_failure_summary "$reason" "$core_device"
      fail "$reason"
    fi
  fi
  staging_app_reset=1
fi

mkdir -p "$EVIDENCE_DIR"
cmd=(
  "$FLUTTER"
  drive
  --no-pub
  --driver="$DRIVER"
  --target="$TEST_TARGET"
  -d "$DEVICE_ID"
  --flavor "$FLAVOR"
  --dart-define="COLLECT_MOBILE_EVIDENCE_MODE=$MOBILE_EVIDENCE_MODE"
  --dart-define="COLLECT_CAMERA_PERMISSION_UAT_PHASE=$CAMERA_PHASE"
  --dart-define="COLLECT_UAT_VARIANT_NAME=$VARIANT_NAME"
  --dart-define="COLLECT_UAT_THEME_MODE=$THEME_MODE"
  --dart-define="COLLECT_UAT_TEXT_SCALE=$TEXT_SCALE"
  --dart-define="COLLECT_UAT_HIGH_CONTRAST=$HIGH_CONTRAST"
  --dart-define="COLLECT_UAT_REDUCED_MOTION=$REDUCED_MOTION"
)
if [[ "$PREBUILD" == "true" ]]; then
  cmd+=(--use-application-binary="$APP_BINARY")
fi

printf '[ios-physical-route-uat] device=%s model=%s flavor=%s bundle=%s target=%s evidence=%s timeout_seconds=%s variant=%s mode=%s\n' \
  "$(ruby -r json -e 'print JSON.parse(ARGV[0])["name"]' "$core_device")" \
  "$(ruby -r json -e 'print JSON.parse(ARGV[0])["model"]' "$core_device")" \
  "$FLAVOR" "$BUNDLE_ID" "$TEST_TARGET" "${EVIDENCE_DIR#$ROOT_DIR/}" "$TIMEOUT_SECONDS" "$VARIANT_NAME" "$UAT_MODE" >&2

set +e
IOS_PHYSICAL_LOG_FILE="$LOG_FILE" \
IOS_PHYSICAL_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
IOS_PHYSICAL_RUNNER_RESULT_FILE="$RUNNER_RESULT_FILE" \
IOS_PHYSICAL_HOST_ACTION_FILE="$HOST_ACTION_FILE" \
IOS_PHYSICAL_MODE="$UAT_MODE" \
IOS_PHYSICAL_DEVICE_ID="$DEVICE_ID" \
IOS_PHYSICAL_XCRUN="$XCRUN" \
IOS_PHYSICAL_BUNDLE_ID="$BUNDLE_ID" \
ruby -r json -r open3 -r pty -r tempfile -r time -e '
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

  log = ENV.fetch("IOS_PHYSICAL_LOG_FILE")
  timeout = Integer(ENV.fetch("IOS_PHYSICAL_TIMEOUT_SECONDS"))
  result = ENV.fetch("IOS_PHYSICAL_RUNNER_RESULT_FILE")
  host_action_file = ENV.fetch("IOS_PHYSICAL_HOST_ACTION_FILE")
  mode = ENV.fetch("IOS_PHYSICAL_MODE")
  device_id = ENV.fetch("IOS_PHYSICAL_DEVICE_ID")
  xcrun = ENV.fetch("IOS_PHYSICAL_XCRUN")
  bundle_id = ENV.fetch("IOS_PHYSICAL_BUNDLE_ID")
  started_at = Time.now
  reader, writer, pid = PTY.spawn(ENV.to_h, *ARGV)
  writer.close
  log_io = File.open(log, "wb")
  host_action = {
    "required" => mode == "lifecycle",
    "attempted" => false,
    "settings_foregrounded" => false,
    "collect_reactivated" => false,
    "failure" => nil
  }
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
        next unless mode == "lifecycle"
        next if host_action["attempted"]
        next unless aggregate.include?("collect_ios_lifecycle_uat:ready-for-background")

        host_action["attempted"] = true
        begin
          settings_result = Tempfile.new(["collect-settings-foreground", ".json"])
          settings_result.close
          _stdout, stderr, status = Open3.capture3(
            xcrun,
            "devicectl",
            "device",
            "process",
            "launch",
            "--device",
            device_id,
            "--json-output",
            settings_result.path,
            "--quiet",
            "com.apple.Preferences"
          )
          host_action["settings_foregrounded"] = status.success?
          raise "settings_foreground_failed" unless status.success?
          sleep 2

          collect_result = Tempfile.new(["collect-app-reactivate", ".json"])
          collect_result.close
          _stdout, stderr, status = Open3.capture3(
            xcrun,
            "devicectl",
            "device",
            "process",
            "launch",
            "--device",
            device_id,
            "--json-output",
            collect_result.path,
            "--quiet",
            bundle_id
          )
          host_action["collect_reactivated"] = status.success?
          raise "collect_reactivation_failed" unless status.success?
        rescue StandardError => error
          host_action["failure"] = error.message
        ensure
          File.write(
            host_action_file,
            JSON.pretty_generate(host_action.merge("generated_at" => Time.now.utc.iso8601)) + "\n"
          )
          settings_result&.unlink
          collect_result&.unlink
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
    sleep 5
  end
  reader_thread.join(5)
  exit_code = timed_out ? 124 : (status&.exitstatus || (status&.termsig ? 128 + status.termsig : 1))
  File.write(
    result,
    JSON.pretty_generate(
      {
        "exit_code" => exit_code,
        "timed_out" => timed_out,
        "pid" => pid,
        "timeout_seconds" => timeout,
        "kill_errors" => kill_errors,
        "host_action" => host_action
      }
    ) + "\n"
  )
  exit(exit_code)
' -- "${cmd[@]}"
rc=$?
set -e

timed_out="$(ruby -r json -e 'd=File.exist?(ARGV[0]) ? JSON.parse(File.read(ARGV[0])) : {}; puts(d["timed_out"] ? "1" : "0")' "$RUNNER_RESULT_FILE")"
[[ "$timed_out" == "1" ]] && rc=124

log_failed=0
if grep -Eq 'Some tests failed|Test failed\.|TimeoutException after|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' "$LOG_FILE"; then
  log_failed=1
  [[ "$rc" -eq 0 ]] && rc=1
fi
build_failed=0
if grep -Eq 'Failed to build iOS app|Error \(Xcode\):|Could not build the precompiled application' "$LOG_FILE"; then
  build_failed=1
  [[ "$rc" -eq 0 ]] && rc=1
fi

completion_marker=0
if grep -Eq 'All tests passed[.!]' "$LOG_FILE"; then
  completion_marker=1
else
  printf '[ios-physical-route-uat][FAIL] Flutter driver did not emit an All tests passed completion marker.\n' >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi

variant_marker=0
observed_variant_marker="$(grep -o 'collect_route_uat:variant:[^[:space:]]*' "$LOG_FILE" | tail -1 || true)"
route_expected=0
route_passes=0
lifecycle_marker=0
camera_marker=0
host_action_pass=0
if [[ "$UAT_MODE" == "route" ]]; then
  if grep -Fq "collect_route_uat:variant:$VARIANT_NAME:theme=$THEME_MODE:" "$LOG_FILE"; then
    variant_marker=1
  else
    printf '[ios-physical-route-uat][FAIL] Flutter driver did not emit the expected variant marker.\n' >>"$LOG_FILE"
    [[ "$rc" -eq 0 ]] && rc=1
  fi

  route_expected="$(awk '/^  _RouteSpec\(/ { count += 1 } END { print count + 0 }' "$TEST_TARGET")"
  route_passes="$(grep -c 'collect_route_uat:pass:' "$LOG_FILE" || true)"
  if [[ "$route_expected" -eq 0 || "$route_passes" -ne "$route_expected" ]]; then
    printf '[ios-physical-route-uat][FAIL] Route completion mismatch: expected=%s passed=%s.\n' "$route_expected" "$route_passes" >>"$LOG_FILE"
    [[ "$rc" -eq 0 ]] && rc=1
  fi
elif [[ "$UAT_MODE" == "lifecycle" ]]; then
  lifecycle_required_markers=(
    'collect_ios_lifecycle_uat:ready-for-background'
    'collect_ios_lifecycle_uat:ordered-transition:'
    'collect_ios_lifecycle_uat:contribution-review-preserved'
    'collect_ios_lifecycle_uat:pass'
  )
  lifecycle_marker=1
  for marker in "${lifecycle_required_markers[@]}"; do
    if ! grep -Fq "$marker" "$LOG_FILE"; then
      lifecycle_marker=0
      printf '[ios-physical-route-uat][FAIL] Missing lifecycle marker: %s.\n' "$marker" >>"$LOG_FILE"
    fi
  done
  if [[ "$lifecycle_marker" != "1" ]]; then
    [[ "$rc" -eq 0 ]] && rc=1
  fi
  if [[ -f "$HOST_ACTION_FILE" ]] && ruby -r json -e '
    d = JSON.parse(File.read(ARGV.fetch(0)))
    exit(d["attempted"] && d["settings_foregrounded"] && d["collect_reactivated"] && d["failure"].nil? ? 0 : 1)
  ' "$HOST_ACTION_FILE"; then
    host_action_pass=1
  else
    printf '[ios-physical-route-uat][FAIL] Physical lifecycle host action did not complete.\n' >>"$LOG_FILE"
    [[ "$rc" -eq 0 ]] && rc=1
  fi
else
  camera_required_markers=(
    'collect_camera_permission_uat:camera-deny-prompt-requested'
    'collect_camera_permission_uat:camera-denied-recovery-visible'
    'collect_camera_permission_uat:camera-settings-recovery-requested'
    'collect_camera_permission_uat:camera-physical-settings-recovery-pass'
  )
  camera_marker=1
  for marker in "${camera_required_markers[@]}"; do
    if ! grep -Fq "$marker" "$LOG_FILE"; then
      camera_marker=0
      printf '[ios-physical-route-uat][FAIL] Missing physical Camera marker: %s.\n' "$marker" >>"$LOG_FILE"
    fi
  done
  if [[ "$camera_marker" != "1" ]]; then
    [[ "$rc" -eq 0 ]] && rc=1
  fi
fi

device_visible_after=0
if "$FLUTTER" devices --machine | ruby -r json -e 'lookup=ARGV[0]; exit(JSON.parse($stdin.read).any?{|d| d["id"]==lookup && d["emulator"]==false && d["isSupported"]==true} ? 0 : 1)' "$DEVICE_ID"; then
  device_visible_after=1
else
  printf '[ios-physical-route-uat][FAIL] Exact physical device was not visible after the run.\n' >>"$LOG_FILE"
  [[ "$rc" -eq 0 ]] && rc=1
fi

status="pass"
if [[ "$timed_out" == "1" ]]; then
  status="timeout"
elif [[ "$rc" -ne 0 || "$log_failed" == "1" ]]; then
  status="fail"
fi
log_sha256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
host_action_sha256=""
if [[ -f "$HOST_ACTION_FILE" ]]; then
  host_action_sha256="$(shasum -a 256 "$HOST_ACTION_FILE" | awk '{print $1}')"
fi

IOS_PHYSICAL_STATUS="$status" \
IOS_PHYSICAL_RC="$rc" \
IOS_PHYSICAL_DEVICE_JSON="$core_device" \
IOS_PHYSICAL_TARGET="$TEST_TARGET" \
IOS_PHYSICAL_MODE="$UAT_MODE" \
IOS_PHYSICAL_LOG="${LOG_FILE#$ROOT_DIR/}" \
IOS_PHYSICAL_LOG_SHA256="$log_sha256" \
IOS_PHYSICAL_TIMED_OUT="$timed_out" \
IOS_PHYSICAL_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
IOS_PHYSICAL_BUILD_FAILED="$build_failed" \
IOS_PHYSICAL_LOG_FAILED="$log_failed" \
IOS_PHYSICAL_COMPLETION_MARKER="$completion_marker" \
IOS_PHYSICAL_VARIANT_MARKER="$variant_marker" \
IOS_PHYSICAL_OBSERVED_VARIANT_MARKER="$observed_variant_marker" \
IOS_PHYSICAL_LIFECYCLE_MARKER="$lifecycle_marker" \
IOS_PHYSICAL_CAMERA_MARKER="$camera_marker" \
IOS_PHYSICAL_HOST_ACTION_PASS="$host_action_pass" \
IOS_PHYSICAL_HOST_ACTION="${HOST_ACTION_FILE#$ROOT_DIR/}" \
IOS_PHYSICAL_HOST_ACTION_SHA256="$host_action_sha256" \
IOS_PHYSICAL_VARIANT_NAME="$VARIANT_NAME" \
IOS_PHYSICAL_THEME_MODE="$THEME_MODE" \
IOS_PHYSICAL_TEXT_SCALE="$TEXT_SCALE" \
IOS_PHYSICAL_HIGH_CONTRAST="$HIGH_CONTRAST" \
IOS_PHYSICAL_REDUCED_MOTION="$REDUCED_MOTION" \
IOS_PHYSICAL_FLAVOR="$FLAVOR" \
IOS_PHYSICAL_BUNDLE_ID="$BUNDLE_ID" \
IOS_PHYSICAL_MOBILE_EVIDENCE_MODE="$MOBILE_EVIDENCE_MODE" \
IOS_PHYSICAL_CAMERA_PHASE="$CAMERA_PHASE" \
IOS_PHYSICAL_STAGING_APP_RESET="$staging_app_reset" \
IOS_PHYSICAL_PREBUILD="$PREBUILD" \
IOS_PHYSICAL_PREBUILD_RC="$prebuild_rc" \
IOS_PHYSICAL_PREBUILD_LOG="${PREBUILD_LOG#$ROOT_DIR/}" \
IOS_PHYSICAL_PREBUILD_LOG_SHA256="$prebuild_sha256" \
IOS_PHYSICAL_ROUTE_EXPECTED="$route_expected" \
IOS_PHYSICAL_ROUTE_PASSES="$route_passes" \
IOS_PHYSICAL_DEVICE_VISIBLE_AFTER="$device_visible_after" \
ruby -r json -r time <<'RUBY' >"$SUMMARY_FILE"
status = ENV.fetch("IOS_PHYSICAL_STATUS")
mode = ENV.fetch("IOS_PHYSICAL_MODE")
build_failed = ENV.fetch("IOS_PHYSICAL_BUILD_FAILED") == "1"
log_failed = ENV.fetch("IOS_PHYSICAL_LOG_FAILED") == "1"
completion_marker = ENV.fetch("IOS_PHYSICAL_COMPLETION_MARKER") == "1"
variant_marker = ENV.fetch("IOS_PHYSICAL_VARIANT_MARKER") == "1"
lifecycle_marker = ENV.fetch("IOS_PHYSICAL_LIFECYCLE_MARKER") == "1"
camera_marker = ENV.fetch("IOS_PHYSICAL_CAMERA_MARKER") == "1"
host_action_pass = ENV.fetch("IOS_PHYSICAL_HOST_ACTION_PASS") == "1"
route_expected = ENV.fetch("IOS_PHYSICAL_ROUTE_EXPECTED").to_i
route_passes = ENV.fetch("IOS_PHYSICAL_ROUTE_PASSES").to_i
device_visible_after = ENV.fetch("IOS_PHYSICAL_DEVICE_VISIBLE_AFTER") == "1"
failure_keys = []
failure_keys << "runner_timeout" if ENV.fetch("IOS_PHYSICAL_TIMED_OUT") == "1"
failure_keys << "native_build_failed" if build_failed
failure_keys << "flutter_test_failure" if log_failed
failure_keys << "completion_marker_missing" unless completion_marker
failure_keys << "prebuild_failed" if ENV.fetch("IOS_PHYSICAL_PREBUILD") == "true" && ENV.fetch("IOS_PHYSICAL_PREBUILD_RC").to_i != 0
if mode == "route"
  failure_keys << "variant_marker_mismatch" unless variant_marker
  failure_keys << "route_completion_mismatch" unless route_expected.positive? && route_passes == route_expected
elsif mode == "lifecycle"
  failure_keys << "lifecycle_marker_mismatch" unless lifecycle_marker
  failure_keys << "host_lifecycle_action_failed" unless host_action_pass
else
  failure_keys << "camera_marker_mismatch" unless camera_marker
  failure_keys << "staging_app_reset_missing" unless ENV.fetch("IOS_PHYSICAL_STAGING_APP_RESET") == "1"
end
failure_keys << "device_not_visible_after" unless device_visible_after
failure_keys << "runner_exit" if ENV.fetch("IOS_PHYSICAL_RC").to_i != 0 && failure_keys.empty?

puts JSON.pretty_generate(
  {
    "generated_at" => Time.now.utc.iso8601,
    "status" => status,
    "evidence_accepted" => status == "pass" && failure_keys.empty?,
    "exit_code" => ENV.fetch("IOS_PHYSICAL_RC").to_i,
    "failure_keys" => failure_keys,
    "device" => JSON.parse(ENV.fetch("IOS_PHYSICAL_DEVICE_JSON")),
    "target" => ENV.fetch("IOS_PHYSICAL_TARGET"),
    "mode" => mode,
    "runner" => "drive",
    "log" => ENV.fetch("IOS_PHYSICAL_LOG"),
    "log_sha256" => ENV.fetch("IOS_PHYSICAL_LOG_SHA256"),
    "timed_out" => ENV.fetch("IOS_PHYSICAL_TIMED_OUT") == "1",
    "timeout_seconds" => ENV.fetch("IOS_PHYSICAL_TIMEOUT_SECONDS").to_i,
    "build_failed" => build_failed,
    "log_failed" => log_failed,
    "completion_marker" => completion_marker,
    "variant_marker" => variant_marker,
    "observed_variant_marker" => ENV.fetch("IOS_PHYSICAL_OBSERVED_VARIANT_MARKER", ""),
    "lifecycle_marker" => lifecycle_marker,
    "host_action_pass" => host_action_pass,
    "host_action" => mode == "lifecycle" ? ENV.fetch("IOS_PHYSICAL_HOST_ACTION") : nil,
    "host_action_sha256" => mode == "lifecycle" ? ENV.fetch("IOS_PHYSICAL_HOST_ACTION_SHA256") : nil,
    "flavor" => ENV.fetch("IOS_PHYSICAL_FLAVOR"),
    "bundle_id" => ENV.fetch("IOS_PHYSICAL_BUNDLE_ID"),
    "mobile_evidence_mode" => ENV.fetch("IOS_PHYSICAL_MOBILE_EVIDENCE_MODE") == "true",
    "camera_phase" => ENV.fetch("IOS_PHYSICAL_CAMERA_PHASE"),
    "staging_app_reset" => ENV.fetch("IOS_PHYSICAL_STAGING_APP_RESET") == "1",
    "prebuild" => {
      "used" => ENV.fetch("IOS_PHYSICAL_PREBUILD") == "true",
      "exit_code" => ENV.fetch("IOS_PHYSICAL_PREBUILD_RC").to_i,
      "log" => ENV.fetch("IOS_PHYSICAL_PREBUILD") == "true" ? ENV.fetch("IOS_PHYSICAL_PREBUILD_LOG") : nil,
      "log_sha256" => ENV.fetch("IOS_PHYSICAL_PREBUILD") == "true" ? ENV.fetch("IOS_PHYSICAL_PREBUILD_LOG_SHA256") : nil,
      "application_binary" => ENV.fetch("IOS_PHYSICAL_PREBUILD") == "true" ? "build/ios/iphoneos/Collect.app" : nil
    },
    "variant" => {
      "name" => ENV.fetch("IOS_PHYSICAL_VARIANT_NAME"),
      "theme_mode" => ENV.fetch("IOS_PHYSICAL_THEME_MODE"),
      "text_scale" => ENV.fetch("IOS_PHYSICAL_TEXT_SCALE").to_f,
      "high_contrast" => ENV.fetch("IOS_PHYSICAL_HIGH_CONTRAST") == "true",
      "reduced_motion" => ENV.fetch("IOS_PHYSICAL_REDUCED_MOTION") == "true"
    },
    "route_expected" => route_expected,
    "route_passes" => route_passes,
    "scope" => {
      "physical_iphone" => true,
      "foreground_background_lifecycle" => mode == "lifecycle" && lifecycle_marker && host_action_pass,
      "contribution_review_state_preserved" => mode == "lifecycle" && lifecycle_marker && host_action_pass,
      "native_camera_permission_dialog" => mode == "camera-settings" && camera_marker,
      "camera_settings_recovery" => mode == "camera-settings" && camera_marker,
      "voiceover" => false
    },
    "screenshots_required" => false,
    "screenshot_disposition" => "Flutter reports no host screenshot capability for this physical target; route/render assertions and native install/launch are retained without screenshots.",
    "device_visible_after" => device_visible_after,
    "secret_handling" => "The physical run uses fixture-only app state. Evidence excludes screenshots, signing material, raw device inventory, serial/ECID values, raw SMS, OTPs, phone/MoMo receiver data, provider tokens, and production customer data."
  }
)
RUBY

printf '[ios-physical-route-uat] status=%s evidence=%s log=%s mode=%s routes=%s/%s\n' \
  "$status" "${SUMMARY_FILE#$ROOT_DIR/}" "${LOG_FILE#$ROOT_DIR/}" "$UAT_MODE" "$route_passes" "$route_expected" >&2
exit "$rc"
