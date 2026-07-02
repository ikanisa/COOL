#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FORMAT="text"
if [[ "${1:-}" == "--json" ]]; then
  OUTPUT_FORMAT="json"
fi

cd "$ROOT_DIR"

OUTPUT_FORMAT="$OUTPUT_FORMAT" ruby -r json -r net/http -r uri -r open3 -r time <<'RUBY'
root = Dir.pwd
output_format = ENV.fetch("OUTPUT_FORMAT")

def read(path)
  File.file?(path) ? File.read(path) : ""
end

def check(status, message, extra = {})
  { "status" => status, "message" => message }.merge(extra)
end

def artifact(root, relative)
  path = File.join(root, relative)
  {
    "path" => path,
    "exists" => File.file?(path),
    "bytes" => File.file?(path) ? File.size(path) : 0,
    "mtime" => File.file?(path) ? File.mtime(path).utc.iso8601 : nil
  }
end

def latest_mtime(root, patterns)
  paths = patterns.flat_map { |pattern| Dir.glob(File.join(root, pattern), File::FNM_DOTMATCH) }
  files = paths.select { |path| File.file?(path) }.reject do |path|
    relative = path.sub(%r{\A#{Regexp.escape(root)}/?}, "")
    relative == "lib/main_public.dart" || relative.start_with?("lib/features/landing/")
  end
  files.map { |path| File.mtime(path) }.max
end

def run(*cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  {
    "status" => status.exitstatus,
    "stdout" => stdout,
    "stderr" => stderr
  }
end

def http_probe(url)
  uri = URI(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 6, read_timeout: 8) do |http|
    http.get(uri.request_uri)
  end
  {
    "url" => url,
    "status_code" => response.code.to_i,
    "content_type" => response["content-type"].to_s,
    "cache_control" => response["cache-control"].to_s,
    "bytes" => response.body.to_s.bytesize
  }
rescue StandardError => e
  {
    "url" => url,
    "status_code" => 0,
    "error" => e.class.name
  }
end

def parse_badging(text)
  {
    "package_name" => text[/package: name='([^']+)'/, 1],
    "version_code" => text[/versionCode='([^']+)'/, 1]&.to_i,
    "version_name" => text[/versionName='([^']+)'/, 1],
    "compile_sdk" => text[/compileSdkVersion='([^']+)'/, 1]&.to_i,
    "min_sdk" => text[/sdkVersion:'([^']+)'/, 1]&.to_i,
    "target_sdk" => text[/targetSdkVersion:'([^']+)'/, 1]&.to_i,
    "permissions" => text.scan(/uses-permission: name='([^']+)'/).flatten.sort
  }
end

pubspec = read(File.join(root, "pubspec.yaml"))
manifest = read(File.join(root, "android/app/src/main/AndroidManifest.xml"))
receiver_manifest = read(File.join(root, "android/app/src/internal_receiver/AndroidManifest.xml"))
assetlinks_source = read(File.join(root, "web/.well-known/assetlinks.json"))
live_deployments = JSON.parse(read(File.join(root, "docs/release/LIVE_DEPLOYMENTS.json"))) rescue {}
console_audit_packet_path = File.join(root, "docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json")
console_audit_packet = JSON.parse(read(console_audit_packet_path)) rescue {}

apk = artifact(root, "build/app/outputs/flutter-apk/app-production-release.apk")
aab = artifact(root, "build/app/outputs/bundle/productionRelease/app-production-release.aab")
source_latest = latest_mtime(root, [
  "lib/**/*.dart",
  "android/app/src/**/*",
  "android/app/build.gradle.kts",
  "android/build.gradle.kts",
  "android/settings.gradle.kts",
  "pubspec.yaml",
  "pubspec.lock",
  "web/.well-known/assetlinks.json"
])

aapt = File.join(root, "../AppData/android/sdk/build-tools/36.1.0/aapt")
zipalign = File.join(root, "../AppData/android/sdk/build-tools/36.1.0/zipalign")
badging = apk["exists"] && File.executable?(aapt) ? run(aapt, "dump", "badging", apk["path"]) : { "status" => 127, "stdout" => "", "stderr" => "aapt missing or APK missing" }
package = parse_badging(badging.fetch("stdout"))
zipalign_16k = apk["exists"] && File.executable?(zipalign) ? run(zipalign, "-c", "-P", "16", "-v", "4", apk["path"]) : { "status" => 127, "stdout" => "", "stderr" => "zipalign missing or APK missing" }

native_libs = []
if aab["exists"]
  native_listing = run("unzip", "-Z1", aab["path"])
  native_libs = native_listing.fetch("stdout").lines.map(&:strip).select { |line| line.end_with?(".so") }
end

policy_urls = %w[
  https://collect.ikanisa.com/#/privacy
  https://collect.ikanisa.com/.well-known/assetlinks.json
  https://admin.collect.ikanisa.com/custom-sw.js
  https://admin.collect.ikanisa.com/main.dart.js
]
http = policy_urls.to_h { |url| [url, http_probe(url)] }

restricted_sms = %w[
  android.permission.READ_SMS
  android.permission.RECEIVE_SMS
  android.permission.SEND_SMS
  android.permission.BROADCAST_SMS
]
main_restricted = restricted_sms.select { |permission| manifest.include?(permission) }
receiver_missing = %w[android.permission.READ_SMS android.permission.RECEIVE_SMS].reject { |permission| receiver_manifest.include?(permission) }
expected_fingerprint = "9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10"

checks = {}
checks["package_identity"] =
  if package["package_name"] == "app.cool.mobile" && package["version_code"].is_a?(Integer) && package["version_name"].to_s.match?(/\A\d+\.\d+\.\d+\z/)
    check("pass", "APK package identity and version metadata are valid.", package)
  else
    check("fail", "APK package identity/version metadata are invalid or unreadable.", package.merge("aapt_status" => badging.fetch("status")))
  end

checks["target_api"] =
  if package["compile_sdk"].to_i >= 35 && package["target_sdk"].to_i >= 35
    check("pass", "APK targets the current Google Play API floor.", "compile_sdk" => package["compile_sdk"], "target_sdk" => package["target_sdk"], "min_sdk" => package["min_sdk"])
  else
    check("blocked", "APK must target API 35+ before Play submission.", "compile_sdk" => package["compile_sdk"], "target_sdk" => package["target_sdk"])
  end

stale = [apk, aab].select { |item| item["exists"] && source_latest && File.mtime(item["path"]) < source_latest }.map { |item| item["path"] }
missing = [apk, aab].reject { |item| item["exists"] }.map { |item| item["path"] }
checks["release_artifacts_fresh"] =
  if missing.empty? && stale.empty?
    check("pass", "APK and AAB exist and are newer than mobile/Android/assetlinks sources.", "source_latest_mtime" => source_latest&.utc&.iso8601, "apk" => apk, "aab" => aab)
  elsif missing.any?
    check("blocked", "Missing production APK/AAB artifacts.", "missing" => missing, "apk" => apk, "aab" => aab)
  else
    check("blocked", "Production APK/AAB artifacts are stale relative to current sources.", "stale" => stale, "source_latest_mtime" => source_latest&.utc&.iso8601, "apk" => apk, "aab" => aab)
  end

checks["sixteen_kb_alignment"] =
  if zipalign_16k.fetch("status") == 0
    check("pass", "APK verifies with zipalign -P 16 for 16 KB page-size packaging alignment.", "native_library_count" => native_libs.length)
  else
    check("blocked", "APK must pass zipalign -P 16 before Play production updates.", "native_library_count" => native_libs.length, "zipalign_status" => zipalign_16k.fetch("status"), "stderr" => zipalign_16k.fetch("stderr").lines.first(5).join)
  end

checks["production_permissions"] =
  if main_restricted.empty? && receiver_missing.empty?
    check("pass", "Production manifest excludes restricted SMS permissions; SMS receiver permissions stay isolated to internal_receiver.", "apk_permissions" => package["permissions"])
  else
    check("fail", "Restricted SMS permission scope is invalid.", "restricted_in_production_manifest" => main_restricted, "receiver_missing" => receiver_missing)
  end

checks["android_app_links"] =
  if manifest.include?('android:autoVerify="true"') &&
      manifest.include?('android:host="collect.ikanisa.com"') &&
      manifest.include?('android:pathPrefix="/c"') &&
      assetlinks_source.include?('"package_name": "app.cool.mobile"') &&
      assetlinks_source.include?(expected_fingerprint)
    status = http.dig("https://collect.ikanisa.com/.well-known/assetlinks.json", "status_code") == 200 ? "pass" : "blocked"
    message = status == "pass" ? "Verified App Links source and live assetlinks endpoint are present." : "Verified App Links source is present but live assetlinks endpoint is not deployed yet."
    check(status, message, "assetlinks_url" => http["https://collect.ikanisa.com/.well-known/assetlinks.json"])
  else
    check("blocked", "Android App Links manifest/source configuration is incomplete.")
  end

policy_status = %w[
  https://collect.ikanisa.com/#/privacy
].all? { |url| http.dig(url, "status_code") == 200 }
checks["play_policy_urls"] =
  if policy_status
    check("pass", "Play privacy, account deletion, and data deletion URL is live.", "urls" => http.select { |url, _| url.include?("privacy") })
  else
    check("blocked", "Play policy URLs must return HTTP 200.", "urls" => http)
  end

admin_status = %w[
  https://admin.collect.ikanisa.com/custom-sw.js
  https://admin.collect.ikanisa.com/main.dart.js
].all? { |url| http.dig(url, "status_code") == 200 }
checks["admin_pwa_live_assets"] =
  if admin_status && live_deployments.dig("deployments", "admin_pwa", "live_gate_status") == "pass"
    check("pass", "Admin PWA live gate metadata and live asset probes pass.", "urls" => http.select { |url, _| url.include?("admin.collect") })
  elsif admin_status
    check("pass", "Admin PWA live asset probes pass; deployment metadata should be kept in sync.", "urls" => http.select { |url, _| url.include?("admin.collect") })
  else
    check("blocked", "Admin PWA live assets must return HTTP 200.", "urls" => http.select { |url, _| url.include?("admin.collect") })
  end

required_packet_surfaces = %w[
  publishing_overview
  production_track
  deep_links
  android_vitals
  pre_launch_report
  app_integrity
  device_catalog
  testing_tracks
  monetization
  reporting_exports
]
packet_surface_missing = required_packet_surfaces.reject do |surface|
  console_audit_packet.dig("play_console_surfaces", surface, "required_evidence").to_s.strip != ""
end
checks["play_console_readiness_packet"] =
  if File.file?(console_audit_packet_path) &&
      console_audit_packet["package_name"] == "app.cool.mobile" &&
      console_audit_packet.dig("target_release", "version_code").to_i == package["version_code"].to_i &&
      console_audit_packet.dig("store_listing", "app_name").to_s != "" &&
      console_audit_packet.dig("app_content", "privacy_policy_url").to_s == "https://collect.ikanisa.com/#/privacy" &&
      console_audit_packet.dig("app_content", "account_deletion_url").to_s == "https://collect.ikanisa.com/#/privacy" &&
      console_audit_packet.dig("app_content", "data_deletion_url").to_s == "https://collect.ikanisa.com/#/privacy" &&
      console_audit_packet.dig("app_content", "permissions", "restricted_sms_permissions_in_production") == false &&
      packet_surface_missing.empty?
    check("pass", "Repo-owned Play Console audit packet is complete for listing, app content, policy, release, and account-controlled audit prompts.", "packet_path" => console_audit_packet_path.sub(%r{\A#{Regexp.escape(root)}/?}, ""), "console_completion_status" => console_audit_packet["console_completion_status"])
  else
    check("blocked", "Repo-owned Play Console audit packet is missing or inconsistent with the current release.", "packet_exists" => File.file?(console_audit_packet_path), "packet_path" => console_audit_packet_path.sub(%r{\A#{Regexp.escape(root)}/?}, ""), "missing_surfaces" => packet_surface_missing)
  end

metadata_files = {
  "title" => "fastlane/metadata/android/en-US/title.txt",
  "short_description" => "fastlane/metadata/android/en-US/short_description.txt",
  "full_description" => "fastlane/metadata/android/en-US/full_description.txt",
  "changelog_9" => "fastlane/metadata/android/en-US/changelogs/9.txt"
}
metadata_items = metadata_files.transform_values do |relative|
  path = File.join(root, relative)
  is_text = !relative.end_with?(".png")
  {
    "path" => relative,
    "exists" => File.file?(path),
    "bytes" => File.file?(path) ? File.size(path) : 0,
    "text" => is_text && File.file?(path) ? File.read(path).strip : "",
    "binary" => !is_text
  }
end
metadata_missing = metadata_items.select { |_name, item| item["exists"] != true || (item["binary"] != true && item["text"].empty?) }.keys
metadata_length_issues = []
metadata_length_issues << "title_over_30_chars" if metadata_items.dig("title", "text").to_s.length > 30
metadata_length_issues << "short_description_over_80_chars" if metadata_items.dig("short_description", "text").to_s.length > 80
metadata_length_issues << "full_description_over_4000_chars" if metadata_items.dig("full_description", "text").to_s.length > 4000
phone_screenshot_paths = Dir.glob(File.join(root, "fastlane/metadata/android/en-US/images/phoneScreenshots/*.png")).sort
checks["play_store_metadata_export"] =
  if metadata_missing.empty? && metadata_length_issues.empty? && phone_screenshot_paths.length >= 2
    check("pass", "Fastlane-compatible Play listing metadata, graphics, screenshots, and release notes are exported from the Console audit packet.", "metadata_files" => metadata_items.transform_values { |item| item.reject { |key, _| key == "text" } }, "phone_screenshot_count" => phone_screenshot_paths.length)
  else
    check("blocked", "Play listing metadata/graphics export is missing or violates Play length limits.", "missing" => metadata_missing, "length_issues" => metadata_length_issues, "phone_screenshot_count" => phone_screenshot_paths.length, "metadata_files" => metadata_items.transform_values { |item| item.reject { |key, _| key == "text" } })
  end

fastlane_files = {
  "supplyfile" => "fastlane/Supplyfile",
  "fastfile" => "fastlane/Fastfile"
}
fastlane_items = fastlane_files.transform_values do |relative|
  path = File.join(root, relative)
  text = File.file?(path) ? File.read(path) : ""
  {
    "path" => relative,
    "exists" => File.file?(path),
    "bytes" => File.file?(path) ? File.size(path) : 0,
    "uses_env_credentials" => text.include?("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"),
    "mentions_package" => text.include?("app.cool.mobile")
  }
end
fastlane_missing = fastlane_items.select { |_name, item| item["exists"] != true || item["uses_env_credentials"] != true }.keys
checks["play_upload_tooling"] =
  if fastlane_missing.empty? && fastlane_items.dig("supplyfile", "mentions_package")
    check("pass", "Fastlane supply upload tooling is present and keeps Play service-account JSON in the environment.", "files" => fastlane_items)
  else
    check("blocked", "Fastlane supply upload tooling is missing or would require unsafe credential handling.", "missing_or_invalid" => fastlane_missing, "files" => fastlane_items)
  end

integrity_sources = {
  "android_gradle" => "android/app/build.gradle.kts",
  "main_activity" => "android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt",
  "flutter_service" => "lib/core/security/play_integrity_service.dart",
  "supabase_function" => "supabase/functions/verify-play-integrity/index.ts",
  "operational_readiness" => "docs/release/PLAY_STORE_READINESS.md"
}
integrity_items = integrity_sources.transform_values do |relative|
  path = File.join(root, relative)
  text = File.file?(path) ? File.read(path) : ""
  {
    "path" => relative,
    "exists" => File.file?(path),
    "bytes" => File.file?(path) ? File.size(path) : 0,
    "has_integrity_marker" => text.include?("Play Integrity") || text.include?("play_integrity") || text.include?("collect/play_integrity") || text.include?("com.google.android.play:integrity"),
    "has_secret_material" => text.match?(/-----BEGIN PRIVATE KEY-----|\"private_key\"\s*:\s*\"|ya29\.|eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/)
  }
end
integrity_missing = integrity_items.select { |_name, item| item["exists"] != true || item["has_integrity_marker"] != true || item["has_secret_material"] == true }.keys
checks["play_integrity_implementation"] =
  if integrity_missing.empty?
    check("pass", "Play Integrity native token request, Flutter service, Supabase verification endpoint, and rollout evidence are present without embedded secret material.", "files" => integrity_items)
  else
    check("blocked", "Play Integrity implementation is missing, incomplete, or contains unsafe secret material.", "missing_or_invalid" => integrity_missing, "files" => integrity_items)
  end

reporting_snapshot_path = File.join(root, ".cache/google_play_optimization/google_play_reporting_snapshot.json")
reporting_snapshot = JSON.parse(read(reporting_snapshot_path)) rescue {}
checks["play_reporting_api_snapshot"] =
  if File.file?(reporting_snapshot_path) && %w[pass blocked].include?(reporting_snapshot["status"].to_s) && Array(reporting_snapshot["metric_sets"] || reporting_snapshot.dig("queries")&.keys).any?
    status = reporting_snapshot["status"] == "pass" ? "pass" : "blocked"
    message = status == "pass" ? "Play Developer Reporting API snapshot was collected." : "Play Developer Reporting API snapshot automation exists, but live vitals retrieval is auth blocked."
    check(status, message, "snapshot_path" => reporting_snapshot_path.sub(%r{\A#{Regexp.escape(root)}/?}, ""), "blockers" => reporting_snapshot["blockers"], "required_scope" => reporting_snapshot["required_scope"])
  else
    check("blocked", "Play Developer Reporting API snapshot evidence is missing. Run scripts/google_play_reporting_snapshot.sh --json.", "snapshot_path" => reporting_snapshot_path.sub(%r{\A#{Regexp.escape(root)}/?}, ""))
  end

required_console_surfaces = {
  "publishing_overview" => "Verify changes in review / managed publishing.",
  "production_track" => "Verify rollout, version codes, countries, and staged rollout state.",
  "app_content" => "Verify Data safety, privacy policy, account deletion, content rating, target audience, ads, financial features, and permissions declarations.",
  "store_listing" => "Verify title, short/full descriptions, graphics, screenshots, category/tags, contact details, and store listing experiments.",
  "deep_links" => "Verify collect.ikanisa.com /c App Link status and assetlinks domain verification.",
  "android_vitals" => "Review crash, ANR, excessive wakeup, slow rendering, and bad behavior thresholds.",
  "pre_launch_report" => "Review device/language/accessibility/security findings before widening rollout.",
  "app_integrity" => "Verify Play App Signing and Play Integrity / automatic protection options.",
  "device_catalog" => "Review exclusions, device reach, app size, and form-factor compatibility."
}
checks["play_console_surface_audit_required"] = check(
  "blocked",
  "Manual/live Play Console optimization audit must be recorded after current changes are deployed because several surfaces are account-controlled.",
  "surfaces" => required_console_surfaces
)

blocked = checks.select { |_key, value| value["status"] == "blocked" }
failed = checks.select { |_key, value| value["status"] == "fail" }
status = failed.any? ? "fail" : blocked.any? ? "blocked" : "pass"

result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "blocker_keys" => blocked.keys,
  "failure_keys" => failed.keys,
  "application_id" => "app.cool.mobile",
  "version" => pubspec[/^version:\s*(\S+)/, 1],
  "checks" => checks,
  "official_source_summary" => [
    "Google Play target API requirements: https://support.google.com/googleplay/android-developer/answer/11926878",
    "Android 16 KB page size guidance: https://developer.android.com/guide/practices/page-sizes",
    "Android App Links: https://developer.android.com/training/app-links",
    "Play Integrity API: https://developer.android.com/google/play/integrity",
    "Android vitals: https://developer.android.com/topic/performance/vitals",
    "Core app quality: https://developer.android.com/docs/quality-guidelines/core-app-quality",
    "Data safety: https://support.google.com/googleplay/android-developer/answer/10787469",
    "Account deletion: https://support.google.com/googleplay/android-developer/answer/13327111"
  ],
  "secret_handling" => "This gate records public URLs, build metadata, certificate fingerprints, and artifact paths only; it must not print signing keys, service account JSON, cookies, raw SMS, phone/MoMo numbers, provider tokens, or production customer data."
}

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[google-play-optimization-gate] status=#{status}"
  blocked.each_key { |key| warn "[google-play-optimization-gate][BLOCKED] #{key}" }
  failed.each_key { |key| warn "[google-play-optimization-gate][FAIL] #{key}" }
end

exit(status == "pass" ? 0 : status == "blocked" ? 99 : 1)
RUBY
