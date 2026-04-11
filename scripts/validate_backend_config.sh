#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/_backend_env.sh"

load_client_env_files "$ROOT_DIR" \
  SUPABASE_URL \
  SUPABASE_ANON_KEY \
  SUPABASE_STAGING_URL \
  SUPABASE_STAGING_ANON_KEY \
  SUPABASE_PRODUCTION_URL \
  SUPABASE_PRODUCTION_ANON_KEY

skip_staging_backend_validation=0
if [[ "${COOL_SKIP_STAGING_BACKEND_VALIDATION:-0}" == "1" ]]; then
  skip_staging_backend_validation=1
fi

has_staging_backend_config=0
if [[ "$skip_staging_backend_validation" != "1" && \
      ( -n "${SUPABASE_STAGING_URL:-}" || -n "${SUPABASE_STAGING_ANON_KEY:-}" ) ]]; then
  has_staging_backend_config=1
fi

validate_flavor() {
  local flavor="${1:?Pass staging or production.}"
  local upper_flavor
  upper_flavor="$(tr '[:lower:]' '[:upper:]' <<<"$flavor")"
  resolve_supabase_client_env "$flavor"
  require_resolved_supabase_client_env "$flavor"
  printf -v "VALIDATED_${upper_flavor}_REF" '%s' "$RESOLVED_SUPABASE_PROJECT_REF"
  printf '==> %s backend: %s (%s)\n' \
    "$flavor" \
    "$RESOLVED_SUPABASE_PROJECT_REF" \
    "$RESOLVED_SUPABASE_URL"
}

validate_flavor production

if [[ "$has_staging_backend_config" == "1" ]]; then
  validate_flavor staging
elif [[ "$skip_staging_backend_validation" == "1" ]]; then
  echo "==> staging backend: skipped (COOL_SKIP_STAGING_BACKEND_VALIDATION=1)"
else
  echo "==> staging backend: skipped (production-only release mode)"
fi

if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_PRODUCTION_URL:-}" && \
      "$SUPABASE_URL" != "$SUPABASE_PRODUCTION_URL" ]]; then
  echo "CRITICAL BLOCKER — Legacy SUPABASE_URL disagrees with SUPABASE_PRODUCTION_URL." >&2
  exit 1
fi

if [[ -n "${SUPABASE_ANON_KEY:-}" && -n "${SUPABASE_PRODUCTION_ANON_KEY:-}" && \
      "$SUPABASE_ANON_KEY" != "$SUPABASE_PRODUCTION_ANON_KEY" ]]; then
  echo "CRITICAL BLOCKER — Legacy SUPABASE_ANON_KEY disagrees with SUPABASE_PRODUCTION_ANON_KEY." >&2
  exit 1
fi

if [[ "$has_staging_backend_config" == "1" && \
      -n "${VALIDATED_STAGING_REF:-}" && -n "${VALIDATED_PRODUCTION_REF:-}" && \
      "$VALIDATED_STAGING_REF" == "$VALIDATED_PRODUCTION_REF" ]]; then
  echo "CRITICAL BLOCKER — staging and production resolve to the same Supabase project (${VALIDATED_STAGING_REF})." >&2
  echo "Set distinct SUPABASE_STAGING_* and SUPABASE_PRODUCTION_* values before release validation." >&2
  exit 1
fi

echo "==> backend config contract looks consistent"
