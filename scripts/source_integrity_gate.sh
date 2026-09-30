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

ROOT_DIR="$ROOT_DIR" OUTPUT_FORMAT="$output_format" ruby -E UTF-8:UTF-8 -r json -r open3 -r time <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")
require File.join(root_dir, "scripts/qa/asset_manifest_integrity")

def source_files(root_dir, roots)
  stdout, _stderr, status = Open3.capture3(
    "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
    "--", *roots, chdir: root_dir
  )
  raise AssetManifestIntegrity::IncompleteInventory, "git_inventory_failed" unless status.success?

  # The working tree may intentionally remove indexed files before the next
  # commit. The manifest checks the current artifact set, as the prior gate did.
  stdout.split("\0").reject(&:empty?).uniq.sort.select do |relative|
    absolute = File.join(root_dir, relative)
    File.file?(absolute) || File.symlink?(absolute)
  end
end

def public_asset_hash(root_dir, relative)
  AssetManifestIntegrity.sha256(root_dir, relative)
rescue AssetManifestIntegrity::InvalidPath
  nil
end

checks = {}
failures = []

# This manifest proves that product artwork bytes match the reviewed inventory.
# The file formats and visual decisions remain outside this gate.
begin
  visual_check = AssetManifestIntegrity.verify(
    root: root_dir,
    observed_paths: source_files(root_dir, AssetManifestIntegrity::ASSET_ROOTS)
  )
rescue AssetManifestIntegrity::IncompleteInventory => e
  visual_check = { "status" => "fail", "reason" => e.message }
end
checks["approved_product_visual_assets"] = visual_check
unless visual_check.fetch("status") == "pass"
  failures << {
    "check" => "approved_product_visual_assets",
    "paths" => (Array(visual_check["missing"]) + Array(visual_check["unexpected"])).uniq,
    "hash_mismatches" => Array(visual_check["hash_mismatches"]),
    "manifest_errors" => Array(visual_check["manifest_errors"]),
    "reason" => visual_check["reason"]
  }.compact
end

canonical_logo = "assets/brand/collect_runtime/app_icons/app-icon-rule.png"
android_logo = "android/app/src/main/res/drawable/collect_launcher_icon.png"
expected_logo_sha256 =
  "c6942d8bac7e860df1993e977277a47121340666b3f44a4f7cff63e079614209"
canonical_logo_sha256 = public_asset_hash(root_dir, canonical_logo)
android_logo_sha256 = public_asset_hash(root_dir, android_logo)
official_logo_pass =
  canonical_logo_sha256 == expected_logo_sha256 &&
  android_logo_sha256 == expected_logo_sha256
checks["official_logo_identity"] = {
  "status" => official_logo_pass ? "pass" : "fail",
  "canonical_path" => canonical_logo,
  "android_path" => android_logo,
  "expected_sha256" => expected_logo_sha256,
  "canonical_sha256" => canonical_logo_sha256,
  "android_sha256" => android_logo_sha256
}
failures << { "check" => "official_logo_identity", "paths" => [canonical_logo, android_logo] } unless official_logo_pass

# Fixture data must stay out of normal runtime paths. Evidence mode is an
# explicit fixture-only branch so CI can detect accidental production imports.
fixture_hits = []
begin
  source_files(root_dir, ["lib"]).grep(/\.dart\z/).each do |relative_path|
    text = AssetManifestIntegrity.read_regular(root_dir, relative_path) { |io| io.read }
    imports_fixture_data = text.include?("FixtureCollectRepository") ||
      text.include?("test/fixtures/") || text.include?("_fixtureCollectState")
    invokes_fixture = text.include?("CollectRepository.fixture") &&
      relative_path != "lib/shared/repositories/collect_repository.dart"
    next unless imports_fixture_data || invokes_fixture

    fixture_hits << { "check" => "fixture_runtime_leak", "path" => relative_path }
  rescue AssetManifestIntegrity::InvalidPath => e
    fixture_hits << { "check" => "unreadable_runtime_source", "path" => relative_path, "reason" => e.message }
  end
rescue AssetManifestIntegrity::IncompleteInventory => e
  fixture_hits << { "check" => "fixture_inventory_failed", "reason" => e.message }
end
begin
  main_source = AssetManifestIntegrity.read_regular(root_dir, "lib/main.dart") { |io| io.read }
  fixture_flag_pass =
    main_source.include?("'COLLECT_MOBILE_EVIDENCE_MODE'") &&
    main_source.include?("if (mobileEvidenceMode)")
rescue AssetManifestIntegrity::InvalidPath
  fixture_flag_pass = false
end
unless fixture_flag_pass
  fixture_hits << { "check" => "fixture_flag_missing", "path" => "lib/main.dart" }
end
checks["fixture_isolation"] = {
  "status" => fixture_hits.empty? ? "pass" : "fail",
  "hits" => fixture_hits
}
failures.concat(fixture_hits)

_secret_stdout, _secret_stderr, secret_status = Open3.capture3(
  "/bin/bash", "scripts/release_secret_scan.sh", chdir: root_dir
)
checks["secret_scan"] = {
  "status" => secret_status.success? ? "pass" : "fail",
  "scanner" => "gitleaks when installed, redacted tracked/untracked fallback otherwise"
}
failures << { "check" => "secret_scan" } unless secret_status.success?

boundary_stdout, _boundary_stderr, boundary_status = Open3.capture3(
  "/bin/bash", "scripts/collect_product_boundary_scan.sh", "--json", chdir: root_dir
)
boundary = begin
  JSON.parse(boundary_stdout)
rescue JSON::ParserError
  {}
end
boundary_pass = boundary_status.success? &&
  boundary["status"] == "pass" && boundary["hit_count"] == 0
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
  "scope" => "asset and runtime source integrity; no visual design acceptance",
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
  puts "[source-integrity] status=#{status} failures=#{failures.length}"
  checks.each do |name, check|
    puts "[source-integrity] #{name}=#{check.fetch("status")}"
  end
end

exit(status == "pass" ? 0 : 1)
RUBY
