#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  PROJECT_REF=<project-ref> SUPABASE_ACCESS_TOKEN=<token> \
    [STRICT_CORE=1] \
    bash scripts/sync_supabase_function_secrets.sh

Required:
  PROJECT_REF              Hosted Supabase project ref.
  SUPABASE_ACCESS_TOKEN    Access token with project-level secrets scope.

Optional:
  STRICT_CORE              Require the release-critical auth/BioPay secrets.

The script maps GitHub-style release secrets onto the Supabase Edge Function
secret names used by this repo, then runs `supabase secrets set`.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

first_present_env() {
  local candidate
  for candidate in "$@"; do
    if [[ -n "${!candidate:-}" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

has_any_env() {
  local candidate
  for candidate in "$@"; do
    if [[ -n "${!candidate:-}" ]]; then
      return 0
    fi
  done
  return 1
}

add_secret() {
  local target="$1"
  shift

  local source_var
  if ! source_var="$(first_present_env "$@")"; then
    return 1
  fi

  secret_pairs+=("$target=${!source_var}")
  secret_names+=("$target")
  return 0
}

require_secret() {
  local target="$1"
  shift
  if ! add_secret "$target" "$@"; then
    missing_secrets+=("$target")
  fi
}

optional_secret() {
  local target="$1"
  shift
  add_secret "$target" "$@" || true
}

require_command supabase

PROJECT_REF="${PROJECT_REF:-${1:-}}"
STRICT_CORE="${STRICT_CORE:-0}"

if [[ -z "$PROJECT_REF" || -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  usage >&2
  exit 1
fi

declare -a secret_pairs=()
declare -a secret_names=()
declare -a missing_secrets=()

require_secret \
  SUPABASE_URL \
  SUPABASE_PRODUCTION_URL \
  SUPABASE_URL \
  COOL_PROJECT_SUPABASE_URL
require_secret \
  SUPABASE_ANON_KEY \
  SUPABASE_PRODUCTION_ANON_KEY \
  SUPABASE_ANON_KEY \
  COOL_PROJECT_SUPABASE_ANON_KEY
require_secret \
  SUPABASE_SERVICE_ROLE_KEY \
  SUPABASE_SERVICE_ROLE_KEY \
  COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY
require_secret \
  FIREBASE_SERVICE_ACCOUNT_JSON \
  FIREBASE_SERVICE_ACCOUNT_JSON \
  FIREBASE_SERVICE_ACCOUNT

if [[ "$STRICT_CORE" == "1" ]]; then
  require_secret WHATSAPP_PHONE_NUMBER_ID WHATSAPP_PHONE_NUMBER_ID
  require_secret WHATSAPP_ACCESS_TOKEN WHATSAPP_ACCESS_TOKEN
  require_secret OTP_CODE_HASH_SECRET OTP_CODE_HASH_SECRET
  require_secret AUTH_PHONE_PASSWORD_SECRET AUTH_PHONE_PASSWORD_SECRET
  require_secret AI_SMS_PARSE_PROVIDER AI_SMS_PARSE_PROVIDER

  if ! has_any_env OPENAI_API_KEY GEMINI_API_KEY; then
    missing_secrets+=("OPENAI_API_KEY or GEMINI_API_KEY")
  fi
fi

optional_secret FIREBASE_PROJECT_ID FIREBASE_PROJECT_ID
optional_secret AI_SMS_PARSE_PROVIDER AI_SMS_PARSE_PROVIDER
optional_secret OPENAI_API_KEY OPENAI_API_KEY
optional_secret OPENAI_SMS_PARSE_MODEL OPENAI_SMS_PARSE_MODEL
optional_secret GEMINI_API_KEY GEMINI_API_KEY
optional_secret GEMINI_SMS_PARSE_MODEL GEMINI_SMS_PARSE_MODEL
optional_secret GOOGLE_MAPS_SERVER_API_KEY GOOGLE_MAPS_SERVER_API_KEY
optional_secret GOOGLE_TRANSLATE_API_KEY GOOGLE_TRANSLATE_API_KEY
optional_secret GOOGLE_WALLET_ISSUER_ID GOOGLE_WALLET_ISSUER_ID
optional_secret \
  GOOGLE_WALLET_SERVICE_ACCOUNT_JSON \
  GOOGLE_WALLET_SERVICE_ACCOUNT_JSON
optional_secret GOOGLE_WALLET_ISSUER_NAME GOOGLE_WALLET_ISSUER_NAME
optional_secret GOOGLE_WALLET_ALLOWED_ORIGINS GOOGLE_WALLET_ALLOWED_ORIGINS
optional_secret COOL_PUBLIC_APP_BASE_URL COOL_PUBLIC_APP_BASE_URL
optional_secret TICKET_QR_HMAC_SECRET TICKET_QR_HMAC_SECRET
optional_secret OTP_TEST_PHONE OTP_TEST_PHONE
optional_secret OTP_TEST_CODE OTP_TEST_CODE
optional_secret \
  GENERATE_AI_CONTENT_CRON_SECRET \
  GENERATE_AI_CONTENT_CRON_SECRET \
  CRON_JOB_SECRET
optional_secret CRON_JOB_SECRET CRON_JOB_SECRET GENERATE_AI_CONTENT_CRON_SECRET

if [[ ${#missing_secrets[@]} -gt 0 ]]; then
  echo "Missing required secret inputs for Supabase sync:" >&2
  printf '  - %s\n' "${missing_secrets[@]}" >&2
  exit 1
fi

if [[ ${#secret_pairs[@]} -eq 0 ]]; then
  echo "No Supabase function secrets resolved from the current environment." >&2
  exit 1
fi

echo "==> syncing ${#secret_names[@]} Supabase function secrets to $PROJECT_REF"
printf '   -> %s\n' "${secret_names[@]}"

supabase secrets set \
  --project-ref "$PROJECT_REF" \
  --workdir "$ROOT_DIR" \
  "${secret_pairs[@]}"

echo "==> Supabase function secrets synced for $PROJECT_REF"
