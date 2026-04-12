#!/usr/bin/env bash

if [[ -n "${_COOL_BACKEND_ENV_SH_LOADED:-}" ]]; then
  return 0
fi
_COOL_BACKEND_ENV_SH_LOADED=1

load_client_env_files() {
  local root_dir="${1:?Pass repo root.}"
  shift || true

  if [[ -f "$root_dir/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$root_dir/.env"
    set +a
  fi

  if [[ ! -f "$root_dir/.env.json" || $# -eq 0 ]]; then
    return 0
  fi

  local json_key
  for json_key in "$@"; do
    if [[ -n "${!json_key:-}" ]]; then
      continue
    fi

    local json_value
    json_value="$(
      jq -r --arg key "$json_key" '.[$key] // empty' "$root_dir/.env.json"
    )"
    if [[ -n "$json_value" ]]; then
      export "$json_key=$json_value"
    fi
  done
}

supabase_project_ref_from_url() {
  local supabase_url="${1:-}"
  sed -nE 's#https?://([^.]+)\.supabase\.co/?#\1#p' <<<"$supabase_url"
}

resolve_supabase_client_env() {
  local flavor="${1:?Pass staging or production.}"
  local upper_flavor
  upper_flavor="$(tr '[:lower:]' '[:upper:]' <<<"$flavor")"

  local specific_url_var="SUPABASE_${upper_flavor}_URL"
  local specific_anon_var="SUPABASE_${upper_flavor}_ANON_KEY"

  local generic_url="${SUPABASE_URL:-}"
  local generic_anon="${SUPABASE_ANON_KEY:-}"
  local specific_url="${!specific_url_var:-}"
  local specific_anon="${!specific_anon_var:-}"

  RESOLVED_SUPABASE_URL="${specific_url:-$generic_url}"
  RESOLVED_SUPABASE_ANON_KEY="${specific_anon:-$generic_anon}"
  RESOLVED_SUPABASE_PROJECT_REF="$(
    supabase_project_ref_from_url "${RESOLVED_SUPABASE_URL:-}"
  )"
  RESOLVED_BACKEND_ENVIRONMENT="$flavor"

  if [[ -z "$specific_url" && -n "$generic_url" ]]; then
    echo "⚠️  Using legacy SUPABASE_URL fallback for $flavor. Prefer $specific_url_var." >&2
  fi
  if [[ -z "$specific_anon" && -n "$generic_anon" ]]; then
    echo "⚠️  Using legacy SUPABASE_ANON_KEY fallback for $flavor. Prefer $specific_anon_var." >&2
  fi
}

require_resolved_supabase_client_env() {
  local flavor="${1:?Pass staging or production.}"
  if [[ -z "${RESOLVED_SUPABASE_URL:-}" ]]; then
    echo "CRITICAL BLOCKER — Missing Supabase URL for $flavor." >&2
    echo "Set SUPABASE_${flavor^^}_URL or legacy SUPABASE_URL." >&2
    return 1
  fi
  if [[ -z "${RESOLVED_SUPABASE_ANON_KEY:-}" ]]; then
    echo "CRITICAL BLOCKER — Missing Supabase anon key for $flavor." >&2
    echo "Set SUPABASE_${flavor^^}_ANON_KEY or legacy SUPABASE_ANON_KEY." >&2
    return 1
  fi
  if [[ -z "${RESOLVED_SUPABASE_PROJECT_REF:-}" ]]; then
    echo "CRITICAL BLOCKER — Unable to derive Supabase project ref from:" >&2
    echo "  ${RESOLVED_SUPABASE_URL:-<unset>}" >&2
    return 1
  fi
}

require_distinct_staging_and_production_supabase_projects() {
  local allow_shared="${ALLOW_SHARED_SUPABASE_PROJECT:-0}"
  if [[ "$allow_shared" == "1" ]]; then
    return 0
  fi

  local staging_url="${SUPABASE_STAGING_URL:-${SUPABASE_URL:-}}"
  local production_url="${SUPABASE_PRODUCTION_URL:-${SUPABASE_URL:-}}"
  local staging_ref
  local production_ref
  staging_ref="$(supabase_project_ref_from_url "$staging_url")"
  production_ref="$(supabase_project_ref_from_url "$production_url")"

  if [[ -z "$staging_ref" || -z "$production_ref" ]]; then
    return 0
  fi

  if [[ "$staging_ref" == "$production_ref" ]]; then
    echo "CRITICAL BLOCKER — staging and production point at the same Supabase project ($staging_ref)." >&2
    echo "Write-heavy UAT is blocked until SUPABASE_STAGING_URL and SUPABASE_PRODUCTION_URL are separated." >&2
    echo "Set ALLOW_SHARED_SUPABASE_PROJECT=1 only for read-only local verification." >&2
    return 1
  fi
}
