#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"
# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

if [[ -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
: "${SUPABASE_DB_ALLOWED_CIDRS:?Set SUPABASE_DB_ALLOWED_CIDRS to a comma or space separated CIDR allowlist}"

IFS=', ' read -r -a cidrs <<< "$SUPABASE_DB_ALLOWED_CIDRS"
args=()
for cidr in "${cidrs[@]}"; do
  [[ -n "$cidr" ]] || continue
  if [[ "$cidr" == "0.0.0.0/0" || "$cidr" == "::/0" ]] && [[ "${ALLOW_PUBLIC_DB_CIDR:-0}" != "1" ]]; then
    printf '[supabase-network][FAIL] Refusing public CIDR %s. Set ALLOW_PUBLIC_DB_CIDR=1 only for intentional rollback.\n' "$cidr" >&2
    exit 1
  fi
  args+=(--db-allow-cidr "$cidr")
done

if [[ "${#args[@]}" -eq 0 ]]; then
  printf '[supabase-network][FAIL] SUPABASE_DB_ALLOWED_CIDRS did not contain any CIDRs.\n' >&2
  exit 1
fi

printf '[supabase-network] applying %s database network CIDR(s)\n' "$((${#args[@]} / 2))"
printf '[supabase-network] this replaces the existing allowlist; include every operator and CI CIDR you still need\n'
SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli network-restrictions update \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --experimental \
  "${args[@]}"

SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli network-restrictions get \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --experimental \
  -o json
