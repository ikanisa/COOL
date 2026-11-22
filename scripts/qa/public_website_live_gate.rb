# frozen_string_literal: true

require 'cgi'
require 'digest'
require_relative 'public_website/checks'
require_relative 'public_website/http'
require_relative 'public_website_links'
require_relative 'public_content_contract'

include PublicWebsiteChecks
include PublicWebsiteHTTP

base_url = ARGV.fetch(0).delete_suffix("/")
canonical_url = ARGV.fetch(1).delete_suffix("/")
mode = ARGV.fetch(2)
root_dir = ARGV.fetch(3)
product_capabilities = CollectProductCapabilities.new(root_dir)
checks = []

group_fixture_code = "f0e5d2a1-9213-45cc-8e03-123456789abc"
group_route = "/c/#{group_fixture_code}"

required_routes = {
  "/" => ["Microsavings and group savings for daily earners", "People earn daily. Finance still works monthly."],
  "/privacy/" => ["Privacy Policy", "Your data. Your choice. Your financial journey."],
  "/terms/" => ["Terms of Use", "Clear rules for using Collect."],
  "/account-deletion/" => ["Delete Your Collect Account", "Delete your Collect account."],
  "/data-deletion/" => ["Data Deletion", "Data deletion and retention"],
  group_route => ["Open this Collect group", "Open in Collect"],
  "/our-partners/" => ["Our Partners"],
  "/trust/" => ["Trust", "Security and trust"],
  "/security/" => ["Security | Collect by IKANISA", "Security, privacy and trust controls."],
  "/sitemap.xml" => ["credit-readiness", "privacy", "trust"],
  "/robots.txt" => ["Allow: /", "Sitemap:"],
}

responses = {}
required_routes.each do |route, required_text|
  page = responses[route] = fetch_page("#{base_url}#{route}")
  body = page.fetch(:body)
  status = page.fetch(:response).code.to_i
  missing = required_text.reject { |text| body.include?(text) }
  check(
    checks,
    "route_#{route.gsub(%r{[^a-zA-Z0-9]+}, "_")}",
    status == 200 && missing.empty?,
    "#{route} returns live content-complete HTTP 200.",
    {
      "status" => status,
      "bytes" => body.bytesize,
      "elapsed_ms" => (page.fetch(:elapsed) * 1000).round,
      "missing_text" => missing,
    },
  )
end

# BEGIN_GROUP_SHARE_STATIC_SHELL_CHECK
# This checks response markup only; browser action, native app, and redirect query preservation need separate evidence.
group_item = responses.fetch(group_route)
group_body = group_item.fetch(:body)
group_headers = group_item.fetch(:headers)
group_shell_ok = group_item.fetch(:response).code.to_i == 200 &&
  group_headers.fetch('referrer-policy', '').strip.downcase == 'no-referrer' &&
  group_headers.fetch('cache-control', '').split(',').any? { |directive| directive.strip.downcase == 'no-store' } &&
  group_body.include?('name="robots" content="noindex, nofollow"') &&
  group_body.include?('data-share-landing="group"') &&
  group_body.include?('<button class="button primary" type="button" data-collect-open-link disabled>') &&
  group_body.include?('<button class="button ghost" type="button" data-collect-copy-link disabled>') &&
  group_body.include?('<meta name="referrer" content="no-referrer">') &&
  group_body.include?(%(<link rel="canonical" href="#{canonical_url}/c/" data-share-canonical>)) &&
  group_body.include?("<noscript>") && group_body.include?("reopen the original link") &&
  !group_body.include?("collect://group/shared-group") && !group_body.include?("data-share-code") &&
  !group_body.include?("app-argument=") && !group_body.include?(group_fixture_code)
check(checks, "group_share_static_shell", group_shell_ok,
  "Static group shell and final response protections only; browser action, actual join and redirect-chain behavior remain separate.")
# END_GROUP_SHARE_STATIC_SHELL_CHECK

(STYLESHEET_PATHS + ["/site.js", "/manifest.json", "/icons/collect.png"]).each do |route|
  responses[route] = fetch_page("#{base_url}#{route}")
end

sitemap_urls = responses.fetch("/sitemap.xml").fetch(:body).scan(%r{<loc>([^<]+)</loc>}).flatten
sitemap_routes = sitemap_urls.map do |url|
  uri = URI(url)
  path = uri.path.empty? ? "/" : uri.path
  path
rescue URI::InvalidURIError
  nil
end.compact.uniq.sort

sitemap_routes.each do |route|
  responses[route] ||= fetch_page("#{base_url}#{route}")
end

pages = responses.transform_values { |row| row.fetch(:body).dup.force_encoding("UTF-8") }
current_content = PublicContentContract.evaluate(root: root_dir, pages: pages, routes: sitemap_routes)
expected_urls = current_content.fetch('expected_routes', []).map { |route| "#{canonical_url}#{route}" }
sitemap_matches_contract = !expected_urls.empty? && expected_urls.sort == sitemap_urls.sort

retired_language_responses = RETIRED_LANGUAGE_ROUTES.to_h do |route|
  [route, fetch_page("#{base_url}#{route}")]
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
  sitemap_matches_contract && sitemap_route_failures.empty?,
  "The sitemap lists the reviewed canonical URLs, and each returns non-empty HTTP 200 content.",
  {
    "route_count" => sitemap_routes.length,
    "failures" => sitemap_route_failures,
    "matches_reviewed_urls" => sitemap_matches_contract,
  },
)

root = responses.fetch("/")
root_body = root.fetch(:body)
root_text = root_body.dup.force_encoding("UTF-8")
root_headers = root.fetch(:headers)
styles = responses.fetch("/styles.css")
stylesheets = responses.values_at(*STYLESHEET_PATHS)
styles_text = stylesheets.map { |entry| entry.fetch(:body).dup.force_encoding("UTF-8") }.join("\n")
styles_served = stylesheets_served?(stylesheets)
site_js = responses.fetch("/site.js")
manifest = responses.fetch("/manifest.json")
collect_icon = responses.fetch("/icons/collect.png")
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
}
live_asset_hash_failures = live_official_asset_hashes.reject do |item, expected_hash|
  item.fetch(:response).code.to_i == 200 && Digest::SHA256.hexdigest(item.fetch(:body)) == expected_hash
end
brand_assets_match_baseline = live_asset_hash_failures.empty? &&
  root_body.include?('<link rel="icon" href="/icons/collect.png" type="image/png">') &&
  root_body.include?('<img src="/icons/collect.png" alt="" width="42" height="42">') &&
  root_body.include?('<meta property="og:image" content="https://collect.ikanisa.com/icons/collect.png">') &&
  !root_body.include?('class="brand-mark"') &&
  manifest.fetch(:response).code.to_i == 200 &&
  manifest.fetch(:body).include?('"src": "/icons/collect.png"') &&
  manifest.fetch(:body).include?('"sizes": "512x512"')
check(
  checks,
  "pre_audit_brand_assets",
  brand_assets_match_baseline,
  "Live official logo, PNG favicon, social image, and manifest icon match the governed immutable asset hash.",
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

conversion = home_conversion_evidence(product_capabilities, root_body)
check(
  checks,
  "public_app_and_whatsapp_support_conversion",
  home_conversion_ok?(product_capabilities, root_body, conversion),
  "Live root exposes the supported app and contact actions.",
  conversion,
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

privacy_links = privacy_link_evidence(privacy_text)
check(
  checks,
  "privacy_semantic_links",
  privacy_links.values.all?(&:empty?),
  "Live privacy policy exposes clearly named links to the reviewed destinations.",
  privacy_links,
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
  *stylesheets,
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
  styles_served && styles_text.include?(":focus-visible")
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

retired_privacy_responses = RETIRED_PRIVACY_REDIRECTS.to_h do |route, _replacement|
  response, = fetch("#{base_url}#{route}", 0)
  [route, response]
end
privacy_redirects_ok = RETIRED_PRIVACY_REDIRECTS.all? do |route, replacement|
  retired_privacy_response?("#{base_url}#{route}", retired_privacy_responses.fetch(route), replacement)
end
audit_added_route_statuses = retired_privacy_responses.transform_values { |response| response.code.to_i }
pre_audit_content_ok = current_content['status'] == 'pass' && privacy_redirects_ok
check(
  checks,
  "pre_audit_content_parity",
  pre_audit_content_ok,
  "Live route copy matches the reviewed current Collect product contract and unreviewed extra routes are absent.",
  current_content.merge("sitemap_routes" => sitemap_routes.sort, "audit_added_route_statuses" => audit_added_route_statuses),
)

action_failures = route_action_failures(product_capabilities, pages)
check(
  checks,
  "consistent_ctas_without_disclaimer_labels",
  action_failures.empty? &&
    !root_text.include?("thousands of users") &&
    !root_text.include?("approved partner names"),
  "Live pages expose the reviewed capability actions.",
  {"failures" => action_failures},
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
  "authentic_app_media_structure",
  !styles_text.include?(".phone-screen") &&
    styles_text.match?(/\.app-capture img\s*\{[^}]*height:\s*auto/m) &&
    responses.values.none? { |entry| entry.fetch(:body).include?('class="phone-shell"') },
  "Live pages use proportional screenshot media and omit invented phone controls; source-image provenance is checked during the build.",
)

mobile_css_ok = styles_served && mobile_css_ready?(styles_text)
check(
  checks,
  "mobile_nav_css",
  mobile_css_ok,
  "Live CSS includes the compact mobile navigation and first-viewport responsive rules.",
)

internal_links = PublicWebsiteLinks.check(
  base_url: "#{base_url}/",
  pages: html_routes.to_h { |route| [route, responses.fetch(route).fetch(:body).dup.force_encoding('UTF-8')] },
  fetcher: lambda do |url|
    key = URI(url).request_uri
    entry = responses[key] ||= fetch_page(url)
    { status: entry.fetch(:response).code.to_i, body: entry.fetch(:body).dup.force_encoding('UTF-8'), content_type: entry.fetch(:headers).fetch('content-type', '') }
  end,
)
check(
  checks,
  "internal_hyperlink_destinations",
  internal_links.fetch(:failures).empty?,
  "Published internal hyperlinks resolve to HTTP 200 destinations and existing HTML fragments.",
  internal_links,
)

payload = check_result(checks, "base_url" => base_url, "canonical_url" => canonical_url)
failed = payload.dig("summary", "failed")

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
