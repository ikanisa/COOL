#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${PUBLIC_WEBSITE_URL:-https://collect.ikanisa.com}"
OUT_DIR="${PUBLIC_WEBSITE_EVIDENCE_DIR:-output/public_website_evidence}"
mkdir -p "$OUT_DIR"

ruby -r json -r net/http -r uri -r time - "$BASE_URL" "$OUT_DIR" <<'RUBY'
base_url = ARGV.fetch(0).delete_suffix("/")
out_dir = ARGV.fetch(1)

def fetch(url)
  uri = URI(url)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = nil
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
    request = Net::HTTP::Get.new(uri)
    response = http.request(request)
  end
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  {
    "url" => url,
    "status" => response.code.to_i,
    "elapsed_ms" => elapsed_ms,
    "headers" => response.each_header.to_h,
    "body" => response.body.to_s,
  }
end

routes = [
  "/",
  "/privacy/",
  "/terms/",
  "/account-deletion/",
  "/data-deletion/",
  "/trust/",
  "/security/",
  "/sitemap.xml",
  "/robots.txt",
  "/styles.css",
  "/site.js",
  "/assets/brand/generated/collect_visual_group_momentum.png",
  "/icons/collect.png",
]
responses = routes.to_h { |route| [route, fetch("#{base_url}#{route}")] }
root = responses.fetch("/")
root_body = root.fetch("body").dup.force_encoding("UTF-8")
styles_body = responses.fetch("/styles.css").fetch("body").dup.force_encoding("UTF-8")
site_js = responses.fetch("/site.js")

json_ld_scripts = root_body.scan(%r{<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>}m).flatten
json_ld_types = []
json_ld_parse_error = nil
begin
  json_ld_scripts.each do |script|
    parsed = JSON.parse(script)
    nodes = parsed.is_a?(Hash) && parsed["@graph"].is_a?(Array) ? parsed["@graph"] : [parsed]
    json_ld_types.concat(nodes.map { |node| node["@type"] if node.is_a?(Hash) }.compact)
  end
rescue JSON::ParserError => e
  json_ld_parse_error = e.message
end

first_party_critical_bytes = [
  responses.fetch("/"),
  responses.fetch("/styles.css"),
  responses.fetch("/site.js"),
  responses.fetch("/assets/brand/generated/collect_visual_group_momentum.png"),
  responses.fetch("/icons/collect.png"),
].sum { |item| item.fetch("body").bytesize }

checks = {
  "http_all_required_routes_200" => responses.slice("/", "/privacy/", "/terms/", "/account-deletion/", "/data-deletion/", "/trust/", "/security/", "/sitemap.xml", "/robots.txt").all? { |_route, item| item.fetch("status") == 200 },
  "root_cacheable_no_noindex" => root.dig("headers", "cache-control").to_s.include?("public") && !root.dig("headers", "x-robots-tag").to_s.downcase.include?("noindex"),
  "valid_structured_data" => json_ld_parse_error.nil? && json_ld_types.include?("Organization") && json_ld_types.include?("SoftwareApplication"),
  "seo_metadata" => root_body.include?('rel="canonical"') && root_body.include?('property="og:title"') && root_body.include?('name="twitter:card"'),
  "no_flutter_or_wasm" => !root_body.match?(/flutter_bootstrap|flutter-view|main\.dart\.js|canvaskit|\.wasm/),
  "static_accessibility_signals" => root_body.include?('<html lang="en">') && root_body.include?('class="skip-link"') && root_body.scan(/<img\b[^>]*>/i).all? { |tag| tag.include?("alt=") } && styles_body.include?(":focus-visible"),
  "english_only_public_site" => root_body.include?('<html lang="en">') &&
    root_body.include?('property="og:locale" content="en_US"') &&
    !responses.fetch("/sitemap.xml").fetch("body").include?("#{base_url}/rw/") &&
    !responses.fetch("/sitemap.xml").fetch("body").include?("#{base_url}/fr/") &&
    !root_body.include?('hreflang="rw"') &&
    !root_body.include?('hreflang="fr"'),
  "performance_budgets" => root.fetch("elapsed_ms") <= 1500 && root_body.bytesize <= 20_000 && styles_body.bytesize <= 30_000 && site_js.fetch("body").bytesize <= 153_600 && first_party_critical_bytes <= 400_000,
  "mobile_responsive_css" => styles_body.include?("@media (max-width: 980px)") && styles_body.include?("@media (max-width: 560px)") && styles_body.include?(".site-nav.open"),
}

payload = {
  "checked_at_utc" => Time.now.utc.iso8601,
  "base_url" => base_url,
  "status" => checks.values.all? ? "pass" : "fail",
  "checks" => checks,
  "metrics" => {
    "root_elapsed_ms" => root.fetch("elapsed_ms"),
    "root_html_bytes" => root_body.bytesize,
    "css_bytes" => styles_body.bytesize,
    "js_bytes" => site_js.fetch("body").bytesize,
    "critical_first_party_bytes" => first_party_critical_bytes,
    "json_ld_types" => json_ld_types,
    "json_ld_parse_error" => json_ld_parse_error,
    "root_cache_control" => root.dig("headers", "cache-control"),
    "root_cf_cache_status" => root.dig("headers", "cf-cache-status"),
  },
  "route_matrix" => responses.transform_values do |item|
    {
      "status" => item.fetch("status"),
      "elapsed_ms" => item.fetch("elapsed_ms"),
      "bytes" => item.fetch("body").bytesize,
      "content_type" => item.dig("headers", "content-type"),
      "cache_control" => item.dig("headers", "cache-control"),
      "cf_cache_status" => item.dig("headers", "cf-cache-status"),
    }
  end,
}

File.write(File.join(out_dir, "live_audit_evidence.json"), JSON.pretty_generate(payload))
puts JSON.pretty_generate(payload.reject { |key, _| key == "route_matrix" })
exit(payload.fetch("status") == "pass" ? 0 : 1)
RUBY
