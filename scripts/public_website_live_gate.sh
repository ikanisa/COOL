#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_URL="${PUBLIC_WEBSITE_URL:-https://collect.ikanisa.com}"
CANONICAL_URL="${PUBLIC_WEBSITE_CANONICAL_URL:-$BASE_URL}"
MODE="${1:-}"
exec ruby "$ROOT_DIR/scripts/qa/public_website_live_gate.rb" "$BASE_URL" "$CANONICAL_URL" "$MODE" "$ROOT_DIR"
