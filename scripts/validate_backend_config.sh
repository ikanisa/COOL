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

validate_flavor() {
  local flavor="${1:?Pass staging or production.}"
  resolve_supabase_client_env "$flavor"
  require_resolved_supabase_client_env "$flavor"
  printf '==> %s backend: %s (%s)\n' \
    "$flavor" \
    "$RESOLVED_SUPABASE_PROJECT_REF" \
    "$RESOLVED_SUPABASE_URL"
}

validate_flavor staging
validate_flavor production

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

if [[ -n "${SUPABASE_STAGING_URL:-}" && -n "${SUPABASE_PRODUCTION_URL:-}" && \
      "$SUPABASE_STAGING_URL" == "$SUPABASE_PRODUCTION_URL" ]]; then
  echo "INFO: staging and production currently share the same Supabase project." >&2
fi

echo "==> backend config contract looks consistent"
