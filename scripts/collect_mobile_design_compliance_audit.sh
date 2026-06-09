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
evidence_dir="${COLLECT_MOBILE_DESIGN_AUDIT_DIR:-$ROOT_DIR/.cache/collect_mobile_design_compliance/$timestamp}"
route_summary="${MOBILE_ROUTE_RENDER_SUMMARY:-$(latest_json "$ROOT_DIR/.cache/mobile_route_render_smoke/*/summary.json")}"
android_uat_summary="${ANDROID_DEVICE_UAT_SUMMARY:-$(latest_json "$ROOT_DIR/.cache/android_device_uat/*/summary.json")}"
mkdir -p "$evidence_dir"

ROOT_DIR="$ROOT_DIR" \
EVIDENCE_DIR="$evidence_dir" \
OUTPUT_FORMAT="$output_format" \
ROUTE_SUMMARY="$route_summary" \
ANDROID_UAT_SUMMARY="$android_uat_summary" \
ruby -r json -r time <<'RUBY'
root = ENV.fetch("ROOT_DIR")
evidence_dir = ENV.fetch("EVIDENCE_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")
route_summary_path = ENV.fetch("ROUTE_SUMMARY")
android_uat_summary_path = ENV.fetch("ANDROID_UAT_SUMMARY")

def rel(root, path)
  path.to_s.delete_prefix("#{root}/")
end

def read(path)
  File.read(path)
end

def json_file(path)
  return nil if path.to_s.empty? || !File.exist?(path)

  JSON.parse(File.read(path))
rescue JSON::ParserError => error
  { "status" => "invalid_json", "error" => error.message }
end

def collect_routes(root)
  router = read(File.join(root, "lib/app/router.dart"))
  list = router[/const collectRoutePaths = <String>\[(.*?)\];/m, 1] || ""
  list.scan(%r{'(/[^']*)'}).flatten.reject { |route| route == "/dev/design-system" }
end

def materialize(route)
  route
    .gsub(":collectionId", "col-church")
    .gsub(":intentId", "intent-render")
    .gsub(":state", "pending")
    .gsub(":slug", "st-michel-building-fund")
end

def scan_files(root, pattern, paths)
  hits = []
  paths.each do |relative|
    absolute = File.join(root, relative)
    next unless File.file?(absolute)

    File.readlines(absolute, chomp: true).each_with_index do |line, index|
      next unless line.match?(pattern)

      hits << {
        "path" => relative,
        "line" => index + 1,
        "text" => line.strip
      }
    end
  end
  hits
end

def all_flutter_files(root)
  Dir[File.join(root, "lib/**/*.dart")].sort.map { |path| rel(root, path) }
end

def status_for(failures)
  failures.empty? ? "pass" : "fail"
end

design = read(File.join(root, "DESIGN.md"))
design_system = read(File.join(root, "docs/design/DESIGN_SYSTEM.md"))
colors = read(File.join(root, "lib/app/theme/collect_colors.dart"))
components = read(File.join(root, "lib/shared/widgets/collect_components.dart"))
shell = read(File.join(root, "lib/core/widgets/collect_shell.dart"))
share_screen = read(File.join(root, "lib/features/collections/share_screen.dart"))
flutter_files = all_flutter_files(root)
route_summary = json_file(route_summary_path)
android_uat_summary = json_file(android_uat_summary_path)

primary_color_block = design[/primary-paint-colors:\n(.*?)tokens:/m, 1] || ""
primary_hexes = primary_color_block.scan(/(?:periwinkle|mint-green|dusty-rose|orange-red):\s*'?(#[0-9A-Fa-f]{6})'?/).flatten
expected_primary_hexes = ["#8885F0", "#3CD070", "#D38B96", "#FF5E43"]
canvas_hex = "#FAF8F5"

checks = []

color_failures = []
color_failures << "DESIGN.md primary paint colors must be exactly #{expected_primary_hexes.join(", ")}." unless primary_hexes == expected_primary_hexes
color_failures << "DESIGN.md must define Paper #{canvas_hex} as canvas, not as a primary paint color." unless design.match?(/canvas:\s+paper:\s*'#{Regexp.escape(canvas_hex)}'/m)
expected_primary_hexes.each do |hex|
  color_failures << "CollectColors.brandPrimaryHexes is missing #{hex}." unless colors.include?(hex)
  dart_hex = "0xFF#{hex.delete_prefix("#")}"
  color_failures << "CollectColors is missing #{dart_hex}." unless colors.include?(dart_hex)
end
color_failures << "CollectColors must keep Paper #{canvas_hex} as brandPaper canvas." unless colors.include?("0xFF#{canvas_hex.delete_prefix("#")}")
brand_primary_block = colors[/brandPrimaryColors = <Color>\[(.*?)\];/m, 1].to_s
color_failures << "CollectColors.brandPrimaryColors must not include Paper canvas." if brand_primary_block.include?("brandPaper")
color_failures << "CollectColors.brandPrimaryColors must not include transparent foundation." if brand_primary_block.include?("transparentColor")
checks << {
  "id" => "four_primary_paint_color_contract",
  "status" => status_for(color_failures),
  "failures" => color_failures,
  "evidence" => ["DESIGN.md", "lib/app/theme/collect_colors.dart"]
}

reference_failures = []
%w[Revolut gradient glass CollectGradientBackground].each do |term|
  reference_failures << "DESIGN.md must include #{term} reference contract." unless design.include?(term)
  reference_failures << "docs/design/DESIGN_SYSTEM.md must include #{term} implementation contract." unless design_system.include?(term)
end
reference_failures << "DESIGN.md must explicitly reject copying Revolut assets/trademarks." unless design.match?(/not a license to copy Revolut assets/i)
reference_failures << "DESIGN_SYSTEM.md must explicitly reject copying Revolut or Monzo assets." unless design_system.match?(/does not copy Revolut or Monzo/i)
checks << {
  "id" => "revolut_reference_collect_owned_contract",
  "status" => status_for(reference_failures),
  "failures" => reference_failures,
  "evidence" => ["DESIGN.md", "docs/design/DESIGN_SYSTEM.md"]
}

gradient_failures = []
%w[screenGradient glassPanel glassPanelStrong glassControl glassBorder glassPanelGradient].each do |token|
  gradient_failures << "CollectColors is missing #{token}." unless colors.include?(token)
end
gradient_failures << "CollectShell must wrap the member app in CollectGradientBackground." unless shell.include?("CollectGradientBackground")
gradient_failures << "PremiumScaffold must render CollectGradientBackground." unless components[/class PremiumScaffold.*?CollectGradientBackground/m]
gradient_failures << "Standalone ShareScreen must render CollectGradientBackground." unless share_screen.include?("CollectGradientBackground")
checks << {
  "id" => "gradient_glass_screen_contract",
  "status" => status_for(gradient_failures),
  "failures" => gradient_failures,
  "evidence" => [
    "lib/app/theme/collect_colors.dart",
    "lib/core/widgets/collect_shell.dart",
    "lib/shared/widgets/collect_components.dart",
    "lib/features/collections/share_screen.dart"
  ]
}

asset_failures = []
wordmark_path = File.join(root, "assets/brand/generated/collect_wordmark_transparent.png")
asset_failures << "Transparent Collect wordmark asset is missing." unless File.file?(wordmark_path)
asset_failures << "CollectBrandMark must use collect_wordmark_transparent.png." unless components.include?("collect_wordmark_transparent.png")
asset_failures << "DESIGN.md must name collect_wordmark_transparent.png as the mobile wordmark." unless design.include?("collect_wordmark_transparent.png")
checks << {
  "id" => "mobile_brand_asset_contract",
  "status" => status_for(asset_failures),
  "failures" => asset_failures,
  "evidence" => [
    "assets/brand/generated/collect_wordmark_transparent.png",
    "lib/shared/widgets/collect_components.dart",
    "DESIGN.md"
  ]
}

forbidden_color_hits = scan_files(
  root,
  /#[0-9A-Fa-f]{6}\b|0x[0-9A-Fa-f]{8}\b|Colors\.[A-Za-z]+\b|CupertinoColors\.[A-Za-z]+\b/,
  flutter_files
).reject do |hit|
  path = hit.fetch("path")
  text = hit.fetch("text")
  path.start_with?("lib/app/theme/") ||
    text.include?("CollectColors.") ||
    text.include?("context.collectColors") ||
    text.include?("_colorFromHex") ||
    text.include?("Color(int.parse")
end
checks << {
  "id" => "no_raw_ui_colors_outside_tokens",
  "status" => forbidden_color_hits.empty? ? "pass" : "fail",
  "hits" => forbidden_color_hits,
  "evidence" => ["lib/**/*.dart"]
}

platform_color_files = [
  "android/app/src/main/res/values/colors.xml",
  "android/app/src/main/res/values/styles.xml",
  "android/app/src/main/res/values-v31/styles.xml",
  "android/app/src/main/res/values-night/styles.xml",
  "android/app/src/main/res/values-night-v31/styles.xml",
  "android/app/src/main/res/drawable/launch_background.xml",
  "android/app/src/main/res/drawable-v21/launch_background.xml",
  "android/app/src/main/res/drawable-night/launch_background.xml",
  "android/app/src/main/res/drawable-night-v21/launch_background.xml",
  "web/manifest.json",
  "web/index.html"
]

allowed_platform_hexes = expected_primary_hexes + [canvas_hex]
platform_color_hits = scan_files(
  root,
  /#[0-9A-Fa-f]{6}\b/,
  platform_color_files
).reject do |hit|
  allowed_platform_hexes.any? { |hex| hit.fetch("text").include?(hex) }
end
legacy_platform_hits = scan_files(
  root,
  /collect_ink|Theme\.Black|#121212|#000000|#262B33|#FFFFFF/i,
  platform_color_files
)
checks << {
  "id" => "platform_metadata_colors_match_contract",
  "status" => platform_color_hits.empty? && legacy_platform_hits.empty? ? "pass" : "fail",
  "hits" => platform_color_hits + legacy_platform_hits,
  "evidence" => platform_color_files
}

domain_hits = scan_files(
  root,
  %r{https://collect\.rw|https://collet\.ikanisa\.com},
  flutter_files + Dir[File.join(root, "test/**/*.dart")].sort.map { |path| rel(root, path) }
)
correct_domain_hits = scan_files(
  root,
  %r{https://collect\.ikanisa\.com},
  flutter_files + Dir[File.join(root, "test/**/*.dart")].sort.map { |path| rel(root, path) }
)
checks << {
  "id" => "share_domain_contract",
  "status" => domain_hits.empty? && !correct_domain_hits.empty? ? "pass" : "fail",
  "hits" => domain_hits,
  "evidence" => correct_domain_hits.map { |hit| "#{hit.fetch("path")}:#{hit.fetch("line")}" }.uniq
}

manual_group_entry_hits = scan_files(
  root,
  /\b(?:Group code or link|Join with link|enter group URL|group URL|group urls|group link input)\b/i,
  flutter_files
)
checks << {
  "id" => "no_manual_group_url_entry",
  "status" => manual_group_entry_hits.empty? ? "pass" : "fail",
  "hits" => manual_group_entry_hits,
  "evidence" => ["lib/**/*.dart"]
}

manage_text = read(File.join(root, "lib/features/collections/collection_manage_screen.dart"))
group_settings_failures = []
group_settings_failures << "Group settings must not include SMS readiness; app access owns it." if manage_text.match?(/SMS readiness/i)
%w[Group\ profile Group\ QR Share\ group Ledger Members Support].each do |label|
  clean_label = label.gsub("\\ ", " ")
  group_settings_failures << "Group settings is missing #{clean_label}." unless manage_text.include?(clean_label)
end
checks << {
  "id" => "group_settings_essential_items",
  "status" => status_for(group_settings_failures),
  "failures" => group_settings_failures,
  "evidence" => ["lib/features/collections/collection_manage_screen.dart"]
}

routes = collect_routes(root)
materialized_routes = routes.flat_map do |route|
  if route.include?(":state")
    %w[pending confirmed expired needs-review].map do |state|
      route
        .gsub(":collectionId", "col-church")
        .gsub(":intentId", "intent-render")
        .gsub(":state", state)
    end
  else
    [materialize(route)]
  end
end.uniq
route_failures = []
capture_checks = []
if route_summary.nil?
  route_failures << "No mobile route render smoke summary found."
elsif route_summary.fetch("status", nil) != "pass"
  route_failures << "Mobile route render smoke status is #{route_summary.fetch("status", "missing")}."
else
  smoke_routes = Array(route_summary["routes"])
  missing = materialized_routes - smoke_routes
  extra = smoke_routes - materialized_routes
  route_failures << "Missing route screenshot coverage: #{missing.join(", ")}." unless missing.empty?
  route_failures << "Smoke summary contains unregistered route(s): #{extra.join(", ")}." unless extra.empty?

  captures = Array(route_summary["captures"])
  captures.each do |capture|
    png_path = File.join(File.dirname(route_summary_path), capture.fetch("path", ""))
    failures = []
    failures << "missing_png" unless File.file?(png_path)
    failures << "too_few_pixels" if capture.fetch("non_background_pixels", 0).to_i < 100
    failures << "too_few_colors" if capture.fetch("distinct_rgb", 0).to_i < 16
    failures << "wrong_viewport" unless capture.fetch("width", 0).to_i == 390 && capture.fetch("height", 0).to_i == 844
    capture_checks << {
      "name" => capture["name"],
      "route" => capture["route"],
      "status" => failures.empty? ? "pass" : "fail",
      "failures" => failures,
      "path" => rel(root, png_path)
    }
  end
  failed_captures = capture_checks.select { |item| item.fetch("status") != "pass" }
  route_failures << "#{failed_captures.length} screenshot capture(s) failed quality checks." unless failed_captures.empty?
end
checks << {
  "id" => "all_production_routes_rendered",
  "status" => status_for(route_failures),
  "failures" => route_failures,
  "route_count" => materialized_routes.length,
  "summary" => rel(root, route_summary_path),
  "captures" => capture_checks
}

android_failures = []
if android_uat_summary.nil?
  android_failures << "No Android device UAT summary found."
elsif android_uat_summary.fetch("status", nil) != "pass"
  android_failures << "Android device UAT status is #{android_uat_summary.fetch("status", "missing")}."
end
checks << {
  "id" => "android_device_uat_evidence",
  "status" => status_for(android_failures),
  "failures" => android_failures,
  "summary" => android_uat_summary_path.to_s.empty? ? nil : rel(root, android_uat_summary_path),
  "target" => android_uat_summary&.fetch("target", nil),
  "device_id" => android_uat_summary&.fetch("device_id", nil),
  "device_model" => android_uat_summary&.fetch("device_model", nil)
}

failed_checks = checks.select { |check| check.fetch("status") != "pass" }
summary = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status_for(failed_checks),
  "design_contract" => "DESIGN.md",
  "design_system" => "docs/design/DESIGN_SYSTEM.md",
  "reference_contract" => "Revolut screenshots inform gradient/glass fintech quality; Collect-owned colors, assets, copy, and product behavior remain mandatory.",
  "primary_colors" => expected_primary_hexes,
  "route_count" => materialized_routes.length,
  "checks" => checks,
  "secret_handling" => "The audit inspects local source paths and generated screenshot metadata only; it does not print secrets, raw SMS, OTPs, PINs, or private receiver data.",
  "remaining_human_review" => "Automated evidence cannot fully certify subjective premium visual taste, TalkBack/VoiceOver narration quality, or real store deep-link handoff UX without manual signoff."
}

File.write(File.join(evidence_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")

report = +"# Collect Mobile Design Compliance Audit\n\n"
report << "- Generated: `#{summary.fetch("generated_at")}`\n"
report << "- Status: `#{summary.fetch("status")}`\n"
report << "- Design contract: `DESIGN.md`\n"
report << "- Primary colors: #{expected_primary_hexes.map { |hex| "`#{hex}`" }.join(", ")}\n"
report << "- Route screenshots checked: `#{materialized_routes.length}`\n"
report << "- Route evidence: `#{summary.dig("checks", checks.index { |c| c["id"] == "all_production_routes_rendered" }, "summary")}`\n"
report << "- Android UAT evidence: `#{summary.dig("checks", checks.index { |c| c["id"] == "android_device_uat_evidence" }, "summary") || "missing"}`\n\n"
report << "## Checks\n\n"
report << "| Check | Status | Evidence |\n"
report << "| --- | --- | --- |\n"
checks.each do |check|
  evidence = Array(check["evidence"]).empty? ? [check["summary"]].compact : Array(check["evidence"])
  report << "| `#{check.fetch("id")}` | `#{check.fetch("status")}` | #{evidence.map { |item| "`#{item}`" }.join("<br>")} |\n"
end
unless failed_checks.empty?
  report << "\n## Failures\n\n"
  failed_checks.each do |check|
    report << "### #{check.fetch("id")}\n"
    Array(check["failures"]).each { |failure| report << "- #{failure}\n" }
    Array(check["hits"]).first(25).each do |hit|
      report << "- `#{hit.fetch("path")}:#{hit.fetch("line")}` #{hit.fetch("text")}\n"
    end
    report << "\n"
  end
end
report << "\n## Human Review Boundary\n\n"
report << "#{summary.fetch("remaining_human_review")}\n"
File.write(File.join(evidence_dir, "report.md"), report)

if output_format == "json"
  puts JSON.pretty_generate(summary)
else
  puts "[collect-mobile-design-audit] status=#{summary.fetch("status")} evidence=#{evidence_dir}"
  checks.each { |check| puts "[collect-mobile-design-audit] #{check.fetch("id")}=#{check.fetch("status")}" }
end

exit(summary.fetch("status") == "pass" ? 0 : 1)
RUBY
