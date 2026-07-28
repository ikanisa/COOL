#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${PUBLIC_WEBSITE_URL:-https://collect.ikanisa.com}"
CANONICAL_URL="${PUBLIC_WEBSITE_CANONICAL_URL:-$BASE_URL}"
MODE="${1:-}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ruby -r json -r net/http -r uri -r time -r cgi -r digest - "$BASE_URL" "$CANONICAL_URL" "$MODE" <<'RUBY'
base_url = ARGV.fetch(0).delete_suffix("/")
canonical_url = ARGV.fetch(1).delete_suffix("/")
mode = ARGV.fetch(2)

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
  "/our-partners/" => ["Our Partners", "Growth Engines for Banks"],
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

["/styles.css", "/site.js", "/manifest.json", "/icons/collect.png", "/assets/brand/collect_runtime/media/group-momentum.png", "/assets/brand/collect_runtime/media/mobile-money-ussd-signal.png", "/assets/brand/collect_runtime/media/qr-share.png"].each do |route|
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

retired_language_routes = ["/rw/", "/rw/group-savings/", "/rw/community-groups/", "/fr/"]
retired_language_responses = retired_language_routes.to_h do |route|
  response, elapsed = fetch("#{base_url}#{route}")
  [route, { response: response, body: response.body.to_s, elapsed: elapsed }]
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
manifest = responses.fetch("/manifest.json")
collect_icon = responses.fetch("/icons/collect.png")
group_momentum = responses.fetch("/assets/brand/collect_runtime/media/group-momentum.png")
mobile_money = responses.fetch("/assets/brand/collect_runtime/media/mobile-money-ussd-signal.png")
qr_share = responses.fetch("/assets/brand/collect_runtime/media/qr-share.png")
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

live_official_asset_hashes = {
  collect_icon => "c6942d8bac7e860df1993e977277a47121340666b3f44a4f7cff63e079614209",
  group_momentum => "9b6278d46d68ce2c61fabef8c634ac00b8cf299008cc54ccc74bd34d480068b2",
  mobile_money => "eaa9fc831baaf3b050d6acdf3de95024098361d6cd9043543ffe159b6c1e8f66",
  qr_share => "9f67af8c93f035738bfb60f3e6964fe69c6908f5e40ae0003bbf1d609c8eafd4",
}
live_asset_hash_failures = live_official_asset_hashes.reject do |item, expected_hash|
  item.fetch(:response).code.to_i == 200 && Digest::SHA256.hexdigest(item.fetch(:body)) == expected_hash
end
brand_assets_match_baseline = live_asset_hash_failures.empty? &&
  root_body.include?('<link rel="icon" href="/icons/collect.png" type="image/png">') &&
  root_body.include?('<img src="/icons/collect.png" alt="" width="42" height="42">') &&
  root_body.include?('<meta property="og:image" content="https://collect.ikanisa.com/assets/brand/collect_runtime/media/group-momentum.png">') &&
  !root_body.include?('class="brand-mark"') &&
  manifest.fetch(:response).code.to_i == 200 &&
  manifest.fetch(:body).include?('"src": "/icons/collect.png"') &&
  manifest.fetch(:body).include?('"sizes": "512x512"')
check(
  checks,
  "pre_audit_brand_assets",
  brand_assets_match_baseline,
  "Live official logo, PNG favicon, manifest icon, and related media match immutable pre-audit deployment hashes.",
  {
    "favicon_status" => collect_icon.fetch(:response).code.to_i,
    "favicon_bytes" => collect_icon.fetch(:body).bytesize,
    "manifest_status" => manifest.fetch(:response).code.to_i,
    "asset_hash_failures" => live_asset_hash_failures.values,
  },
)

html_routes = sitemap_routes.reject { |route| route.end_with?(".xml") || route.end_with?(".txt") }
metadata_failures = []
html_routes.each do |route|
  html = responses.fetch(route).fetch(:body)
  headers = responses.fetch(route).fetch(:headers)
  scripts, types, parse_error = json_ld_types_for(html)
  expected_canonical = "#{canonical_url}#{route}"
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
  root_body.include?('aria-label="Get Collect by IKANISA for Android on Google Play"') &&
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

privacy_semantic_links = {
  "/subprocessors/" => ["/subprocessors", "View subprocessor information"],
  "/privacy-request/" => ["/privacy-request", "Submit a privacy request"],
  "/account-deletion/" => ["/account-deletion", "Open the account-deletion page"],
  "/cookies/" => ["/cookies", "Read the cookie and website technology notice"],
}
semantic_privacy_links_ok = privacy_semantic_links.all? do |href, (visible_text, accessible_label)|
  privacy_text.match?(%r{<a[^>]+href="#{Regexp.escape(href)}"[^>]+aria-label="#{Regexp.escape(accessible_label)}"[^>]*>#{Regexp.escape(visible_text)}</a>})
end
check(
  checks,
  "privacy_semantic_links",
  semantic_privacy_links_ok,
  "Live privacy policy preserves baseline visible copy while exposing accessible destination links.",
)

check(
  checks,
  "robots_and_sitemap",
  robots.fetch(:body).include?("Allow: /") &&
    sitemap.fetch(:body).include?("#{canonical_url}/credit-readiness") &&
    sitemap.fetch(:body).include?("#{canonical_url}/privacy") &&
    sitemap.fetch(:body).include?("#{canonical_url}/trust") &&
    !sitemap.fetch(:body).include?("#{canonical_url}/subprocessors") &&
    !sitemap.fetch(:body).include?("#{canonical_url}/privacy-request") &&
    !sitemap.fetch(:body).include?("#{canonical_url}/cookies") &&
    !sitemap.fetch(:body).include?("#{canonical_url}/rw/") &&
    !sitemap.fetch(:body).include?("#{canonical_url}/fr/"),
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

retired_language_failures = retired_language_responses.each_with_object([]) do |(route, item), failures|
  status = item.fetch(:response).code.to_i
  failures << { "route" => route, "status" => status } unless status == 404
end
english_only_decision_ok = retired_language_failures.empty? &&
  root_text.include?('<html lang="en">') &&
  root_text.include?('property="og:locale" content="en_US"') &&
  root_text.include?('hreflang="x-default"') &&
  root_text.include?('hreflang="en"') &&
  !root_text.include?('hreflang="rw"') &&
  !root_text.include?('hreflang="fr"') &&
  !root_text.include?('class="language-switcher"') &&
  !sitemap.fetch(:body).include?("#{canonical_url}/fr/") &&
  !sitemap.fetch(:body).include?("#{canonical_url}/rw/")
check(
  checks,
  "english_only_language_decision",
  english_only_decision_ok,
  "Live site publishes English only and does not offer Kinyarwanda or French routes.",
  { "retired_language_failures" => retired_language_failures },
)

baseline_content_hashes = {
  "/" => "b2169213424406487a483b3f63f4da7eea0fab02b84c2bfe83ff38f16394f777",
  "/account-deletion/" => "babea5394605a96828fb360183a451844391688f9d3a6076d2bc0fa33e9c7c20",
  "/community-groups/" => "6d03734da650cb4eb6fd8c61a137f510325c6a0c423adf3549cd4a8c2141faec",
  "/craas/" => "4c76feb5743537083aa26fcf1aed8aad09a41132d8d2861d213041c666bf51ae",
  "/credit-readiness/" => "2e1115e55a8b88d08ffe1b0ab4f363141e45150452ab877001988045ba05d29a",
  "/data-deletion/" => "111a293fbfe484ff5b60492f767a346fd122b248ae47f75a36324f7992181468",
  "/diaspora/" => "b9701015bcedb88f3e01763be03eb5810621351f30b563cfbaca93874f5c8572",
  "/group-savings/" => "39ba203d22c98296280dc2b18881d0925cfa000f7697ba3e0880887a1517e069",
  "/insurance/" => "45f3c5ff49d1c55f6176edd12a98239461b8f04945efbd4027c8820b17a8938f",
  "/our-partners/" => "71847e2f5bcbdf9c417538d28affcbf2abfa26b63da6a259008928d550c73a37",
  "/partners/" => "1e4e27420078ae877ab173a9030403fb50af55fc2c8d575dd16d3c04bbd3c0bd",
  "/privacy/" => "f2f3adea4445cd718dd333bb48c55d1bf1bf2b8dc20aceac352ba783b1bba362",
  "/protection/" => "2ff3af315af909e6a654fe58151f2ece90b9fdc3cfcaeaf2005be1ced46ec306",
  "/security/" => "75386bfd0766d5ad2ec4bc19f635a5eba2605d3513e5ec76fd0c6597c2bff8fa",
  "/terms/" => "0789ed2e6df4d5cbb333840ef9468a7cfa3f25ba8cf01c30ad75aefc8927065c",
  "/trust/" => "5f6b11b13e3464a9d73b44a43864e0e25c04e9a62dda9b5f1cbb6e202821472a",
}
content_hash_failures = baseline_content_hashes.each_with_object([]) do |(route, expected_hash), failures|
  html = responses.fetch(route).fetch(:body).dup.force_encoding("UTF-8").gsub(/<script\b.*?<\/script>/mi, " ").gsub(/<style\b.*?<\/style>/mi, " ")
  visible_text = CGI.unescapeHTML(html.gsub(/<[^>]+>/, "\n")).lines.map { |line| line.gsub(/\s+/, " ").strip }.reject(&:empty?).join("\n").gsub(/© \d{4}/, "© YEAR")
  actual_hash = Digest::SHA256.hexdigest(visible_text)
  failures << { "route" => route, "expected" => expected_hash, "actual" => actual_hash } unless actual_hash == expected_hash
end
audit_added_routes = ["/subprocessors/", "/privacy-request/", "/cookies/"]
audit_added_route_statuses = audit_added_routes.to_h do |route|
  response, = fetch("#{base_url}#{route}")
  [route, response.code.to_i]
end
pre_audit_content_ok = sitemap_routes.sort == baseline_content_hashes.keys.sort && content_hash_failures.empty? && audit_added_route_statuses.values.all? { |status| status == 404 }
check(
  checks,
  "pre_audit_content_parity",
  pre_audit_content_ok,
  "All live routes match the pre-audit visible-content baseline and audit-added routes are absent.",
  { "hash_failures" => content_hash_failures, "sitemap_routes" => sitemap_routes.sort, "audit_added_route_statuses" => audit_added_route_statuses },
)

check(
  checks,
  "consistent_ctas_without_disclaimer_labels",
  root_body.scan(">Get the App<").length >= 2 &&
    root_body.scan(">Create Group Saving<").length >= 2 &&
    root_body.scan(">Get in Touch<").length >= 2 &&
    !root_text.include?("Questions visitors ask") &&
    !root_body.include?("faq-section") &&
    !root_text.include?("thousands of users") &&
    !root_text.include?("approved partner names"),
  "Live root uses the consistent CTA trio without redundant availability labels.",
)

partners_text = responses.fetch("/our-partners/").fetch(:body).dup.force_encoding("UTF-8")
check(
  checks,
  "partner_status_disclaimer_absent",
  !partners_text.include?("Current public status") &&
    !partners_text.include?("No institution is presented here as a live Collect partner yet.") &&
    !partners_text.include?("No financial institution is presented on this website as a live Collect partner yet.") &&
    !partners_text.include?("Partner names, regulators, and licence references will be published only after") &&
    !partners_text.include?("It is not presented here as a bank, deposit taker, lender or insurer") &&
    !root_text.include?("No financial institution is presented on this website as a live Collect partner until"),
  "Live routes omit the removed internal partner-status disclaimer.",
)
check(
  checks,
  "redundant_disclaimer_blocks_absent",
  !root_text.include?("Currently available for Android through the official Collect by IKANISA Google Play listing") &&
    !root_text.include?("iOS availability is not currently advertised") &&
    !root_text.include?("This website is published in English only") &&
    !root_text.include?("Fee clarity") &&
    !root_text.include?("How Collect makes money") &&
    !root_text.include?("Evidence boundary") &&
    !root_text.include?("Public evidence and market context") &&
    !root_text.include?("No financial institution is presented on this website as a live Collect partner until") &&
    !partners_text.include?("Current public status") &&
    !partners_text.include?("Public evidence and market context"),
  "Live routes omit the removed availability, language, fee, and evidence disclaimer labels.",
)
check(
  checks,
  "platform_neutral_mockup",
  styles_text.include?(".phone-notch,.phone-status{display:none}"),
  "Live CSS hides iOS-specific status chrome from decorative device mockups.",
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
  "canonical_url" => canonical_url,
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
