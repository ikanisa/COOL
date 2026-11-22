#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EVIDENCE_DIR="${PUBLIC_WEBSITE_EVIDENCE_DIR:-output/public_website_evidence}"
OUT_PATH="${PUBLIC_WEBSITE_COMPLETION_REPORT:-.cache/public_website_completion_report/REPORT.md}"

mkdir -p "$EVIDENCE_DIR" "$(dirname "$OUT_PATH")"

COMPLETION_JSON="$(mktemp)"
trap 'rm -f "$COMPLETION_JSON"' EXIT

set +e
scripts/public_website_completion_gate.sh --json > "$COMPLETION_JSON"
GATE_RC=$?
set -e

ruby "$ROOT_DIR/scripts/qa/public_website/completion_report.rb" "$COMPLETION_JSON" "$OUT_PATH" "$GATE_RC"
