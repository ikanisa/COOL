#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${PUBLIC_WEBSITE_URL:-https://collect.ikanisa.com}"
MODE="${1:-}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ruby -r json -r net/http -r uri -r time - "$BASE_URL" "$MODE" <<'RUBY'
base_url = ARGV.fetch(0).delete_suffix("/")
mode = ARGV.fetch(1)

def fetch(url)
  uri = URI(url)
  response = nil
  elapsed = nil
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
    request = Net::HTTP::Get.new(uri)
    response = http.request(request)
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  [response, elapsed]
end

checks = []

def check(checks, id, passed, message, details = {})
  checks << {
    "id" => id,
    "status" => passed ? "pass" : "fail",
    "message" => message,
    "details" => details,
  }
end

def json_ld_types_for(html)
  scripts = html.scan(%r{<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>}m).flatten
  types = []
  parse_error = nil
  begin
    scripts.each do |script|
      parsed = JSON.parse(script)
      nodes = parsed.is_a?(Hash) && parsed["@graph"].is_a?(Array) ? parsed["@graph"] : [parsed]
      types.concat(nodes.map { |node| node["@type"] if node.is_a?(Hash) }.compact)
    end
  rescue JSON::ParserError => e
    parse_error = e.message
  end
  [scripts, types, parse_error]
end

required_routes = {
  "/" => ["Credit-ready", "How credit-readiness works"],
  "/privacy/" => ["Privacy Policy", "Data Deletion", "Account deletion request"],
  "/terms/" => ["Terms"],
  "/account-deletion/" => ["Account Deletion"],
  "/data-deletion/" => ["Data Deletion"],
  "/trust/" => ["Trust", "deletion"],
  "/security/" => ["Trust", "deletion"],
  "/rw/" => ["Collect"],
  "/fr/" => ["Collect"],
  "/sitemap.xml" => ["credit-readiness", "privacy", "trust", "rw", "fr"],
  "/robots.txt" => ["Allow: /", "Sitemap:"],
}

responses = {}
required_routes.each do |route, required_text|
  url = "#{base_url}#{route}"
  response, elapsed = fetch(url)
  body = response.body.to_s
  headers = response.each_header.to_h
  responses[route] = { response: response, body: body, headers: headers, elapsed: elapsed }
  missing = required_text.reject { |text| body.include?(text) }
  check(
    checks,
    "route_#{route.gsub(%r{[^a-zA-Z0-9]+}, "_")}",
    response.code.to_i == 200 && missing.empty?,
    "#{route} returns live content-complete HTTP 200.",
    {
      "status" => response.code.to_i,
      "bytes" => body.bytesize,
      "elapsed_ms" => (elapsed * 1000).round,
      "missing_text" => missing,
    },
  )
end

["/styles.css", "/site.js", "/assets/brand/generated/collect_visual_group_momentum.png", "/icons/collect.png"].each do |route|
  url = "#{base_url}#{route}"
  response, elapsed = fetch(url)
  responses[route] = {
    response: response,
    body: response.body.to_s,
    headers: response.each_header.to_h,
    elapsed: elapsed
  }
end

sitemap_routes = responses.fetch("/sitemap.xml").fetch(:body).scan(%r{<loc>([^<]+)</loc>}).flatten.map do |url|
  uri = URI(url)
  path = uri.path.empty? ? "/" : uri.path
  path
rescue URI::InvalidURIError
  nil
end.compact.uniq.sort

sitemap_routes.each do |route|
  next if responses.key?(route)

  response, elapsed = fetch("#{base_url}#{route}")
  responses[route] = {
    response: response,
    body: response.body.to_s,
    headers: response.each_header.to_h,
    elapsed: elapsed
  }
end

sitemap_route_failures = []
sitemap_routes.each do |route|
  item = responses.fetch(route)
  next if item.fetch(:response).code.to_i == 200 && item.fetch(:body).bytesize.positive?

  sitemap_route_failures << {
    "route" => route,
    "status" => item.fetch(:response).code.to_i,
    "bytes" => item.fetch(:body).bytesize,
    "elapsed_ms" => (item.fetch(:elapsed) * 1000).round,
  }
end
check(
  checks,
  "sitemap_live_routes",
  sitemap_routes.length >= 18 && sitemap_route_failures.empty?,
  "Every URL listed in the live sitemap returns non-empty HTTP 200 content.",
  {
    "route_count" => sitemap_routes.length,
    "failures" => sitemap_route_failures,
  },
)

root = responses.fetch("/")
root_body = root.fetch(:body)
root_text = root_body.dup.force_encoding("UTF-8")
root_headers = root.fetch(:headers)
styles = responses.fetch("/styles.css")
styles_text = styles.fetch(:body).dup.force_encoding("UTF-8")
site_js = responses.fetch("/site.js")
privacy = responses.fetch("/privacy/")
privacy_text = privacy.fetch(:body).dup.force_encoding("UTF-8")
robots = responses.fetch("/robots.txt")
sitemap = responses.fetch("/sitemap.xml")
rw = responses.fetch("/rw/")
rw_text = rw.fetch(:body).dup.force_encoding("UTF-8")
fr = responses.fetch("/fr/")
fr_text = fr.fetch(:body).dup.force_encoding("UTF-8")

check(
  checks,
  "no_noindex",
  !root_headers.fetch("x-robots-tag", "").downcase.include?("noindex") && !root_body.downcase.include?("noindex"),
  "Live root has no noindex marker.",
  { "x_robots_tag" => root_headers["x-robots-tag"] },
)

check(
  checks,
  "security_headers",
  ["content-security-policy", "x-content-type-options", "referrer-policy"].all? { |header| root_headers.key?(header) },
  "Live root has required security headers.",
  root_headers.select { |key, _| ["content-security-policy", "x-content-type-options", "referrer-policy"].include?(key) },
)

check(
  checks,
  "cache_policy",
  root_headers.fetch("cache-control", "").include?("public") && !root_headers.fetch("cache-control", "").include?("no-store"),
  "Live root cache policy is public and avoids no-store.",
  { "cache_control" => root_headers["cache-control"], "cf_cache_status" => root_headers["cf-cache-status"] },
)

flutter_markers = ["flutter_bootstrap", "flutter-view", "main.dart.js", "canvaskit", ".wasm"]
found_flutter = flutter_markers.select { |marker| root_body.include?(marker) }
check(
  checks,
  "no_flutter_critical_path",
  found_flutter.empty?,
  "Live root has no Flutter/CanvasKit/WASM critical-path markers.",
  { "found" => found_flutter },
)

json_ld_scripts, json_ld_types, json_ld_parse_error = json_ld_types_for(root_body)
metadata_ok = root_body.include?('rel="canonical"') &&
  root_body.include?('property="og:title"') &&
  json_ld_scripts.any? &&
  json_ld_parse_error.nil? &&
  (json_ld_types.include?("Organization") || json_ld_types.include?("FinancialService")) &&
  json_ld_types.include?("SoftwareApplication")
check(
  checks,
  "metadata",
  metadata_ok,
  "Live root includes canonical, valid JSON-LD, and social metadata.",
  { "json_ld_types" => json_ld_types, "json_ld_parse_error" => json_ld_parse_error },
)

html_routes = sitemap_routes.reject { |route| route.end_with?(".xml") || route.end_with?(".txt") }
metadata_failures = []
html_routes.each do |route|
  html = responses.fetch(route).fetch(:body)
  headers = responses.fetch(route).fetch(:headers)
  scripts, types, parse_error = json_ld_types_for(html)
  expected_canonical = "#{base_url}#{route}"
  route_ok = !headers.fetch("x-robots-tag", "").downcase.include?("noindex") &&
    !html.downcase.include?("noindex") &&
    html.include?(%(<link rel="canonical" href="#{expected_canonical}">)) &&
    html.include?('property="og:title"') &&
    html.include?('property="og:description"') &&
    html.include?('name="twitter:card"') &&
    scripts.any? &&
    parse_error.nil? &&
    types.include?("Organization") &&
    types.include?("SoftwareApplication")
  unless route_ok
    metadata_failures << {
      "route" => route,
      "expected_canonical" => expected_canonical,
      "json_ld_types" => types,
      "json_ld_parse_error" => parse_error,
      "x_robots_tag" => headers["x-robots-tag"]
    }
  end
end
check(
  checks,
  "html_route_metadata",
  metadata_failures.empty?,
  "Every live HTML route has no noindex, canonical URL, social metadata, and valid JSON-LD.",
  { "failures" => metadata_failures },
)

check(
  checks,
  "self_serve_conversion",
  root_body.include?("lead-form") && root_body.include?('type="email"'),
  "Live root includes non-WhatsApp self-serve conversion path.",
)

check(
  checks,
  "hash_privacy_compatibility",
  root_body.include?("Privacy Policy and Data Deletion") && root_body.include?("site.js"),
  "Live root supports /#/privacy users with visible policy fallback and redirect script.",
)

check(
  checks,
  "policy_deletion_content",
  privacy_text.include?("Collect does not sell customer personal data") &&
    privacy_text.include?("Account deletion request") &&
    privacy_text.include?("info@ikanisa.com"),
  "Live privacy route contains deletion and support contact content.",
)

check(
  checks,
  "robots_and_sitemap",
  robots.fetch(:body).include?("Allow: /") &&
    sitemap.fetch(:body).include?("#{base_url}/credit-readiness") &&
    sitemap.fetch(:body).include?("#{base_url}/privacy") &&
    sitemap.fetch(:body).include?("#{base_url}/trust"),
  "Live robots and sitemap expose required crawl routes.",
)

sitemap_body = sitemap.fetch(:body)
sitemap_url_count = sitemap_body.scan(%r{<url>}).length
sitemap_lastmod_values = sitemap_body.scan(%r{<lastmod>([^<]+)</lastmod>}).flatten
sitemap_lastmod_ok = sitemap_url_count.positive? &&
  sitemap_lastmod_values.length == sitemap_url_count &&
  sitemap_lastmod_values.all? { |value| value.match?(/\A\d{4}-\d{2}-\d{2}\z/) }
check(
  checks,
  "sitemap_lastmod",
  sitemap_lastmod_ok,
  "Live sitemap includes ISO date lastmod for every URL.",
  {
    "url_count" => sitemap_url_count,
    "lastmod_count" => sitemap_lastmod_values.length,
    "lastmod_values" => sitemap_lastmod_values.uniq,
  },
)

first_party_asset_bytes = [
  root,
  styles,
  site_js,
  responses.fetch("/assets/brand/generated/collect_visual_group_momentum.png"),
  responses.fetch("/icons/collect.png"),
].sum { |item| item.fetch(:body).bytesize }
check(
  checks,
  "performance_budget",
  root.fetch(:elapsed) <= 1.5 &&
    root_body.bytesize <= 20_000 &&
    styles.fetch(:body).bytesize <= 30_000 &&
    site_js.fetch(:body).bytesize <= 153_600 &&
    first_party_asset_bytes <= 400_000,
  "Live root and critical first-party assets stay within public-site performance budgets.",
  {
    "root_elapsed_ms" => (root.fetch(:elapsed) * 1000).round,
    "root_html_bytes" => root_body.bytesize,
    "css_bytes" => styles.fetch(:body).bytesize,
    "js_bytes" => site_js.fetch(:body).bytesize,
    "critical_first_party_asset_bytes" => first_party_asset_bytes
  },
)

accessibility_ok = root_text.include?('<html lang="en">') &&
  root_text.include?('name="viewport"') &&
  root_text.include?('class="skip-link"') &&
  root_text.scan(/<img\b[^>]*>/i).all? { |tag| tag.include?("alt=") } &&
  root_text.scan(/<input\b[^>]*>/i).all? { |tag| tag.include?('type="hidden"') || tag.include?("aria-label=") || root_text.include?("<label>") } &&
  !root_text.scan(/<button\b[^>]*>(.*?)<\/button>/mi).any? { |label| label.join.strip.empty? } &&
  styles_text.include?(":focus-visible")
check(
  checks,
  "static_accessibility",
  accessibility_ok,
  "Live root has required static accessibility signals.",
)

localized_ok = rw_text.include?('<html lang="rw">') &&
  rw_text.include?("Kuzigama") &&
  fr_text.include?('<html lang="fr">') &&
  fr_text.include?("épargne")
check(
  checks,
  "localized_routes",
  localized_ok,
  "Live localized routes expose Kinyarwanda and French language attributes and localized copy.",
)

hreflang_targets = {
  "en" => "#{base_url}/",
  "rw" => "#{base_url}/rw/",
  "fr" => "#{base_url}/fr/",
  "x-default" => "#{base_url}/",
}
localized_hreflang_routes = {
  "/" => {
    "html" => root_text,
    "lang" => "en",
    "locale" => "en_US",
  },
  "/rw/" => {
    "html" => rw_text,
    "lang" => "rw",
    "locale" => "rw_RW",
  },
  "/fr/" => {
    "html" => fr_text,
    "lang" => "fr",
    "locale" => "fr_FR",
  },
}
hreflang_failures = []
localized_hreflang_routes.each do |route, data|
  html = data.fetch("html")
  missing = []
  missing << "html_lang" unless html.include?(%(<html lang="#{data.fetch("lang")}">))
  missing << "og_locale" unless html.include?(%(property="og:locale" content="#{data.fetch("locale")}"))
  hreflang_targets.each do |code, href|
    missing << "hreflang_#{code}" unless html.include?(%(rel="alternate" hreflang="#{code}" href="#{href}"))
  end
  next if missing.empty?

  hreflang_failures << { "route" => route, "missing" => missing }
end
check(
  checks,
  "localized_hreflang",
  hreflang_failures.empty?,
  "Live localized home routes expose reciprocal hreflang and OG locale metadata.",
  { "failures" => hreflang_failures },
)

mobile_css_ok = styles_text.include?("@media (max-width: 980px)") &&
  styles_text.include?(".site-nav.open") &&
  styles_text.include?("position: absolute") &&
  styles_text.include?("@media (max-width: 560px)") &&
  styles_text.include?("overflow: visible")
check(
  checks,
  "mobile_nav_css",
  mobile_css_ok,
  "Live CSS includes the compact mobile navigation and first-viewport responsive rules.",
)

failed = checks.count { |item| item.fetch("status") == "fail" }
payload = {
  "status" => failed.zero? ? "pass" : "fail",
  "base_url" => base_url,
  "checked_at_utc" => Time.now.utc.iso8601,
  "summary" => {
    "total" => checks.length,
    "passed" => checks.length - failed,
    "failed" => failed,
  },
  "checks" => checks,
}

if mode == "--json"
  puts JSON.pretty_generate(payload)
else
  puts "#{payload.fetch("status")} #{payload.dig("summary", "passed")}/#{payload.dig("summary", "total")} failed=#{failed}"
  checks.each do |item|
    next if item.fetch("status") == "pass"

    warn "FAIL #{item.fetch("id")}: #{item.fetch("message")} #{item.fetch("details").inspect}"
  end
end

exit(failed.zero? ? 0 : 1)
RUBY
