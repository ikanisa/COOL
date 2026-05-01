#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  DATABASE_URL="postgresql://..." scripts/migrations/apply_supabase_migrations.sh
  APPLY_MIGRATIONS=1 DATABASE_URL="postgresql://..." scripts/migrations/apply_supabase_migrations.sh

Environment:
  DATABASE_URL or SUPABASE_DB_URL  Remote Supabase Postgres connection string.
  APPLY_MIGRATIONS                 Set to 1 to apply. Defaults to dry-run.

The script validates the local migration tree before touching the remote
database. It never uses the linked project implicitly; pass the target database
URL explicitly through an environment variable.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

require_command supabase

target_db_url="${DATABASE_URL:-${SUPABASE_DB_URL:-}}"
if [[ -z "$target_db_url" ]]; then
  usage >&2
  exit 1
fi

echo "==> validating local Supabase migrations"
bash "$ROOT_DIR/scripts/migrations/validate_supabase_migrations.sh"

if [[ "${APPLY_MIGRATIONS:-0}" == "1" ]]; then
  echo "==> applying Supabase migrations to explicit DATABASE_URL target"
  supabase db push --db-url "$target_db_url" --yes
else
  echo "==> dry-run Supabase migration push for explicit DATABASE_URL target"
  supabase db push --db-url "$target_db_url" --dry-run
  echo "Dry-run only. Set APPLY_MIGRATIONS=1 to apply the validated plan."
fi
