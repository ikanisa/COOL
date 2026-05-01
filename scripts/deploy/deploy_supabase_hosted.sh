#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  PROJECT_REF=<project-ref> SUPABASE_DB_PASSWORD=<db-password> \
    [FUNCTIONS_ENV_FILE=supabase/functions/.env] \
    [INCLUDE_SEED=1] \
    [PRUNE_FUNCTIONS=0] \
    [RUN_SMOKE=1] \
    bash scripts/deploy/deploy_supabase_hosted.sh

Required:
  PROJECT_REF             Hosted Supabase project ref.
  SUPABASE_DB_PASSWORD    Remote Postgres password for the hosted project.

Optional:
  FUNCTIONS_ENV_FILE      .env file used for `supabase secrets set`.
                          Defaults to `supabase/functions/.env`.
  INCLUDE_SEED            Set to 0 to skip Supabase seed files during db push.
  PRUNE_FUNCTIONS         Set to 1 to delete remote functions missing locally.
  RUN_SMOKE               Set to 0 to skip remote contract smoke checks.
  SKIP_SECRETS            Set to 1 to skip `supabase secrets set`.
  SKIP_FUNCTIONS          Set to 1 to skip Edge Function deployment.
  SKIP_DB_PUSH            Set to 1 to skip migration apply.

Notes:
  - The current Supabase CLI profile (or SUPABASE_ACCESS_TOKEN in your shell)
    must have project-level access to PROJECT_REF for secrets/functions.
  - This script does not write app runtime secrets into tracked files.
  - Flutter builds still need SUPABASE_URL and SUPABASE_ANON_KEY at build time.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command jq
require_command supabase

PROJECT_REF="${PROJECT_REF:-${1:-}}"
SUPABASE_DB_PASSWORD="${SUPABASE_DB_PASSWORD:-}"
FUNCTIONS_ENV_FILE="${FUNCTIONS_ENV_FILE:-$ROOT_DIR/supabase/functions/.env}"
INCLUDE_SEED="${INCLUDE_SEED:-1}"
PRUNE_FUNCTIONS="${PRUNE_FUNCTIONS:-0}"
RUN_SMOKE="${RUN_SMOKE:-1}"
SKIP_SECRETS="${SKIP_SECRETS:-0}"
SKIP_FUNCTIONS="${SKIP_FUNCTIONS:-0}"
SKIP_DB_PUSH="${SKIP_DB_PUSH:-0}"

if [[ -z "$PROJECT_REF" ]]; then
  usage >&2
  exit 1
fi

if [[ "$SKIP_DB_PUSH" != "1" && -z "$SUPABASE_DB_PASSWORD" ]]; then
  echo "SUPABASE_DB_PASSWORD is required unless SKIP_DB_PUSH=1." >&2
  exit 1
fi

project_visible="$(
  supabase projects list --output json |
    jq -e --arg ref "$PROJECT_REF" '.[] | select(.ref == $ref)' >/dev/null 2>&1 &&
    echo yes || echo no
)"

if [[ "$project_visible" != "yes" ]]; then
  echo "Project $PROJECT_REF is not visible to the current Supabase CLI profile." >&2
  echo "Use a profile or SUPABASE_ACCESS_TOKEN that has project access." >&2
  exit 1
fi

echo "==> validating local Supabase migrations"
bash "$ROOT_DIR/scripts/migrations/validate_supabase_migrations.sh"

if [[ "$SKIP_DB_PUSH" != "1" ]]; then
  echo "==> linking local workspace to $PROJECT_REF"
  supabase link \
    --project-ref "$PROJECT_REF" \
    --password "$SUPABASE_DB_PASSWORD" \
    --workdir "$ROOT_DIR"

  echo "==> applying hosted database migrations"
  db_push_args=(
    db push
    --linked
    --workdir "$ROOT_DIR"
    --password "$SUPABASE_DB_PASSWORD"
    --include-all
  )
  if [[ "$INCLUDE_SEED" == "1" ]]; then
    db_push_args+=(--include-seed)
  fi
  supabase "${db_push_args[@]}"
else
  echo "==> skipping database migration apply"
fi

if [[ "$SKIP_SECRETS" != "1" ]]; then
  if [[ ! -f "$FUNCTIONS_ENV_FILE" ]]; then
    echo "Missing FUNCTIONS_ENV_FILE: $FUNCTIONS_ENV_FILE" >&2
    echo "Create it from supabase/functions/.env.example or set SKIP_SECRETS=1." >&2
    exit 1
  fi
  echo "==> syncing Edge Function secrets from $FUNCTIONS_ENV_FILE"
  supabase secrets set \
    --env-file "$FUNCTIONS_ENV_FILE" \
    --project-ref "$PROJECT_REF" \
    --workdir "$ROOT_DIR"
else
  echo "==> skipping secret sync"
fi

if [[ "$SKIP_FUNCTIONS" != "1" ]]; then
  echo "==> deploying Edge Functions"
  function_names=()
  while IFS= read -r function_name; do
    function_names+=("$function_name")
  done < <(
    find "$ROOT_DIR/supabase/functions" -maxdepth 2 -name index.ts |
      sed "s#^$ROOT_DIR/supabase/functions/##; s#/index.ts\$##" |
      sort
  )

  if [[ ${#function_names[@]} -eq 0 ]]; then
    echo "No Edge Functions found under supabase/functions." >&2
    exit 1
  fi

  for function_name in "${function_names[@]}"; do
    echo "   -> $function_name"
    supabase functions deploy "$function_name" \
      --project-ref "$PROJECT_REF" \
      --use-api \
      --workdir "$ROOT_DIR"
  done

  if [[ "$PRUNE_FUNCTIONS" == "1" ]]; then
    echo "==> pruning remote functions that are missing locally"
    supabase functions deploy \
      --project-ref "$PROJECT_REF" \
      --use-api \
      --prune \
      --workdir "$ROOT_DIR"
  fi
else
  echo "==> skipping Edge Function deploy"
fi

if [[ "$RUN_SMOKE" == "1" ]]; then
  echo "==> running hosted Supabase contract smoke"
  PROJECT_REF="$PROJECT_REF" bash "$ROOT_DIR/scripts/supabase_contract_smoke.sh"
else
  echo "==> skipping hosted smoke"
fi

echo "==> hosted Supabase deployment workflow completed for $PROJECT_REF"
