#!/bin/bash

# ==============================================================================
# Purge Mock Data Batches
# ------------------------------------------------------------------------------
# Usage:
#   ./scripts/purge_mocks.sh <SUPABASE_URL> <SUPABASE_SERVICE_ROLE_KEY>
#
# Description:
#   This script connects to the specified Supabase environment and executes the 
#   `purge_mock_batch` RPC for all known mock data batches. It is intended to 
#   be run as a deployment gate step for production environments to ensure zero 
#   mock data bleeds into live environments.
# ==============================================================================

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: Missing required arguments."
  echo "Usage: ./scripts/purge_mocks.sh <SUPABASE_URL> <SUPABASE_SERVICE_ROLE_KEY>"
  exit 1
fi

SUPABASE_URL="$1"
SERVICE_ROLE_KEY="$2"

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
  
  RESPONSE=$(curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/purge_mock_batch" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"p_mock_batch\": \"$BATCH\"}")
    
  echo "Result: $RESPONSE"
done

echo "------------------------------------------------------------"
echo "Mock data purge sequence completed successfully."
