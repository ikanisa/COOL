#!/usr/bin/env bash

# ==============================================================================
# Purge Mock Data Batches
# ------------------------------------------------------------------------------
# Usage:
#   SUPABASE_URL=<url> SUPABASE_SERVICE_ROLE_KEY=<key> \
#     bash scripts/deploy/purge_mocks.sh
#
# Description:
#   This script connects to the specified Supabase environment and executes the
#   `purge_mock_batch` RPC for all known mock data batches. It is intended to
#   be run as a deployment gate step for production environments to ensure zero
#   mock data bleeds into live environments.
# ==============================================================================

set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-}"
SERVICE_ROLE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-${SERVICE_ROLE_KEY:-}}"

if [[ -z "$SUPABASE_URL" || -z "$SERVICE_ROLE_KEY" ]]; then
  echo "Error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required." >&2
  echo "Usage: SUPABASE_URL=<url> SUPABASE_SERVICE_ROLE_KEY=<key> bash scripts/deploy/purge_mocks.sh" >&2
  exit 1
fi

# List of known mock batches introduced by seed migrations
MOCK_BATCHES=(
  "app_demo_seed_20260311"
  "partners_mock_seed_20260311"
)

echo "Starting mock data purge..."
echo "Target environment URL: $SUPABASE_URL"

for BATCH in "${MOCK_BATCHES[@]}"; do
  echo "------------------------------------------------------------"
  echo "Purging batch: $BATCH"

  RESPONSE=$(curl --fail-with-body -sS -X POST "$SUPABASE_URL/rest/v1/rpc/purge_mock_batch" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"p_mock_batch\": \"$BATCH\"}")

  echo "Result: $RESPONSE"
done

echo "------------------------------------------------------------"
echo "Mock data purge sequence completed successfully."
