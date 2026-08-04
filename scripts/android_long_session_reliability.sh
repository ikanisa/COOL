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
  printf 'adb\n'
}

ADB_BIN="$(resolve_adb)"
DEVICE_ID="${ANDROID_RELIABILITY_DEVICE_ID:-}"
ALLOW_PHYSICAL="${ANDROID_RELIABILITY_ALLOW_PHYSICAL:-false}"
PACKAGE="${ANDROID_RELIABILITY_PACKAGE:-app.cool.mobile.dev}"
ACTIVITY="${ANDROID_RELIABILITY_ACTIVITY:-app.cool.mobile.MainActivity}"
DURATION_SECONDS="${ANDROID_RELIABILITY_DURATION_SECONDS:-600}"
ACTION_INTERVAL_SECONDS="${ANDROID_RELIABILITY_ACTION_INTERVAL_SECONDS:-2}"
SAMPLE_INTERVAL_SECONDS="${ANDROID_RELIABILITY_SAMPLE_INTERVAL_SECONDS:-30}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_RELIABILITY_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_long_session_reliability/$timestamp}"
LOG_FILE="$EVIDENCE_DIR/android_long_session_reliability.txt"
LOGCAT_FILE="$EVIDENCE_DIR/logcat.txt"
MEMORY_FILE="$EVIDENCE_DIR/memory_samples.tsv"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"

fail() {
  printf '[android-long-session][FAIL] %s\n' "$*" >&2
  exit 1
}

if [[ -z "$DEVICE_ID" ]]; then
  fail "ANDROID_RELIABILITY_DEVICE_ID is required."
fi
if [[ "$DEVICE_ID" != emulator-* && "$ALLOW_PHYSICAL" != "true" ]]; then
  fail "Physical-device interaction is disabled. Use a controlled emulator or explicitly opt in."
fi
if ! "$ADB_BIN" devices | awk \
  'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' \
  id="$DEVICE_ID"; then
  fail "Android target $DEVICE_ID is not connected and authorized."
fi
if ! "$ADB_BIN" -s "$DEVICE_ID" shell pm path "$PACKAGE" | grep -q '^package:'; then
  fail "Package $PACKAGE is not installed on $DEVICE_ID."
fi
if [[ "$PACKAGE" != *.dev ]]; then
  fail "The default reliability harness is fixture-only and refuses a non-dev package."
fi
if ! [[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] || (( DURATION_SECONDS < 60 )); then
  fail "ANDROID_RELIABILITY_DURATION_SECONDS must be an integer of at least 60."
fi
if ! [[ "$ACTION_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || (( ACTION_INTERVAL_SECONDS < 1 )); then
  fail "ANDROID_RELIABILITY_ACTION_INTERVAL_SECONDS must be a positive integer."
fi
if ! [[ "$SAMPLE_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || (( SAMPLE_INTERVAL_SECONDS < 5 )); then
  fail "ANDROID_RELIABILITY_SAMPLE_INTERVAL_SECONDS must be at least 5 seconds."
fi

interfering_harnesses="$(
  ps -axo pid=,command= |
    awk -v self="$$" '
      $1 != self &&
      $0 ~ /scripts\/android_native_accessibility_measurement[.]sh/ {
        print $0
      }
    '
)"
if [[ -n "$interfering_harnesses" ]]; then
  fail "A native accessibility harness is active and could reset the fixture package: $interfering_harnesses"
fi

mkdir -p "$EVIDENCE_DIR/screenshots" "$EVIDENCE_DIR/dumpsys"
: >"$LOG_FILE"
printf 'elapsed_seconds\tpid\ttotal_pss_kb\ttotal_rss_kb\n' >"$MEMORY_FILE"

record() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

screen_size="$("$ADB_BIN" -s "$DEVICE_ID" shell wm size | tr -d '\r')"
physical_width="$(printf '%s\n' "$screen_size" | sed -n 's/^Physical size: \([0-9][0-9]*\)x[0-9][0-9]*$/\1/p' | tail -1)"
physical_height="$(printf '%s\n' "$screen_size" | sed -n 's/^Physical size: [0-9][0-9]*x\([0-9][0-9]*\)$/\1/p' | tail -1)"
screen_width="$(printf '%s\n' "$screen_size" | sed -n 's/^Override size: \([0-9][0-9]*\)x[0-9][0-9]*$/\1/p' | tail -1)"
screen_height="$(printf '%s\n' "$screen_size" | sed -n 's/^Override size: [0-9][0-9]*x\([0-9][0-9]*\)$/\1/p' | tail -1)"
if [[ -z "$screen_width" || -z "$screen_height" ]]; then
  screen_width="$physical_width"
  screen_height="$physical_height"
fi
[[ -n "$screen_width" && -n "$screen_height" &&
  -n "$physical_width" && -n "$physical_height" ]] ||
  fail "Could not resolve the Android display size."

nav_y=$((physical_height * 91 / 100))
home_x=$((physical_width * 13 / 100))
groups_x=$((physical_width * 31 / 100))
contribute_x=$((physical_width * 50 / 100))
activity_x=$((physical_width * 69 / 100))
profile_x=$((physical_width * 88 / 100))
route_x=("$home_x" "$groups_x" "$contribute_x" "$activity_x" "$profile_x")
route_names=("home" "groups" "contribute" "activity" "profile")

package_version="$("$ADB_BIN" -s "$DEVICE_ID" shell dumpsys package "$PACKAGE" |
  sed -n 's/^[[:space:]]*versionName=//p' | head -1 | tr -d '\r')"
package_code="$("$ADB_BIN" -s "$DEVICE_ID" shell dumpsys package "$PACKAGE" |
  sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -1 | tr -d '\r')"
avd_name="$("$ADB_BIN" -s "$DEVICE_ID" emu avd name 2>/dev/null | tr -d '\r' | head -1)"

record "device_id=$DEVICE_ID"
record "avd_name=$avd_name"
record "package=$PACKAGE"
record "version_name=$package_version"
record "version_code=$package_code"
record "render_display=${screen_width}x${screen_height}"
record "physical_touch_display=${physical_width}x${physical_height}"
record "duration_seconds=$DURATION_SECONDS"
record "action_interval_seconds=$ACTION_INTERVAL_SECONDS"
record "sample_interval_seconds=$SAMPLE_INTERVAL_SECONDS"
record "scope=controlled Android target; installed dev fixture; no production mutation"

"$ADB_BIN" -s "$DEVICE_ID" logcat -c
"$ADB_BIN" -s "$DEVICE_ID" shell am start -W \
  -n "$PACKAGE/$ACTIVITY" >>"$LOG_FILE"
sleep 3
initial_pid="$("$ADB_BIN" -s "$DEVICE_ID" shell pidof "$PACKAGE" | tr -d '\r')"
[[ -n "$initial_pid" ]] || fail "The app process did not start."
record "initial_pid=$initial_pid"
"$ADB_BIN" -s "$DEVICE_ID" exec-out screencap -p \
  >"$EVIDENCE_DIR/screenshots/01-start.png"

start_epoch="$(date +%s)"
next_sample=0
cycle=0
background_foreground_count=0
route_action_count=0
pid_change_count=0
last_pid="$initial_pid"
failure_reason=""

while true; do
  now_epoch="$(date +%s)"
  elapsed=$((now_epoch - start_epoch))
  if (( elapsed >= DURATION_SECONDS )); then
    break
  fi

  index=$((cycle % ${#route_x[@]}))
  "$ADB_BIN" -s "$DEVICE_ID" shell input tap "${route_x[$index]}" "$nav_y"
  route_action_count=$((route_action_count + 1))
  record "action elapsed=$elapsed route=${route_names[$index]}"

  if (( cycle > 0 && cycle % 15 == 0 )); then
    "$ADB_BIN" -s "$DEVICE_ID" shell input keyevent KEYCODE_HOME
    sleep 1
    "$ADB_BIN" -s "$DEVICE_ID" shell am start -W \
      -n "$PACKAGE/$ACTIVITY" >>"$LOG_FILE"
    background_foreground_count=$((background_foreground_count + 1))
    record "action elapsed=$elapsed background_foreground=true"
  fi

  current_pid="$("$ADB_BIN" -s "$DEVICE_ID" shell pidof "$PACKAGE" | tr -d '\r')"
  if [[ -z "$current_pid" ]]; then
    failure_reason="app_process_disappeared_at_${elapsed}s"
    record "failure_reason=$failure_reason"
    break
  fi
  if [[ "$current_pid" != "$last_pid" ]]; then
    pid_change_count=$((pid_change_count + 1))
    record "pid_change elapsed=$elapsed previous=$last_pid current=$current_pid"
    last_pid="$current_pid"
  fi

  if (( elapsed >= next_sample )); then
    meminfo="$("$ADB_BIN" -s "$DEVICE_ID" shell dumpsys meminfo "$PACKAGE")"
    total_pss="$(printf '%s\n' "$meminfo" | awk '/TOTAL PSS:/ { print $3; exit }')"
    total_rss="$(printf '%s\n' "$meminfo" | awk '/TOTAL RSS:/ { print $3; exit }')"
    if [[ -z "$total_pss" ]]; then
      total_pss="$(printf '%s\n' "$meminfo" | awk '$1 == "TOTAL" { print $2; exit }')"
    fi
    if [[ -z "$total_rss" ]]; then
      total_rss="$(printf '%s\n' "$meminfo" | awk '$1 == "TOTAL" { print $8; exit }')"
    fi
    total_pss="${total_pss:-0}"
    total_rss="${total_rss:-0}"
    printf '%s\t%s\t%s\t%s\n' \
      "$elapsed" "$current_pid" "$total_pss" "$total_rss" >>"$MEMORY_FILE"
    printf '%s\n' "$meminfo" >"$EVIDENCE_DIR/dumpsys/meminfo-${elapsed}s.txt"
    "$ADB_BIN" -s "$DEVICE_ID" shell dumpsys gfxinfo "$PACKAGE" \
      >"$EVIDENCE_DIR/dumpsys/gfxinfo-${elapsed}s.txt"
    next_sample=$((elapsed + SAMPLE_INTERVAL_SECONDS))
  fi

  cycle=$((cycle + 1))
  sleep "$ACTION_INTERVAL_SECONDS"
done

final_pid="$("$ADB_BIN" -s "$DEVICE_ID" shell pidof "$PACKAGE" | tr -d '\r')"
"$ADB_BIN" -s "$DEVICE_ID" logcat -d -v threadtime >"$LOGCAT_FILE"
"$ADB_BIN" -s "$DEVICE_ID" shell dumpsys activity exit-info "$PACKAGE" \
  >"$EVIDENCE_DIR/dumpsys/application-exit-info.txt" 2>&1 || true
"$ADB_BIN" -s "$DEVICE_ID" shell dumpsys activity processes \
  >"$EVIDENCE_DIR/dumpsys/activity-processes.txt"
"$ADB_BIN" -s "$DEVICE_ID" shell dumpsys dropbox \
  --print system_app_crash system_app_anr data_app_crash data_app_anr \
  >"$EVIDENCE_DIR/dumpsys/dropbox-crash-anr.txt" 2>&1 || true
if [[ -n "$final_pid" ]]; then
  "$ADB_BIN" -s "$DEVICE_ID" exec-out screencap -p \
    >"$EVIDENCE_DIR/screenshots/02-end.png"
fi

crash_anr_matches="$(
  grep -E \
    "FATAL EXCEPTION:.*|ANR in ${PACKAGE}|am_crash.*${PACKAGE}|am_anr.*${PACKAGE}|Process ${PACKAGE} .* has died|Fatal signal .*${PACKAGE}" \
    "$LOGCAT_FILE" || true
)"
crash_anr_count=0
if [[ -n "$crash_anr_matches" ]]; then
  printf '%s\n' "$crash_anr_matches" >"$EVIDENCE_DIR/crash_anr_matches.txt"
  crash_anr_count="$(printf '%s\n' "$crash_anr_matches" | wc -l | tr -d ' ')"
fi

DEVICE_ID="$DEVICE_ID" \
AVD_NAME="$avd_name" \
PACKAGE="$PACKAGE" \
PACKAGE_VERSION="$package_version" \
PACKAGE_CODE="$package_code" \
DURATION_SECONDS="$DURATION_SECONDS" \
ACTION_INTERVAL_SECONDS="$ACTION_INTERVAL_SECONDS" \
SAMPLE_INTERVAL_SECONDS="$SAMPLE_INTERVAL_SECONDS" \
INITIAL_PID="$initial_pid" \
FINAL_PID="$final_pid" \
FAILURE_REASON="$failure_reason" \
PID_CHANGE_COUNT="$pid_change_count" \
ROUTE_ACTION_COUNT="$route_action_count" \
BACKGROUND_FOREGROUND_COUNT="$background_foreground_count" \
CRASH_ANR_COUNT="$crash_anr_count" \
MEMORY_FILE="$MEMORY_FILE" \
EVIDENCE_DIR="$EVIDENCE_DIR" \
SUMMARY_FILE="$SUMMARY_FILE" \
ruby <<'RUBY'
require "csv"
require "digest"
require "json"
require "time"

memory_rows = CSV.read(ENV.fetch("MEMORY_FILE"), headers: true, col_sep: "\t")
pss_values = memory_rows.map { |row| row.fetch("total_pss_kb").to_i }
rss_values = memory_rows.map { |row| row.fetch("total_rss_kb").to_i }
crash_anr_count = Integer(ENV.fetch("CRASH_ANR_COUNT"))
pid_change_count = Integer(ENV.fetch("PID_CHANGE_COUNT"))
evidence_dir = ENV.fetch("EVIDENCE_DIR")
files = Dir[File.join(evidence_dir, "**", "*")].select { |path| File.file?(path) }
  .reject do |path|
    path.end_with?("summary.json") ||
      path.end_with?("android_long_session_reliability.txt")
  end
hashes = files.sort.to_h do |path|
  [path.delete_prefix("#{evidence_dir}/"), Digest::SHA256.file(path).hexdigest]
end

checks = {
  "process_alive_at_end" => !ENV.fetch("FINAL_PID").empty?,
  "no_observed_crash_or_anr_in_scoped_logcat" => crash_anr_count.zero?,
  "no_unexpected_pid_change" => pid_change_count.zero?,
  "route_actions_completed" => Integer(ENV.fetch("ROUTE_ACTION_COUNT")).positive?,
  "background_foreground_cycles_completed" =>
    Integer(ENV.fetch("BACKGROUND_FOREGROUND_COUNT")).positive?,
  "memory_samples_recorded" => !memory_rows.empty?
}
summary = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => checks.values.all? ? "pass" : "fail",
  "scope" => "bounded controlled-emulator dev-fixture reliability run; no production backend, Play Console, or physical-device evidence",
  "device_id" => ENV.fetch("DEVICE_ID"),
  "avd_name" => ENV.fetch("AVD_NAME"),
  "package" => ENV.fetch("PACKAGE"),
  "version_name" => ENV.fetch("PACKAGE_VERSION"),
  "version_code" => ENV.fetch("PACKAGE_CODE"),
  "duration_seconds" => Integer(ENV.fetch("DURATION_SECONDS")),
  "action_interval_seconds" => Integer(ENV.fetch("ACTION_INTERVAL_SECONDS")),
  "sample_interval_seconds" => Integer(ENV.fetch("SAMPLE_INTERVAL_SECONDS")),
  "initial_pid" => ENV.fetch("INITIAL_PID"),
  "final_pid" => ENV.fetch("FINAL_PID"),
  "failure_reason" =>
    (ENV.fetch("FAILURE_REASON").empty? ? nil : ENV.fetch("FAILURE_REASON")),
  "pid_change_count" => pid_change_count,
  "route_action_count" => Integer(ENV.fetch("ROUTE_ACTION_COUNT")),
  "background_foreground_count" => Integer(ENV.fetch("BACKGROUND_FOREGROUND_COUNT")),
  "crash_anr_match_count" => crash_anr_count,
  "memory" => {
    "sample_count" => memory_rows.length,
    "first_total_pss_kb" => pss_values.first,
    "last_total_pss_kb" => pss_values.last,
    "max_total_pss_kb" => pss_values.max,
    "first_total_rss_kb" => rss_values.first,
    "last_total_rss_kb" => rss_values.last,
    "max_total_rss_kb" => rss_values.max
  },
  "checks" => checks,
  "limitations" => [
    "Absence of a matching scoped logcat event does not replace authorized Play Developer Reporting.",
    "The run uses deterministic fixture data and does not prove live-backend or payment-provider reliability.",
    "The bounded run is not a soak-test substitute and does not close physical-device or production monitoring gates."
  ],
  "artifact_sha256" => hashes
}
File.write(ENV.fetch("SUMMARY_FILE"), JSON.pretty_generate(summary) + "\n")
exit(summary.fetch("status") == "pass" ? 0 : 1)
RUBY

record "final_pid=$final_pid"
record "route_action_count=$route_action_count"
record "background_foreground_count=$background_foreground_count"
record "crash_anr_match_count=$crash_anr_count"
record "summary=$SUMMARY_FILE"
record "result=pass"
printf '%s\n' "$EVIDENCE_DIR"
