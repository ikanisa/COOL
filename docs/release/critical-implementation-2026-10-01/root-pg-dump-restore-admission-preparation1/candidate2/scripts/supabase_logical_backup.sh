#!/usr/bin/env bash
set -euo pipefail
umask 077

case "${1:-}" in
  --help|-h)
    printf '%s\n' \
      'Usage: scripts/supabase_logical_backup.sh --confirm-partial-export' \
      'PARTIAL EXPORT ONLY: public schema; public data only with INCLUDE_DATA=1.' \
      'Does not preserve privileges, Auth, private/action schemas, Storage objects,' \
      'global roles/passwords, Edge Functions, provider settings or secrets.' \
      'This is not a full recovery backup. See docs/RECOVERY_RUNBOOK.md.' \
      'Run only after the data export and private output location are authorized.'
    exit 0
    ;;
  --confirm-partial-export) ;;
  *)
    printf '[supabase-backup][REFUSED] This script is a partial public export, not a recovery backup. Use --help.\n' >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"
# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"

# New protocol: an externally reviewed operation binds output paths and scope.
# Local client probes run with a credential-free environment before .env loads.
backup_dir="$(collect_pg_archive output-directory)"

if [[ -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

: "${DATABASE_URL:?DATABASE_URL is required}"

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

schema_file="$backup_dir/public_schema.sql"
data_file="$backup_dir/public_data.sql"

printf '[supabase-backup] writing schema dump to %s\n' "$schema_file"
collect_pg_url_service "$DATABASE_URL" pg_dump_cli \
  --schema=public \
  --schema-only \
  --no-owner \
  --no-privileges \
  --file="$schema_file"

if [[ "${INCLUDE_DATA:-0}" == "1" ]]; then
  printf '[supabase-backup] writing data dump to %s\n' "$data_file"
  collect_pg_url_service "$DATABASE_URL" pg_dump_cli \
    --schema=public \
    --data-only \
    --no-owner \
    --no-privileges \
    --format=plain \
    --file="$data_file"
else
  printf '[supabase-backup] skipped data dump; set INCLUDE_DATA=1 to include public table data\n'
fi

printf '[supabase-backup] PARTIAL public export complete: %s\n' "$backup_dir"
printf '[supabase-backup] NOT a full recovery backup: Auth, private schemas, privileges, Storage objects and platform configuration are excluded.\n'
