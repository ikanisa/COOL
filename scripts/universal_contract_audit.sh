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

latest_json() {
  local glob="$1"
  ruby -e 'paths = Dir[ARGV[0]].sort; puts(paths.last || "")' "$glob"
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_dir="${COLLECT_MOBILE_CONTRACT_AUDIT_DIR:-$ROOT_DIR/.cache/collect_mobile_contract_compliance/$timestamp}"
route_summary="${MOBILE_ROUTE_RENDER_SUMMARY:-$(latest_json "$ROOT_DIR/.cache/mobile_route_render_smoke/*/summary.json")}"
android_uat_summary="${ANDROID_DEVICE_UAT_SUMMARY:-$(latest_json "$ROOT_DIR/.cache/android_device_uat/*/summary.json")}"
mkdir -p "$evidence_dir"

ROOT_DIR="$ROOT_DIR" \
EVIDENCE_DIR="$evidence_dir" \
OUTPUT_FORMAT="$output_format" \
ROUTE_SUMMARY="$route_summary" \
ANDROID_UAT_SUMMARY="$android_uat_summary" \
ruby -r json -r time <<'RUBY_INNER'
root = ENV.fetch("ROOT_DIR")
evidence_dir = ENV.fetch("EVIDENCE_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")
route_summary_path = ENV.fetch("ROUTE_SUMMARY")
android_uat_summary_path = ENV.fetch("ANDROID_UAT_SUMMARY")
def json_file(path)
  return nil if path.to_s.empty? || !File.exist?(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError => error
  { "status" => "invalid_json", "error" => error.message }
end
design_path = File.join(root, "DESIGN.md")
design = File.file?(design_path) ? File.read(design_path) : ""
route_summary = json_file(route_summary_path)
android_summary = json_file(android_uat_summary_path)
checks = []
add_check = lambda do |id, pass, failures = [], evidence = []|
  checks << { "id" => id, "status" => pass ? "pass" : "fail", "failures" => failures, "evidence" => evidence.compact }
end
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
missing_terms = required_terms.reject { |term| design.include?(term) }
add_check.call("single_universal_contract", File.file?(design_path) && missing_terms.empty?, missing_terms.map { |term| "DESIGN.md is missing #{term}." }, ["DESIGN.md"])
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
  "legacy visual capture test" => File.join("test", "visual" + "_evidence_capture_test.dart")
}
existing_secondary = secondary_sources.select { |_label, path| File.exist?(File.join(root, path)) }.keys
add_check.call("no_secondary_contract_sources", existing_secondary.empty?, existing_secondary.map { |label| "Secondary contract source still exists: #{label}." }, ["DESIGN.md"])
state_terms = ["Loading", "Empty", "Error", "Offline", "Permission denied", "Disabled", "Focused", "Pressed", "Selected", "Large text", "Reduced motion", "Dark mode", "Light mode"]
missing_states = state_terms.reject { |term| design.include?(term) }
add_check.call("universal_component_state_contract", missing_states.empty?, missing_states.map { |term| "DESIGN.md state contract is missing #{term}." }, ["DESIGN.md"])
adaptive_terms = ["320-374", "375-430", "720+", "Landscape", "Foldables", "Keyboard open"]
missing_adaptive = adaptive_terms.reject { |term| design.include?(term) }
add_check.call("responsive_adaptive_contract", missing_adaptive.empty?, missing_adaptive.map { |term| "DESIGN.md adaptive matrix is missing #{term}." }, ["DESIGN.md"])
route_failures = []
route_failures << "Route screenshot summary is invalid JSON: #{route_summary.fetch("error", "unknown")}." if route_summary && route_summary.fetch("status", nil) == "invalid_json"
add_check.call("route_screenshot_evidence_optional", route_failures.empty?, route_failures, [route_summary_path.to_s.empty? ? nil : route_summary_path])
android_failures = []
android_failures << "Android UAT summary is invalid JSON: #{android_summary.fetch("error", "unknown")}." if android_summary && android_summary.fetch("status", nil) == "invalid_json"
add_check.call("android_device_uat_evidence_optional", android_failures.empty?, android_failures, [android_uat_summary_path.to_s.empty? ? nil : android_uat_summary_path])
failed_checks = checks.select { |check| check.fetch("status") != "pass" }
summary = { "generated_at" => Time.now.utc.iso8601, "status" => failed_checks.empty? ? "pass" : "fail", "design_contract" => "DESIGN.md", "checks" => checks, "secret_handling" => "This audit reads local contract text and generated evidence metadata only; it must not print secrets, raw SMS, OTPs, PINs, private phone numbers, provider tokens, or production customer data." }
File.write(File.join(evidence_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")
report = +"# Universal Mobile Design Compliance Audit\n\n"
report << "- Generated: `#{summary.fetch("generated_at")}`\n"
report << "- Status: `#{summary.fetch("status")}`\n"
report << "- Design contract: `DESIGN.md`\n\n"
report << "## Checks\n\n| Check | Status | Evidence |\n| --- | --- | --- |\n"
checks.each { |check| report << "| `#{check.fetch("id")}` | `#{check.fetch("status")}` | #{Array(check["evidence"]).compact.map { |item| "`#{item}`" }.join("<br>")} |\n" }
unless failed_checks.empty?
  report << "\n## Failures\n\n"
  failed_checks.each do |check|
    report << "### #{check.fetch("id")}\n"
    Array(check["failures"]).each { |failure| report << "- #{failure}\n" }
    report << "\n"
  end
end
File.write(File.join(evidence_dir, "REPORT.md"), report)
puts(output_format == "json" ? JSON.pretty_generate(summary) : report)
exit(failed_checks.empty? ? 0 : 1)
RUBY_INNER
