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

def read_dart_library(root, relative)
  path = File.join(root, relative)
  source = read(path)
  library_dir = File.dirname(path)
  parts = source.scan(/^\s*part\s+['"]([^'"]+)['"];/).flatten
  ([source] + parts.map { |part| read(File.join(library_dir, part)) }).join("\n")
end

def png_size(path)
  bytes = File.binread(path)
  return nil unless bytes.bytesize >= 24 && bytes.byteslice(1, 3) == "PNG"

  {
    "width" => bytes.byteslice(16, 4).unpack1("N"),
    "height" => bytes.byteslice(20, 4).unpack1("N")
  }
rescue Errno::ENOENT
  nil
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
    .gsub(":publicId", "038491")
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
revolut_alignment_plan = read(File.join(root, "docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md"))
runtime_asset_intake = read(File.join(root, "docs/design/COLLECT_RUNTIME_ASSET_INTAKE_2026-06-29.md"))
revolut_blocker_register = read(File.join(root, "docs/design/REVOLUT_ALIGNMENT_BLOCKER_REGISTER_2026-06-27.md"))
pubspec = read(File.join(root, "pubspec.yaml"))
colors = read(File.join(root, "lib/app/theme/collect_colors.dart"))
component_tokens = read(File.join(root, "lib/app/theme/collect_component_tokens.dart"))
runtime_tokens = read(File.join(root, "lib/app/theme/collect_runtime_tokens.dart"))
components = read(File.join(root, "lib/shared/widgets/collect_components.dart"))
chrome = read_dart_library(root, "lib/shared/widgets/collect_chrome.dart")
runtime_assets = read(File.join(root, "lib/app/theme/collect_runtime_assets.dart"))
foundation = read(File.join(root, "lib/shared/widgets/collect_foundation.dart"))
inputs = read(File.join(root, "lib/shared/widgets/collect_inputs.dart"))
financial_components = read_dart_library(root, "lib/shared/widgets/collect_financial_components.dart")
shell = read(File.join(root, "lib/core/widgets/collect_shell.dart"))
share_screen = read(File.join(root, "lib/features/collections/share_screen.dart"))
home_screen = read(File.join(root, "lib/features/home/home_screen.dart"))
collections_screen = read(File.join(root, "lib/features/collections/collections_screen.dart"))
main_entry = read(File.join(root, "lib/main.dart"))
route_smoke_script = read(File.join(root, "scripts/mobile_route_render_smoke.sh"))
theme_parity_path = File.join(root, "test/features/theme_mode_visual_parity_test.dart")
theme_parity_test = File.file?(theme_parity_path) ? read(theme_parity_path) : ""
flutter_files = all_flutter_files(root)
route_summary = json_file(route_summary_path)
android_uat_summary = json_file(android_uat_summary_path)

collect_font_files = Dir[
  File.join(root, "assets/fonts/collect/**/*.{ttf,otf,woff,woff2}")
]
collect_runtime_brand_asset_files = Dir[
  File.join(root, "assets/brand/collect_runtime/**/*.{png,jpg,jpeg,webp,svg,gif,json}")
].reject { |path| File.basename(path).casecmp("README.md").zero? }
runtime_token_spec_files = Dir[
  File.join(root, "docs/design/collect_runtime_tokens/**/*.{json,yaml,yml,md}")
].reject { |path| File.basename(path).casecmp("README.md").zero? }
runtime_asset_roots = %w[
  assets/brand/collect_runtime/
  assets/brand/collect_runtime/logos/
  assets/brand/collect_runtime/app_icons/
  assets/brand/collect_runtime/splash/
  assets/brand/collect_runtime/icons/
  assets/brand/collect_runtime/media/
]
blocker_recorded = lambda do |key|
  revolut_blocker_register.match?(/\|\s*#{Regexp.escape(key)}\s*\|[^|\n]*\|\s*Blocked\s*\|/i)
end

primary_color_block = design[/primary-colors:\n(.*?)secondary-support-colors:/m, 1] || ""
primary_hexes = primary_color_block.scan(/(?:periwinkle|mint-green|dusty-rose|orange-red):\s*'?(#[0-9A-Fa-f]{6})'?/).flatten
expected_primary_hexes = ["#8885F0", "#3CD070", "#D38B96", "#FF5E43"]
canvas_hex = "#FAF8F5"

checks = []

color_failures = []
color_failures << "DESIGN.md primary colors must preserve exactly #{expected_primary_hexes.join(", ")} as the only distinct brand colors." unless primary_hexes == expected_primary_hexes
color_failures << "DESIGN.md must define Paper #{canvas_hex} as canvas, not as a primary color." unless design.match?(/canvas:\s+paper:\s*'#{Regexp.escape(canvas_hex)}'/m)
expected_primary_hexes.each do |hex|
  color_failures << "CollectColors.brandPrimaryHexes is missing required primary #{hex}." unless colors.include?(hex)
  dart_hex = "0xFF#{hex.delete_prefix("#")}"
  color_failures << "CollectColors is missing required primary #{dart_hex}." unless colors.include?(dart_hex)
end
color_failures << "CollectColors must keep Paper #{canvas_hex} as brandPaper canvas." unless colors.include?("0xFF#{canvas_hex.delete_prefix("#")}")
brand_primary_block = colors[/brandPrimaryColors = <Color>\[(.*?)\];/m, 1].to_s
color_failures << "CollectColors.brandPrimaryColors must not include Paper canvas." if brand_primary_block.include?("brandPaper")
color_failures << "CollectColors.brandPrimaryColors must not include Ink support tokens." if brand_primary_block.include?("inkPrimary")
color_failures << "CollectColors.brandPrimaryColors must not include transparent foundation." if brand_primary_block.include?("transparentColor")
checks << {
  "id" => "four_primary_color_distinction_contract",
  "status" => status_for(color_failures),
  "failures" => color_failures,
  "evidence" => ["DESIGN.md", "lib/app/theme/collect_colors.dart"]
}

secondary_expectations = {
  "inkPrimary" => "#252044",
  "inkSecondary" => "#4B4664",
  "inkMuted" => "#5F5A76",
  "secondarySurfaceReadable" => "#FFFDFB",
  "secondarySurfaceMuted" => "#F1ECF7",
  "secondaryBorderSoft" => "#DED8EA",
  "secondaryBorderAccent" => "#CDC7F5",
  "secondaryFocusRing" => "#6F67E8",
  "semanticSuccessForeground" => "#137A3F",
  "semanticInfoForeground" => "#514DD2",
  "semanticWarningForeground" => "#B9472E",
  "semanticDangerForeground" => "#B3261E",
  "semanticSuccessContainer" => "#E7F8ED",
  "semanticInfoContainer" => "#ECEBFF",
  "semanticWarningContainer" => "#FFE9E3",
  "semanticDangerContainer" => "#FFE5DF",
  "semanticNeutralContainer" => "#F1ECF7"
}
secondary_failures = []
secondary_expectations.each do |token, hex|
  dart_hex = "0xFF#{hex.delete_prefix("#")}"
  secondary_failures << "CollectColors is missing #{token} #{dart_hex}." unless colors.include?(token) && colors.include?(dart_hex)
  secondary_failures << "DESIGN.md is missing secondary/support color #{hex}." unless design.include?(hex)
  secondary_failures << "DESIGN_SYSTEM.md is missing secondary/support color #{hex}." unless design_system.include?(hex)
end
%w[
  successForeground: semanticSuccessForeground
  infoForeground: semanticInfoForeground
  warningForeground: semanticWarningForeground
  dangerForeground: semanticDangerForeground
  successContainer: semanticSuccessContainer
  infoContainer: semanticInfoContainer
  warningContainer: semanticWarningContainer
  dangerContainer: semanticDangerContainer
  neutralContainer: semanticNeutralContainer
].each do |binding|
  secondary_failures << "CollectColors.light must bind #{binding}." unless colors.include?(binding)
end
[
  "CollectStatusTone.success => successForeground",
  "CollectStatusTone.warning => warningForeground",
  "CollectStatusTone.danger => dangerForeground",
  "CollectStatusTone.info => infoForeground",
  "CollectStatusTone.success => successContainer",
  "CollectStatusTone.warning => warningContainer",
  "CollectStatusTone.danger => dangerContainer",
  "CollectStatusTone.info => infoContainer"
].each do |mapping|
  secondary_failures << "CollectColors status helpers must use #{mapping}." unless colors.include?(mapping)
end
checks << {
  "id" => "secondary_palette_semantic_contrast_contract",
  "status" => status_for(secondary_failures),
  "failures" => secondary_failures,
  "evidence" => [
    "DESIGN.md",
    "docs/design/DESIGN_SYSTEM.md",
    "lib/app/theme/collect_colors.dart"
  ]
}

reference_failures = []
%w[Revolut gradient glass CollectGradientBackground].each do |term|
  reference_failures << "DESIGN.md must include #{term} reference contract." unless design.include?(term)
  reference_failures << "docs/design/DESIGN_SYSTEM.md must include #{term} implementation contract." unless design_system.include?(term)
end
reference_failures << "DESIGN.md must define runtime reference inputs." unless design.match?(/Runtime reference inputs/i)
reference_failures << "DESIGN_SYSTEM.md must define Collect-owned runtime branding with Revolut as a quality benchmark." unless design_system.match?(/Revolut references remain a quality and interaction benchmark/i) && design_system.match?(/shipped runtime branding uses Collect-owned assets/i)
reference_failures << "The Revolut-quality alignment plan must define the 100 percent alignment target." unless revolut_alignment_plan.match?(/100 percent Revolut-quality alignment/i)
reference_failures << "The runtime asset intake must define intake paths." unless runtime_asset_intake.match?(/assets\/fonts\/collect/) && runtime_asset_intake.match?(/assets\/brand\/collect_runtime/)
reference_failures << "The Revolut alignment blocker register must state a blocked or code-owned pass decision." unless revolut_blocker_register.match?(/Current decision:\s+\*\*(BLOCKED|CODE-OWNED MOBILE ALIGNMENT PASS)/i)
checks << {
  "id" => "collect_runtime_alignment_contract",
  "status" => status_for(reference_failures),
  "failures" => reference_failures,
  "evidence" => [
    "DESIGN.md",
    "docs/design/DESIGN_SYSTEM.md",
    "docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md",
    "docs/design/COLLECT_RUNTIME_ASSET_INTAKE_2026-06-29.md",
    "docs/design/REVOLUT_ALIGNMENT_BLOCKER_REGISTER_2026-06-27.md"
  ]
}

font_failures = []
font_installed = !collect_font_files.empty? &&
  pubspec.match?(/fonts:\s*\n/m) &&
  pubspec.include?("assets/fonts/collect/")
unless font_installed || blocker_recorded.call("collect_font_files")
  font_failures << "Collect runtime font files are missing and blocker key collect_font_files is not recorded as Blocked."
end
unless font_installed || blocker_recorded.call("collect_font_license_metadata")
  font_failures << "Collect runtime font approval/license metadata is missing and blocker key collect_font_license_metadata is not recorded as Blocked."
end
checks << {
  "id" => "collect_font_installed_or_blocked",
  "status" => status_for(font_failures),
  "failures" => font_failures,
  "installed" => font_installed,
  "font_file_count" => collect_font_files.length,
  "evidence" => [
    "pubspec.yaml",
    "assets/fonts/collect/",
    "docs/design/REVOLUT_ALIGNMENT_BLOCKER_REGISTER_2026-06-27.md"
  ]
}

runtime_asset_failures = []
runtime_asset_installed = !collect_runtime_brand_asset_files.empty?
installed_runtime_inputs = {
  "collect_logo_wordmark_assets" => File.file?(File.join(root, "assets/brand/collect_runtime/logos/wordmark.png")),
  "collect_platform_icon_assets" =>
    File.file?(File.join(root, "assets/brand/collect_runtime/app_icons/app_icon.png")) &&
    File.file?(File.join(root, "assets/brand/collect_runtime/app_icons/collect-web-512.png")),
  "collect_splash_launch_assets" =>
    File.file?(File.join(root, "assets/brand/collect_runtime/splash/splash_mark.png")) &&
    File.file?(File.join(root, "assets/brand/collect_runtime/splash/splash_background.png")),
  "collect_icon_set_mapping" =>
    File.file?(File.join(root, "assets/brand/collect_runtime/icons/icon-mapping.json")),
  "collect_component_tokens" => !runtime_token_spec_files.empty?,
  "collect_route_reference_matrix" =>
    File.file?(File.join(root, "docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md")),
  "collect_public_web_assets" =>
    File.file?(File.join(root, "assets/brand/collect_runtime/media/share-preview.png"))
}
runtime_asset_roots.each do |asset_root|
  runtime_asset_failures << "pubspec.yaml must declare #{asset_root} for Collect runtime intake." unless pubspec.include?("- #{asset_root}")
end
%w[
  collect_logo_wordmark_assets
  collect_platform_icon_assets
  collect_splash_launch_assets
  collect_icon_set_mapping
  collect_component_tokens
  collect_route_reference_matrix
  collect_public_web_assets
].each do |key|
  next if installed_runtime_inputs.fetch(key, false)
  runtime_asset_failures << "Required Collect runtime input #{key} is not installed and is not recorded as Blocked." unless blocker_recorded.call(key)
end
brand_provenance = read(File.join(root, "assets/brand/collect_runtime/PROVENANCE.md"))
runtime_asset_failures << "Runtime brand provenance must state Collect-owned sources." unless brand_provenance.include?("Collect Runtime Brand Kit Provenance") && brand_provenance.include?("Collect-owned")
runtime_asset_failures << "Runtime brand assets must not be sourced from external screenshots." if brand_provenance.include?("/Users/jeanbosco/Downloads/Revolut10")
checks << {
  "id" => "collect_runtime_assets_installed_or_blocked",
  "status" => status_for(runtime_asset_failures),
  "failures" => runtime_asset_failures,
  "installed" => runtime_asset_installed,
  "asset_file_count" => collect_runtime_brand_asset_files.length,
  "evidence" => [
    "assets/brand/collect_runtime/",
    "docs/design/COLLECT_RUNTIME_ASSET_INTAKE_2026-06-29.md",
    "docs/design/REVOLUT_ALIGNMENT_BLOCKER_REGISTER_2026-06-27.md"
  ]
}

switchpoint_failures = []
switchpoint_failures << "CollectRuntimeAssets must expose the stable asset root." unless runtime_assets.include?("collectAssetRoot = 'assets/brand/collect_runtime'")
switchpoint_failures << "CollectRuntimeAssets must expose the logo intake root." unless runtime_assets.include?(%q{logoAssetRoot = '$collectAssetRoot/logos'})
switchpoint_failures << "CollectRuntimeAssets must expose the app-icon intake root." unless runtime_assets.include?(%q{appIconAssetRoot = '$collectAssetRoot/app_icons'})
switchpoint_failures << "CollectRuntimeAssets must expose the splash intake root." unless runtime_assets.include?(%q{splashAssetRoot = '$collectAssetRoot/splash'})
switchpoint_failures << "CollectBrandMark must route wordmark rendering through CollectRuntimeAssets." unless chrome.include?("CollectRuntimeAssets.wordmarkAssetPath")
switchpoint_failures << "CollectBrandMark must route app-icon rendering through CollectRuntimeAssets." unless chrome.include?("CollectRuntimeAssets.appIconAssetPath")
switchpoint_failures << "LaunchSplashScreen must route splash mark rendering through CollectRuntimeAssets." unless read(File.join(root, "lib/features/launch/launch_splash_screen.dart")).include?("CollectRuntimeAssets.splashMarkAssetPath")

runtime_wordmark_path = File.join(root, "assets/brand/collect_runtime/logos/wordmark.png")
runtime_app_icon_path = File.join(root, "assets/brand/collect_runtime/app_icons/app_icon.png")
runtime_splash_mark_path = File.join(root, "assets/brand/collect_runtime/splash/splash_mark.png")
runtime_web_icon_path = File.join(root, "assets/brand/collect_runtime/app_icons/collect-web-512.png")
runtime_share_preview_path = File.join(root, "assets/brand/collect_runtime/media/share-preview.png")
switchpoint_failures << "Collect runtime wordmark is installed but CollectRuntimeAssets.wordmarkAssetPath still uses the fallback." if File.file?(runtime_wordmark_path) && !runtime_assets.match?(/wordmarkAssetPath\s*=\s*expectedWordmarkPath/)
switchpoint_failures << "Collect runtime app icon is installed but CollectRuntimeAssets.appIconAssetPath still uses the fallback." if File.file?(runtime_app_icon_path) && !runtime_assets.match?(/appIconAssetPath\s*=\s*expectedAppIconPath/)
switchpoint_failures << "Collect runtime splash mark is installed but CollectRuntimeAssets.splashMarkAssetPath still uses the fallback." if File.file?(runtime_splash_mark_path) && !runtime_assets.match?(/splashMarkAssetPath\s*=\s*expectedSplashMarkPath/)
if File.file?(runtime_web_icon_path)
  web_manifest = read(File.join(root, "web/manifest.json"))
  web_index = read(File.join(root, "web/index.html"))
  switchpoint_failures << "Collect runtime web icon is installed but web/manifest.json still points to collect-admin.png." if web_manifest.include?("collect-admin.png")
  switchpoint_failures << "Collect runtime web icon is installed but web/index.html still points to collect-admin.png." if web_index.include?("collect-admin.png")
end
if File.file?(runtime_share_preview_path)
  public_assets = read(File.join(root, "scripts/public_website_audit_evidence.sh"))
  switchpoint_failures << "Collect runtime share preview is installed but public website evidence does not check it." unless public_assets.include?("collect_runtime") || public_assets.include?("share-preview.png")
end
checks << {
  "id" => "collect_runtime_asset_switchpoints",
  "status" => status_for(switchpoint_failures),
  "failures" => switchpoint_failures,
  "evidence" => [
    "pubspec.yaml",
    "lib/app/theme/collect_runtime_assets.dart",
    "lib/shared/widgets/collect_chrome.dart",
    "lib/features/launch/launch_splash_screen.dart",
    "web/manifest.json",
    "web/index.html"
  ]
}

token_failures = []
token_failures << "CollectRuntimeTokens must define the full secondary color role map." unless runtime_tokens.include?("secondaryColorRoles")
%w[
  inkPrimary
  inkSecondary
  inkMuted
  surfaceReadable
  surfaceMuted
  borderSoft
  borderAccent
  focusRing
  successForeground
  infoForeground
  warningForeground
  dangerForeground
  successContainer
  infoContainer
  warningContainer
  dangerContainer
  neutralContainer
].each do |role|
  token_failures << "CollectRuntimeTokens.secondaryColorRoles must include #{role}." unless runtime_tokens.include?("'#{role}'")
end
%w[
  #252044
  #4B4664
  #5F5A76
  #FFFDFB
  #F1ECF7
  #DED8EA
  #CDC7F5
  #6F67E8
  #137A3F
  #514DD2
  #B9472E
  #B3261E
  #E7F8ED
  #ECEBFF
  #FFE9E3
  #FFE5DF
].each do |hex|
  token_failures << "CollectRuntimeTokens.secondaryColorHexes must include #{hex}." unless runtime_tokens.include?("'#{hex}'")
end
{
  "lib/app/theme/collect_component_tokens.dart" => component_tokens,
  "lib/shared/widgets/collect_chrome.dart" => chrome,
  "lib/shared/widgets/collect_foundation.dart" => foundation,
  "lib/shared/widgets/collect_inputs.dart" => inputs,
  "lib/shared/widgets/collect_financial_components.dart" => financial_components
}.each do |relative, text|
  token_failures << "#{relative} must use CollectRuntimeTokens." unless text.include?("CollectRuntimeTokens")
end
token_failures << "collect_components.dart must export CollectRuntimeTokens." unless components.include?("collect_runtime_tokens.dart")
checks << {
  "id" => "collect_runtime_component_token_switchpoints",
  "status" => status_for(token_failures),
  "failures" => token_failures,
  "evidence" => [
    "lib/app/theme/collect_runtime_tokens.dart",
    "lib/app/theme/collect_component_tokens.dart",
    "lib/shared/widgets/collect_chrome.dart",
    "lib/shared/widgets/collect_foundation.dart",
    "lib/shared/widgets/collect_inputs.dart",
    "lib/shared/widgets/collect_financial_components.dart",
    "test/features/design_system_components_test.dart"
  ]
}

claim_guard_failures = []
if revolut_blocker_register.match?(/Current decision:\s+\*\*BLOCKED\*\*/i)
  claim_guard_failures << "Blocker register must explicitly prohibit 100 percent alignment claims while rows are blocked." unless revolut_blocker_register.match?(/Do not claim 100 percent (Collect runtime|Revolut-quality) alignment/i)
end
claim_guard_failures << "Alignment plan must require approved runtime fonts before final claim." unless revolut_alignment_plan.match?(/Approved runtime fonts are bundled/i)
claim_guard_failures << "Alignment plan must preserve the four primary colors." unless revolut_alignment_plan.match?(/#8885F0/) && revolut_alignment_plan.match?(/#3CD070/) && revolut_alignment_plan.match?(/#D38B96/) && revolut_alignment_plan.match?(/#FF5E43/)
checks << {
  "id" => "revolut_100_percent_claim_guard",
  "status" => status_for(claim_guard_failures),
  "failures" => claim_guard_failures,
  "evidence" => [
    "docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md",
    "docs/design/REVOLUT_ALIGNMENT_BLOCKER_REGISTER_2026-06-27.md"
  ]
}

gradient_failures = []
%w[screenGradient glassPanel glassPanelStrong glassControl glassBorder glassPanelGradient].each do |token|
  gradient_failures << "CollectColors is missing #{token}." unless colors.include?(token)
end
gradient_failures << "CollectShell must wrap the member app in CollectGradientBackground." unless shell.include?("CollectGradientBackground")
gradient_failures << "PremiumScaffold must render CollectGradientBackground." unless chrome[/class PremiumScaffold.*?CollectGradientBackground/m]
gradient_failures << "Standalone ShareScreen must render CollectGradientBackground." unless share_screen.include?("CollectGradientBackground")
checks << {
  "id" => "gradient_glass_screen_contract",
  "status" => status_for(gradient_failures),
  "failures" => gradient_failures,
  "evidence" => [
    "lib/app/theme/collect_colors.dart",
    "lib/core/widgets/collect_shell.dart",
    "lib/shared/widgets/collect_chrome.dart",
    "lib/features/collections/share_screen.dart"
  ]
}

theme_parity_failures = []
theme_parity_failures << "Theme visual parity test is missing." unless File.file?(theme_parity_path)
[
  "light and dark mode surfaces have strong visual separation",
  "route background families stay stable across light and dark modes",
  "computeLuminance",
  "Brightness.light",
  "Brightness.dark",
  "surfaceReadable",
  "glassPanel",
  "glassControl",
  "borderAccent",
  "screenGradientForPath"
].each do |needle|
  theme_parity_failures << "Theme visual parity test must assert #{needle}." unless theme_parity_test.include?(needle)
end
%w[
  /home
  /groups
  /groups/create
  /groups/col-church/pay/intent/state/pending
  /groups/col-church/share
  /settings/help
  /offline
].each do |route|
  theme_parity_failures << "Theme visual parity test must cover route #{route}." unless theme_parity_test.include?(route)
end
theme_parity_failures << "DESIGN.md must name theme_mode_visual_parity_test.dart as a parity gate." unless design.include?("theme_mode_visual_parity_test.dart")
theme_parity_failures << "DESIGN_SYSTEM.md must name theme_mode_visual_parity_test.dart as a parity gate." unless design_system.include?("theme_mode_visual_parity_test.dart")
theme_parity_failures << "DESIGN.md must require visually distinct light and dark modes." unless design.match?(/Light and dark modes must be visually distinct/i)
theme_parity_failures << "DESIGN_SYSTEM.md must require distinct modes." unless design_system.match?(/Distinct modes/i)
checks << {
  "id" => "theme_mode_visual_parity_gate",
  "status" => status_for(theme_parity_failures),
  "failures" => theme_parity_failures,
  "evidence" => [
    "test/features/theme_mode_visual_parity_test.dart",
    "DESIGN.md",
    "docs/design/DESIGN_SYSTEM.md"
  ]
}

route_evidence_failures = []
route_evidence_failures << "main.dart must declare COLLECT_MOBILE_EVIDENCE_MODE." unless main_entry.include?("COLLECT_MOBILE_EVIDENCE_MODE")
route_evidence_failures << "main.dart must seed CollectRepository.fixture() only behind evidence mode." unless main_entry.include?("CollectRepository.fixture()") && main_entry.include?("if (mobileEvidenceMode)")
route_evidence_failures << "mobile_route_render_smoke.sh must build with COLLECT_MOBILE_EVIDENCE_MODE=true." unless route_smoke_script.include?("--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true")
route_evidence_failures << "DESIGN_SYSTEM.md must document sanitized fixture evidence mode for route screenshots." unless design_system.match?(/sanitized fixture evidence mode/i)
checks << {
  "id" => "route_screenshot_fixture_evidence_gate",
  "status" => status_for(route_evidence_failures),
  "failures" => route_evidence_failures,
  "evidence" => [
    "lib/main.dart",
    "scripts/mobile_route_render_smoke.sh",
    "docs/design/DESIGN_SYSTEM.md"
  ]
}

top_chrome_failures = []
top_chrome_failures << "Home top chrome must keep the Revolut-style search slot visible." unless home_screen.include?("searchLabel: 'Search'") && home_screen.include?("onSearchTap: () => context.go('/groups/search')")
top_chrome_failures << "Home top chrome must expose two compact action circles." unless home_screen.include?("tooltip: 'Notifications'") && home_screen.include?("tooltip: 'Scan QR code'")
top_chrome_failures << "Groups top chrome must bind the search controller." unless collections_screen.scan("searchController: _search").length >= 2
top_chrome_failures << "Groups top chrome must update the visible search query." unless collections_screen.scan("onSearchChanged: (value) => setState(() => _query = value)").length >= 2
top_chrome_failures << "Groups top chrome must not suppress search." if collections_screen.include?("showSearch: false")
checks << {
  "id" => "revolut_top_chrome_search_contract",
  "status" => status_for(top_chrome_failures),
  "failures" => top_chrome_failures,
  "evidence" => [
    "lib/features/home/home_screen.dart",
    "lib/features/collections/collections_screen.dart"
  ]
}

asset_failures = []
wordmark_path = File.join(root, "assets/brand/collect_runtime/logos/wordmark.png")
app_icon_path = File.join(root, "assets/brand/collect_runtime/app_icons/app_icon.png")
splash_mark_path = File.join(root, "assets/brand/collect_runtime/splash/splash_mark.png")
asset_failures << "Collect runtime wordmark asset is missing." unless File.file?(wordmark_path)
asset_failures << "Collect runtime app icon asset is missing." unless File.file?(app_icon_path)
asset_failures << "Collect runtime splash mark asset is missing." unless File.file?(splash_mark_path)
asset_failures << "CollectBrandMark must use the stable runtime asset registry." unless chrome.include?("CollectRuntimeAssets.wordmarkAssetPath")
asset_failures << "Runtime asset registry must use expectedWordmarkPath once the kit is installed." unless runtime_assets.match?(/wordmarkAssetPath\s*=\s*expectedWordmarkPath/)
asset_failures << "Runtime asset registry must use expectedAppIconPath once the kit is installed." unless runtime_assets.match?(/appIconAssetPath\s*=\s*expectedAppIconPath/)
asset_failures << "Runtime asset registry must use expectedSplashMarkPath once the kit is installed." unless runtime_assets.match?(/splashMarkAssetPath\s*=\s*expectedSplashMarkPath/)
asset_failures << "DESIGN_SYSTEM.md must name the runtime wordmark intake target." unless design_system.include?("assets/brand/collect_runtime/logos/wordmark.png")
checks << {
  "id" => "mobile_brand_asset_contract",
  "status" => status_for(asset_failures),
  "failures" => asset_failures,
  "evidence" => [
    "assets/brand/collect_runtime/logos/wordmark.png",
    "assets/brand/collect_runtime/app_icons/app_icon.png",
    "assets/brand/collect_runtime/splash/splash_mark.png",
    "lib/shared/widgets/collect_chrome.dart",
    "docs/design/DESIGN_SYSTEM.md"
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
).reject do |hit|
  hit.fetch("text").include?('<style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">')
end
checks << {
  "id" => "platform_metadata_colors_match_contract",
  "status" => platform_color_hits.empty? && legacy_platform_hits.empty? ? "pass" : "fail",
  "hits" => platform_color_hits + legacy_platform_hits,
  "evidence" => platform_color_files
}

native_launch_failures = []
manifest = read(File.join(root, "android/app/src/main/AndroidManifest.xml"))
native_launch_failures << "Android MainActivity must use @style/LaunchTheme." unless manifest.include?('android:theme="@style/LaunchTheme"')
native_launch_failures << "Android MainActivity must declare NormalTheme metadata." unless manifest.include?('android:name="io.flutter.embedding.android.NormalTheme"') && manifest.include?('android:resource="@style/NormalTheme"')

%w[
  android/app/src/main/res/values/styles.xml
  android/app/src/main/res/values-night/styles.xml
].each do |relative|
  text = read(File.join(root, relative))
  native_launch_failures << "#{relative} must use @drawable/launch_background for LaunchTheme." unless text.include?("<item name=\"android:windowBackground\">@drawable/launch_background</item>")
  native_launch_failures << "#{relative} must disable forceDark for launch." unless text.include?("<item name=\"android:forceDarkAllowed\">false</item>")
end

%w[
  android/app/src/main/res/values-v31/styles.xml
  android/app/src/main/res/values-night-v31/styles.xml
].each do |relative|
  text = read(File.join(root, relative))
  native_launch_failures << "#{relative} must use @color/collect_launch_background as Android 12+ splash background." unless text.include?("<item name=\"android:windowSplashScreenBackground\">@color/collect_launch_background</item>")
  native_launch_failures << "#{relative} must use the Collect launcher icon as Android 12+ splash icon." unless text.include?("<item name=\"android:windowSplashScreenAnimatedIcon\">@drawable/collect_launcher_icon</item>")
end

%w[
  android/app/src/main/res/drawable/launch_background.xml
  android/app/src/main/res/drawable-v21/launch_background.xml
  android/app/src/main/res/drawable-night/launch_background.xml
  android/app/src/main/res/drawable-night-v21/launch_background.xml
].each do |relative|
  text = read(File.join(root, relative))
  native_launch_failures << "#{relative} must use collect_launch_background launch foundation." unless text.include?('@color/collect_launch_background')
  native_launch_failures << "#{relative} must not flash the paper launch foundation." if text.include?('@color/collect_paper')
  native_launch_failures << "#{relative} must center the Collect splash logo." unless text.include?('@drawable/collect_splash_logo')
end

expected_splash_sizes = {
  "android/app/src/main/res/drawable/collect_splash_logo.png" => [280, 82],
  "android/app/src/main/res/drawable-mdpi/collect_splash_logo.png" => [280, 82],
  "android/app/src/main/res/drawable-hdpi/collect_splash_logo.png" => [420, 123],
  "android/app/src/main/res/drawable-xhdpi/collect_splash_logo.png" => [560, 163],
  "android/app/src/main/res/drawable-xxhdpi/collect_splash_logo.png" => [840, 245],
  "android/app/src/main/res/drawable-xxxhdpi/collect_splash_logo.png" => [1120, 327],
  "android/app/src/main/res/drawable-night/collect_splash_logo.png" => [280, 82],
  "android/app/src/main/res/drawable-night-mdpi/collect_splash_logo.png" => [280, 82],
  "android/app/src/main/res/drawable-night-hdpi/collect_splash_logo.png" => [420, 123],
  "android/app/src/main/res/drawable-night-xhdpi/collect_splash_logo.png" => [560, 163],
  "android/app/src/main/res/drawable-night-xxhdpi/collect_splash_logo.png" => [840, 245],
  "android/app/src/main/res/drawable-night-xxxhdpi/collect_splash_logo.png" => [1120, 327],
  "android/app/src/main/res/drawable/collect_launcher_icon.png" => [512, 512]
}
expected_splash_sizes.each do |relative, expected|
  size = png_size(File.join(root, relative))
  native_launch_failures << "#{relative} must be a #{expected[0]}x#{expected[1]} PNG." unless size && [size["width"], size["height"]] == expected
end

checks << {
  "id" => "native_android_launch_splash_contract",
  "status" => status_for(native_launch_failures),
  "failures" => native_launch_failures,
  "evidence" => [
    "android/app/src/main/AndroidManifest.xml",
    "android/app/src/main/res/values/styles.xml",
    "android/app/src/main/res/values-v31/styles.xml",
    "android/app/src/main/res/values-night/styles.xml",
    "android/app/src/main/res/values-night-v31/styles.xml",
    "android/app/src/main/res/drawable*/launch_background.xml",
    "android/app/src/main/res/drawable*/collect_splash_logo.png",
    "android/app/src/main/res/drawable/collect_launcher_icon.png"
  ]
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
    capture_path = capture.fetch("path", "")
    png_path = if capture_path.start_with?(".cache/", "/", "build/", "docs/")
      File.join(root, capture_path)
    else
      File.join(File.dirname(route_summary_path), capture_path)
    end
    width = capture.fetch("width", nil).to_i
    height = capture.fetch("height", nil).to_i
    if (width <= 0 || height <= 0) && File.file?(png_path)
      size = png_size(png_path)
      width = size&.fetch("width", 0).to_i
      height = size&.fetch("height", 0).to_i
    end
    capture_status = capture.fetch("status", nil)
    physical_device_capture = capture.key?("bytes") && !capture.key?("non_background_pixels")
    failures = []
    failures << "missing_png" unless File.file?(png_path)
    failures << "capture_status_#{capture_status}" if capture_status && capture_status != "pass"
    if physical_device_capture
      failures << "too_small_file" if capture.fetch("bytes", 0).to_i < 8000
      failures << "invalid_physical_viewport" if width < 320 || height < 640
    else
      failures << "too_few_pixels" if capture.fetch("non_background_pixels", 0).to_i < 100
      failures << "too_few_colors" if capture.fetch("distinct_rgb", 0).to_i < 16
      failures << "wrong_viewport" unless width == 390 && height == 844
    end
    capture_checks << {
      "name" => capture["name"],
      "route" => capture["route"],
      "status" => failures.empty? ? "pass" : "fail",
      "failures" => failures,
      "path" => rel(root, png_path),
      "width" => width,
      "height" => height
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
  "reference_contract" => "Revolut screenshots are the quality benchmark; shipped runtime branding uses documented Collect-owned assets unless a separately approved replacement kit is supplied.",
  "primary_colors" => expected_primary_hexes,
  "route_count" => materialized_routes.length,
  "checks" => checks,
  "secret_handling" => "The audit inspects local source paths and generated screenshot metadata only; it does not print secrets, raw SMS, OTPs, PINs, or private receiver data.",
  "external_approval_scope" => "This audit owns code/design evidence. Store release, public parity claims, and third-party approval workflows remain separate governance actions."
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
report << "\n## External Approval Scope\n\n"
report << "#{summary.fetch("external_approval_scope")}\n"
File.write(File.join(evidence_dir, "report.md"), report)

if output_format == "json"
  puts JSON.pretty_generate(summary)
else
  puts "[collect-mobile-design-audit] status=#{summary.fetch("status")} evidence=#{evidence_dir}"
  checks.each { |check| puts "[collect-mobile-design-audit] #{check.fetch("id")}=#{check.fetch("status")}" }
end

exit(summary.fetch("status") == "pass" ? 0 : 1)
RUBY
