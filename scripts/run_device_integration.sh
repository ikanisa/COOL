#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"
source "$ROOT_DIR/scripts/_backend_env.sh"

FLAVOR="${FLAVOR:-staging}"
DEVICE="${DEVICE:-}"
TARGET="${TARGET:-integration_test/critical_journeys_test.dart}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"
UAT_DIR="${UAT_DIR:-$ROOT_DIR/.uat}"

load_client_env_files "$ROOT_DIR" \
  SUPABASE_URL \
  SUPABASE_ANON_KEY \
  SUPABASE_STAGING_URL \
  SUPABASE_STAGING_ANON_KEY \
  SUPABASE_PRODUCTION_URL \
  SUPABASE_PRODUCTION_ANON_KEY \
  COOL_DEEP_LINK_HOST
resolve_supabase_client_env "$FLAVOR"
require_resolved_supabase_client_env "$FLAVOR"

cmd=(
  "$FLUTTER_BIN" test
  "$TARGET"
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

mkdir -p "$UAT_DIR"

timeout_prefix=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_prefix=(gtimeout --preserve-status "$TIMEOUT_SECONDS")
elif command -v timeout >/dev/null 2>&1; then
  timeout_prefix=(timeout --preserve-status "$TIMEOUT_SECONDS")
fi

redacted_cmd=("${cmd[@]}")
for index in "${!redacted_cmd[@]}"; do
  case "${redacted_cmd[$index]}" in
    --dart-define=SUPABASE_ANON_KEY=*)
      redacted_cmd[$index]='--dart-define=SUPABASE_ANON_KEY=[REDACTED]'
      ;;
  esac
done

capture_failure_diagnostics() {
  local exit_code="$1"
  if [[ "$exit_code" -eq 0 ]]; then
    return
  fi

  echo "==> collecting integration failure diagnostics into $UAT_DIR"
  if [[ -n "$DEVICE" ]] && command -v adb >/dev/null 2>&1; then
    local adb_cmd=(adb -s "$DEVICE")
    "${adb_cmd[@]}" logcat -d -t 300 >"$UAT_DIR/device_integration_logcat.txt" 2>&1 || true
    "${adb_cmd[@]}" shell dumpsys activity activities >"$UAT_DIR/device_integration_activity.txt" 2>&1 || true
    if "${adb_cmd[@]}" shell uiautomator dump /sdcard/cool_uat.xml >/dev/null 2>&1; then
      "${adb_cmd[@]}" pull /sdcard/cool_uat.xml "$UAT_DIR/device_integration_ui.xml" >/dev/null 2>&1 || true
      "${adb_cmd[@]}" shell rm -f /sdcard/cool_uat.xml >/dev/null 2>&1 || true
    fi
  fi
}

printable_cmd=("${redacted_cmd[@]}")
if [[ "${#timeout_prefix[@]}" -gt 0 ]]; then
  printable_cmd=("${timeout_prefix[@]}" "${printable_cmd[@]}")
fi

printf '==> %q ' "${printable_cmd[@]}"
printf '\n'
set +e
if [[ "${#timeout_prefix[@]}" -gt 0 ]]; then
  "${timeout_prefix[@]}" "${cmd[@]}"
else
  "${cmd[@]}"
fi
status=$?
set -e

capture_failure_diagnostics "$status"
exit "$status"
