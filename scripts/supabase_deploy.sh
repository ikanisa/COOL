#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"

EXPECTED_FUNCTIONS=(
  allocate-payment
  auth-send-whatsapp-otp
  dispatch-notifications
  ingest-payment-sms
  parse-payment-sms
  send-notification
  stripe-create-customer
  stripe-create-setup-intent
  stripe-create-diaspora-contribution
  stripe-webhook
  verify-play-integrity
)

NO_VERIFY_JWT_FUNCTIONS=(
  auth-send-whatsapp-otp
  stripe-webhook
)

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
: "${SUPABASE_DB_PASSWORD:?SUPABASE_DB_PASSWORD is required}"

log() {
  printf '[supabase-deploy] %s\n' "$*"
}

log "pushing database migrations"
SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db push -p "$SUPABASE_DB_PASSWORD"

for function_name in "${EXPECTED_FUNCTIONS[@]}"; do
  log "deploying Edge Function: $function_name"
  if printf '%s\n' "${NO_VERIFY_JWT_FUNCTIONS[@]}" | grep -qx "$function_name"; then
    SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli functions deploy "$function_name" --project-ref "$SUPABASE_PROJECT_REF" --no-verify-jwt
  else
    SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli functions deploy "$function_name" --project-ref "$SUPABASE_PROJECT_REF"
  fi
done

log "running linked readiness gate"
"$ROOT_DIR/scripts/supabase_production_readiness.sh"
