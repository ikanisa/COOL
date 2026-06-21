#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_FORMAT="text"
if [[ "${1:-}" == "--json" ]]; then
  OUTPUT_FORMAT="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

PACKET_PATH="${GOOGLE_PLAY_CONSOLE_AUDIT_PACKET:-docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET_2026-06-21.json}"
METADATA_DIR="${GOOGLE_PLAY_METADATA_DIR:-fastlane/metadata/android}"
OUTPUT_PATH="${OUTPUT_PATH:-.cache/google_play_optimization/google_play_metadata_export.json}"

ROOT_DIR="$ROOT_DIR" PACKET_PATH="$PACKET_PATH" METADATA_DIR="$METADATA_DIR" OUTPUT_PATH="$OUTPUT_PATH" OUTPUT_FORMAT="$OUTPUT_FORMAT" ruby -r json -r fileutils -r time <<'RUBY'
root = ENV.fetch("ROOT_DIR")
packet_path = File.expand_path(ENV.fetch("PACKET_PATH"), root)
metadata_dir = File.expand_path(ENV.fetch("METADATA_DIR"), root)
output_path = File.expand_path(ENV.fetch("OUTPUT_PATH"), root)
output_format = ENV.fetch("OUTPUT_FORMAT")

packet = JSON.parse(File.read(packet_path))
release = packet.fetch("target_release")
listing = packet.fetch("store_listing")
language = listing.fetch("default_language", "en-US")
language_dir = File.join(metadata_dir, language)
changelog_dir = File.join(language_dir, "changelogs")
FileUtils.mkdir_p(changelog_dir)

files = {
  File.join(language_dir, "title.txt") => listing.fetch("app_name"),
  File.join(language_dir, "short_description.txt") => listing.fetch("short_description"),
  File.join(language_dir, "full_description.txt") => listing.fetch("full_description"),
  File.join(changelog_dir, "#{release.fetch("version_code")}.txt") => release.fetch("release_notes").fetch(language)
}

files.each do |path, content|
  File.write(path, content.to_s.strip + "\n")
end

checks = {}
checks["title_length"] = listing.fetch("app_name").length <= 30 ? "pass" : "fail"
checks["short_description_length"] = listing.fetch("short_description").length <= 80 ? "pass" : "fail"
checks["full_description_length"] = listing.fetch("full_description").length <= 4000 ? "pass" : "fail"
checks["release_notes_present"] = release.fetch("release_notes").fetch(language).strip.empty? ? "fail" : "pass"
checks["metadata_files_written"] = files.keys.all? { |path| File.file?(path) && File.size(path).positive? } ? "pass" : "fail"

status = checks.value?("fail") ? "fail" : "pass"
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "package_name" => packet.fetch("package_name"),
  "version" => "#{release.fetch("version_name")}+#{release.fetch("version_code")}",
  "metadata_dir" => metadata_dir.sub(%r{\A#{Regexp.escape(root)}/?}, ""),
  "language" => language,
  "files" => files.keys.map do |path|
    {
      "path" => path.sub(%r{\A#{Regexp.escape(root)}/?}, ""),
      "bytes" => File.size(path)
    }
  end,
  "checks" => checks,
  "usage" => [
    "Review generated metadata before upload.",
    "Use Android Publisher API or fastlane supply only after Play credentials are available and account-controlled app-content questions are confirmed.",
    "Generated metadata excludes screenshots and graphics; those remain Console assets or future asset-library exports."
  ],
  "secret_handling" => "This export writes public store listing text and release notes only. It does not write Play credentials, signing keys, cookies, tokens, raw SMS, payment identifiers, or customer data."
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(result) + "\n")

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[google-play-metadata-export] status=#{status}"
  puts "[google-play-metadata-export] metadata_dir=#{result.fetch("metadata_dir")}"
  puts "[google-play-metadata-export] evidence=#{output_path.sub(%r{\A#{Regexp.escape(root)}/?}, "")}"
end

exit(status == "pass" ? 0 : 1)
RUBY
