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

design_contract="${UNIVERSAL_DESIGN_CONTRACT:-DESIGN.md}"

OUTPUT_FORMAT="$output_format" \
ROOT_DIR="$ROOT_DIR" \
DESIGN_CONTRACT="$design_contract" \
ruby -r json -r time <<'RUBY_INNER'
format = ENV.fetch("OUTPUT_FORMAT")
root = ENV.fetch("ROOT_DIR")
design_contract = ENV.fetch("DESIGN_CONTRACT")
design_path = File.expand_path(design_contract, root)
blockers = []
checks = {}
if !File.exist?(design_path)
  blockers << "Universal design contract is missing: #{design_contract}."
else
  design = File.read(design_path)
  required_terms = [
    "Universal Mobile App Design Standard 2026",
    "Any production mobile app",
    "Screen Archetypes",
    "Universal Token Model",
    "Universal Component Library",
    "State Requirements",
    "Responsive And Adaptive Standard",
    "Accessibility Standard",
    "Visual QA Standard",
    "Flutter Implementation Standard",
    "Quality Gates",
    "Universal App Generation Prompt"
  ]
  required_terms.each do |term|
    present = design.include?(term)
    checks[term] = { "status" => present ? "pass" : "blocked" }
    blockers << "DESIGN.md is missing required term: #{term}." unless present
  end
end
secondary_paths = [
  "docs/design",
  "docs/archive/2026-05/design",
  "docs/archive/2026-06/design",
  "design-qa.md"
]
secondary_paths.each do |path|
  absent = !File.exist?(File.join(root, path))
  checks["secondary_absent: #{path}"] = { "status" => absent ? "pass" : "blocked" }
  blockers << "Secondary design authority still exists: #{path}." unless absent
end
blockers.uniq!
status = blockers.any? ? "blocked" : "pass"
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "decision" => status == "pass" ? "GO" : "NO-GO",
  "design_contract" => design_contract,
  "blocker_keys" => status == "pass" ? [] : ["universal_design_contract"],
  "failure_keys" => [],
  "blockers" => blockers,
  "checks" => checks,
  "secret_handling" => "This gate reads repo design text only. Do not add secrets, signing keys, raw SMS bodies, OTPs, private phone numbers, raw receiver MoMo numbers, provider tokens, or production customer data."
}
if format == "json"
  puts JSON.pretty_generate(result)
else
  puts "Status: #{status}"
  puts "Decision: #{result.fetch("decision")}"
  puts "Design contract: #{design_contract}"
  blockers.each { |blocker| puts "- #{blocker}" }
end
exit(status == "pass" ? 0 : 1)
RUBY_INNER
