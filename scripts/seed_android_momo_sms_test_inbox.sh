#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-seed}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ADB_BIN="${ADB_BIN:-adb}"
DEVICE="${DEVICE:-}"
SEED_PREFIX="Cool CI M-Money Sync"

device_args=()
if [[ -n "$DEVICE" ]]; then
  device_args=(-s "$DEVICE")
fi

run_adb_shell() {
  local command="${1:?}"
  "$ADB_BIN" "${device_args[@]}" shell "$command"
}

cleanup_seed_rows() {
  run_adb_shell "content delete --uri content://sms/inbox --where \"body LIKE '$SEED_PREFIX %'\" >/dev/null 2>&1 || true"
}

insert_seed_row() {
  local sender="${1:?}"
  local body="${2:?}"
  local timestamp_ms="${3:?}"
  run_adb_shell "content insert --uri content://sms/inbox --bind address:s:'$sender' --bind body:s:'$body' --bind date:l:$timestamp_ms --bind read:i:1 --bind seen:i:1 >/dev/null"
}

case "$ACTION" in
  clean)
    cleanup_seed_rows
    ;;
  query)
    run_adb_shell "content query --uri content://sms/inbox --projection address:body:date --where \"body LIKE '$SEED_PREFIX %'\""
    ;;
  seed)
    cleanup_seed_rows

    now_ms="$(( $(date +%s) * 1000 ))"
    newest_ms="$(( now_ms - 3600 * 1000 ))"
    recent_ms="$(( now_ms - 2 * 3600 * 1000 ))"
    older_ms="$(( now_ms - 26 * 3600 * 1000 ))"

    insert_seed_row \
      "M-Money" \
      "$SEED_PREFIX Seed 1. TxId: CI-0001. Payment of 1,500 RWF completed. New balance: 8,500 RWF." \
      "$newest_ms"

    insert_seed_row \
      "M-Money Alerts" \
      "$SEED_PREFIX Seed 2. TxId: CI-0002. Payment of 2,500 RWF completed. New balance: 9,100 RWF." \
      "$recent_ms"

    insert_seed_row \
      "M-Money" \
      "$SEED_PREFIX Seed 3. TxId: CI-0003. Payment of 800 RWF completed. New balance: 7,000 RWF." \
      "$older_ms"
    run_adb_shell "content query --uri content://sms/inbox --projection address:body:date --where \"body LIKE '$SEED_PREFIX %'\""
    ;;
  *)
    echo "Usage: $0 [seed|clean|query]" >&2
    exit 1
    ;;
esac
