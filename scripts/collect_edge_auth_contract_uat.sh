#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Inventory and auth wiring only. Handler and database behavior have their own
# executable tests; this gate does not claim hosted or provider acceptance.
ruby "$ROOT_DIR/scripts/edge_function_inventory.rb" auth-check
printf '[collect-edge-auth-uat] Edge Function auth contract UAT passed\n'
