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
  blockers << "Universal contract is missing: #{design_contract}."
else
  design = File.read(design_path)
  required_terms = [
    "Universal App Design Standard 2026",
    "Any production mobile app",
    "native Flutter TV app",
    "admin panel",
    "Cross-Surface Product Architecture",
    "Screen Archetypes",
    "Universal Token Model",
    "Universal Component Library",
    "State Requirements",
    "Responsive And Adaptive Standard",
    "Native Flutter TV Standard",
    "Admin Panel Standard",
    "Accessibility Standard",
    "Visual QA Standard",
    "Flutter Implementation Standard",
    "Robust Implementation Goal",
    "Quality Gates",
    "Universal App Generation Prompt",
    "native TV packaging"
  ]
  required_terms.each do |term|
    present = design.include?(term)
    checks[term] = { "status" => present ? "pass" : "blocked" }
    blockers << "DESIGN.md is missing required term: #{term}." unless present
  end
end
secondary_sources = {
  "design folder" => File.join("docs", "design"),
  "archived May design folder" => File.join("docs", "archive", "2026-05", "design"),
  "archived June design folder" => File.join("docs", "archive", "2026-06", "design"),
  "legacy QA markdown" => "design" + "-qa.md",
  "legacy brand asset tree" => File.join("assets", "brand"),
  "runtime source-variant folder" => File.join("assets", "runtime", "source_" + "variants"),
  "runtime icon mapping data" => File.join("assets", "runtime", "collect_runtime", "icons", "icon-" + "mapping.json"),
  "legacy public website visual QA script" => File.join("scripts", "public_website_playwright_" + "visual_qa.js"),
  "legacy mobile design audit script" => File.join("scripts", "collect_mobile_" + "design_compliance_audit.sh"),
  "legacy universal design gate script" => File.join("scripts", "universal_" + "design_contract_gate.sh"),
  "legacy parity signoff gate script" => File.join("scripts", "re" + "volut_parity_signoff_gate.sh"),
  "legacy product design audit gate script" => File.join("scripts", "product_" + "design_mobile_audit_artifact_gate.sh"),
  "developer design catalog screen" => File.join("lib", "features", "dev", "design" + "_system_catalog_screen.dart"),
  "legacy visual capture test" => File.join("test", "visual" + "_evidence_capture_test.dart"),
  "legacy scope applicability record" => File.join("docs", "release", "UNIVERSAL_SCOPE_APPLICABILITY.json"),
  "legacy COOL surface scope evidence" => File.join("docs", "release", "COOL_SURFACE_SCOPE_EVIDENCE.json")
}
secondary_sources.each do |label, path|
  absent = !File.exist?(File.join(root, path))
  checks["secondary_absent: #{label}"] = { "status" => absent ? "pass" : "blocked" }
  blockers << "Secondary contract source still exists: #{label}." unless absent
end
tracked_paths = IO.popen(["git", "ls-files"], chdir: root, &:read).to_s.lines.map(&:strip)
forbidden_tracked_paths = tracked_paths.reject do |path|
  path == "DESIGN.md" ||
    !path.match?(
      %r{(^|/)(design)(/|\.|-|_)|design[_-]|[_-]design|DESIGN_SYSTEM|design-system|figma|wireframe|prototype|visual_qa|collect_mobile_design|product_design|revolut_parity|baseline_routes|icon-mapping|source_variants|assets/brand|^assets/fonts/|^assets/runtime/|^web/icons/|^ios/Runner/Assets\.xcassets/.*\.(png|jpg|jpeg|webp)$|^android/app/src/main/res/.*/.*\.(png|webp)$|brand-primary-colors}i
    )
end
checks["tracked_design_source_paths"] = {
  "status" => forbidden_tracked_paths.empty? ? "pass" : "blocked",
  "paths" => forbidden_tracked_paths
}
forbidden_tracked_paths.each do |path|
  blockers << "Forbidden tracked design source path remains: #{path}."
end
blockers.uniq!
status = blockers.any? ? "blocked" : "pass"
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "decision" => status == "pass" ? "GO" : "NO-GO",
  "design_contract" => design_contract,
  "blocker_keys" => status == "pass" ? [] : ["universal_contract"],
  "failure_keys" => [],
  "blockers" => blockers,
  "checks" => checks,
  "secret_handling" => "This gate reads repo contract text only. Do not add secrets, signing keys, raw SMS bodies, OTPs, private phone numbers, raw receiver MoMo numbers, provider tokens, or production customer data."
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
