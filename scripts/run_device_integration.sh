#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"
source "$ROOT_DIR/scripts/_backend_env.sh"

FLAVOR="${FLAVOR:-staging}"
DEVICE="${DEVICE:-}"
TARGET="${TARGET:-integration_test/critical_journeys_test.dart}"

load_client_env_files "$ROOT_DIR" \
  SUPABASE_URL \
  SUPABASE_ANON_KEY \
  SUPABASE_STAGING_URL \
  SUPABASE_STAGING_ANON_KEY \
  SUPABASE_PRODUCTION_URL \
  SUPABASE_PRODUCTION_ANON_KEY \
  COOL_DEEP_LINK_HOST
resolve_supabase_client_env "$FLAVOR"
require_resolved_supabase_client_env "$FLAVOR"

cmd=(
  "$FLUTTER_BIN" test
  "$TARGET"
  "--flavor=$FLAVOR"
  "--dart-define=FLAVOR=$FLAVOR"
  "--dart-define=SUPABASE_URL=${RESOLVED_SUPABASE_URL}"
  "--dart-define=SUPABASE_ANON_KEY=${RESOLVED_SUPABASE_ANON_KEY}"
  "--dart-define=SUPABASE_PROJECT_REF=${RESOLVED_SUPABASE_PROJECT_REF}"
  "--dart-define=BACKEND_ENVIRONMENT=${RESOLVED_BACKEND_ENVIRONMENT}"
  "--dart-define=COOL_DEEP_LINK_HOST=${COOL_DEEP_LINK_HOST:-cool.app}"
)

if [[ -n "$DEVICE" ]]; then
  cmd+=("-d" "$DEVICE")
fi

printf '==> %q ' "${cmd[@]}"
printf '\n'
"${cmd[@]}"
