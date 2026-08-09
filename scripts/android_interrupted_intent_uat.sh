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

ADB="$(resolve_adb)"
DEVICE_ID="${ANDROID_INTERRUPTED_INTENT_DEVICE_ID:-}"
ALLOW_PHYSICAL="${ANDROID_INTERRUPTED_INTENT_ALLOW_PHYSICAL:-false}"
export COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY="${COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY:-false}"
PACKAGE="${ANDROID_INTERRUPTED_INTENT_PACKAGE:-app.cool.mobile.dev}"
ACTIVITY="${ANDROID_INTERRUPTED_INTENT_ACTIVITY:-app.cool.mobile.MainActivity}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_INTERRUPTED_INTENT_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_interrupted_intent_uat/$timestamp}"
SCREENSHOT_DIR="$EVIDENCE_DIR/screenshots"
UI_DIR="$EVIDENCE_DIR/ui"
LOG_FILE="$EVIDENCE_DIR/android_interrupted_intent_uat.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
APK="$ROOT_DIR/build/app/outputs/flutter-apk/app-dev-debug.apk"

fail() {
  printf '[android-interrupted-intent-uat][FAIL] %s\n' "$*" >&2
  exit 1
}

if [[ -z "$DEVICE_ID" ]]; then
  fail "ANDROID_INTERRUPTED_INTENT_DEVICE_ID is required."
fi
if [[ "$DEVICE_ID" != emulator-* && "$ALLOW_PHYSICAL" != "true" ]]; then
  fail "Physical-device mutation is disabled. Use a controlled emulator."
fi
if ! "$ADB" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  fail "Android target $DEVICE_ID is not connected and authorized."
fi

mkdir -p "$SCREENSHOT_DIR" "$UI_DIR"
: >"$LOG_FILE"

record() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

dump_ui() {
  local name="$1"
  local remote="/data/local/tmp/collect-interrupted-intent-$name.xml"
  "$ADB" -s "$DEVICE_ID" shell uiautomator dump --compressed "$remote" >/dev/null
  "$ADB" -s "$DEVICE_ID" exec-out cat "$remote" >"$UI_DIR/$name.xml"
  "$ADB" -s "$DEVICE_ID" shell rm -f "$remote" >/dev/null 2>&1 || true
}

wait_for_text() {
  local expected="$1"
  local name="$2"
  local timeout_seconds="${3:-90}"
  local deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    dump_ui "$name"
    if grep -Fq "$expected" "$UI_DIR/$name.xml"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

capture() {
  local name="$1"
  "$ADB" -s "$DEVICE_ID" exec-out screencap -p >"$SCREENSHOT_DIR/$name.png"
  [[ -s "$SCREENSHOT_DIR/$name.png" ]] || fail "Screenshot $name is empty."
}

start_launcher() {
  "$ADB" -s "$DEVICE_ID" shell am start -W \
    -n "$PACKAGE/$ACTIVITY" >>"$LOG_FILE"
}

record "device_id=$DEVICE_ID"
record "avd_name=$("$ADB" -s "$DEVICE_ID" emu avd name 2>/dev/null | tr -d '\r' | head -1)"
record "target=integration_test/mobile_interrupted_intent_evidence_app.dart"

flutter build apk \
  --debug \
  --flavor dev \
  --dart-define=FLAVOR=dev \
  --no-pub \
  -t integration_test/mobile_interrupted_intent_evidence_app.dart \
  >>"$LOG_FILE" 2>&1
[[ -s "$APK" ]] || fail "Debug evidence APK was not produced."

"$ADB" -s "$DEVICE_ID" install -r "$APK" >>"$LOG_FILE"
"$ADB" -s "$DEVICE_ID" shell pm clear "$PACKAGE" >>"$LOG_FILE"

start_launcher
wait_for_text "Interrupted intent retained" "01-seeded" 90 ||
  fail "The evidence app did not persist and expose the seeded intent."
capture "01-seeded-before-process-death"
seed_pid="$("$ADB" -s "$DEVICE_ID" shell pidof "$PACKAGE" | tr -d '\r')"
[[ -n "$seed_pid" ]] || fail "Seed process PID is missing."
record "seed_pid=$seed_pid"

"$ADB" -s "$DEVICE_ID" shell am force-stop "$PACKAGE"
if [[ -n "$("$ADB" -s "$DEVICE_ID" shell pidof "$PACKAGE" | tr -d '\r')" ]]; then
  fail "The controlled process remained alive after force-stop."
fi
record "process_death_verified=true"

start_launcher
wait_for_text "St Michel building fund" "02-cold-recovered" 120 ||
  fail "The cold restart did not restore and open the persisted group intent."
capture "02-cold-restart-recovered"
recovered_pid="$("$ADB" -s "$DEVICE_ID" shell pidof "$PACKAGE" | tr -d '\r')"
[[ -n "$recovered_pid" && "$recovered_pid" != "$seed_pid" ]] ||
  fail "Cold restart did not create a distinct application process."
record "recovered_pid=$recovered_pid"

"$ADB" -s "$DEVICE_ID" shell am start -W \
  -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d "https://collect.ikanisa.com/c/kigali-lions-away-kit" \
  "$PACKAGE" >>"$LOG_FILE"
wait_for_text "Kigali Lions away kit" "03-warm-link" 120 ||
  fail "The warm App Link did not open the second controlled group."
capture "03-warm-app-link"
warm_pid="$("$ADB" -s "$DEVICE_ID" shell pidof "$PACKAGE" | tr -d '\r')"
[[ "$warm_pid" == "$recovered_pid" ]] ||
  fail "Warm App Link replaced the process instead of using the singleTop activity."
record "warm_single_process_verified=true"

"$ADB" -s "$DEVICE_ID" shell am force-stop "$PACKAGE"
start_launcher
wait_for_text "Total collected" "04-cleared-restart" 120 ||
  fail "A completed intent was replayed after its success-clearing restart."
capture "04-completed-intents-not-replayed"
record "completed_intents_not_replayed=true"

"$ADB" -s "$DEVICE_ID" shell dumpsys activity activities \
  >"$EVIDENCE_DIR/activity_state.txt"

DEVICE_ID="$DEVICE_ID" \
PACKAGE="$PACKAGE" \
APK="$APK" \
EVIDENCE_DIR="$EVIDENCE_DIR" \
SEED_PID="$seed_pid" \
RECOVERED_PID="$recovered_pid" \
WARM_PID="$warm_pid" \
ruby -r digest -r json -r time <<'RUBY' >"$SUMMARY_FILE"
root = ENV.fetch("EVIDENCE_DIR")
files = Dir[File.join(root, "**", "*")].select { |path| File.file?(path) }
  .reject do |path|
    path.end_with?("summary.json") ||
      path.end_with?("android_interrupted_intent_uat.txt")
  end
hashes = files.sort.to_h do |path|
  [path.delete_prefix("#{root}/"), Digest::SHA256.file(path).hexdigest]
end
apk = ENV.fetch("APK")
puts JSON.pretty_generate(
  "generated_at" => Time.now.utc.iso8601,
  "status" => "pass",
  "scope" => "controlled Android emulator; fixture data; no production mutation",
  "device_id" => ENV.fetch("DEVICE_ID"),
  "package" => ENV.fetch("PACKAGE"),
  "apk" => {
    "path" => apk,
    "bytes" => File.size(apk),
    "sha256" => Digest::SHA256.file(apk).hexdigest
  },
  "checks" => {
    "persisted_before_process_death" => true,
    "process_death_and_distinct_cold_restart" =>
      ENV.fetch("SEED_PID") != ENV.fetch("RECOVERED_PID"),
    "cold_restart_recovered_intent" => true,
    "warm_app_link_same_process" =>
      ENV.fetch("RECOVERED_PID") == ENV.fetch("WARM_PID"),
    "completed_intents_not_replayed" => true
  },
  "artifact_sha256" => hashes
)
RUBY

record "summary=$SUMMARY_FILE"
record "result=pass"
printf '%s\n' "$EVIDENCE_DIR"
