#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${PUBLIC_WEBSITE_URL:-https://collect.ikanisa.com}"
OUT_DIR="${PUBLIC_WEBSITE_EVIDENCE_DIR:-output/public_website_evidence}"
mkdir -p "$OUT_DIR"

ruby -r json -r net/http -r uri -r time -r digest - "$BASE_URL" "$OUT_DIR" <<'RUBY'
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
  "/our-partners/",
  "/trust/",
  "/security/",
  "/sitemap.xml",
  "/robots.txt",
  "/styles.css",
  "/site.js",
  "/manifest.json",
  "/icons/collect.png",
  "/assets/brand/collect_runtime/media/group-momentum.png",
  "/assets/brand/collect_runtime/media/mobile-money-ussd-signal.png",
  "/assets/brand/collect_runtime/media/qr-share.png",
]
responses = routes.to_h { |route| [route, fetch("#{base_url}#{route}")] }
retired_language_routes = ["/rw/", "/rw/group-savings/", "/rw/community-groups/", "/fr/"]
retired_language_responses = retired_language_routes.to_h { |route| [route, fetch("#{base_url}#{route}")] }
root = responses.fetch("/")
root_body = root.fetch("body").dup.force_encoding("UTF-8")
styles_body = responses.fetch("/styles.css").fetch("body").dup.force_encoding("UTF-8")
site_js = responses.fetch("/site.js")
manifest = responses.fetch("/manifest.json")
collect_icon = responses.fetch("/icons/collect.png")
group_momentum = responses.fetch("/assets/brand/collect_runtime/media/group-momentum.png")
mobile_money = responses.fetch("/assets/brand/collect_runtime/media/mobile-money-ussd-signal.png")
qr_share = responses.fetch("/assets/brand/collect_runtime/media/qr-share.png")
privacy_body = responses.fetch("/privacy/").fetch("body").dup.force_encoding("UTF-8")
partners_body = responses.fetch("/our-partners/").fetch("body").dup.force_encoding("UTF-8")
sitemap_body = responses.fetch("/sitemap.xml").fetch("body").dup.force_encoding("UTF-8")

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
].sum { |item| item.fetch("body").bytesize }

checks = {
  "http_all_required_routes_200" => responses.reject { |route, _item| ["/styles.css", "/site.js"].include?(route) }.all? { |_route, item| item.fetch("status") == 200 },
  "root_cacheable_no_noindex" => root.dig("headers", "cache-control").to_s.include?("public") && !root.dig("headers", "x-robots-tag").to_s.downcase.include?("noindex"),
  "valid_structured_data" => json_ld_parse_error.nil? && json_ld_types.include?("Organization") && json_ld_types.include?("SoftwareApplication"),
  "seo_metadata" => root_body.include?('rel="canonical"') && root_body.include?('property="og:title"') && root_body.include?('name="twitter:card"'),
  "pre_audit_brand_assets" => collect_icon.fetch("status") == 200 && Digest::SHA256.hexdigest(collect_icon.fetch("body")) == "c6942d8bac7e860df1993e977277a47121340666b3f44a4f7cff63e079614209" &&
    group_momentum.fetch("status") == 200 && Digest::SHA256.hexdigest(group_momentum.fetch("body")) == "9b6278d46d68ce2c61fabef8c634ac00b8cf299008cc54ccc74bd34d480068b2" &&
    mobile_money.fetch("status") == 200 && Digest::SHA256.hexdigest(mobile_money.fetch("body")) == "eaa9fc831baaf3b050d6acdf3de95024098361d6cd9043543ffe159b6c1e8f66" &&
    qr_share.fetch("status") == 200 && Digest::SHA256.hexdigest(qr_share.fetch("body")) == "9f67af8c93f035738bfb60f3e6964fe69c6908f5e40ae0003bbf1d609c8eafd4" &&
    root_body.include?('<link rel="icon" href="/icons/collect.png" type="image/png">') &&
    root_body.include?('<img src="/icons/collect.png" alt="" width="42" height="42">') &&
    root_body.include?('<meta property="og:image" content="https://collect.ikanisa.com/assets/brand/collect_runtime/media/group-momentum.png">') &&
    !root_body.include?('class="brand-mark"') &&
    manifest.fetch("status") == 200 && manifest.fetch("body").include?('"src": "/icons/collect.png"') && manifest.fetch("body").include?('"sizes": "512x512"'),
  "no_flutter_or_wasm" => !root_body.match?(/flutter_bootstrap|flutter-view|main\.dart\.js|canvaskit|\.wasm/),
  "static_accessibility_signals" => root_body.include?('<html lang="en">') && root_body.include?('class="skip-link"') && root_body.scan(/<img\b[^>]*>/i).all? { |tag| tag.include?("alt=") } && styles_body.include?(":focus-visible"),
  "english_only_language_decision" => root_body.include?('<html lang="en">') &&
    root_body.include?('property="og:locale" content="en_US"') &&
    root_body.include?('hreflang="x-default"') &&
    root_body.include?('hreflang="en"') &&
    !root_body.include?('hreflang="rw"') &&
    !root_body.include?('hreflang="fr"') &&
    !root_body.include?('class="language-switcher"') &&
    retired_language_responses.values.all? { |item| item.fetch("status") == 404 } &&
    !sitemap_body.include?("#{base_url}/rw/") &&
    !sitemap_body.include?("#{base_url}/fr/"),
  "privacy_references_are_links" => {
    "/subprocessors/" => ["/subprocessors", "View subprocessor information"],
    "/privacy-request/" => ["/privacy-request", "Submit a privacy request"],
    "/account-deletion/" => ["/account-deletion", "Open the account-deletion page"],
    "/cookies/" => ["/cookies", "Read the cookie and website technology notice"],
  }.all? { |href, (visible_text, accessible_label)|
    privacy_body.match?(%r{<a[^>]+href="#{Regexp.escape(href)}"[^>]+aria-label="#{Regexp.escape(accessible_label)}"[^>]*>#{Regexp.escape(visible_text)}</a>})
  },
  "partner_status_disclaimer_absent" => !partners_body.include?("Current public status") &&
    !partners_body.include?("No institution is presented here as a live Collect partner yet.") &&
    !partners_body.include?("No financial institution is presented on this website as a live Collect partner yet.") &&
    !partners_body.include?("Partner names, regulators, and licence references will be published only after") &&
    !partners_body.include?("It is not presented here as a bank, deposit taker, lender or insurer") &&
    !root_body.include?("No financial institution is presented on this website as a live Collect partner until"),
  "redundant_disclaimer_blocks_absent" => [root_body, partners_body].all? { |body|
    !body.include?("Currently available for Android through the official Collect by IKANISA Google Play listing") &&
      !body.include?("iOS availability is not currently advertised") &&
      !body.include?("This website is published in English only") &&
      !body.include?("Fee clarity") &&
      !body.include?("How Collect makes money") &&
      !body.include?("Evidence boundary") &&
      !body.include?("Public evidence and market context") &&
      !body.include?("Current public status") &&
      !body.include?("No institution is presented here as a live Collect partner yet.")
  } && styles_body.include?(".phone-notch,.phone-status{display:none}"),
  "performance_budgets" => root.fetch("elapsed_ms") <= 1500 && root_body.bytesize <= 20_000 && styles_body.bytesize <= 30_000 && site_js.fetch("body").bytesize <= 153_600 && first_party_critical_bytes <= 400_000,
  "mobile_responsive_css" => styles_body.match?(/@media\s*\(\s*max-width\s*:\s*980px\s*\)/) && styles_body.match?(/@media\s*\(\s*max-width\s*:\s*560px\s*\)/) && styles_body.include?(".site-nav.open"),
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
