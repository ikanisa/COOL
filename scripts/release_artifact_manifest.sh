#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${RELEASE_ARTIFACT_ROOT:-$ROOT_DIR}"

output_format="text"
include_all_platforms="false"
for arg in "$@"; do
  case "$arg" in
    --json)
      output_format="json"
      ;;
    --all-platforms)
      include_all_platforms="true"
      ;;
    *)
      printf 'usage: %s [--json] [--all-platforms]\n' "$0" >&2
      exit 2
      ;;
  esac
done

if [[ -n "${RELEASE_ARTIFACT_MANIFEST_PATH:-}" ]]; then
  MANIFEST_PATH="$RELEASE_ARTIFACT_MANIFEST_PATH"
elif [[ "$include_all_platforms" == "true" ]]; then
  MANIFEST_PATH="$ROOT_DIR/output/release_artifacts/CROSS_PLATFORM_BUILD_ARTIFACT_CHECKSUMS_$(date -u +%Y-%m-%d).sha256"
else
  MANIFEST_PATH="$ROOT_DIR/output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_$(date -u +%Y-%m-%d).sha256"
fi

ARTIFACT_ROOT="$ARTIFACT_ROOT" \
MANIFEST_PATH="$MANIFEST_PATH" \
OUTPUT_FORMAT="$output_format" \
INCLUDE_ALL_PLATFORMS="$include_all_platforms" \
IOS_RELEASE_ARCHIVE_PATH="${IOS_RELEASE_ARCHIVE_PATH:-}" \
COLLECT_ANDROID_RELEASE_APK_PATH="${COLLECT_ANDROID_RELEASE_APK_PATH:-build/app/outputs/flutter-apk/app-production-release.apk}" \
COLLECT_ANDROID_RELEASE_AAB_PATH="${COLLECT_ANDROID_RELEASE_AAB_PATH:-build/app/outputs/bundle/productionRelease/app-production-release.aab}" \
ruby -r digest -r fileutils -r json -r open3 -r pathname -r time <<'RUBY'
artifact_root = File.expand_path(ENV.fetch("ARTIFACT_ROOT"))
manifest_path = File.expand_path(ENV.fetch("MANIFEST_PATH"))
output_format = ENV.fetch("OUTPUT_FORMAT")
include_all_platforms = ENV.fetch("INCLUDE_ALL_PLATFORMS") == "true"

android_artifact_paths = [
  ENV.fetch("COLLECT_ANDROID_RELEASE_APK_PATH"),
  ENV.fetch("COLLECT_ANDROID_RELEASE_AAB_PATH")
]
required_artifacts = android_artifact_paths + [
  "build/web/index.html",
  "build/web/flutter_bootstrap.js",
  "build/web/main.dart.js",
  "build/web/manifest.json",
  "build/web/custom-sw.js",
  "build/web/_headers",
  "build/web/robots.txt"
]

if include_all_platforms
  required_artifacts.concat(
    [
      "build/public_web/index.html",
      "build/public_web/styles.css",
      "build/public_web/sections.css",
      "build/public_web/site.js",
      "build/public_web/manifest.json",
      "build/public_web/_headers",
      "build/public_web/robots.txt",
      "build/public_web/sitemap.xml",
      "build/public_web/.well-known/apple-app-site-association",
      "build/public_web/.well-known/assetlinks.json"
    ]
  )

  archive_path = ENV.fetch("IOS_RELEASE_ARCHIVE_PATH").strip
  if archive_path.empty?
    warn "[release-artifact-manifest][BLOCKED] IOS_RELEASE_ARCHIVE_PATH is required with --all-platforms."
    exit 99
  end
  archive_path = File.expand_path(archive_path, artifact_root)
  unless archive_path.start_with?(artifact_root + File::SEPARATOR)
    warn "[release-artifact-manifest][FAIL] iOS archive must be inside the artifact root."
    exit 1
  end
  archive_relative = Pathname.new(archive_path).relative_path_from(Pathname.new(artifact_root)).to_s
  required_artifacts.concat(
    [
      File.join(archive_relative, "Info.plist"),
      File.join(archive_relative, "Products/Applications/Collect.app/Collect"),
      File.join(archive_relative, "Products/Applications/Collect.app/Info.plist"),
      File.join(archive_relative, "Products/Applications/Collect.app/PrivacyInfo.xcprivacy"),
      File.join(archive_relative, "dSYMs/Collect.app.dSYM/Contents/Resources/DWARF/Collect")
    ]
  )
end

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
  ],
  "public_web" => [
    "scripts/public_static_site_build.rb",
    "scripts/public_landing_prepare_build.sh",
    "assets/brand/collect_runtime/**/*",
    "pubspec.yaml",
    "pubspec.lock"
  ],
  "ios" => [
    "lib/**/*.dart",
    "ios/Runner/**/*",
    "ios/Flutter/*.xcconfig",
    "ios/Podfile",
    "ios/Podfile.lock",
    "ios/Runner.xcodeproj/**/*",
    "pubspec.yaml",
    "pubspec.lock"
  ]
}

def artifact_group(relative_path, android_artifact_paths)
  return "android" if android_artifact_paths.include?(relative_path)
  return "admin_web" if relative_path.start_with?("build/web/")
  return "public_web" if relative_path.start_with?("build/public_web/")
  return "ios" if relative_path.include?(".xcarchive/")
  "unknown"
end

def source_files(root, patterns)
  paths = patterns.flat_map { |pattern| Dir.glob(File.join(root, pattern), File::FNM_DOTMATCH) }
    .select { |path| File.file?(path) }
    .reject { |path| path.include?("/build/") || path.include?("/.dart_tool/") || path.include?("/.gradle/") }
    .reject { |path| path.end_with?("/ios/Flutter/Generated.xcconfig") }
    .reject { |path| File.basename(path) == "GeneratedPluginRegistrant.java" }
  paths.uniq.sort
end

def latest_source_mtime(root, patterns)
  source_files(root, patterns).map { |path| File.mtime(path) }.max
end

def source_fingerprint(root, patterns)
  digest = Digest::SHA256.new
  source_files(root, patterns).each do |path|
    relative = Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
    digest << relative << "\0" << Digest::SHA256.file(path).hexdigest << "\n"
  end
  digest.hexdigest
end

source_latest_mtimes = source_patterns.transform_values do |patterns|
  latest_source_mtime(artifact_root, patterns)
end
source_fingerprints = source_patterns.transform_values do |patterns|
  source_fingerprint(artifact_root, patterns)
end

source_revision, revision_status = Open3.capture2("git", "-C", artifact_root, "rev-parse", "HEAD")
source_revision = revision_status.success? ? source_revision.strip : nil
tracked_status, tracked_status_result = Open3.capture2(
  "git", "-C", artifact_root, "status", "--porcelain", "--untracked-files=no"
)
tracked_worktree_clean = tracked_status_result.success? && tracked_status.strip.empty?

artifacts = required_artifacts.map do |relative_path|
  absolute_path = File.expand_path(relative_path, artifact_root)
  present = absolute_path.start_with?(artifact_root + File::SEPARATOR) && File.file?(absolute_path)
  group = artifact_group(relative_path, android_artifact_paths)
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
  "scope" => include_all_platforms ? "android_admin_public_ios" : "android_admin",
  "source_revision" => source_revision,
  "tracked_worktree_clean" => tracked_worktree_clean,
  "artifact_root" => artifact_root,
  "manifest_path" => manifest_path,
  "manifest_written" => status == "pass",
  "artifact_count" => artifacts.count,
  "missing_artifacts" => missing,
  "stale_artifacts" => stale,
  "source_latest_mtimes" => source_latest_mtimes.transform_values { |mtime| mtime&.utc&.iso8601 },
  "source_fingerprints" => source_fingerprints,
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
