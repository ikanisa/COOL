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

OUTPUT_FORMAT="$output_format" ROOT_DIR="$ROOT_DIR" ruby -r json -r time -r uri -r open3 -r digest <<'RUBY'
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
    .reject { |path| File.basename(path) == "GeneratedPluginRegistrant.java" }
  paths.map { |path| File.mtime(path) }.max
end

def iso8601_utc?(value)
  Time.iso8601(value.to_s)
  value.to_s.end_with?("Z")
rescue ArgumentError, TypeError
  false
end

def valid_https_url?(value)
  uri = URI.parse(value.to_s)
  uri.is_a?(URI::HTTPS) && uri.host.to_s.strip != ""
rescue URI::InvalidURIError
  false
end

def evidence_reference_valid?(value, root_dir)
  reference = value.to_s.strip
  return false if reference == ""
  return true if valid_https_url?(reference)
  return false if reference.match?(/\A[a-z][a-z0-9+.-]*:/i)

  expanded_root = File.expand_path(root_dir)
  expanded_path = File.expand_path(reference, expanded_root)
  inside_repo = expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}/")
  inside_repo && File.exist?(expanded_path)
end

MOBILE_APPROVAL_EVIDENCE_PATTERNS = {
  "android_release_signing_review" => [
    %r{\Adocs/release/RELEASE_STATUS\.md\z},
    %r{\Aoutput/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_[0-9-]+\.sha256\z},
    %r{\A\.cache/mobile_release_gate/[^/]+/summary\.json\z},
    %r{\A\.cache/android_install/[^/]+/final_release_summary\.json\z}
  ],
  "ios_release_scope" => [
    %r{\Adocs/release/RELEASE_STATUS\.md\z},
    %r{\Adocs/release/RELEASE_APPROVAL_PACKET\.md\z},
    %r{\A\.cache/mobile_release_gate/[^/]+/summary\.json\z}
  ]
}

def evidence_reference_in_scope?(key, value)
  reference = value.to_s.strip
  return false if reference == ""
  return true if valid_https_url?(reference)
  return false if reference.match?(/\A[a-z][a-z0-9+.-]*:/i)

  normalized = reference.sub(%r{\A\./}, "")
  MOBILE_APPROVAL_EVIDENCE_PATTERNS.fetch(key, []).any? do |pattern|
    reference.match?(pattern) || normalized.match?(pattern)
  end
end

def executable_file?(path)
  path.to_s.strip != "" && File.file?(path) && File.executable?(path)
end

def latest_executable(paths)
  paths.select { |path| executable_file?(path) }.sort.last
end

def find_apksigner(root_dir)
  candidates = [
    ENV["APKSIGNER_BIN"],
    *Dir[File.join(ENV["ANDROID_HOME"].to_s, "build-tools/*/apksigner")],
    *Dir[File.join(ENV["ANDROID_SDK_ROOT"].to_s, "build-tools/*/apksigner")],
    *Dir[File.join(Dir.home, "Library/Android/sdk/build-tools/*/apksigner")],
    *Dir[File.join(root_dir, "../AppData/android/sdk/build-tools/*/apksigner")]
  ].compact
  latest_executable(candidates)
end

def find_jarsigner
  candidates = [
    ENV["JARSIGNER_BIN"],
    "/usr/bin/jarsigner",
    "/usr/libexec/java_home"
  ].compact
  direct = latest_executable(candidates.reject { |path| path.end_with?("java_home") })
  return direct if direct

  java_home = Open3.capture2("/usr/libexec/java_home").then { |stdout, status| status.success? ? stdout.strip : "" } rescue ""
  candidate = File.join(java_home, "bin/jarsigner")
  executable_file?(candidate) ? candidate : nil
end

def apk_signature_check(root_dir, path)
  apksigner = find_apksigner(root_dir)
  return check("blocked", "apksigner is required to verify the production APK signature.") unless apksigner
  return check("blocked", "Production APK is missing.") unless File.file?(path)

  output, status = Open3.capture2e(apksigner, "verify", "--verbose", path)
  if status.success?
    check(
      "pass",
      "Production APK signature verifies with apksigner.",
      "tool" => apksigner,
      "v1" => output.match?(/Verified using v1 scheme.*true/i),
      "v2" => output.match?(/Verified using v2 scheme.*true/i),
      "v3" => output.match?(/Verified using v3 scheme.*true/i)
    )
  else
    check("blocked", "Production APK does not verify with apksigner.")
  end
end

def aab_signature_check(path)
  jarsigner = find_jarsigner
  return check("blocked", "jarsigner is required to verify the production AAB signature.") unless jarsigner
  return check("blocked", "Production AAB is missing.") unless File.file?(path)

  output, status = Open3.capture2e(jarsigner, "-verify", path)
  if status.success? && output.match?(/jar verified/i)
    check("pass", "Production AAB signature verifies with jarsigner.", "tool" => jarsigner)
  else
    check("blocked", "Production AAB does not verify with jarsigner.")
  end
end

def template_manifest?(manifest_path, manifest)
  basename = File.basename(manifest_path).downcase
  basename.include?("example") ||
    manifest["template"] == true ||
    manifest["secret_handling"].to_s.match?(/\btemplate only\b/i)
end

def placeholder_approval_record?(record)
  placeholder_reviewers = [
    "Product Reviewer",
    "Mobile UAT Reviewer",
    "Android Release Reviewer",
    "Mobile Release Reviewer",
    "Release Owner"
  ]
  placeholder_notes = [
    "Approved SMS-first Groups product definition.",
    "Approved sanitized Android SMS UAT evidence.",
    "Approved current APK/AAB and Play App Signing review.",
    "Approved Android-only scope for this go-live.",
    "Approved after all prerequisite gates were approved."
  ]

  placeholder_reviewers.include?(record["reviewer"].to_s.strip) ||
    record["signed_at"].to_s.strip == "2026-06-01T00:00:00Z" ||
    placeholder_notes.include?(record["notes"].to_s.strip)
end

SENSITIVE_APPROVAL_METADATA_PATTERNS = {
  "supabase_service_role" => /service[_-]?role\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "openai_api_key" => /sk-[A-Za-z0-9_\-]{20,}/,
  "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "rwanda_phone_number" => /\+250\d{9}\b/,
  "raw_momo_sms" => /\b(?:m-pesa|momo|mobile money|transaction id)\b.*\b(?:\+250\d{9}|\d{6,})/i
}

def sensitive_approval_metadata?(record)
  %w[reviewer signed_at evidence_reference notes].any? do |field|
    text = record[field].to_s
    next false if text.strip == ""

    SENSITIVE_APPROVAL_METADATA_PATTERNS.any? { |_name, pattern| text.match?(pattern) }
  end
end

def release_approval_records(root_dir)
  path = ENV.fetch("RELEASE_APPROVALS_JSON", File.join(root_dir, "docs/release/RELEASE_APPROVALS.json"))
  data = JSON.parse(File.read(path))
  return {} if template_manifest?(path, data)

  Array(data["approvals"]).each_with_object({}) do |record, memo|
    key = record["key"].to_s.strip
    memo[key] = record if key != ""
  end
rescue JSON::ParserError, Errno::ENOENT
  {}
end

def release_approval_valid?(records, key, root_dir, allow_out_of_scope: false)
  record = records[key] || {}
  status = record["status"].to_s.strip
  decision = record["decision"].to_s.strip
  acceptable_status =
    if allow_out_of_scope
      (status == "approved" && decision == "GO") ||
        (status == "out_of_scope" && decision == "OUT_OF_SCOPE")
    else
      status == "approved" && decision == "GO"
    end

  acceptable_status &&
    !placeholder_approval_record?(record) &&
    !sensitive_approval_metadata?(record) &&
    record["reviewer"].to_s.strip.length >= 2 &&
    iso8601_utc?(record["signed_at"]) &&
    record["evidence_reference"].to_s.strip.length >= 3 &&
    evidence_reference_valid?(record["evidence_reference"], root_dir) &&
    evidence_reference_in_scope?(key, record["evidence_reference"]) &&
    record["sanitized_evidence"] == true &&
    record["contains_production_customer_data"] != true &&
    (key != "android_release_signing_review" || record["signing_keys_exposed"] != true)
end

def approved_artifact_version(record)
  explicit = record["artifact_version"].to_s.strip
  return explicit unless explicit == ""

  record["notes"].to_s[/\b[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+\b/]
end

def approved_android_artifact_digests(record)
  value = record["android_artifact_sha256"]
  return {} unless value.is_a?(Hash)

  value.transform_keys(&:to_s).transform_values { |digest| digest.to_s.strip.downcase }
end

pubspec = read(File.join(root_dir, "pubspec.yaml"))
gradle = read(File.join(root_dir, "android/app/build.gradle.kts"))
main_manifest = read(File.join(root_dir, "android/app/src/main/AndroidManifest.xml"))
receiver_manifest = read(File.join(root_dir, "android/app/src/internal_receiver/AndroidManifest.xml"))
production_manifest = read(File.join(root_dir, "android/app/src/production/AndroidManifest.xml"))
main_activity = read(File.join(root_dir, "android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt"))
release_approvals = release_approval_records(root_dir)

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
checks["base_manifest_restricted_sms_permissions_absent"] =
  if restricted_in_main.empty?
    check("pass", "Base Android manifest excludes restricted SMS permissions; production receive-only SMS opt-in is evaluated separately.")
  else
    check("fail", "Base Android manifest includes restricted SMS permissions; keep the production receive-only opt-in flavor-scoped.", "permissions" => restricted_in_main)
  end

receiver_has_receive = receiver_manifest.include?("android.permission.RECEIVE_SMS")
receiver_has_read = receiver_manifest.include?("android.permission.READ_SMS")
checks["internal_receiver_sms_permissions_present"] =
  if receiver_has_receive && !receiver_has_read
    check("pass", "internal_receiver declares RECEIVE_SMS without inbox-history READ_SMS access.")
  else
    check(
      "fail",
      "internal_receiver must declare RECEIVE_SMS and must not declare READ_SMS.",
      "receive_sms_present" => receiver_has_receive,
      "read_sms_present" => receiver_has_read
    )
  end

production_has_receive = production_manifest.include?("android.permission.RECEIVE_SMS")
production_has_read = production_manifest.include?("android.permission.READ_SMS")
checks["production_sms_permissions_minimized"] =
  if production_has_receive && !production_has_read
    check("pass", "Production declares RECEIVE_SMS without inbox-history READ_SMS access.")
  else
    check(
      "fail",
      "Production must declare RECEIVE_SMS and must not declare READ_SMS.",
      "receive_sms_present" => production_has_receive,
      "read_sms_present" => production_has_read
    )
  end

telephony_optional_pattern = /android:name=["']android\.hardware\.telephony["'][^>]*android:required=["']false["']/m
checks["sms_telephony_feature_optional"] =
  if production_manifest.match?(telephony_optional_pattern) && receiver_manifest.match?(telephony_optional_pattern)
    check("pass", "SMS-capable flavors keep parent telephony hardware optional so non-telephony devices remain installable.")
  else
    check("fail", "SMS-capable flavors must explicitly declare android.hardware.telephony with android:required=false.")
  end

checks["android_sms_runtime_permission_request"] =
  if main_activity.include?("requestPermissions(SMS_PERMISSIONS") &&
      main_activity.include?("onRequestPermissionsResult") &&
      main_activity.include?("Manifest.permission.RECEIVE_SMS") &&
      !main_activity.include?("Manifest.permission.READ_SMS")
    check("pass", "Android SMS access requests RECEIVE_SMS before enabling ingestion and does not request inbox history.")
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
    "android/gradle.properties",
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

apk_signature = apk_signature_check(root_dir, artifacts.fetch("android_release_apk").fetch("path"))
aab_signature = aab_signature_check(artifacts.fetch("android_release_aab").fetch("path"))
checks["android_release_artifact_signatures"] =
  if apk_signature.fetch("status") == "pass" && aab_signature.fetch("status") == "pass"
    check(
      "pass",
      "Production APK and AAB signatures verify.",
      "apk" => apk_signature,
      "aab" => aab_signature
    )
  else
    check(
      "blocked",
      "Production APK and AAB must be signed and signature-verified before release review.",
      "apk" => apk_signature,
      "aab" => aab_signature
    )
  end

android_signing_record = release_approvals["android_release_signing_review"] || {}
android_signing_reviewed_from_manifest =
  release_approval_valid?(release_approvals, "android_release_signing_review", root_dir)
current_artifact_version = version_match && version_match[1]
approved_android_artifact_version = approved_artifact_version(android_signing_record)
android_signing_version_current =
  current_artifact_version &&
  approved_android_artifact_version == current_artifact_version
current_android_artifact_digests = artifacts.transform_values do |item|
  item.fetch("exists") ? Digest::SHA256.file(item.fetch("path")).hexdigest : nil
end
recorded_android_artifact_digests = approved_android_artifact_digests(android_signing_record)
android_signing_digests_current =
  %w[apk aab].all? do |artifact_key|
    record_key = artifact_key
    artifact_name = artifact_key == "apk" ? "android_release_apk" : "android_release_aab"
    recorded_android_artifact_digests[record_key].to_s.match?(/\A[0-9a-f]{64}\z/) &&
      recorded_android_artifact_digests[record_key] == current_android_artifact_digests[artifact_name]
  end
android_signing_time = Time.iso8601(android_signing_record["signed_at"].to_s) rescue nil
latest_android_artifact_time = artifacts.values.select { |item| item.fetch("exists") }.map { |item| File.mtime(item.fetch("path")).utc }.max
android_signing_after_artifacts =
  android_signing_time &&
  latest_android_artifact_time &&
  android_signing_time >= latest_android_artifact_time

android_signing_reviewed =
  android_signing_reviewed_from_manifest &&
  android_signing_version_current &&
  android_signing_digests_current &&
  android_signing_after_artifacts

checks["android_release_signing_review"] =
  if android_signing_reviewed
    check(
      "pass",
      "Android release signing was explicitly reviewed.",
      "source" => "release_approvals_manifest",
      "review_note" => android_signing_record["notes"],
      "reviewer" => android_signing_record["reviewer"],
      "reviewed_at" => android_signing_record["signed_at"],
      "evidence_reference" => android_signing_record["evidence_reference"],
      "artifact_version" => approved_android_artifact_version,
      "android_artifact_sha256" => recorded_android_artifact_digests
    )
  else
    check(
      "blocked",
      "Android release signing / Play App Signing review must be explicitly recorded for the current artifact version in docs/release/RELEASE_APPROVALS.json.",
      "current_artifact_version" => current_artifact_version,
      "approved_artifact_version" => approved_android_artifact_version,
      "approval_record_valid" => android_signing_reviewed_from_manifest,
      "approval_version_current" => android_signing_version_current,
      "approved_android_artifact_sha256" => recorded_android_artifact_digests,
      "current_android_artifact_sha256" => current_android_artifact_digests,
      "approval_artifact_digests_current" => android_signing_digests_current,
      "approval_after_android_artifacts" => android_signing_after_artifacts
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

ios_record = release_approvals["ios_release_scope"] || {}
ios_approved_from_manifest =
  release_approval_valid?(release_approvals, "ios_release_scope", root_dir) &&
  ios_record["status"].to_s.strip == "approved"
ios_scoped_out_from_manifest =
  release_approval_valid?(release_approvals, "ios_release_scope", root_dir, allow_out_of_scope: true) &&
  ios_record["status"].to_s.strip == "out_of_scope"

ios_approved = ios_approved_from_manifest
ios_scoped_out = ios_scoped_out_from_manifest

checks["ios_release_scope"] =
  if ios_approved
    check(
      "pass",
      "iOS release evidence is approved.",
      "source" => "release_approvals_manifest",
      "reviewer" => ios_record["reviewer"],
      "reviewed_at" => ios_record["signed_at"],
      "evidence_reference" => ios_record["evidence_reference"]
    )
  elsif ios_scoped_out
    check(
      "pass",
      "iOS is explicitly scoped out for this go-live.",
      "source" => "release_approvals_manifest",
      "scope_note" => ios_record["notes"],
      "reviewer" => ios_record["reviewer"],
      "reviewed_at" => ios_record["signed_at"],
      "evidence_reference" => ios_record["evidence_reference"]
    )
  else
    check(
      "blocked",
      "iOS release scope needs signed evidence or an explicit Android-only scope note in docs/release/RELEASE_APPROVALS.json.",
      "required_evidence" => [
        "ios_release_scope status=approved decision=GO with reviewer/signed_at/evidence_reference",
        "or ios_release_scope status=out_of_scope decision=OUT_OF_SCOPE with reviewer/signed_at/evidence_reference"
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
    "restricted_sms_permissions_scope" =>
      restricted_in_main.empty? &&
      receiver_has_receive && !receiver_has_read &&
      production_has_receive && !production_has_read ? "receive_only_flavors" : "invalid",
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
