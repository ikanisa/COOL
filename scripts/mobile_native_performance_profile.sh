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

usage() {
  cat <<'USAGE'
usage: scripts/mobile_native_performance_profile.sh [--json]

Runs Collect mobile integration coverage in Flutter profile mode and stores
startup/perf trace artifacts. If the configured Android device is unavailable,
the script writes a blocked JSON summary and exits 99.

Environment:
  ADB
  FLUTTER                            default: /Volumes/PRO-G40/flutter_3_44/bin/flutter
  MOBILE_PERF_DEVICE_ID              default: 13111JEC215558
  MOBILE_PERF_FLAVOR                 default: production
  MOBILE_PERF_TEST_TARGET            default: integration_test/app_uat_smoke_test.dart
  MOBILE_PERF_DRIVER                 default: test_driver/integration_test.dart
  MOBILE_PERF_TIMEOUT_SECONDS        default: 1200
  MOBILE_PERF_EVIDENCE_DIR           default: .cache/mobile_native_performance_profile/<timestamp>
USAGE
}

OUTPUT_FORMAT="text"
case "${1:-}" in
  "")
    ;;
  --json)
    OUTPUT_FORMAT="json"
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

ADB="$(resolve_adb)"
FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
DEVICE_ID="${MOBILE_PERF_DEVICE_ID:-13111JEC215558}"
FLAVOR="${MOBILE_PERF_FLAVOR:-production}"
TEST_TARGET="${MOBILE_PERF_TEST_TARGET:-integration_test/app_uat_smoke_test.dart}"
DRIVER="${MOBILE_PERF_DRIVER:-test_driver/integration_test.dart}"
TIMEOUT_SECONDS="${MOBILE_PERF_TIMEOUT_SECONDS:-1200}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${MOBILE_PERF_EVIDENCE_DIR:-$ROOT_DIR/.cache/mobile_native_performance_profile/$timestamp}"
LOG_FILE="$EVIDENCE_DIR/mobile_native_performance_profile.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
RUNNER_RESULT_FILE="$EVIDENCE_DIR/runner_result.json"
TRACE_FILE="$EVIDENCE_DIR/timeline.binpb"
SCREENSHOT_DIR="$EVIDENCE_DIR/screenshots"

mkdir -p "$EVIDENCE_DIR" "$SCREENSHOT_DIR"

write_summary() {
  local status="$1"
  local exit_code="$2"
  local reason="${3:-}"
  MOBILE_PERF_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  MOBILE_PERF_STATUS="$status" \
  MOBILE_PERF_EXIT_CODE="$exit_code" \
  MOBILE_PERF_REASON="$reason" \
  MOBILE_PERF_DEVICE_ID="$DEVICE_ID" \
  MOBILE_PERF_FLAVOR="$FLAVOR" \
  MOBILE_PERF_TEST_TARGET="$TEST_TARGET" \
  MOBILE_PERF_DRIVER="$DRIVER" \
  MOBILE_PERF_EVIDENCE_DIR="$EVIDENCE_DIR" \
  MOBILE_PERF_LOG_FILE="$LOG_FILE" \
  MOBILE_PERF_RESULT_FILE="$RUNNER_RESULT_FILE" \
  MOBILE_PERF_TRACE_FILE="$TRACE_FILE" \
  MOBILE_PERF_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
  ruby -r json -e '
    root = Dir.pwd
    def rel(root, path)
      path.to_s.delete_prefix("#{root}/")
    end

    trace = ENV.fetch("MOBILE_PERF_TRACE_FILE")
    log = ENV.fetch("MOBILE_PERF_LOG_FILE")
    result = ENV.fetch("MOBILE_PERF_RESULT_FILE")
    status = ENV.fetch("MOBILE_PERF_STATUS")
    reason = ENV.fetch("MOBILE_PERF_REASON")
    runner = File.exist?(result) ? JSON.parse(File.read(result)) : {}
    trace_bytes = File.exist?(trace) ? File.size(trace) : 0
    log_bytes = File.exist?(log) ? File.size(log) : 0
    failures = []
    failures << reason unless reason.empty?
    if status == "pass"
      failures << "Profile-mode runner did not exit cleanly." unless runner.fetch("exit_code", 1).to_i == 0
      failures << "Perfetto timeline trace was not written." unless trace_bytes > 1024
      failures << "Profile run log was not written." unless log_bytes > 0
    end
    computed_status =
      if status == "blocked"
        "blocked"
      elsif failures.empty?
        "pass"
      else
        "fail"
      end
    summary = {
      "generated_at" => ENV.fetch("MOBILE_PERF_GENERATED_AT"),
      "status" => computed_status,
      "mode" => "profile",
      "device_id" => ENV.fetch("MOBILE_PERF_DEVICE_ID"),
      "flavor" => ENV.fetch("MOBILE_PERF_FLAVOR"),
      "target" => ENV.fetch("MOBILE_PERF_TEST_TARGET"),
      "driver" => ENV.fetch("MOBILE_PERF_DRIVER"),
      "timeout_seconds" => ENV.fetch("MOBILE_PERF_TIMEOUT_SECONDS").to_i,
      "artifacts" => {
        "evidence_dir" => rel(root, ENV.fetch("MOBILE_PERF_EVIDENCE_DIR")),
        "log" => rel(root, log),
        "runner_result" => rel(root, result),
        "trace" => rel(root, trace),
        "screenshots" => rel(root, File.join(ENV.fetch("MOBILE_PERF_EVIDENCE_DIR"), "screenshots"))
      },
      "metrics" => {
        "trace_bytes" => trace_bytes,
        "log_bytes" => log_bytes,
        "runner_exit_code" => runner["exit_code"],
        "timed_out" => runner["timed_out"]
      },
      "checks" => [
        {
          "id" => "profile_mode_runner",
          "status" => runner.fetch("exit_code", 1).to_i == 0 ? "pass" : computed_status,
          "evidence" => [rel(root, log), rel(root, result)]
        },
        {
          "id" => "perfetto_timeline_trace",
          "status" => trace_bytes > 1024 ? "pass" : computed_status,
          "evidence" => [rel(root, trace)]
        }
      ],
      "failures" => failures,
      "secret_handling" => "The profile script stores tool logs, screenshots, and timeline metadata only. It must not print OTPs, raw SMS, PINs, signing secrets, or private receiver data."
    }
    File.write(File.join(ENV.fetch("MOBILE_PERF_EVIDENCE_DIR"), "summary.json"), JSON.pretty_generate(summary) + "\n")
  '
}

if ! "$ADB" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  write_summary "blocked" 99 "Android performance device $DEVICE_ID is not connected and authorized over ADB."
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    cat "$SUMMARY_FILE"
  else
    printf '[mobile-native-performance][BLOCKED] Android device %s is not connected and authorized. evidence=%s\n' "$DEVICE_ID" "${EVIDENCE_DIR#$ROOT_DIR/}" >&2
  fi
  exit 99
fi

window_state="$("$ADB" -s "$DEVICE_ID" shell dumpsys window 2>/dev/null || true)"
if grep -q 'mKeyguardShowing=true' <<<"$window_state" ||
  grep -Eiq 'm(CurrentFocus|FocusedApp)=.*(Keyguard|Lockscreen)' <<<"$window_state"; then
  write_summary "blocked" 99 "Android performance device $DEVICE_ID is locked."
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    cat "$SUMMARY_FILE"
  else
    printf '[mobile-native-performance][BLOCKED] Android device %s is locked. evidence=%s\n' "$DEVICE_ID" "${EVIDENCE_DIR#$ROOT_DIR/}" >&2
  fi
  exit 99
fi

cmd=(
  "$FLUTTER"
  drive
  --profile
  --no-pub
  --driver="$DRIVER"
  --target="$TEST_TARGET"
  -d "$DEVICE_ID"
  --flavor "$FLAVOR"
  --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true
  --trace-startup
  --trace-to-file="$TRACE_FILE"
  --timeout="$TIMEOUT_SECONDS"
)

printf '[mobile-native-performance] adb=%s device=%s flavor=%s target=%s evidence=%s timeout_seconds=%s\n' \
  "$ADB" "$DEVICE_ID" "$FLAVOR" "$TEST_TARGET" "${EVIDENCE_DIR#$ROOT_DIR/}" "$TIMEOUT_SECONDS" >&2

set +e
FLUTTER_TEST_OUTPUTS_DIR="$EVIDENCE_DIR" \
INTEGRATION_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
MOBILE_PERF_LOG_FILE="$LOG_FILE" \
MOBILE_PERF_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
MOBILE_PERF_RUNNER_RESULT_FILE="$RUNNER_RESULT_FILE" \
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

  log = ENV.fetch("MOBILE_PERF_LOG_FILE")
  timeout = Integer(ENV.fetch("MOBILE_PERF_TIMEOUT_SECONDS"))
  result = ENV.fetch("MOBILE_PERF_RUNNER_RESULT_FILE")
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
run_exit=$?
set -e

if [[ "$run_exit" == "0" ]]; then
  write_summary "pass" 0 ""
else
  write_summary "fail" "$run_exit" "Profile-mode Flutter drive exited with code $run_exit."
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  cat "$SUMMARY_FILE"
else
  status="$(ruby -r json -e 'puts JSON.parse(File.read(ARGV[0])).fetch("status")' "$SUMMARY_FILE")"
  printf '[mobile-native-performance] status=%s evidence=%s\n' "$status" "${EVIDENCE_DIR#$ROOT_DIR/}" >&2
fi

summary_status="$(ruby -r json -e 'puts JSON.parse(File.read(ARGV[0])).fetch("status")' "$SUMMARY_FILE")"
case "$summary_status" in
  pass)
    exit 0
    ;;
  blocked)
    exit 99
    ;;
  *)
    if [[ "$run_exit" == "0" ]]; then
      exit 1
    fi
    exit "$run_exit"
    ;;
esac
