#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/dev/flutterw}"
source "$ROOT_DIR/scripts/lib/_backend_env.sh"

FLAVOR="${FLAVOR:-staging}"
DEVICE="${DEVICE:-}"
SUITE="${SUITE:-smoke}"
TARGET="${TARGET:-}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"
UAT_DIR="${UAT_DIR:-$ROOT_DIR/.uat}"
AUTO_GRANT_SMS_PERMISSION="${AUTO_GRANT_SMS_PERMISSION:-0}"
AUTO_INSTALL_BASE_APK="${AUTO_INSTALL_BASE_APK:-1}"

require_command() {
  local command_name="${1:?missing command name}"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Missing executable Flutter wrapper: $FLUTTER_BIN" >&2
  exit 1
fi

load_client_env_files "$ROOT_DIR" \
  SUPABASE_URL \
  SUPABASE_ANON_KEY \
  SUPABASE_STAGING_URL \
  SUPABASE_STAGING_ANON_KEY \
  SUPABASE_PRODUCTION_URL \
  SUPABASE_PRODUCTION_ANON_KEY \
  COOL_DEEP_LINK_HOST
require_distinct_staging_and_production_supabase_projects
resolve_supabase_client_env "$FLAVOR"
require_resolved_supabase_client_env "$FLAVOR"

mkdir -p "$UAT_DIR"

timeout_prefix=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_prefix=(gtimeout --preserve-status "$TIMEOUT_SECONDS")
elif command -v timeout >/dev/null 2>&1; then
  timeout_prefix=(timeout --preserve-status "$TIMEOUT_SECONDS")
fi

device_args=()
if [[ -n "$DEVICE" ]]; then
  device_args=(-s "$DEVICE")
fi

resolve_suite_targets() {
  if [[ -n "$TARGET" ]]; then
    printf '%s\n' "$TARGET"
    return 0
  fi

  case "$SUITE" in
    smoke)
      printf '%s\n' "integration_test/critical_journeys_test.dart"
      ;;
    auth)
      printf '%s\n' "integration_test/auth_review_flow_test.dart"
      ;;
    groups)
      printf '%s\n' "integration_test/group_core_journeys_test.dart"
      ;;
    momo-sms)
      printf '%s\n' "integration_test/momo_sms_inbox_sync_test.dart"
      ;;
    admin-savings)
      printf '%s\n' "integration_test/admin_savings_flow_test.dart"
      ;;
    all)
      cat <<'EOF'
integration_test/critical_journeys_test.dart
integration_test/auth_review_flow_test.dart
integration_test/group_core_journeys_test.dart
integration_test/momo_sms_inbox_sync_test.dart
integration_test/admin_savings_flow_test.dart
EOF
      ;;
    *)
      echo "Unsupported SUITE: $SUITE" >&2
      echo "Supported values: smoke, auth, groups, momo-sms, admin-savings, all" >&2
      exit 1
      ;;
  esac
}

resolve_package_name() {
  case "$FLAVOR" in
    production) printf '%s\n' "app.cool.mobile" ;;
    staging) printf '%s\n' "app.cool.mobile.staging" ;;
    *)
      echo "Unsupported FLAVOR: $FLAVOR" >&2
      exit 1
      ;;
  esac
}

resolve_base_apk_path() {
  case "$FLAVOR" in
    production) printf '%s\n' "$ROOT_DIR/build/app/outputs/flutter-apk/app-production-debug.apk" ;;
    staging) printf '%s\n' "$ROOT_DIR/build/app/outputs/flutter-apk/app-staging-debug.apk" ;;
    *)
      echo "Unsupported FLAVOR: $FLAVOR" >&2
      exit 1
      ;;
  esac
}

print_cmd() {
  local rendered=("$@")
  local index
  for index in "${!rendered[@]}"; do
    case "${rendered[$index]}" in
      --dart-define=SUPABASE_ANON_KEY=*)
        rendered[$index]='--dart-define=SUPABASE_ANON_KEY=[REDACTED]'
        ;;
    esac
  done

  if [[ "${#timeout_prefix[@]}" -gt 0 ]]; then
    rendered=("${timeout_prefix[@]}" "${rendered[@]}")
  fi

  printf '==> %q ' "${rendered[@]}"
  printf '\n'
}

run_with_timeout() {
  if [[ "${#timeout_prefix[@]}" -gt 0 ]]; then
    "${timeout_prefix[@]}" "$@"
  else
    "$@"
  fi
}

target_basename() {
  local target="${1:?missing target}"
  basename "$target" .dart
}

target_requires_sms_permission() {
  local target="${1:?missing target}"
  [[ "$target" == *"momo_sms_inbox_sync_test.dart" ]]
}

package_installed() {
  local package_name="${1:?missing package name}"
  adb "${device_args[@]}" shell pm list packages "$package_name" 2>/dev/null |
    grep -q "package:${package_name}$"
}

build_base_apk() {
  local apk_path="${1:?missing apk path}"
  local build_cmd=(
    "$FLUTTER_BIN" build apk
    --debug
    "--flavor=$FLAVOR"
    "--target=lib/main.dart"
    "--dart-define=FLAVOR=$FLAVOR"
    "--dart-define=SUPABASE_URL=${RESOLVED_SUPABASE_URL}"
    "--dart-define=SUPABASE_ANON_KEY=${RESOLVED_SUPABASE_ANON_KEY}"
    "--dart-define=SUPABASE_PROJECT_REF=${RESOLVED_SUPABASE_PROJECT_REF}"
    "--dart-define=BACKEND_ENVIRONMENT=${RESOLVED_BACKEND_ENVIRONMENT}"
    "--dart-define=COOL_DEEP_LINK_HOST=${COOL_DEEP_LINK_HOST:-cool.app}"
  )
  print_cmd "${build_cmd[@]}"
  run_with_timeout "${build_cmd[@]}"

  if [[ ! -f "$apk_path" ]]; then
    echo "Expected base APK not found after build: $apk_path" >&2
    exit 1
  fi
}

ensure_package_installed() {
  local package_name="${1:?missing package name}"
  local apk_path="${2:?missing apk path}"

  if package_installed "$package_name"; then
    return 0
  fi

  if [[ "$AUTO_INSTALL_BASE_APK" != "1" ]]; then
    echo "Package $package_name is not installed on the device." >&2
    echo "Set AUTO_INSTALL_BASE_APK=1 to build and install the base debug APK automatically." >&2
    exit 1
  fi

  if [[ ! -f "$apk_path" ]]; then
    echo "==> base package missing on device; building debug APK"
    build_base_apk "$apk_path"
  fi

  echo "==> installing base debug APK"
  adb "${device_args[@]}" install -r "$apk_path"

  if ! package_installed "$package_name"; then
    echo "Failed to install $package_name on the target device." >&2
    exit 1
  fi
}

has_granted_permission() {
  local package_name="${1:?missing package name}"
  local permission_name="${2:?missing permission name}"
  adb "${device_args[@]}" shell dumpsys package "$package_name" 2>/dev/null |
    grep -q "${permission_name}: granted=true"
}

ensure_sms_permissions() {
  local package_name="${1:?missing package name}"

  if [[ "$AUTO_GRANT_SMS_PERMISSION" == "1" ]]; then
    adb "${device_args[@]}" shell pm grant "$package_name" android.permission.READ_SMS >/dev/null 2>&1 || true
    adb "${device_args[@]}" shell pm grant "$package_name" android.permission.RECEIVE_SMS >/dev/null 2>&1 || true
  fi

  if ! has_granted_permission "$package_name" "android.permission.READ_SMS"; then
    echo "READ_SMS is not granted for $package_name on the target device." >&2
    echo "Grant it manually or rerun with AUTO_GRANT_SMS_PERMISSION=1." >&2
    exit 1
  fi
}

device_preflight() {
  local package_name="${1:?missing package name}"
  local apk_path="${2:?missing apk path}"
  shift 2
  local targets=("$@")

  require_command adb
  echo "==> waiting for Android device"
  adb "${device_args[@]}" wait-for-device
  adb "${device_args[@]}" shell input keyevent 82 >/dev/null 2>&1 || true

  ensure_package_installed "$package_name" "$apk_path"

  local target
  for target in "${targets[@]}"; do
    if target_requires_sms_permission "$target"; then
      ensure_sms_permissions "$package_name"
      break
    fi
  done
}

seed_sms_suite() {
  local artifact_stem="${1:?missing artifact stem}"
  DEVICE="$DEVICE" bash "$ROOT_DIR/scripts/qa/seed_android_momo_sms_test_inbox.sh" clean >/dev/null 2>&1 || true
  DEVICE="$DEVICE" bash "$ROOT_DIR/scripts/qa/seed_android_momo_sms_test_inbox.sh" seed \
    >"$UAT_DIR/${artifact_stem}_seed_output.txt"
}

cleanup_sms_suite() {
  DEVICE="$DEVICE" bash "$ROOT_DIR/scripts/qa/seed_android_momo_sms_test_inbox.sh" clean >/dev/null 2>&1 || true
}

capture_failure_diagnostics() {
  local exit_code="${1:?missing exit code}"
  local target="${2:?missing target}"
  if [[ "$exit_code" -eq 0 ]]; then
    return
  fi

  local artifact_stem
  artifact_stem="$(target_basename "$target")"

  echo "==> collecting integration failure diagnostics into $UAT_DIR"
  if command -v adb >/dev/null 2>&1; then
    adb "${device_args[@]}" logcat -d -t 300 >"$UAT_DIR/${artifact_stem}_logcat.txt" 2>&1 || true
    adb "${device_args[@]}" shell dumpsys activity activities >"$UAT_DIR/${artifact_stem}_activity.txt" 2>&1 || true
    adb "${device_args[@]}" shell dumpsys package "$(resolve_package_name)" >"$UAT_DIR/${artifact_stem}_package.txt" 2>&1 || true
    adb "${device_args[@]}" exec-out screencap -p >"$UAT_DIR/${artifact_stem}_screen.png" 2>/dev/null || true
    if adb "${device_args[@]}" shell uiautomator dump /sdcard/cool_uat.xml >/dev/null 2>&1; then
      adb "${device_args[@]}" pull /sdcard/cool_uat.xml "$UAT_DIR/${artifact_stem}_ui.xml" >/dev/null 2>&1 || true
      adb "${device_args[@]}" shell rm -f /sdcard/cool_uat.xml >/dev/null 2>&1 || true
    fi
    if target_requires_sms_permission "$target"; then
      DEVICE="$DEVICE" bash "$ROOT_DIR/scripts/qa/seed_android_momo_sms_test_inbox.sh" query \
        >"$UAT_DIR/${artifact_stem}_seeded_sms.txt" 2>&1 || true
    fi
  fi
}

run_target() {
  local target="${1:?missing target}"
  local artifact_stem
  artifact_stem="$(target_basename "$target")"

  if target_requires_sms_permission "$target"; then
    echo "==> seeding Android SMS inbox for $artifact_stem"
    seed_sms_suite "$artifact_stem"
  fi

  local cmd=(
    "$FLUTTER_BIN" test
    "$target"
    "--flavor=$FLAVOR"
    "--dart-define=FLAVOR=$FLAVOR"
    "--dart-define=SUPABASE_URL=${RESOLVED_SUPABASE_URL}"
    "--dart-define=SUPABASE_ANON_KEY=${RESOLVED_SUPABASE_ANON_KEY}"
    "--dart-define=SUPABASE_PROJECT_REF=${RESOLVED_SUPABASE_PROJECT_REF}"
    "--dart-define=BACKEND_ENVIRONMENT=${RESOLVED_BACKEND_ENVIRONMENT}"
    "--dart-define=COOL_DEEP_LINK_HOST=${COOL_DEEP_LINK_HOST:-cool.app}"
  )

  if [[ -n "$DEVICE" ]]; then
    cmd+=("-d" "$DEVICE")
  fi

  print_cmd "${cmd[@]}"
  set +e
  run_with_timeout "${cmd[@]}"
  local status=$?
  set -e

  capture_failure_diagnostics "$status" "$target"

  if target_requires_sms_permission "$target"; then
    cleanup_sms_suite
  fi

  return "$status"
}

main() {
  require_command bash

  local targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    targets+=("$target")
  done < <(resolve_suite_targets)
  if [[ "${#targets[@]}" -eq 0 ]]; then
    echo "No integration targets resolved." >&2
    exit 1
  fi

  echo "==> flutter pub get"
  "$FLUTTER_BIN" pub get

  local package_name
  package_name="$(resolve_package_name)"
  local apk_path
  apk_path="$(resolve_base_apk_path)"

  device_preflight "$package_name" "$apk_path" "${targets[@]}"

  local target
  for target in "${targets[@]}"; do
    echo "==> running $(target_basename "$target")"
    run_target "$target"
  done
}

main "$@"
