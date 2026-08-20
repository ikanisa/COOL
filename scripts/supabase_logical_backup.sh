#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

if [[ -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${DATABASE_URL:?DATABASE_URL is required}"

PG_DUMP_BIN="${PG_DUMP_BIN:-}"
if [[ -z "$PG_DUMP_BIN" ]]; then
  for candidate in \
    /usr/local/Cellar/postgresql@17/*/bin/pg_dump \
    /opt/homebrew/Cellar/postgresql@17/*/bin/pg_dump \
    /usr/local/Cellar/libpq/*/bin/pg_dump \
    /opt/homebrew/Cellar/libpq/*/bin/pg_dump \
    "$(command -v pg_dump 2>/dev/null || true)"; do
    if [[ -x "$candidate" ]]; then
      PG_DUMP_BIN="$candidate"
      break
    fi
  done
fi

[[ -n "$PG_DUMP_BIN" && -x "$PG_DUMP_BIN" ]] || {
  printf '[supabase-backup][FAIL] pg_dump 17+ is required for this Supabase Postgres server.\n' >&2
  exit 1
}

dump_version="$("$PG_DUMP_BIN" --version | awk '{
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^[0-9]+([.][0-9]+)?$/) {
      print $i
      exit
    }
  }
}')"
dump_major="${dump_version%%.*}"
if [[ "$dump_major" -lt 17 ]]; then
  printf '[supabase-backup][FAIL] pg_dump 17+ is required; found %s at %s.\n' "$dump_version" "$PG_DUMP_BIN" >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir=".cache/supabase_backups/$timestamp"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

schema_file="$backup_dir/public_schema.sql"
data_file="$backup_dir/public_data.sql"

printf '[supabase-backup] writing schema dump to %s\n' "$schema_file"
"$PG_DUMP_BIN" "$DATABASE_URL" \
  --schema=public \
  --schema-only \
  --no-owner \
  --no-privileges \
  --file="$schema_file"

if [[ "${INCLUDE_DATA:-0}" == "1" ]]; then
  printf '[supabase-backup] writing data dump to %s\n' "$data_file"
  "$PG_DUMP_BIN" "$DATABASE_URL" \
    --schema=public \
    --data-only \
    --no-owner \
    --no-privileges \
    --format=plain \
    --file="$data_file"
else
  printf '[supabase-backup] skipped data dump; set INCLUDE_DATA=1 to include public table data\n'
fi

printf '[supabase-backup] complete: %s\n' "$backup_dir"
