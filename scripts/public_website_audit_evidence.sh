#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${PUBLIC_WEBSITE_URL:-https://collect.ikanisa.com}"
OUT_DIR="${PUBLIC_WEBSITE_EVIDENCE_DIR:-output/public_website_evidence}"

exec ruby "$ROOT_DIR/scripts/qa/public_website/live_audit.rb" "$BASE_URL" "$OUT_DIR"
