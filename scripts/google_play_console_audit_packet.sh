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

PACKET_PATH="${GOOGLE_PLAY_CONSOLE_AUDIT_PACKET:-docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json}"
OUTPUT_PATH="${OUTPUT_PATH:-.cache/google_play_optimization/google_play_console_audit_packet.json}"

ROOT_DIR="$ROOT_DIR" PACKET_PATH="$PACKET_PATH" OUTPUT_PATH="$OUTPUT_PATH" OUTPUT_FORMAT="$OUTPUT_FORMAT" ruby -r digest -r json -r net/http -r uri -r time -r fileutils <<'RUBY'
root = ENV.fetch("ROOT_DIR")
packet_path = File.expand_path(ENV.fetch("PACKET_PATH"), root)
output_path = File.expand_path(ENV.fetch("OUTPUT_PATH"), root)
output_format = ENV.fetch("OUTPUT_FORMAT")

def check(status, message, extra = {})
  { "status" => status, "message" => message }.merge(extra)
end

def dig_value(hash, path)
  path.reduce(hash) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
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
    "bytes" => response.body.to_s.bytesize
  }
rescue StandardError => e
  {
    "url" => url,
    "status_code" => 0,
    "error" => e.class.name
  }
end

packet = JSON.parse(File.read(packet_path))
checks = {}

required_fields = {
  "package_name" => ["package_name"],
  "release_version_name" => ["target_release", "version_name"],
  "release_version_code" => ["target_release", "version_code"],
  "release_track" => ["target_release", "track"],
  "release_notes" => ["target_release", "release_notes", "en-US"],
  "store_app_name" => ["store_listing", "app_name"],
  "store_short_description" => ["store_listing", "short_description"],
  "store_full_description" => ["store_listing", "full_description"],
  "store_category" => ["store_listing", "category"],
  "store_contact_email" => ["store_listing", "contact", "email"],
  "store_website" => ["store_listing", "contact", "website"],
  "privacy_policy_url" => ["app_content", "privacy_policy_url"],
  "account_deletion_url" => ["app_content", "account_deletion_url"],
  "data_deletion_url" => ["app_content", "data_deletion_url"],
  "app_links_assetlinks_url" => ["play_console_surfaces", "deep_links", "assetlinks_url"]
}
missing_fields = required_fields.select { |_name, path| dig_value(packet, path).to_s.strip.empty? }.keys
checks["required_fields"] =
  if missing_fields.empty?
    check("pass", "Required Google Play packet fields are present.")
  else
    check("fail", "Google Play packet is missing required fields.", "missing_fields" => missing_fields)
  end

short_description = dig_value(packet, ["store_listing", "short_description"]).to_s
full_description = dig_value(packet, ["store_listing", "full_description"]).to_s
app_name = dig_value(packet, ["store_listing", "app_name"]).to_s
listing_issues = []
listing_issues << "app_name_over_30_chars" if app_name.length > 30
listing_issues << "short_description_over_80_chars" if short_description.length > 80
listing_issues << "full_description_over_4000_chars" if full_description.length > 4000
checks["store_listing_lengths"] =
  if listing_issues.empty?
    check("pass", "Store listing text fits Play length limits.", "app_name_chars" => app_name.length, "short_description_chars" => short_description.length, "full_description_chars" => full_description.length)
  else
    check("fail", "Store listing text exceeds Play length limits.", "issues" => listing_issues)
  end

artifact_paths = {
  "aab" => dig_value(packet, ["target_release", "aab_path"]),
  "brand_icon_source" => dig_value(packet, ["store_listing", "assets", "brand_icon_source"]),
  "launcher_icon" => dig_value(packet, ["store_listing", "assets", "launcher_icon"])
}
artifact_items = artifact_paths.transform_values do |relative|
  path = relative.to_s.empty? ? "" : File.join(root, relative.to_s)
  {
    "path" => relative,
    "exists" => !relative.to_s.empty? && File.file?(path),
    "bytes" => !relative.to_s.empty? && File.file?(path) ? File.size(path) : 0
  }
end
missing_artifacts = artifact_items.select { |_name, item| item["exists"] != true }.keys
assets = dig_value(packet, ["store_listing", "assets"]) || {}
expected_asset_hashes = {
  "brand_icon_source" => assets["brand_icon_sha256"].to_s,
  "launcher_icon" => assets["launcher_icon_sha256"].to_s
}
asset_hash_failures = expected_asset_hashes.each_with_object([]) do |(name, expected), failures|
  item = artifact_items.fetch(name)
  path = item["exists"] ? File.join(root, item.fetch("path")) : ""
  actual = path.empty? ? "" : Digest::SHA256.file(path).hexdigest
  failures << { "artifact" => name, "expected" => expected, "actual" => actual } if expected.empty? || actual != expected
end
checks["required_artifacts"] =
  if missing_artifacts.empty? && asset_hash_failures.empty?
    check("pass", "Required Play release artifacts and official Collect icon hashes are present.", "artifacts" => artifact_items)
  else
    check("fail", "Required Play release artifacts are missing or an icon differs from the approved official source.", "missing_artifacts" => missing_artifacts, "asset_hash_failures" => asset_hash_failures, "artifacts" => artifact_items)
  end

feature_graphic = assets.fetch("feature_graphic", {})
phone_screenshot_policy = assets.fetch("phone_screenshots", {})
official_icon_policy =
  assets["brand_icon_source"] == "assets/brand/collect_runtime/app_icons/app-icon-rule.png" &&
  assets["brand_icon_sha256"] == "c6942d8bac7e860df1993e977277a47121340666b3f44a4f7cff63e079614209" &&
  asset_hash_failures.empty?
screenshots_path = phone_screenshot_policy["path"].to_s
screenshots_dir = screenshots_path.empty? ? "" : File.join(root, screenshots_path)
phone_screenshots = screenshots_dir.empty? ? [] : Dir.glob(File.join(screenshots_dir, "*.png")).sort.map do |path|
  {
    "path" => path.sub(%r{\A#{Regexp.escape(root)}/?}, ""),
    "bytes" => File.size(path)
  }
end
minimum_screenshots = phone_screenshot_policy["minimum_required"].to_i
current_screenshots =
  phone_screenshot_policy["status"] == "current_product_capture" &&
  phone_screenshot_policy["source"] == "native_product_capture_only"
official_feature_graphic = feature_graphic["status"] == "approved_official_asset"
checks["store_graphics"] =
  if official_icon_policy && current_screenshots && official_feature_graphic && phone_screenshots.length >= minimum_screenshots
    check("pass", "Play visual exports use the approved Collect icon and current native product captures.", "phone_screenshot_count" => phone_screenshots.length, "phone_screenshots" => phone_screenshots)
  else
    check("blocked", "Play visual export awaits an owner-approved feature graphic and refreshed native screenshots; fabricated assets are forbidden.", "official_icon_policy" => official_icon_policy, "feature_graphic_status" => feature_graphic["status"], "phone_screenshot_status" => phone_screenshot_policy["status"], "phone_screenshot_count" => phone_screenshots.length, "minimum_required" => minimum_screenshots)
  end

urls = [
  dig_value(packet, ["store_listing", "contact", "website"]),
  dig_value(packet, ["app_content", "privacy_policy_url"]),
  dig_value(packet, ["app_content", "account_deletion_url"]),
  dig_value(packet, ["app_content", "data_deletion_url"]),
  dig_value(packet, ["play_console_surfaces", "deep_links", "assetlinks_url"])
].compact.uniq
url_results = urls.to_h { |url| [url, http_probe(url)] }
bad_urls = url_results.select { |_url, result| result["status_code"] != 200 }
checks["public_urls"] =
  if bad_urls.empty?
    check("pass", "Public Play policy, website, deletion, and App Links URLs return HTTP 200.", "urls" => url_results)
  else
    check("blocked", "One or more public Play URLs is not reachable.", "urls" => url_results)
  end

data_categories = Array(dig_value(packet, ["app_content", "data_safety", "collected_data_categories"]))
required_categories = ["Personal info", "Financial info", "Photos and videos", "App activity"]
present_categories = data_categories.map { |item| item["category"].to_s }
missing_categories = required_categories - present_categories
checks["data_safety_categories"] =
  if missing_categories.empty?
    check("pass", "Data safety packet covers the expected Collect data categories.", "categories" => present_categories)
  else
    check("fail", "Data safety packet is missing expected categories.", "missing_categories" => missing_categories, "categories" => present_categories)
  end

production_permissions = Array(dig_value(packet, ["app_content", "permissions", "production_permissions"]))
restricted_sms = %w[android.permission.READ_SMS android.permission.RECEIVE_SMS android.permission.SEND_SMS android.permission.BROADCAST_SMS]
restricted_present = production_permissions & restricted_sms
checks["permissions_scope"] =
  if restricted_present.empty? && dig_value(packet, ["app_content", "permissions", "restricted_sms_permissions_in_production"]) == false
    check("pass", "Production Play permission packet excludes restricted SMS permissions.", "production_permissions" => production_permissions)
  else
    check("fail", "Restricted SMS permissions must not be declared for the production Play release.", "restricted_present" => restricted_present)
  end

surfaces = packet.fetch("play_console_surfaces", {})
required_surfaces = %w[
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
missing_surfaces = required_surfaces.reject { |key| surfaces.dig(key, "required_evidence").to_s.strip != "" }
checks["console_surface_coverage"] =
  if missing_surfaces.empty?
    check("pass", "Play Console audit packet covers all required account-controlled surfaces.", "surfaces" => required_surfaces)
  else
    check("fail", "Play Console audit packet is missing required surface evidence prompts.", "missing_surfaces" => missing_surfaces)
  end

blocked = checks.select { |_key, value| value["status"] == "blocked" }
failed = checks.select { |_key, value| value["status"] == "fail" }
status = failed.any? ? "fail" : blocked.any? ? "blocked" : "pass"

result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "packet_path" => packet_path.sub(%r{\A#{Regexp.escape(root)}/?}, ""),
  "package_name" => packet["package_name"],
  "version" => "#{dig_value(packet, ["target_release", "version_name"])}+#{dig_value(packet, ["target_release", "version_code"])}",
  "console_completion_status" => packet["console_completion_status"],
  "blocker_keys" => blocked.keys,
  "failure_keys" => failed.keys,
  "checks" => checks,
  "next_console_actions" => [
    "Upload the AAB to the production draft release after Android Publisher API auth or browser file upload is available.",
    "Record live Play Console evidence for publishing overview, production track, app content, store listing, deep links, Android vitals, pre-launch report, app integrity, device catalog, testing tracks, and reporting exports.",
    "Keep any reviewer credentials, service account JSON, cookies, bearer tokens, signing keys, raw SMS, payment identifiers, and customer data out of this packet and out of evidence logs."
  ],
  "official_sources" => Array(packet["official_sources"]),
  "secret_handling" => packet["secret_handling"]
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(result) + "\n")

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[google-play-console-audit-packet] status=#{status}"
  blocked.each_key { |key| warn "[google-play-console-audit-packet][BLOCKED] #{key}" }
  failed.each_key { |key| warn "[google-play-console-audit-packet][FAIL] #{key}" }
  puts "[google-play-console-audit-packet] evidence=#{output_path.sub(%r{\A#{Regexp.escape(root)}/?}, "")}"
end

exit(status == "pass" ? 0 : status == "blocked" ? 99 : 1)
RUBY
