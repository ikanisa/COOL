#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"
# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

if [[ "${COLLECT_SKIP_DOTENV:-0}" != "1" && -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

UAT_SQL="$ROOT_DIR/scripts/bank_transfer_rollback_uat.sql"
SUPABASE_DB_QUERY_MODE="${SUPABASE_DB_QUERY_MODE:-linked}"
SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS="${SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS:-30}"

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  "$@" &
  local command_pid=$!
  (
    sleep "$timeout_seconds"
    if kill -0 "$command_pid" >/dev/null 2>&1; then
      kill -TERM "$command_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "$command_pid" >/dev/null 2>&1 || true
    fi
  ) &
  local timer_pid=$!
  local status=0
  wait "$command_pid" || status=$?
  kill "$timer_pid" >/dev/null 2>&1 || true
  wait "$timer_pid" >/dev/null 2>&1 || true
  return "$status"
}

if [[ "$SUPABASE_DB_QUERY_MODE" == "local" ]]; then
  local_db_container="${SUPABASE_LOCAL_DB_CONTAINER:-supabase_db_collect}"
  if ! docker inspect "$local_db_container" >/dev/null 2>&1; then
    printf '[collect-linked-uat][FAIL] Local Supabase database container is unavailable: %s\n' "$local_db_container" >&2
    exit 1
  fi
  docker exec -i "$local_db_container" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$UAT_SQL"
  printf '[collect-linked-uat] bank-transfer rollback UAT passed via local database query\n'
  exit 0
fi

: "${DATABASE_URL:?DATABASE_URL is required}"
READINESS_DATABASE_URL="${SUPABASE_READINESS_DATABASE_URL:-${DATABASE_POOLER_URL:-$DATABASE_URL}}"

if [[ "$SUPABASE_DB_QUERY_MODE" != "direct" ]]; then
  export SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
  if run_with_timeout "$SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS" \
    supabase_cli db query --linked -f "$UAT_SQL" -o json --agent=yes >/dev/null; then
    printf '[collect-linked-uat] bank-transfer rollback UAT passed via linked database query\n'
    exit 0
  fi
  printf '[collect-linked-uat][WARN] Linked query failed after %ss; trying the Management API query path.\n' \
    "$SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS" >&2

  if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" && -n "${SUPABASE_PROJECT_REF:-}" ]] &&
    supabase_management_query_file "$UAT_SQL" >/dev/null; then
    printf '[collect-linked-uat] bank-transfer rollback UAT passed via Supabase Management API query\n'
    exit 0
  fi
  printf '[collect-linked-uat][WARN] Management API query failed; falling back to the readiness database URL.\n' >&2
fi

psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$UAT_SQL"
printf '[collect-linked-uat] bank-transfer rollback UAT passed via direct database query\n'
