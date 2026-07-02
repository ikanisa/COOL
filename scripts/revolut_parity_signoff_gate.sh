#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
case "${1:-}" in
  --json) output_format="json" ;;
  "") ;;
  *)
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

matrix_path="${MOBI_REVOLUT_ALIGNMENT_MATRIX:-docs/design/MOBI_REVOLUT_100_PERCENT_ALIGNMENT_MATRIX.md}"

OUTPUT_FORMAT="$output_format" \
ROOT_DIR="$ROOT_DIR" \
MATRIX_PATH="$matrix_path" \
ruby -r json -r time <<'RUBY'
format = ENV.fetch("OUTPUT_FORMAT")
matrix_path = ENV.fetch("MATRIX_PATH")

blockers = []
checks = {}

if !File.exist?(matrix_path)
  blockers << "MOBI/Revolut alignment matrix is missing: #{matrix_path}."
else
  matrix = File.read(matrix_path)
  required_terms = [
    "100% MOBI/Revolut experiential parity",
    "## Non-Negotiable Target",
    "## Revolut Reference Route Mapping",
    "## MOBI Comparator Matrix",
    "## Comparative Implementation Table",
    "## Current Gap Table",
    "## Required Current Evidence",
    "## Deletion Register",
    "Active Deletion Decision",
    "MOBI evidence",
    "Revolut reference behavior",
    "Collect implementation files",
    "Contradiction handling",
    "scripts/product_design_mobile_audit_artifact_gate.sh",
    "docs/release/product_design_mobile_audit_2026-06-26/",
    "External filings",
    "IMG_2739.PNG",
    "IMG_2755.PNG",
    "StatefulShellRoute.indexedStack",
    "ConnectivityOverlay",
    "CollectAsyncStateView"
  ]
  required_terms.each do |term|
    present = matrix.include?(term)
    checks[term] = { "status" => present ? "pass" : "blocked" }
    blockers << "Alignment matrix is missing required term: #{term}." unless present
  end
end

split_authority_path = "docs/design/COLLECT_MOBI_REVOLUT_REPO_LEVEL_IMPLEMENTATION_TABLE_2026-07-02.md"
split_authority_absent = !File.exist?(split_authority_path)
checks["single_matrix_authority"] = { "status" => split_authority_absent ? "pass" : "blocked" }
blockers << "Split repo-level design authority still exists: #{split_authority_path}." unless split_authority_absent

stale_paths = [
  "docs/release/product_design_mobile_audit_2026-06-26",
  "docs/release/COLLECT_PREMIUM_MOBILE_FRONTEND_COMPLETION_REPORT_2026-06-27.md",
  "docs/release/CRITICAL_NATIVE_MOBILE_EXPERIENCE_AUDIT_2026-06-29.md",
  "docs/release/MOBILE_ON_DEVICE_QA_REPORT_2026-06-30.md",
  "docs/release/MOBILE_SCREEN_ROUTE_UAT_REVIEW_2026-06-30.md",
  "docs/design/ANDROID_TALKBACK_REVIEW_PACKET_2026-06-29.md"
]
stale_paths.each do |path|
  absent = !File.exist?(path)
  checks["stale_absent: #{path}"] = { "status" => absent ? "pass" : "blocked" }
  blockers << "Stale active UI/UX contradiction artifact still exists: #{path}." unless absent
end

blockers.uniq!
status = blockers.any? ? "blocked" : "pass"

result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "decision" => status == "pass" ? "GO" : "NO-GO",
  "matrix" => matrix_path,
  "blocker_keys" => status == "pass" ? [] : ["mobi_revolut_alignment_matrix"],
  "failure_keys" => [],
  "blockers" => blockers,
  "checks" => checks,
  "secret_handling" => "This gate reads repo design text only. Do not add secrets, signing keys, raw SMS bodies, OTPs, private phone numbers, raw receiver MoMo numbers, provider tokens, or production customer data."
}

if format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[mobi-revolut-alignment] status=#{status} decision=#{result.fetch("decision")}"
  blockers.each { |blocker| warn "[mobi-revolut-alignment][BLOCKED] #{blocker}" }
end

exit(status == "pass" ? 0 : status == "blocked" ? 99 : 1)
RUBY
