#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command adb
if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Missing executable Flutter wrapper: $FLUTTER_BIN" >&2
  exit 1
fi

FLAVOR="${FLAVOR:-staging}"
DEVICE="${DEVICE:-}"
TARGET="${TARGET:-integration_test/momo_sms_inbox_sync_test.dart}"
DRIVER="${DRIVER:-test_driver/integration_test.dart}"
ARTIFACT_DIR="${ARTIFACT_DIR:-build/momo_sms_device_integration}"

device_args=()
if [[ -n "$DEVICE" ]]; then
  device_args=(-s "$DEVICE")
fi

case "$FLAVOR" in
  production)
    package_name="app.cool.mobile"
    apk_path="build/app/outputs/flutter-apk/app-production-debug.apk"
    ;;
  staging)
    package_name="app.cool.mobile.staging"
    apk_path="build/app/outputs/flutter-apk/app-staging-debug.apk"
    ;;
  *)
    echo "Unsupported FLAVOR: $FLAVOR" >&2
    exit 1
    ;;
esac

mkdir -p "$ARTIFACT_DIR"

collect_artifacts() {
  adb "${device_args[@]}" logcat -d >"$ARTIFACT_DIR/logcat.txt" 2>/dev/null || true
  DEVICE="$DEVICE" bash "$ROOT_DIR/scripts/seed_android_momo_sms_test_inbox.sh" query >"$ARTIFACT_DIR/seeded_sms_query.txt" 2>/dev/null || true
  adb "${device_args[@]}" shell dumpsys package "$package_name" >"$ARTIFACT_DIR/package_dump.txt" 2>/dev/null || true
}

cleanup() {
  DEVICE="$DEVICE" bash "$ROOT_DIR/scripts/seed_android_momo_sms_test_inbox.sh" clean || true
}

trap 'collect_artifacts; cleanup' EXIT

echo "==> waiting for Android device"
adb "${device_args[@]}" wait-for-device
adb "${device_args[@]}" shell input keyevent 82 >/dev/null 2>&1 || true

echo "==> flutter pub get"
"$FLUTTER_BIN" pub get

echo "==> build device integration apk"
"$FLUTTER_BIN" build apk \
  --debug \
  "--flavor=$FLAVOR" \
  "--target=$TARGET" \
  "--dart-define=FLAVOR=$FLAVOR"

echo "==> install apk"
adb "${device_args[@]}" install -r "$apk_path"

echo "==> grant SMS permissions"
adb "${device_args[@]}" shell pm grant "$package_name" android.permission.READ_SMS
adb "${device_args[@]}" shell pm grant "$package_name" android.permission.RECEIVE_SMS

echo "==> seed Android SMS inbox"
DEVICE="$DEVICE" bash "$ROOT_DIR/scripts/seed_android_momo_sms_test_inbox.sh" seed \
  >"$ARTIFACT_DIR/seed_output.txt"

echo "==> run M-Money SMS device integration"
drive_cmd=(
  "$FLUTTER_BIN" drive
  "--driver=$DRIVER"
  "--target=$TARGET"
  "--use-application-binary=$apk_path"
  "--flavor=$FLAVOR"
  "--dart-define=FLAVOR=$FLAVOR"
)

if [[ -n "$DEVICE" ]]; then
  drive_cmd+=(-d "$DEVICE")
fi

"${drive_cmd[@]}"
