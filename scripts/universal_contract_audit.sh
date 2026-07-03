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

def repo_source_paths(root)
  raw = IO.popen(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    chdir: root,
    &:read
  ).to_s
  raw.split("\0").reject(&:empty?).uniq
end

def source_text_file?(root, path)
  return false if path == "DESIGN.md"
  return false if path.start_with?(".git/", ".dart_tool/", ".cache/", "build/", "ios/Pods/")
  return false if ["scripts/universal_contract_gate.sh", "scripts/universal_contract_audit.sh"].include?(path)
  absolute = File.join(root, path)
  return false unless File.file?(absolute)

  sample = File.open(absolute, "rb") { |file| file.read(8192).to_s }
  !sample.include?("\x00")
rescue Errno::ENOENT, Errno::EACCES
  false
end

def forbidden_design_content_hits(root)
  forbidden_patterns = {
    "legacy surface scope evidence id" => /COOL_SURFACE_SCOPE_EVIDENCE/,
    "legacy strict audit artifact id" => /COOL_UNIVERSAL_DESIGN_STRICT_AUDIT/,
    "legacy surface scope lowercase id" => /surface_scope_evidence|cool_surface_scope/,
    "legacy applicability escape hatch" => /cool_tv_not_applicable|not_applicable_entries|route_evidence_map/,
    "secondary release-doc authority wording" => /DESIGN\.md\s+and\s+docs\/release/i,
    "legacy token source list names" => /brandPrimaryHexes|secondaryColorHexes|required_css_vars|brand_color_contract|shared_primary_color_contract/,
    "legacy generated runtime asset path" => %r{assets/runtime/generated},
    "legacy Play screenshot export path" => %r{fastlane/metadata/android/en-US/images/phoneScreenshots},
    "old mobile-only design contract" => /Universal Mobile App Design Standard 2026/
  }
  hits = []
  repo_source_paths(root).each do |path|
    next unless source_text_file?(root, path)

    content = File.read(File.join(root, path), mode: "rb")
    forbidden_patterns.each do |label, pattern|
      next unless content.match?(pattern)

      hits << { "path" => path, "pattern" => label }
    end
  rescue Errno::ENOENT, Errno::EACCES, ArgumentError
    next
  end
  hits
end

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
  "not_applicable_for_cool",
  "COOL has no TV product surface in this release",
  "Admin Panel Standard",
  "Accessibility Standard",
  "Visual QA Standard",
  "Flutter Implementation Standard",
  "Robust Implementation Goal",
  "Quality Gates",
  "Universal App Generation Prompt",
  "native TV packaging"
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
  "legacy visual capture test" => File.join("test", "visual" + "_evidence_capture_test.dart"),
  "legacy scope applicability record" => File.join("docs", "release", "UNIVERSAL_SCOPE_APPLICABILITY.json"),
  "legacy COOL surface scope evidence" => File.join("docs", "release", "COOL_SURFACE_SCOPE_EVIDENCE.json")
}
existing_secondary = secondary_sources.select { |_label, path| File.exist?(File.join(root, path)) }.keys
add_check.call("no_secondary_contract_sources", existing_secondary.empty?, existing_secondary.map { |label| "Secondary contract source still exists: #{label}." }, ["DESIGN.md"])
tracked_paths = IO.popen(["git", "ls-files"], chdir: root, &:read).to_s.lines.map(&:strip)
forbidden_tracked_paths = tracked_paths.reject do |path|
  path == "DESIGN.md" ||
    !path.match?(
      %r{(^|/)(design)(/|\.|-|_)|design[_-]|[_-]design|DESIGN_SYSTEM|design-system|figma|wireframe|prototype|visual_qa|collect_mobile_design|product_design|revolut_parity|baseline_routes|icon-mapping|source_variants|assets/brand|^assets/fonts/|^assets/runtime/|^web/icons/|^ios/Runner/Assets\.xcassets/.*\.(png|jpg|jpeg|webp)$|^android/app/src/main/res/.*/.*\.(png|webp)$|brand-primary-colors}i
    )
end
add_check.call(
  "tracked_design_source_paths",
  forbidden_tracked_paths.empty?,
  forbidden_tracked_paths.map { |path| "Forbidden tracked design source path remains: #{path}." },
  ["DESIGN.md"]
)
forbidden_content_hits = forbidden_design_content_hits(root)
add_check.call(
  "forbidden_design_content_patterns",
  forbidden_content_hits.empty?,
  forbidden_content_hits.map { |hit| "Forbidden legacy design authority content remains in #{hit.fetch("path")}: #{hit.fetch("pattern")}." },
  ["DESIGN.md"]
)
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
report = +"# Universal App Design Compliance Audit\n\n"
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
