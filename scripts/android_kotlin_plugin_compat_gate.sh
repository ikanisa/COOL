#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
if [[ "${1:-}" == "--json" ]]; then
  output_format="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

OUTPUT_FORMAT="$output_format" ROOT_DIR="$ROOT_DIR" ruby -r json -r time <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")
plugins_file = File.join(root_dir, ".flutter-plugins-dependencies")

def read_json(path)
  JSON.parse(File.read(path))
rescue Errno::ENOENT, JSON::ParserError
  nil
end

def safe_plugin_path(path)
  expanded = File.expand_path(path.to_s)
  return nil unless File.directory?(expanded)
  expanded
end

def kotlin_plugin_markers(text)
  markers = []
  markers << "apply plugin: 'kotlin-android'" if text.include?("apply plugin: 'kotlin-android'")
  markers << 'apply plugin: "kotlin-android"' if text.include?('apply plugin: "kotlin-android"')
  markers << 'id("kotlin-android")' if text.include?('id("kotlin-android")')
  markers << "id 'kotlin-android'" if text.include?("id 'kotlin-android'")
  markers << 'org.jetbrains.kotlin.android' if text.include?('org.jetbrains.kotlin.android')
  markers << 'org.jetbrains.kotlin:kotlin-gradle-plugin' if text.include?('org.jetbrains.kotlin:kotlin-gradle-plugin')
  markers.uniq
end

plugins_json = read_json(plugins_file)
failures = []
android_plugins = []

if plugins_json.nil?
  failures << ".flutter-plugins-dependencies is missing or invalid; run flutter pub get first."
else
  android_plugins = Array(plugins_json.dig("plugins", "android"))
end

plugin_results = android_plugins.map do |plugin|
  name = plugin.fetch("name", "").to_s
  path = safe_plugin_path(plugin["path"])
  gradle_files = path.nil? ? [] : Dir[File.join(path, "android/build.gradle{,.kts}")]
  markers = []
  gradle_files.each do |gradle_file|
    markers.concat(kotlin_plugin_markers(File.read(gradle_file)))
  rescue Errno::ENOENT
    next
  end
  {
    "name" => name,
    "path" => path,
    "gradle_files" => gradle_files,
    "applies_kotlin_gradle_plugin" => markers.any?,
    "markers" => markers.uniq,
  }
end

direct_kotlin_plugins = plugin_results.select { |plugin| plugin.fetch("applies_kotlin_gradle_plugin") }

status =
  if failures.any?
    "fail"
  elsif direct_kotlin_plugins.any?
    "warning"
  else
    "pass"
  end

summary = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "plugin_count" => plugin_results.count,
  "direct_kotlin_plugin_count" => direct_kotlin_plugins.count,
  "direct_kotlin_plugins" => direct_kotlin_plugins.map { |plugin|
    {
      "name" => plugin.fetch("name"),
      "markers" => plugin.fetch("markers"),
    }
  },
  "failures" => failures,
  "secret_handling" => "This gate reports plugin names and Gradle marker strings only; it does not read or print signing or environment secrets.",
}

if output_format == "json"
  puts JSON.pretty_generate(summary)
else
  puts "[android-kotlin-plugin-compat] status=#{status}"
  if direct_kotlin_plugins.any?
    names = direct_kotlin_plugins.map { |plugin| plugin.fetch("name") }.join(", ")
    puts "[android-kotlin-plugin-compat] direct_kotlin_plugins=#{names}"
  end
  failures.each { |failure| warn "[android-kotlin-plugin-compat][FAIL] #{failure}" }
end

exit(status == "fail" ? 1 : 0)
RUBY
