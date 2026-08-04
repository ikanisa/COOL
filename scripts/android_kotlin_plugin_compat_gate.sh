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

def kotlin_plugin_application_markers(text)
  markers = []
  markers << "apply plugin: 'kotlin-android'" if text.include?("apply plugin: 'kotlin-android'")
  markers << 'apply plugin: "kotlin-android"' if text.include?('apply plugin: "kotlin-android"')
  markers << 'apply(plugin = "org.jetbrains.kotlin.android")' if text.include?('apply(plugin = "org.jetbrains.kotlin.android")')
  markers << 'id("kotlin-android")' if text.include?('id("kotlin-android")')
  markers << "id 'kotlin-android'" if text.include?("id 'kotlin-android'")
  markers.uniq
end

def kotlin_plugin_classpath_markers(text)
  markers = []
  markers << 'org.jetbrains.kotlin:kotlin-gradle-plugin' if text.include?('org.jetbrains.kotlin:kotlin-gradle-plugin')
  markers.uniq
end

def conditional_fallback(text)
  return "agp_major_lt_9" if text.match?(/if\s*\(\s*agpMajor\s*<\s*9\s*\)/)
  return "built_in_kotlin_disabled" if text.match?(/if\s*\(\s*!builtInKotlin\s*\)/)
  nil
end

def current_agp_major(root_dir)
  settings = [
    File.join(root_dir, "android/settings.gradle.kts"),
    File.join(root_dir, "android/settings.gradle"),
  ].find { |path| File.file?(path) }
  return nil if settings.nil?
  text = File.read(settings)
  match = text.match(/com\.android\.application["']?\)??\s+version\s+["'](\d+)/)
  match ||= text.match(/com\.android\.tools\.build:gradle:(\d+)/)
  match && match[1].to_i
end

def built_in_kotlin_enabled(root_dir)
  path = File.join(root_dir, "android/gradle.properties")
  return nil unless File.file?(path)
  value = File.readlines(path, chomp: true)
    .map(&:strip)
    .reject { |line| line.empty? || line.start_with?("#") }
    .find { |line| line.start_with?("android.builtInKotlin=") }
  return nil if value.nil?
  value.split("=", 2).last.strip == "true"
end

plugins_json = read_json(plugins_file)
failures = []
android_plugins = []
agp_major = current_agp_major(root_dir)
built_in_kotlin = built_in_kotlin_enabled(root_dir)

failures << "Unable to determine the app Android Gradle Plugin major version." if agp_major.nil?

if plugins_json.nil?
  failures << ".flutter-plugins-dependencies is missing or invalid; run flutter pub get first."
else
  android_plugins = Array(plugins_json.dig("plugins", "android"))
end

plugin_results = android_plugins.map do |plugin|
  name = plugin.fetch("name", "").to_s
  path = safe_plugin_path(plugin["path"])
  gradle_files = path.nil? ? [] : Dir[File.join(path, "android/build.gradle{,.kts}")]
  application_markers = []
  classpath_markers = []
  fallbacks = []
  gradle_files.each do |gradle_file|
    text = File.read(gradle_file)
    application_markers.concat(kotlin_plugin_application_markers(text))
    classpath_markers.concat(kotlin_plugin_classpath_markers(text))
    fallback = conditional_fallback(text)
    fallbacks << fallback unless fallback.nil?
  rescue Errno::ENOENT
    next
  end
  application_markers.uniq!
  fallbacks.uniq!
  unconditional_application = application_markers.any? && fallbacks.empty?
  applies_on_current_graph =
    if unconditional_application
      true
    elsif application_markers.empty?
      false
    else
      fallbacks.any? do |fallback|
        (fallback == "agp_major_lt_9" && agp_major && agp_major < 9) ||
          (fallback == "built_in_kotlin_disabled" && built_in_kotlin != true)
      end
    end
  {
    "name" => name,
    "path" => path,
    "gradle_files" => gradle_files,
    "applies_kotlin_gradle_plugin" => applies_on_current_graph,
    "application_markers" => application_markers,
    "classpath_markers" => classpath_markers.uniq,
    "conditional_fallbacks" => fallbacks,
    "unconditional_application" => unconditional_application,
    "future_built_in_kotlin_ready" => !unconditional_application,
  }
end

direct_kotlin_plugins = plugin_results.select { |plugin| plugin.fetch("applies_kotlin_gradle_plugin") }
future_not_ready_plugins = plugin_results.reject { |plugin| plugin.fetch("future_built_in_kotlin_ready") }

status =
  if failures.any?
    "fail"
  elsif direct_kotlin_plugins.any? || future_not_ready_plugins.any?
    "warning"
  else
    "pass"
  end

summary = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "app_agp_major" => agp_major,
  "app_built_in_kotlin_enabled" => built_in_kotlin,
  "plugin_count" => plugin_results.count,
  "direct_kotlin_plugin_count" => direct_kotlin_plugins.count,
  "direct_kotlin_plugins" => direct_kotlin_plugins.map { |plugin|
    {
      "name" => plugin.fetch("name"),
      "markers" => plugin.fetch("application_markers"),
      "conditional_fallbacks" => plugin.fetch("conditional_fallbacks"),
    }
  },
  "future_built_in_kotlin_ready_count" => plugin_results.count { |plugin| plugin.fetch("future_built_in_kotlin_ready") },
  "future_not_ready_plugin_count" => future_not_ready_plugins.count,
  "future_not_ready_plugins" => future_not_ready_plugins.map { |plugin|
    {
      "name" => plugin.fetch("name"),
      "markers" => plugin.fetch("application_markers"),
    }
  },
  "failures" => failures,
  "interpretation" => "Classpath declarations and kotlin compilerOptions are not treated as direct KGP application. Conditional AGP<9 or built-in-Kotlin-disabled fallbacks are evaluated against the current app graph.",
  "platform_boundary" => "Flutter 3.44 can migrate source syntax, but official Flutter guidance requires Flutter 3.47 or later before android.builtInKotlin=true can be enabled and validated.",
  "secret_handling" => "This gate reports plugin names, Gradle compatibility markers, and public build configuration only; it does not read or print signing or environment secrets.",
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
