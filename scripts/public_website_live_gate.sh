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
  "/" => ["Microsavings and group savings for daily earners", "People earn daily. Finance still works monthly."],
  "/privacy/" => ["Privacy Policy", "Your data. Your choice. Your financial journey."],
  "/terms/" => ["Terms of Use", "Clear rules for using Collect."],
  "/account-deletion/" => ["Delete Your Collect Account", "Delete your Collect account."],
  "/data-deletion/" => ["Data Deletion", "Data deletion and retention"],
  "/trust/" => ["Trust", "Security and trust"],
  "/security/" => ["Security | Collect by IKANISA", "Security, privacy and trust controls."],
  "/sitemap.xml" => ["credit-readiness", "privacy", "trust"],
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

["/styles.css", "/site.js", "/assets/runtime/collect_runtime/media/group-momentum.png", "/icons/collect.png"].each do |route|
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
  sitemap_routes.length >= 16 && sitemap_route_failures.empty?,
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
  "public_app_and_whatsapp_support_conversion",
  root_body.scan(/https:\/\/wa\.me\//).length >= 3 &&
    root_body.include?("https://play.google.com/store/apps/details?id=app.cool.mobile") &&
    root_body.include?("Get the App") &&
    root_body.include?("Create Group Saving") &&
    root_body.include?("Get in Touch") &&
    !root_body.include?("Available on Android") &&
    !root_body.include?("WhatsApp support options") &&
    !root_body.include?("Partner Inquiry") &&
    !root_body.include?("Privacy or Deletion") &&
    !root_body.include?("WhatsApp for app access") &&
    !root_body.include?("Ask for app access") &&
    !root_body.include?('type="email"') &&
    !root_body.include?('name="email"'),
  "Live root exposes public app download and lean WhatsApp support CTAs with no support panel or email form.",
)

check(
  checks,
  "source_backed_market_context",
  root_body.include?("96%") &&
    root_body.include?("85%") &&
    root_body.include?("72%") &&
    root_body.include?("24%"),
  "Live root presents public market figures.",
)

check(
  checks,
  "hash_privacy_compatibility",
    root_body.include?("site.js") &&
    site_js.fetch(:body).include?("window.location.hash === '#/privacy'") &&
    privacy.fetch(:response).code.to_i == 200 &&
    privacy_text.include?("Privacy Policy"),
  "Live root supports /#/privacy users by redirecting to the canonical privacy route.",
)

check(
  checks,
  "policy_deletion_content",
  privacy_text.include?("We do not sell personal data") &&
    privacy_text.include?("Account deletion and data deletion") &&
    privacy_text.include?("info@ikanisa.com") &&
    !privacy_text.match?(/\b(?:privacy|support|complaints|partnerships)@ikanisa\.com\b/) &&
    !privacy_text.match?(/\[[A-Za-z][A-Za-z ]+\]/),
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
  responses.fetch("/assets/runtime/collect_runtime/media/group-momentum.png"),
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

localized_live_markers = {
  "sitemap_rw" => sitemap.fetch(:body).include?("#{base_url}/rw/"),
  "sitemap_fr" => sitemap.fetch(:body).include?("#{base_url}/fr/diaspora/"),
  "root_hreflang_rw" => root_text.include?('hreflang="rw"'),
  "root_hreflang_fr" => root_text.include?('hreflang="fr"'),
}
english_only_ok = root_text.include?('<html lang="en">') &&
  root_text.include?('property="og:locale" content="en_US"') &&
  localized_live_markers.values.none?
check(
  checks,
  "english_only_public_site",
  english_only_ok,
  "Live public site is English-only until approved localized copy exists.",
  { "localized_live_markers" => localized_live_markers.select { |_key, value| value } },
)

check(
  checks,
  "consistent_ctas_no_faq_or_proof",
  root_body.scan(">Get the App<").length >= 2 &&
    root_body.scan(">Create Group Saving<").length >= 2 &&
    root_body.scan(">Get in Touch<").length >= 2 &&
    !root_text.include?("Questions visitors ask") &&
    !root_body.include?("faq-section") &&
    !root_text.include?("What Collect can prove publicly") &&
    !root_text.include?("Available on Android") &&
    !root_text.include?("thousands of users") &&
    !root_text.include?("approved partner names"),
  "Live root uses the consistent CTA trio and omits FAQ, proof and availability labels.",
)

mobile_css_ok = styles_text.match?(/@media\s*\(\s*max-width\s*:\s*980px\s*\)/) &&
  styles_text.include?(".site-nav.open") &&
  styles_text.match?(/position\s*:\s*absolute/) &&
  styles_text.match?(/@media\s*\(\s*max-width\s*:\s*560px\s*\)/) &&
  styles_text.match?(/overflow\s*:\s*visible/)
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
