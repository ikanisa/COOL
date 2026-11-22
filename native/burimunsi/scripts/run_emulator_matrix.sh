#!/usr/bin/env bash
# Explicit CI-only API26/API36 synthetic instrumentation. Never target a physical phone.
# Requires installed/licensed google_apis x86_64 images; does not accept licences.
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo 'This helper is restricted to an ephemeral GitHub Actions runner. Use native_pipeline.py instrument locally.' >&2
  exit 2
fi
: "${ANDROID_HOME:?Set ANDROID_HOME}"
: "${RUNNER_TEMP:?Set RUNNER_TEMP}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:?Pass the successful build evidence directory}"
OUT="${2:?Pass a new emulator evidence directory}"
mkdir "$OUT"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
test -x "$SDKMANAGER" && test -x "$AVDMANAGER" && test -x "$ADB"
test -r /dev/kvm && test -w /dev/kvm
# Restrict AVD creation/deletion to this run; do not touch the user's .android directory.
export ANDROID_AVD_HOME="$OUT/avds"
mkdir "$ANDROID_AVD_HOME"
export ANDROID_EMULATOR_HOME="$OUT/emulator-home"
mkdir "$ANDROID_EMULATOR_HOME"
PID=''
SERIAL=''
cleanup() {
  if [[ -n "$PID" ]]; then
    "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
}
finish() {
  cleanup
  # These paths were freshly created under the caller's new CI evidence directory.
  rm -rf -- "$ANDROID_AVD_HOME" "$ANDROID_EMULATOR_HOME"
}
trap finish EXIT
for API in 26 36; do
  IMAGE="system-images;android-$API;google_apis;x86_64"
  "$SDKMANAGER" --sdk_root="$ANDROID_HOME" emulator "$IMAGE" </dev/null >"$OUT/sdk-api$API.log" 2>&1
  test -x "$EMULATOR"
  NAME="BuriMunsi_API${API}_${GITHUB_RUN_ID:-local}_${GITHUB_RUN_ATTEMPT:-1}"
  printf 'no\n' | "$AVDMANAGER" create avd --name "$NAME" --package "$IMAGE" >"$OUT/avd-api$API.log" 2>&1
  SERIAL='emulator-5580'
  if "$ADB" devices | grep -q "^$SERIAL[[:space:]]"; then
    echo "Refusing to take over an existing emulator: $SERIAL" >&2; exit 2
  fi
  "$EMULATOR" -avd "$NAME" -port 5580 -no-window -no-audio -no-boot-anim \
    -no-snapshot -gpu swiftshader_indirect -accel on >"$OUT/emulator-api$API.log" 2>&1 &
  PID=$!
  READY=false
  for _ in $(seq 1 180); do
    if ! kill -0 "$PID" 2>/dev/null; then echo 'Emulator exited before boot' >&2; exit 2; fi
    if [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then READY=true; break; fi
    sleep 2
  done
  if [[ "$READY" != true ]]; then echo 'Emulator boot timed out' >&2; exit 2; fi
  "$ADB" -s "$SERIAL" shell input keyevent 82
  python3 "$HERE/scripts/native_pipeline.py" instrument --execute \
    --build-evidence "$BUILD" --output "$OUT/api$API" --serial "$SERIAL"
  cleanup
  PID=''
done
# Keep logs/screenshots, not large writable AVD disk images.
rm -rf -- "$ANDROID_AVD_HOME" "$ANDROID_EMULATOR_HOME"
