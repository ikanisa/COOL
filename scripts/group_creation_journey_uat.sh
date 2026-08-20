#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${DATABASE_URL:-}" ]]; then
  DATABASE_URL="postgresql://postgres@127.0.0.1:54332/postgres"
  export PGPASSWORD="${PGPASSWORD:-postgres}"
fi

if [[ "$DATABASE_URL" != postgresql://*127.0.0.1* && "$DATABASE_URL" != postgresql://*localhost* ]]; then
  : "${COLLECT_ALLOW_LINKED_GROUP_JOURNEY_UAT:?Set COLLECT_ALLOW_LINKED_GROUP_JOURNEY_UAT only for an explicitly authorized rollback-only linked UAT}"
fi

if command -v psql >/dev/null 2>&1; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/group_creation_journey_uat.sql
elif [[ "$DATABASE_URL" == postgresql://*127.0.0.1* || "$DATABASE_URL" == postgresql://*localhost* ]] &&
  docker inspect supabase_db_collect >/dev/null 2>&1; then
  docker exec -i supabase_db_collect psql -U postgres -d postgres \
    -v ON_ERROR_STOP=1 < scripts/group_creation_journey_uat.sql
else
  echo "psql is required" >&2
  exit 1
fi
