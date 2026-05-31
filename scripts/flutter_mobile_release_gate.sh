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

def read(path)
  File.read(path)
rescue Errno::ENOENT
  ""
end

def check(status, message, extra = {})
  {"status" => status, "message" => message}.merge(extra)
end

def artifact(path)
  exists = File.file?(path)
  {
    "path" => path,
    "exists" => exists,
    "bytes" => exists ? File.size(path) : nil,
    "mtime" => exists ? File.mtime(path).utc.iso8601 : nil
  }
end

def latest_source_mtime(root_dir, patterns)
  paths = patterns.flat_map { |pattern| Dir.glob(File.join(root_dir, pattern), File::FNM_DOTMATCH) }
    .select { |path| File.file?(path) }
    .reject { |path| path.include?("/build/") || path.include?("/.dart_tool/") || path.include?("/.gradle/") }
  paths.map { |path| File.mtime(path) }.max
end

def iso8601_utc?(value)
  Time.iso8601(value.to_s)
  value.to_s.end_with?("Z")
rescue ArgumentError, TypeError
  false
end

pubspec = read(File.join(root_dir, "pubspec.yaml"))
gradle = read(File.join(root_dir, "android/app/build.gradle.kts"))
main_manifest = read(File.join(root_dir, "android/app/src/main/AndroidManifest.xml"))
receiver_manifest = read(File.join(root_dir, "android/app/src/internal_receiver/AndroidManifest.xml"))
main_activity = read(File.join(root_dir, "android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt"))

checks = {}

version_match = pubspec.match(/^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$/)
checks["pubspec_version"] =
  if version_match
    check("pass", "pubspec version has semantic version plus build metadata.", "version" => version_match[1])
  else
    check("fail", "pubspec.yaml must define version as MAJOR.MINOR.PATCH+BUILD.")
  end

gradle_expectations = {
  "android_namespace" => 'namespace = "app.cool.mobile"',
  "android_application_id" => 'applicationId = "app.cool.mobile"',
  "production_flavor" => 'create("production")',
  "dev_suffix_isolated" => 'applicationIdSuffix = ".dev"',
  "internal_receiver_suffix_isolated" => 'applicationIdSuffix = ".receiver"',
  "version_code_from_flutter" => 'versionCode = flutter.versionCode',
  "version_name_from_flutter" => 'versionName = flutter.versionName',
  "java_17_source" => 'sourceCompatibility = JavaVersion.VERSION_17',
  "java_17_target" => 'targetCompatibility = JavaVersion.VERSION_17',
  "kotlin_jvm_17" => 'JvmTarget.JVM_17'
}

gradle_expectations.each do |name, needle|
  checks[name] =
    if gradle.include?(needle)
      check("pass", "Android Gradle config contains #{needle}.")
    else
      check("fail", "Android Gradle config is missing #{needle}.")
    end
end

checks["production_internet_permission"] =
  if main_manifest.include?("android.permission.INTERNET")
    check("pass", "Production Android manifest includes INTERNET for Supabase/network calls.")
  else
    check("fail", "Production Android manifest must include INTERNET.")
  end

restricted_permissions = %w[
  android.permission.READ_SMS
  android.permission.RECEIVE_SMS
]

restricted_in_main = restricted_permissions.select { |permission| main_manifest.include?(permission) }
checks["production_restricted_sms_permissions_absent"] =
  if restricted_in_main.empty?
    check("pass", "Production Android manifest excludes restricted SMS permissions.")
  else
    check("fail", "Production Android manifest includes restricted SMS permissions.", "permissions" => restricted_in_main)
  end

receiver_missing = restricted_permissions.reject { |permission| receiver_manifest.include?(permission) }
checks["internal_receiver_sms_permissions_present"] =
  if receiver_missing.empty?
    check("pass", "Restricted SMS permissions are isolated to the internal_receiver flavor manifest.")
  else
    check("fail", "internal_receiver manifest must declare READ_SMS and RECEIVE_SMS.", "missing_permissions" => receiver_missing)
  end

checks["android_sms_runtime_permission_request"] =
  if main_activity.include?("requestPermissions(SMS_PERMISSIONS") &&
      main_activity.include?("onRequestPermissionsResult") &&
      main_activity.include?("Manifest.permission.RECEIVE_SMS") &&
      main_activity.include?("Manifest.permission.READ_SMS")
    check("pass", "Android SMS access requests runtime SMS permissions before enabling ingestion.")
  else
    check("fail", "Android SMS access must request and verify runtime SMS permissions before enabling ingestion.")
  end

artifact_paths = {
  "android_release_apk" => "build/app/outputs/flutter-apk/app-production-release.apk",
  "android_release_aab" => "build/app/outputs/bundle/productionRelease/app-production-release.aab"
}
artifacts = artifact_paths.transform_values { |relative_path| artifact(File.join(root_dir, relative_path)) }

missing_artifacts = artifacts.select { |_name, item| !item.fetch("exists") }.keys
android_source_latest_mtime = latest_source_mtime(
  root_dir,
  [
    "lib/**/*.dart",
    "android/app/src/**/*",
    "android/app/build.gradle.kts",
    "android/build.gradle.kts",
    "android/settings.gradle.kts",
    "pubspec.yaml",
    "pubspec.lock"
  ]
)
stale_android_artifacts = artifacts.select do |_name, item|
  item.fetch("exists") &&
    android_source_latest_mtime &&
    File.mtime(item.fetch("path")) < android_source_latest_mtime
end.keys
checks["android_release_artifacts"] =
  if missing_artifacts.empty? && stale_android_artifacts.empty?
    check(
      "pass",
      "Production APK and AAB release artifacts exist and are newer than Android/mobile sources.",
      "source_latest_mtime" => android_source_latest_mtime&.utc&.iso8601,
      "artifacts" => artifacts
    )
  elsif missing_artifacts.any?
    check("blocked", "Production Android release artifacts must be built before GO.", "missing_artifacts" => missing_artifacts, "artifacts" => artifacts)
  else
    check(
      "blocked",
      "Production Android release artifacts are older than current Android/mobile sources.",
      "source_latest_mtime" => android_source_latest_mtime&.utc&.iso8601,
      "stale_artifacts" => stale_android_artifacts,
      "artifacts" => artifacts
    )
  end

android_signing_reviewed =
  ENV["ANDROID_RELEASE_SIGNING_REVIEWED"] == "1" &&
  ENV.fetch("ANDROID_RELEASE_SIGNING_NOTE", "").strip.length >= 12 &&
  ENV.fetch("ANDROID_RELEASE_SIGNING_REVIEWER", "").strip.length >= 2 &&
  iso8601_utc?(ENV["ANDROID_RELEASE_SIGNING_REVIEWED_AT"]) &&
  ENV.fetch("ANDROID_RELEASE_SIGNING_EVIDENCE", "").strip.length >= 3

checks["android_release_signing_review"] =
  if android_signing_reviewed
    check(
      "pass",
      "Android release signing was explicitly reviewed.",
      "review_note" => ENV.fetch("ANDROID_RELEASE_SIGNING_NOTE"),
      "reviewer" => ENV.fetch("ANDROID_RELEASE_SIGNING_REVIEWER"),
      "reviewed_at" => ENV.fetch("ANDROID_RELEASE_SIGNING_REVIEWED_AT"),
      "evidence_reference" => ENV.fetch("ANDROID_RELEASE_SIGNING_EVIDENCE")
    )
  else
    check(
      "blocked",
      "Android release signing / Play App Signing review must be explicitly recorded.",
      "required_env" => [
        "ANDROID_RELEASE_SIGNING_REVIEWED=1",
        "ANDROID_RELEASE_SIGNING_NOTE",
        "ANDROID_RELEASE_SIGNING_REVIEWER",
        "ANDROID_RELEASE_SIGNING_REVIEWED_AT",
        "ANDROID_RELEASE_SIGNING_EVIDENCE"
      ]
    )
  end

ios_files = {
  "info_plist" => "ios/Runner/Info.plist",
  "production_scheme" => "ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme",
  "release_production_xcconfig" => "ios/Flutter/Release-production.xcconfig"
}.transform_values { |relative_path| artifact(File.join(root_dir, relative_path)) }

ios_file_status = ios_files.values.all? { |item| item.fetch("exists") } ? "pass" : "fail"
checks["ios_release_files"] = check(
  ios_file_status,
  ios_file_status == "pass" ? "iOS production scheme/config files exist." : "iOS production scheme/config files are missing.",
  "files" => ios_files
)

ios_evidence = {}
ios_evidence_path = ENV.fetch("IOS_RELEASE_EVIDENCE_JSON", "").strip
if ios_evidence_path != ""
  begin
    ios_evidence = JSON.parse(File.read(ios_evidence_path))
  rescue JSON::ParserError, Errno::ENOENT => error
    ios_evidence = {"parse_error" => error.message}
  end
end

ios_approved =
  ios_evidence["ios_release_approved"] == true &&
  ios_evidence["device_uat_signed"] == true &&
  ios_evidence["testflight_or_archive_reviewed"] == true &&
  ios_evidence["reviewed_by"].to_s.strip.length >= 2 &&
  iso8601_utc?(ios_evidence["reviewed_at"]) &&
  ios_evidence["evidence_reference"].to_s.strip.length >= 3

ios_scoped_out =
  ENV["IOS_RELEASE_OUT_OF_SCOPE"] == "1" &&
  ENV.fetch("IOS_RELEASE_SCOPE_NOTE", "").strip.length >= 12 &&
  ENV.fetch("IOS_RELEASE_SCOPE_REVIEWER", "").strip.length >= 2 &&
  iso8601_utc?(ENV["IOS_RELEASE_SCOPE_REVIEWED_AT"]) &&
  ENV.fetch("IOS_RELEASE_SCOPE_EVIDENCE", "").strip.length >= 3

checks["ios_release_scope"] =
  if ios_approved
    check(
      "pass",
      "iOS release evidence is approved.",
      "evidence_path" => ios_evidence_path,
      "reviewer" => ios_evidence["reviewed_by"],
      "reviewed_at" => ios_evidence["reviewed_at"],
      "evidence_reference" => ios_evidence["evidence_reference"]
    )
  elsif ios_scoped_out
    check(
      "pass",
      "iOS is explicitly scoped out for this go-live.",
      "scope_note" => ENV.fetch("IOS_RELEASE_SCOPE_NOTE"),
      "reviewer" => ENV.fetch("IOS_RELEASE_SCOPE_REVIEWER"),
      "reviewed_at" => ENV.fetch("IOS_RELEASE_SCOPE_REVIEWED_AT"),
      "evidence_reference" => ENV.fetch("IOS_RELEASE_SCOPE_EVIDENCE")
    )
  else
    check(
      "blocked",
      "iOS release scope needs signed evidence or an explicit Android-only scope note.",
      "required_evidence" => [
        "IOS_RELEASE_EVIDENCE_JSON with ios_release_approved/device_uat_signed/testflight_or_archive_reviewed/reviewed_by/reviewed_at/evidence_reference",
        "or IOS_RELEASE_OUT_OF_SCOPE=1 with IOS_RELEASE_SCOPE_NOTE/IOS_RELEASE_SCOPE_REVIEWER/IOS_RELEASE_SCOPE_REVIEWED_AT/IOS_RELEASE_SCOPE_EVIDENCE"
      ]
    )
  end

failures = checks.select { |_name, item| item.fetch("status") == "fail" }
blocked = checks.select { |_name, item| item.fetch("status") == "blocked" }
status = if failures.any?
  "fail"
elsif blocked.any?
  "blocked"
else
  "pass"
end

result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "blocker_keys" => blocked.keys,
  "failure_keys" => failures.keys,
  "android" => {
    "application_id" => "app.cool.mobile",
    "production_flavor" => "production",
    "restricted_sms_permissions_scope" => restricted_in_main.empty? && receiver_missing.empty? ? "internal_receiver_only" : "invalid",
    "artifacts" => artifacts
  },
  "ios" => {
    "files" => ios_files,
    "release_scope" => checks.fetch("ios_release_scope").fetch("status")
  },
  "checks" => checks,
  "secret_handling" => "This gate records metadata, artifact paths, review notes, and blocker keys only; it must not print signing keys or secret values."
}

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[flutter-mobile-release-gate] status=#{status}"
  blocked.each_key { |key| warn "[flutter-mobile-release-gate][BLOCKED] #{key}" }
  failures.each_key { |key| warn "[flutter-mobile-release-gate][FAIL] #{key}" }
end

exit(status == "pass" ? 0 : status == "blocked" ? 99 : 1)
RUBY
