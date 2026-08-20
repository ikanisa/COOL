#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"
# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

EXPECTED_FUNCTIONS=(
  auth-send-whatsapp-otp
  dispatch-notifications
  ingest-bank-email
  ingest-bank-sms
  ingest-bank-statement
  send-notification
)

NO_VERIFY_JWT_FUNCTIONS=(
  auth-send-whatsapp-otp
  dispatch-notifications
  ingest-bank-email
  send-notification
)

RETIRED_FUNCTIONS=(
  stripe-create-customer
  stripe-create-diaspora-contribution
  stripe-create-setup-intent
  stripe-webhook
  ingest-payment-sms
  parse-payment-sms
  verify-play-integrity
)

if [[ -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
: "${SUPABASE_DB_PASSWORD:?SUPABASE_DB_PASSWORD is required}"
: "${SUPABASE_URL:?SUPABASE_URL is required}"

log() {
  printf '[supabase-deploy] %s\n' "$*"
}

[[ "${CONFIRM_SUPABASE_DEPLOY:-}" == "$SUPABASE_PROJECT_REF" ]] || {
  printf '[supabase-deploy][FAIL] Set CONFIRM_SUPABASE_DEPLOY=%s for this exact project.\n' "$SUPABASE_PROJECT_REF" >&2
  exit 1
}

project_ref_file="$ROOT_DIR/supabase/.temp/project-ref"
[[ -f "$project_ref_file" && ! -L "$project_ref_file" ]] || {
  printf '[supabase-deploy][FAIL] Supabase linked project reference is missing.\n' >&2
  exit 1
}
linked_ref="$(tr -d '[:space:]' < "$project_ref_file")"
[[ "$linked_ref" == "$SUPABASE_PROJECT_REF" ]] || {
  printf '[supabase-deploy][FAIL] Linked project does not match SUPABASE_PROJECT_REF.\n' >&2
  exit 1
}
[[ "${SUPABASE_URL%/}" == "https://${SUPABASE_PROJECT_REF}.supabase.co" ]] || {
  printf '[supabase-deploy][FAIL] SUPABASE_URL does not match SUPABASE_PROJECT_REF.\n' >&2
  exit 1
}

log "validating local migration chain and target visibility"
"$ROOT_DIR/scripts/migrations/validate_supabase_migrations.sh"
SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli projects list -o json |
  SUPABASE_PROJECT_REF="$SUPABASE_PROJECT_REF" ruby -r json -e '
    ref = ENV.fetch("SUPABASE_PROJECT_REF")
    project = JSON.parse(STDIN.read).find { |row| [row["id"], row["ref"]].include?(ref) }
    abort("confirmed project is not visible to this access token") unless project
  '
SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
  SUPABASE_DB_PASSWORD="$SUPABASE_DB_PASSWORD" \
  supabase_cli db push --dry-run

log "pushing database migrations"
SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
  SUPABASE_DB_PASSWORD="$SUPABASE_DB_PASSWORD" \
  supabase_cli db push

remote_function_inventory="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
  supabase_cli functions list --project-ref "$SUPABASE_PROJECT_REF" -o json)"
for function_name in "${RETIRED_FUNCTIONS[@]}"; do
  if ruby -r json -e '
      name = ARGV.fetch(0)
      exit(JSON.parse(STDIN.read).any? { |row| row["name"] == name } ? 0 : 1)
    ' "$function_name" <<< "$remote_function_inventory"; then
    log "deleting retired Edge Function: $function_name"
    SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
      supabase_cli functions delete "$function_name" \
        --project-ref "$SUPABASE_PROJECT_REF" --yes
  fi
done

for function_name in "${EXPECTED_FUNCTIONS[@]}"; do
  log "deploying Edge Function: $function_name"
  if printf '%s\n' "${NO_VERIFY_JWT_FUNCTIONS[@]}" | grep -qx "$function_name"; then
    SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli functions deploy "$function_name" --project-ref "$SUPABASE_PROJECT_REF" --no-verify-jwt
  else
    SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli functions deploy "$function_name" --project-ref "$SUPABASE_PROJECT_REF"
  fi
done

log "running linked readiness gate"
SUPABASE_READY_STRICT_PLATFORM=1 "$ROOT_DIR/scripts/supabase_production_readiness.sh"
