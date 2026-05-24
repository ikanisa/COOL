#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"

LEVEL="${SUPABASE_ADVISORS_LEVEL:-error}"
FAIL_ON="${SUPABASE_ADVISORS_FAIL_ON:-error}"

log() {
  printf '[supabase-advisors] %s\n' "$*"
}

run_advisor() {
  local type="$1"
  log "checking linked $type advisors at level=$LEVEL fail-on=$FAIL_ON"
  SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db advisors \
    --linked \
    --type "$type" \
    --level "$LEVEL" \
    --fail-on "$FAIL_ON" \
    --agent=yes
}

run_advisor security
run_advisor performance
log "linked advisor gate passed"
