#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
MODE="${1:-}"

ruby -r json -r uri -r time - "$BUILD_DIR" "$MODE" <<'RUBY'
build_dir = ARGV.fetch(0)
mode = ARGV.fetch(1)

def read(path)
  File.file?(path) ? File.read(path) : ""
end

def file_size(path)
  File.file?(path) ? File.size(path) : 0
end

def route_index(build_dir, route)
  return File.join(build_dir, "index.html") if route == "/"
  File.join(build_dir, route.delete_prefix("/").delete_suffix("/"), "index.html")
end

checks = []

def check(checks, id, status, message, details = {})
  checks << {
    "id" => id,
    "status" => status,
    "message" => message,
    "details" => details,
  }
end

def pass_if(condition)
  condition ? "pass" : "fail"
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

headers_path = File.join(build_dir, "_headers")
headers = read(headers_path)
root_index = route_index(build_dir, "/")
root_html = read(root_index)
robots_path = File.join(build_dir, "robots.txt")
robots = read(robots_path)
sitemap_path = File.join(build_dir, "sitemap.xml")
sitemap = read(sitemap_path)

check(
  checks,
  "build_dir_exists",
  pass_if(Dir.exist?(build_dir)),
  Dir.exist?(build_dir) ? "Public build directory exists." : "Missing public build directory.",
  "build_dir" => build_dir
)

required_routes = {
  "/" => ["Microsavings and group savings for daily earners", "Collect"],
  "/group-savings/" => ["Group savings"],
  "/diaspora/" => ["Diaspora"],
  "/privacy/" => ["Privacy Policy", "Account deletion and data deletion"],
  "/terms/" => ["Terms"],
  "/account-deletion/" => ["Account Deletion"],
  "/data-deletion/" => ["Data Deletion"],
}

alternative_routes = {
  "credit_readiness" => [["/credit-readiness/", "Credit"], ["/craas/", "Credit"]],
  "protection" => [["/protection/", "Protection"], ["/insurance/", "Insurance"]],
  "partners" => [["/partners/", "Partners"], ["/our-partners/", "Partners"]],
  "trust" => [["/trust/", "Trust"], ["/security/", "Security"]],
}

required_routes.each do |route, required_text|
  path = route_index(build_dir, route)
  html = read(path)
  ok = File.file?(path) && required_text.all? { |text| html.include?(text) }
  check(
    checks,
    "route#{route.gsub(%r{[^a-zA-Z0-9]+}, "_")}",
    pass_if(ok),
    ok ? "#{route} has content-complete HTML." : "#{route} is missing or lacks required content.",
    "path" => path,
    "required_text" => required_text,
    "bytes" => file_size(path)
  )
end

retired_routes = ["/impact/"]
retired_route_files = retired_routes.select { |route| File.exist?(route_index(build_dir, route)) }
check(
  checks,
  "retired_routes_absent",
  pass_if(retired_route_files.empty?),
  retired_route_files.empty? ? "Retired public routes are absent from the generated build." : "Generated build still contains retired public routes.",
  "retired_present" => retired_route_files
)

alternative_routes.each do |id, options|
  matches = options.select do |route, text|
    html = read(route_index(build_dir, route))
    File.file?(route_index(build_dir, route)) && html.include?(text)
  end
  check(
    checks,
    "route_#{id}",
    pass_if(matches.any?),
    matches.any? ? "#{id} route is present." : "#{id} route is missing.",
    "accepted_routes" => options.map(&:first),
    "matched_routes" => matches.map(&:first)
  )
end

localized_routes = ["/rw/", "/fr/"]
localized_route_files = localized_routes.select { |route| File.file?(route_index(build_dir, route)) }
localized_markers = ["hreflang=\"rw\"", "hreflang=\"fr\"", "property=\"og:locale\" content=\"rw_RW\"", "property=\"og:locale\" content=\"fr_FR\""]
localized_metadata = localized_markers.select { |marker| root_html.include?(marker) || sitemap.include?(marker) }
english_only_ok = localized_route_files.empty? &&
  localized_metadata.empty? &&
  root_html.include?('<html lang="en">') &&
  root_html.include?('property="og:locale" content="en_US"')
check(
  checks,
  "english_only_public_site",
  pass_if(english_only_ok),
  english_only_ok ? "Public site is English-only with no localized route output." : "Public site still exposes localized route or metadata output.",
  "localized_route_files" => localized_route_files,
  "localized_metadata" => localized_metadata
)

raw_html_ok = root_html.include?("<main") &&
  root_html.include?("<h1") &&
  root_html.include?("Collect") &&
  root_html.include?("Microsavings and group savings for daily earners")
check(
  checks,
  "root_raw_html_content",
  pass_if(raw_html_ok),
  raw_html_ok ? "Root has meaningful raw HTML content." : "Root raw HTML content is insufficient.",
  "path" => root_index,
  "bytes" => file_size(root_index)
)

no_noindex = !headers.downcase.include?("noindex") &&
  !root_html.downcase.include?("noindex")
check(
  checks,
  "no_public_noindex",
  pass_if(no_noindex),
  no_noindex ? "No noindex marker found in public headers/root HTML." : "Public output contains noindex.",
  "headers_path" => headers_path
)

canonical_ok = root_html.include?('<link rel="canonical" href="https://collect.ikanisa.com/')
check(
  checks,
  "canonical_root",
  pass_if(canonical_ok),
  canonical_ok ? "Root canonical URL exists." : "Root canonical URL is missing.",
  "path" => root_index
)

og_ok = root_html.include?('property="og:title"') &&
  root_html.include?('property="og:description"') &&
  root_html.include?('property="og:image"') &&
  root_html.include?('name="twitter:card"')
check(
  checks,
  "social_metadata",
  pass_if(og_ok),
  og_ok ? "Root social metadata exists." : "Root social metadata is incomplete."
)

json_ld_scripts = root_html.scan(%r{<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>}m).flatten
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
json_ld_ok = json_ld_scripts.any? &&
  json_ld_parse_error.nil? &&
  (json_ld_types.include?("Organization") || json_ld_types.include?("FinancialService")) &&
  json_ld_types.include?("SoftwareApplication")
check(
  checks,
  "structured_data",
  pass_if(json_ld_ok),
  json_ld_ok ? "Structured data is valid JSON-LD." : "Missing or invalid Organization/FinancialService and SoftwareApplication JSON-LD.",
  "types" => json_ld_types,
  "parse_error" => json_ld_parse_error
)

robots_ok = robots.include?("User-agent: *") &&
  robots.include?("Allow: /") &&
  !robots.include?("Disallow: /")
check(
  checks,
  "robots_allow",
  pass_if(robots_ok),
  robots_ok ? "robots.txt allows public crawling." : "robots.txt does not clearly allow crawling.",
  "path" => robots_path
)

required_sitemap_paths = ["/", "/group-savings", "/diaspora", "/privacy", "/terms", "/account-deletion", "/data-deletion"]
missing_sitemap = required_sitemap_paths.reject { |path| sitemap.include?("https://collect.ikanisa.com#{path}") }
retired_sitemap_paths = ["/impact"]
retired_sitemap = retired_sitemap_paths.select { |path| sitemap.include?("https://collect.ikanisa.com#{path}") }
check(
  checks,
  "sitemap_routes",
  pass_if(missing_sitemap.empty? && retired_sitemap.empty?),
  missing_sitemap.empty? && retired_sitemap.empty? ? "Sitemap includes required public routes and excludes retired routes." : "Sitemap is missing required routes or still includes retired routes.",
  "missing" => missing_sitemap,
  "retired_present" => retired_sitemap,
  "path" => sitemap_path
)

sitemap_url_count = sitemap.scan(%r{<url>}).length
sitemap_lastmod_values = sitemap.scan(%r{<lastmod>([^<]+)</lastmod>}).flatten
sitemap_lastmod_ok = sitemap_url_count.positive? &&
  sitemap_lastmod_values.length == sitemap_url_count &&
  sitemap_lastmod_values.all? { |value| value.match?(/\A\d{4}-\d{2}-\d{2}\z/) }
check(
  checks,
  "sitemap_lastmod",
  pass_if(sitemap_lastmod_ok),
  sitemap_lastmod_ok ? "Sitemap includes ISO date lastmod for every URL." : "Sitemap is missing valid lastmod dates.",
  "url_count" => sitemap_url_count,
  "lastmod_count" => sitemap_lastmod_values.length,
  "lastmod_values" => sitemap_lastmod_values.uniq,
  "path" => sitemap_path
)

sitemap_route_failures = []
sitemap.scan(%r{<loc>([^<]+)</loc>}).flatten.each do |url|
  begin
    uri = URI(url)
  rescue URI::InvalidURIError
    sitemap_route_failures << { "url" => url, "failure" => "invalid_uri" }
    next
  end

  route = uri.path.empty? ? "/" : uri.path
  unless uri.scheme == "https" && uri.host == "collect.ikanisa.com"
    sitemap_route_failures << { "url" => url, "route" => route, "failure" => "wrong_host_or_scheme" }
    next
  end
  unless route == "/" || route.end_with?("/")
    sitemap_route_failures << { "url" => url, "route" => route, "failure" => "non_canonical_no_slash_route" }
    next
  end

  path = route_index(build_dir, route)
  html = read(path)
  scripts, types, parse_error = json_ld_types_for(html)
  route_ok = File.file?(path) &&
    html.bytesize.positive? &&
    !html.downcase.include?("noindex") &&
    html.include?(%(<link rel="canonical" href="#{url}">)) &&
    html.include?('property="og:title"') &&
    html.include?('property="og:description"') &&
    html.include?('name="twitter:card"') &&
    scripts.any? &&
    parse_error.nil? &&
    types.include?("Organization") &&
    types.include?("SoftwareApplication")

  next if route_ok

  sitemap_route_failures << {
    "url" => url,
    "route" => route,
    "path" => path,
    "file_exists" => File.file?(path),
    "bytes" => html.bytesize,
    "json_ld_types" => types,
    "json_ld_parse_error" => parse_error,
  }
end
check(
  checks,
  "sitemap_route_metadata",
  pass_if(sitemap_route_failures.empty?),
  sitemap_route_failures.empty? ? "Every sitemap route has local non-redirecting metadata-complete HTML." : "One or more sitemap routes lacks complete local metadata.",
  "failures" => sitemap_route_failures
)

assetlinks_path = File.join(build_dir, ".well-known", "assetlinks.json")
assetlinks = read(assetlinks_path)
assetlinks_ok = assetlinks.include?("app.cool.mobile") && assetlinks.include?("sha256_cert_fingerprints")
check(
  checks,
  "assetlinks",
  pass_if(assetlinks_ok),
  assetlinks_ok ? "assetlinks.json is present for Android App Links." : "assetlinks.json is missing or incomplete.",
  "path" => assetlinks_path
)

flutter_markers = [
  "flutter_bootstrap.js",
  "main.dart.js",
  "flutter-view",
  "_flutter.loader",
]
flutter_in_root = flutter_markers.select { |marker| root_html.include?(marker) }
flutter_files = Dir.glob(File.join(build_dir, "**", "*")).select do |path|
  File.file?(path) && File.basename(path).match?(/\A(main(\..*)?\.dart\.js|flutter_bootstrap\.js|flutter\.js|flutter_service_worker\.js)\z/)
end
canvaskit_files = Dir.glob(File.join(build_dir, "canvaskit", "**", "*")).select { |path| File.file?(path) }
critical_path_static = flutter_in_root.empty? && flutter_files.empty? && canvaskit_files.empty?
check(
  checks,
  "no_flutter_public_critical_path",
  pass_if(critical_path_static),
  critical_path_static ? "Public build has no Flutter/CanvasKit critical-path files." : "Public build still includes Flutter/CanvasKit critical-path files.",
  "root_markers" => flutter_in_root,
  "flutter_files" => flutter_files.map { |path| path.delete_prefix(build_dir + "/") },
  "canvaskit_file_count" => canvaskit_files.length
)

js_files = Dir.glob(File.join(build_dir, "**", "*.js")).select { |path| File.file?(path) }
js_total = js_files.sum { |path| File.size(path) }
js_budget = Integer(ENV.fetch("PUBLIC_SITE_JS_BUDGET_BYTES", "153600"))
check(
  checks,
  "js_budget",
  pass_if(js_total <= js_budget),
  js_total <= js_budget ? "JavaScript budget is within limit." : "JavaScript exceeds public-site budget.",
  "budget_bytes" => js_budget,
  "actual_bytes" => js_total,
  "files" => js_files.map { |path| [path.delete_prefix(build_dir + "/"), File.size(path)] }.to_h
)

wasm_files = Dir.glob(File.join(build_dir, "**", "*.wasm")).select { |path| File.file?(path) }
check(
  checks,
  "no_wasm",
  pass_if(wasm_files.empty?),
  wasm_files.empty? ? "No WASM files in public build." : "Public build contains WASM files.",
  "files" => wasm_files.map { |path| path.delete_prefix(build_dir + "/") }
)

headers_required = {
  "x-frame-options" => "DENY",
  "x-content-type-options" => "nosniff",
  "referrer-policy" => "strict-origin-when-cross-origin",
  "content-security-policy" => "default-src",
}
missing_headers = headers_required.reject do |key, value|
  headers.downcase.include?(key) && headers.include?(value)
end
check(
  checks,
  "security_headers",
  pass_if(missing_headers.empty?),
  missing_headers.empty? ? "Security headers are present." : "Security headers are missing or incomplete.",
  "missing" => missing_headers.keys,
  "path" => headers_path
)

bad_cache = headers.include?("Cache-Control: no-store")
immutable_asset_cache = headers.include?("max-age=31536000") && headers.include?("immutable")
cache_ok = !bad_cache && immutable_asset_cache
check(
  checks,
  "cache_policy",
  pass_if(cache_ok),
  cache_ok ? "Public cache policy avoids no-store and keeps immutable assets." : "Public cache policy is not benchmark-ready.",
  "contains_no_store" => bad_cache,
  "contains_immutable_assets" => immutable_asset_cache
)

privacy_text = read(route_index(build_dir, "/privacy/"))
policy_ok = privacy_text.include?("Privacy Policy") &&
  privacy_text.include?("We do not sell personal data") &&
  privacy_text.include?("Account deletion and data deletion") &&
  privacy_text.include?("info@ikanisa.com") &&
  !privacy_text.match?(/\b(?:privacy|support|complaints|partnerships)@ikanisa\.com\b/) &&
  !privacy_text.match?(/\[[A-Za-z][A-Za-z ]+\]/)
check(
  checks,
  "policy_content",
  pass_if(policy_ok),
  policy_ok ? "Policy route contains Play deletion contact content." : "Policy route lacks required deletion/contact content."
)

whatsapp_links = root_html.scan(/https:\/\/wa\.me\//).length
app_download_url = "https://play.google.com/store/apps/details?id=app.cool.mobile"
public_app_and_whatsapp_support = whatsapp_links >= 3 &&
  root_html.include?(app_download_url) &&
  root_html.include?("Get the App") &&
  root_html.include?("Create Group") &&
  root_html.include?("Get in Touch") &&
  !root_html.include?("WhatsApp support options") &&
  !root_html.include?("Partner Inquiry") &&
  !root_html.include?("Privacy or Deletion") &&
  !root_html.include?("WhatsApp for app access") &&
  !root_html.include?("Ask for app access") &&
  !root_html.include?("mailto:") &&
  !root_html.include?('type="email"') &&
  !root_html.include?('name="email"')
check(
  checks,
  "public_app_and_whatsapp_support_conversion",
  pass_if(public_app_and_whatsapp_support),
  public_app_and_whatsapp_support ? "Root exposes public app download and lean WhatsApp support CTAs with no support panel or email form." : "Root support path is missing public app download, WhatsApp support CTA, or still exposes wrong support content.",
  "whatsapp_link_count" => whatsapp_links
)

credit_readiness_ok = root_html.downcase.include?("credit-readiness") &&
  root_html.include?("Payments work. Financial progress still does not.") &&
  root_html.include?("Credit-readiness gap") &&
  root_html.downcase.include?("bank-ready loan files")
check(
  checks,
  "credit_readiness_explainer",
  pass_if(credit_readiness_ok),
  credit_readiness_ok ? "Credit-readiness and provider boundaries are explained on the home page." : "Missing credit-readiness or provider-boundary explanation."
)

source_backed_market_context_ok = root_html.include?("96%") &&
  root_html.include?("85%") &&
  root_html.include?("72%") &&
  root_html.include?("24%")
check(
  checks,
  "source_backed_market_context",
  pass_if(source_backed_market_context_ok),
  source_backed_market_context_ok ? "Home market figures are present." : "Home market figures are missing."
)

legal_route_prefixes = %w[
  privacy terms account-deletion data-deletion trust security
]
public_html_paths = Dir.glob(File.join(build_dir, "**", "*.html")).select { |path| File.file?(path) }.reject do |path|
  relative = path.delete_prefix(build_dir + "/")
  legal_route_prefixes.any? { |prefix| relative == "#{prefix}/index.html" }
end
banned_public_claim_patterns = {
  "consent" => /consent/i,
  "email_support" => /\bemail\b|mailto:/i,
  "projection_or_scenario" => /projection|scenario|estimate/i,
  "unsupported_partner_names" => /Revolut|Malta|three Rwanda banks/i,
  "deck_only_market_figures" => /RWF 50|150B|300K|100K|35B|3-5x|US\$0\.5B|864M|19,807B|351\.3B|169,570|7,169,324|67\.6B|26\.2%|25,000|70,000|~60%|~0%/i,
  "restricted_financial_claims" => /host[- ]bank|custody|collateral lock|collateralized|underwrit|Stripe fallback|backup payment|Android\/iOS live/i,
}
public_claim_failures = []
public_html_paths.each do |path|
  html = read(path)
  banned_public_claim_patterns.each do |id, pattern|
    next unless html.match?(pattern)

    public_claim_failures << { "file" => path.delete_prefix(build_dir + "/"), "pattern" => id }
  end
end
check(
  checks,
  "public_claim_guard",
  pass_if(public_claim_failures.empty?),
  public_claim_failures.empty? ? "Generated public HTML avoids deck-only, unsupported, email, consent, projection, and restricted financial claims." : "Generated public HTML contains banned public-claim content.",
  "failures" => public_claim_failures
)

failed = checks.select { |item| item["status"] != "pass" }
result = {
  "status" => failed.empty? ? "pass" : "fail",
  "build_dir" => build_dir,
  "checked_at_utc" => Time.now.utc.iso8601,
  "summary" => {
    "total" => checks.length,
    "passed" => checks.count { |item| item["status"] == "pass" },
    "failed" => failed.length,
  },
  "checks" => checks,
}

if mode == "--json"
  puts JSON.pretty_generate(result)
else
  puts "public_website_quality_gate=#{result["status"]}"
  checks.each do |item|
    puts "[#{item["status"].upcase}] #{item["id"]}: #{item["message"]}"
  end
end

exit(failed.empty? ? 0 : 1)
RUBY
