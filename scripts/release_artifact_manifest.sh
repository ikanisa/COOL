#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${RELEASE_ARTIFACT_ROOT:-$ROOT_DIR}"
MANIFEST_PATH="${RELEASE_ARTIFACT_MANIFEST_PATH:-$ROOT_DIR/output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_$(date -u +%Y-%m-%d).sha256}"

output_format="text"
if [[ "${1:-}" == "--json" ]]; then
  output_format="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

ARTIFACT_ROOT="$ARTIFACT_ROOT" MANIFEST_PATH="$MANIFEST_PATH" OUTPUT_FORMAT="$output_format" ruby -r digest -r fileutils -r json -r time <<'RUBY'
artifact_root = File.expand_path(ENV.fetch("ARTIFACT_ROOT"))
manifest_path = File.expand_path(ENV.fetch("MANIFEST_PATH"))
output_format = ENV.fetch("OUTPUT_FORMAT")

required_artifacts = [
  "build/app/outputs/flutter-apk/app-production-release.apk",
  "build/app/outputs/bundle/productionRelease/app-production-release.aab",
  "build/web/index.html",
  "build/web/flutter_bootstrap.js",
  "build/web/main.dart.js",
  "build/web/manifest.json",
  "build/web/custom-sw.js",
  "build/web/_headers",
  "build/web/robots.txt"
]

source_patterns = {
  "android" => [
    "lib/**/*.dart",
    "android/app/src/**/*",
    "android/app/build.gradle.kts",
    "android/build.gradle.kts",
    "android/gradle.properties",
    "android/settings.gradle.kts",
    "pubspec.yaml",
    "pubspec.lock"
  ],
  "admin_web" => [
    "lib/**/*.dart",
    "web/**/*",
    "pubspec.yaml",
    "pubspec.lock"
  ]
}

def artifact_group(relative_path)
  return "android" if relative_path.start_with?("build/app/")
  return "admin_web" if relative_path.start_with?("build/web/")
  "unknown"
end

def latest_source_mtime(root, patterns)
  paths = patterns.flat_map { |pattern| Dir.glob(File.join(root, pattern), File::FNM_DOTMATCH) }
    .select { |path| File.file?(path) }
    .reject { |path| path.include?("/build/") || path.include?("/.dart_tool/") || path.include?("/.gradle/") }
    .reject { |path| File.basename(path) == "GeneratedPluginRegistrant.java" }
  paths.map { |path| File.mtime(path) }.max
end

source_latest_mtimes = source_patterns.transform_values do |patterns|
  latest_source_mtime(artifact_root, patterns)
end

artifacts = required_artifacts.map do |relative_path|
  absolute_path = File.expand_path(relative_path, artifact_root)
  present = absolute_path.start_with?(artifact_root + File::SEPARATOR) && File.file?(absolute_path)
  group = artifact_group(relative_path)
  source_latest_mtime = source_latest_mtimes[group]
  artifact = {
    "path" => relative_path,
    "group" => group,
    "present" => present,
    "source_latest_mtime" => source_latest_mtime&.utc&.iso8601
  }
  if present
    artifact["bytes"] = File.size(absolute_path)
    artifact["sha256"] = Digest::SHA256.file(absolute_path).hexdigest
    artifact["mtime"] = File.mtime(absolute_path).utc.iso8601
    artifact["fresh"] = source_latest_mtime.nil? || File.mtime(absolute_path) >= source_latest_mtime
  end
  artifact
end

missing = artifacts.reject { |artifact| artifact.fetch("present") }.map { |artifact| artifact.fetch("path") }
stale = artifacts.select { |artifact| artifact.fetch("present") && artifact["fresh"] == false }.map { |artifact| artifact.fetch("path") }
failures = []

if missing.empty? && stale.empty?
  manifest_dir = File.dirname(manifest_path)
  begin
    FileUtils.mkdir_p(manifest_dir)
    lines = artifacts.map { |artifact| "#{artifact.fetch("sha256")}  #{artifact.fetch("path")}" }
    File.write(manifest_path, lines.join("\n") + "\n")
  rescue SystemCallError => e
    failures << "failed to write checksum manifest: #{e.class}: #{e.message}"
  end
end

status =
  if failures.any?
    "fail"
  elsif missing.any? || stale.any?
    "blocked"
  else
    "pass"
  end

summary = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "artifact_root" => artifact_root,
  "manifest_path" => manifest_path,
  "manifest_written" => status == "pass",
  "artifact_count" => artifacts.count,
  "missing_artifacts" => missing,
  "stale_artifacts" => stale,
  "source_latest_mtimes" => source_latest_mtimes.transform_values { |mtime| mtime&.utc&.iso8601 },
  "failures" => failures,
  "artifacts" => artifacts
}

if output_format == "json"
  puts JSON.pretty_generate(summary)
else
  puts "[release-artifact-manifest] status=#{status}"
  puts "[release-artifact-manifest] manifest=#{manifest_path}"
  artifacts.each do |artifact|
    marker = artifact.fetch("present") ? artifact.fetch("sha256") : "MISSING"
    puts "[release-artifact-manifest] #{marker}  #{artifact.fetch("path")}"
  end
  failures.each { |failure| warn "[release-artifact-manifest][FAIL] #{failure}" }
  missing.each { |path| warn "[release-artifact-manifest][BLOCKED] missing #{path}" }
  stale.each { |path| warn "[release-artifact-manifest][BLOCKED] stale #{path}" }
end

exit(status == "pass" ? 0 : (status == "blocked" ? 99 : 1))
RUBY
