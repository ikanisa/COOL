#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
PYTHON="${PYTHON:-python3}"
REFERENCE_DIR="${REVOLUT_REFERENCE_DIR:-/Users/jeanbosco/Downloads/Revolut10}"
EVIDENCE_DIR="${COLLECT_VISUAL_EVIDENCE_DIR:-$ROOT_DIR/.cache/collect_visual_evidence/$(date -u +%Y%m%dT%H%M%SZ)}"
FRESH_CAPTURE="${COLLECT_VISUAL_EVIDENCE_FRESH:-0}"

mkdir -p "$EVIDENCE_DIR/contact_sheets"

if [[ ! -d "$REFERENCE_DIR" ]]; then
  printf '[collect-visual-evidence][FAIL] reference directory missing: %s\n' "$REFERENCE_DIR" >&2
  exit 1
fi

latest_json() {
  local glob="$1"
  ruby -e 'paths = Dir[ARGV[0]].sort; puts(paths.last || "")' "$glob"
}

if [[ "$FRESH_CAPTURE" == "1" ]]; then
  COLLECT_VISUAL_EVIDENCE_DIR="$EVIDENCE_DIR" \
    "$FLUTTER" test --no-pub test/visual_evidence_capture_test.dart
  MOBILE_DIR="$EVIDENCE_DIR/mobile"
  ADMIN_DIR="$EVIDENCE_DIR/admin"
  MODE="fresh_flutter_test_capture"
  FRESHNESS_CAVEAT="Fresh Flutter-test screenshots were requested. If this script passed, source screenshots were generated during this run."
else
  MOBILE_SUMMARY="${MOBILE_VISUAL_SOURCE_SUMMARY:-$(latest_json "$ROOT_DIR/.cache/mobile_route_render_smoke/*/summary.json")}"
  ADMIN_SUMMARY="${ADMIN_VISUAL_SOURCE_SUMMARY:-$(latest_json "$ROOT_DIR/.cache/admin_pwa_render_smoke/*/summary.json")}"
  if [[ -z "$MOBILE_SUMMARY" || ! -f "$MOBILE_SUMMARY" ]]; then
    printf '[collect-visual-evidence][FAIL] no mobile route summary found. Set MOBILE_VISUAL_SOURCE_SUMMARY or run mobile route evidence first.\n' >&2
    exit 1
  fi
  if [[ -z "$ADMIN_SUMMARY" || ! -f "$ADMIN_SUMMARY" ]]; then
    printf '[collect-visual-evidence][FAIL] no admin render summary found. Set ADMIN_VISUAL_SOURCE_SUMMARY or run admin render evidence first.\n' >&2
    exit 1
  fi
  MOBILE_DIR="$(dirname "$MOBILE_SUMMARY")"
  ADMIN_DIR="$(dirname "$ADMIN_SUMMARY")"
  MODE="contact_sheets_from_available_evidence"
  FRESHNESS_CAVEAT="Contact sheets were generated now from the newest available PNG evidence; source route/admin screenshots may be prior evidence and do not replace a fresh post-implementation render smoke."
fi

"$PYTHON" "$ROOT_DIR/scripts/generate_visual_evidence_contact_sheets.py" \
  --reference-dir "$REFERENCE_DIR" \
  --mobile-dir "$MOBILE_DIR" \
  --admin-dir "$ADMIN_DIR" \
  --output-dir "$EVIDENCE_DIR/contact_sheets" >"$EVIDENCE_DIR/contact_sheets/stdout.json"

cat >"$EVIDENCE_DIR/summary.json" <<JSON
{
  "status": "pass",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mode": "$MODE",
  "reference_dir": "$REFERENCE_DIR",
  "mobile_source_dir": "$MOBILE_DIR",
  "admin_source_dir": "$ADMIN_DIR",
  "contact_sheets": "contact_sheets/contact_sheets.json",
  "freshness_caveat": "$FRESHNESS_CAVEAT",
  "privacy": "Visual evidence must not include raw secrets, raw SMS bodies, OTPs, PINs, provider tokens, service-role keys, private phone numbers, raw receiver MoMo numbers, or production customer data."
}
JSON

printf '[collect-visual-evidence] pass evidence=%s\n' "$EVIDENCE_DIR"
