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

ROOT_DIR="$ROOT_DIR" OUTPUT_FORMAT="$output_format" ruby -r digest -r json -r open3 -r time <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")

def relative(root_dir, path)
  path.delete_prefix("#{root_dir}/")
end

def tracked_and_untracked_files(root_dir, roots)
  stdout, _stderr, status = Open3.capture3(
    "git",
    "ls-files",
    "-z",
    "--cached",
    "--others",
    "--exclude-standard",
    "--",
    *roots,
    chdir: root_dir
  )
  raise "git file inventory failed" unless status.success?

  stdout.split("\0").reject(&:empty?).select do |path|
    File.file?(File.join(root_dir, path))
  end.sort
end

def text_file?(path)
  %w[
    .dart .gradle .html .js .json .kts .m .md .mm .plist .rb .sh .swift
    .toml .ts .txt .xcconfig .xml .yaml .yml
  ].include?(File.extname(path).downcase) ||
    %w[Podfile pubspec.lock pubspec.yaml].include?(File.basename(path))
end

def file_sha256(path)
  return nil unless File.file?(path)

  Digest::SHA256.file(path).hexdigest
end

failures = []
checks = {}

expected_typefaces = %w[Inter-Variable.ttf OFL-Inter.txt].sort
typeface_files = Dir[File.join(root_dir, "assets/typefaces/*")]
  .select { |path| File.file?(path) }
  .map { |path| File.basename(path) }
  .sort
checks["exclusive_inter_typefaces"] = {
  "status" => typeface_files == expected_typefaces ? "pass" : "fail",
  "expected" => expected_typefaces,
  "observed" => typeface_files
}
unless typeface_files == expected_typefaces
  failures << {
    "check" => "exclusive_inter_typefaces",
    "paths" => typeface_files
  }
end

asset_roots = %w[
  assets
  android/app/src/main/res
  ios/Runner/Assets.xcassets
  web
]
repository_files = tracked_and_untracked_files(root_dir, ["."])
asset_files = tracked_and_untracked_files(root_dir, asset_roots)
prohibited_asset_extensions = %w[.svg .svgz .ico]
prohibited_assets = repository_files.select do |path|
  prohibited_asset_extensions.include?(File.extname(path).downcase)
end
checks["no_prohibited_product_artwork"] = {
  "status" => prohibited_assets.empty? ? "pass" : "fail",
  "scope" => "tracked and non-ignored untracked repository files",
  "prohibited_extensions" => prohibited_asset_extensions,
  "paths" => prohibited_assets
}
unless prohibited_assets.empty?
  failures << {
    "check" => "no_prohibited_product_artwork",
    "paths" => prohibited_assets
  }
end

approved_visual_manifest =
  "assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256"
approved_visual_manifest_path = File.join(root_dir, approved_visual_manifest)
approved_visual_hashes = {}
visual_manifest_errors = []
if File.file?(approved_visual_manifest_path)
  File.readlines(approved_visual_manifest_path, chomp: true).each_with_index do |line, index|
    next if line.empty?

    match = line.match(/\A([0-9a-f]{64})  (.+)\z/)
    unless match
      visual_manifest_errors << {
        "line" => index + 1,
        "reason" => "invalid SHA-256 manifest entry"
      }
      next
    end
    path = match[2]
    if approved_visual_hashes.key?(path)
      visual_manifest_errors << {
        "line" => index + 1,
        "reason" => "duplicate visual asset path",
        "path" => path
      }
      next
    end
    approved_visual_hashes[path] = match[1]
  end
else
  visual_manifest_errors << {
    "reason" => "approved visual asset manifest is missing",
    "path" => approved_visual_manifest
  }
end

visual_asset_extensions = %w[.png .jpg .jpeg .webp .svg .svgz .ico]
observed_visual_assets = asset_files.select do |path|
  visual_asset_extensions.include?(File.extname(path).downcase)
end.sort
approved_visual_assets = approved_visual_hashes.keys.sort
missing_visual_assets = approved_visual_assets - observed_visual_assets
unexpected_visual_assets = observed_visual_assets - approved_visual_assets
hash_mismatches = approved_visual_hashes.each_with_object([]) do |entry, mismatches|
  path, expected_sha256 = entry
  actual_sha256 = file_sha256(File.join(root_dir, path))
  next if actual_sha256 == expected_sha256

  mismatches << {
    "path" => path,
    "expected_sha256" => expected_sha256,
    "actual_sha256" => actual_sha256
  }
end
approved_visual_assets_pass =
  visual_manifest_errors.empty? &&
  missing_visual_assets.empty? &&
  unexpected_visual_assets.empty? &&
  hash_mismatches.empty?
checks["approved_product_visual_assets"] = {
  "status" => approved_visual_assets_pass ? "pass" : "fail",
  "manifest" => approved_visual_manifest,
  "approved_count" => approved_visual_assets.length,
  "observed_count" => observed_visual_assets.length,
  "missing" => missing_visual_assets,
  "unexpected" => unexpected_visual_assets,
  "hash_mismatches" => hash_mismatches,
  "manifest_errors" => visual_manifest_errors
}
unless approved_visual_assets_pass
  failures << {
    "check" => "approved_product_visual_assets",
    "paths" => (missing_visual_assets + unexpected_visual_assets).uniq,
    "hash_mismatches" => hash_mismatches,
    "manifest_errors" => visual_manifest_errors
  }
end

canonical_logo = File.join(
  root_dir,
  "assets/brand/collect_runtime/app_icons/app-icon-rule.png"
)
android_logo = File.join(
  root_dir,
  "android/app/src/main/res/drawable/collect_launcher_icon.png"
)
expected_logo_sha256 =
  "c6942d8bac7e860df1993e977277a47121340666b3f44a4f7cff63e079614209"
canonical_logo_sha256 = file_sha256(canonical_logo)
android_logo_sha256 = file_sha256(android_logo)
official_logo_pass =
  canonical_logo_sha256 == expected_logo_sha256 &&
  android_logo_sha256 == expected_logo_sha256
checks["official_logo_identity"] = {
  "status" => official_logo_pass ? "pass" : "fail",
  "canonical_path" => relative(root_dir, canonical_logo),
  "android_path" => relative(root_dir, android_logo),
  "expected_sha256" => expected_logo_sha256,
  "canonical_sha256" => canonical_logo_sha256,
  "android_sha256" => android_logo_sha256
}
unless official_logo_pass
  failures << {
    "check" => "official_logo_identity",
    "paths" => [
      relative(root_dir, canonical_logo),
      relative(root_dir, android_logo)
    ]
  }
end

runtime_roots = %w[
  lib
  android/app/src/main
  ios/Runner
  web
  pubspec.yaml
  pubspec.lock
  scripts/public_static_site_build.rb
]
runtime_files = tracked_and_untracked_files(root_dir, runtime_roots)
runtime_text_files = runtime_files.select { |path| text_file?(path) }
forbidden_runtime_patterns = {
  "legacy_font_family" => /aeonik|roboto|jetbrains\s*mono/i,
  "legacy_icon_or_svg_package" => /cupertino_icons|flutter_svg/i,
  "inline_or_widget_svg" => /<svg|data:image\/svg|SvgPicture/,
  "legacy_avatar_logo" =>
    /collect_top_chrome_avatar_initial|Text\(\s*["']C["']\s*[,)]/
}
runtime_hits = []
runtime_text_files.each do |path|
  text = File.read(File.join(root_dir, path))
  forbidden_runtime_patterns.each do |check, pattern|
    next unless text.match?(pattern)

    runtime_hits << {
      "check" => check,
      "path" => path
    }
  end
end
checks["no_legacy_runtime_typography_or_artwork"] = {
  "status" => runtime_hits.empty? ? "pass" : "fail",
  "scanned_files" => runtime_text_files.length,
  "hits" => runtime_hits
}
failures.concat(runtime_hits) unless runtime_hits.empty?

typography_scope = tracked_and_untracked_files(
  root_dir,
  %w[lib/features lib/shared lib/admin]
).select { |path| path.end_with?(".dart") }
raw_typography_hits = []
typography_scope.each do |path|
  text = File.read(File.join(root_dir, path))
  if text.match?(/\b(?:TextStyle|DefaultTextStyle)\s*\(/)
    raw_typography_hits << {
      "check" => "raw_feature_typography",
      "path" => path
    }
  end
  if text.match?(/FontWeight\.w(?:800|900)/)
    raw_typography_hits << {
      "check" => "unsupported_heavy_weight",
      "path" => path
    }
  end
end
checks["centralized_feature_typography"] = {
  "status" => raw_typography_hits.empty? ? "pass" : "fail",
  "scanned_files" => typography_scope.length,
  "hits" => raw_typography_hits
}
failures.concat(raw_typography_hits) unless raw_typography_hits.empty?

font_declaration_hits = []
runtime_text_files.each do |path|
  text = File.read(File.join(root_dir, path))
  next unless text.match?(/fontFamily\s*:|font-family\s*:/)

  allowed =
    %w[
      lib/app/theme/collect_theme.dart
      lib/app/theme/collect_typography.dart
    ].include?(path) ||
    (
      %w[web/index.html scripts/public_static_site_build.rb].include?(path) &&
      text.scan(/font-family\s*:\s*([^;\n]+)/).all? do |declaration|
        declaration.first.match?(/\bInter\b/)
      end
    )
  next if allowed

  font_declaration_hits << {
    "check" => "uncontrolled_font_declaration",
    "path" => path
  }
end
checks["controlled_font_declarations"] = {
  "status" => font_declaration_hits.empty? ? "pass" : "fail",
  "hits" => font_declaration_hits
}
failures.concat(font_declaration_hits) unless font_declaration_hits.empty?

pubspec = File.read(File.join(root_dir, "pubspec.yaml"))
runtime_typography = File.read(
  File.join(root_dir, "lib/app/theme/collect_runtime_typography.dart")
)
theme = File.read(File.join(root_dir, "lib/app/theme/collect_theme.dart"))
inter_wiring_pass =
  pubspec.include?("family: Inter") &&
  pubspec.include?("asset: assets/typefaces/Inter-Variable.ttf") &&
  runtime_typography.include?("fontFamily = 'Inter'") &&
  theme.include?("fontFamily: CollectTypography.fontFamily")
checks["inter_runtime_wiring"] = {
  "status" => inter_wiring_pass ? "pass" : "fail"
}
failures << { "check" => "inter_runtime_wiring" } unless inter_wiring_pass

fixture_hits = []
Dir[File.join(root_dir, "lib/**/*.dart")].sort.each do |absolute_path|
  relative_path = relative(root_dir, absolute_path)
  text = File.read(absolute_path)
  next unless text.include?("CollectRepository.fixture")
  next if %w[
    lib/main.dart
    lib/shared/repositories/collect_repository.dart
  ].include?(relative_path)

  fixture_hits << {
    "check" => "fixture_runtime_leak",
    "path" => relative_path
  }
end
main_source = File.read(File.join(root_dir, "lib/main.dart"))
fixture_flag_pass =
  main_source.include?("'COLLECT_MOBILE_EVIDENCE_MODE'") &&
  main_source.include?("if (mobileEvidenceMode)")
unless fixture_flag_pass
  fixture_hits << {
    "check" => "fixture_flag_missing",
    "path" => "lib/main.dart"
  }
end
checks["fixture_isolation"] = {
  "status" => fixture_hits.empty? ? "pass" : "fail",
  "hits" => fixture_hits
}
failures.concat(fixture_hits) unless fixture_hits.empty?

_secret_stdout, _secret_stderr, secret_status = Open3.capture3(
  "/bin/bash",
  "scripts/release_secret_scan.sh",
  chdir: root_dir
)
checks["secret_scan"] = {
  "status" => secret_status.success? ? "pass" : "fail",
  "scanner" => "gitleaks when installed, redacted tracked/untracked fallback otherwise"
}
failures << { "check" => "secret_scan" } unless secret_status.success?

boundary_stdout, _boundary_stderr, boundary_status = Open3.capture3(
  "/bin/bash",
  "scripts/collect_product_boundary_scan.sh",
  "--json",
  chdir: root_dir
)
boundary =
  begin
    JSON.parse(boundary_stdout)
  rescue JSON::ParserError
    {}
  end
boundary_pass =
  boundary_status.success? &&
  boundary["status"] == "pass" &&
  boundary["hit_count"] == 0
checks["product_boundary"] = {
  "status" => boundary_pass ? "pass" : "fail",
  "scanned_files" => boundary["scanned_files"],
  "hit_count" => boundary["hit_count"]
}
failures << { "check" => "product_boundary" } unless boundary_pass

status = failures.empty? ? "pass" : "fail"
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "checks" => checks,
  "failure_count" => failures.length,
  "failures" => failures,
  "secret_handling" =>
    "This gate reports checks, paths, counts, and public asset hashes only. " \
    "Secret values, credentials, raw SMS, OTPs, phone/MoMo numbers, provider " \
    "tokens, and production customer data are never printed."
}

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[revolut-parity-source-hygiene] status=#{status} failures=#{failures.length}"
  checks.each do |name, check|
    puts "[revolut-parity-source-hygiene] #{name}=#{check.fetch("status")}"
  end
end

exit(status == "pass" ? 0 : 1)
RUBY
