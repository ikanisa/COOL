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
  "/" => ["Credit-ready", "Collect"],
  "/group-savings/" => ["Group savings"],
  "/diaspora/" => ["Diaspora"],
  "/impact/" => ["Impact"],
  "/privacy/" => ["Privacy Policy", "Data Deletion"],
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

["/rw/", "/fr/"].each do |route|
  path = route_index(build_dir, route)
  html = read(path)
  ok = File.file?(path) && html.include?("Collect")
  check(
    checks,
    "localized#{route.gsub(%r{[^a-zA-Z0-9]+}, "_")}",
    pass_if(ok),
    ok ? "#{route} localized route exists." : "#{route} localized route is missing.",
    "path" => path
  )
end

localized_hreflang_routes = {
  "/" => {
    "lang" => "en",
    "locale" => "en_US",
  },
  "/rw/" => {
    "lang" => "rw",
    "locale" => "rw_RW",
  },
  "/fr/" => {
    "lang" => "fr",
    "locale" => "fr_FR",
  },
}
hreflang_failures = []
localized_hreflang_routes.each do |route, expected|
  html = read(route_index(build_dir, route))
  missing = []
  missing << "html_lang" unless html.include?(%(<html lang="#{expected["lang"]}">))
  missing << "og_locale" unless html.include?(%(property="og:locale" content="#{expected["locale"]}"))
  hreflang_targets = {
    "en" => "https://collect.ikanisa.com/",
    "rw" => "https://collect.ikanisa.com/rw/",
    "fr" => "https://collect.ikanisa.com/fr/",
    "x-default" => "https://collect.ikanisa.com/",
  }
  hreflang_targets.each do |code, href|
    missing << "hreflang_#{code}" unless html.include?(%(rel="alternate" hreflang="#{code}" href="#{href}"))
  end
  next if missing.empty?

  hreflang_failures << { "route" => route, "missing" => missing }
end
check(
  checks,
  "localized_hreflang",
  pass_if(hreflang_failures.empty?),
  hreflang_failures.empty? ? "Localized home routes expose reciprocal hreflang and OG locale metadata." : "Localized home route hreflang metadata is incomplete.",
  "failures" => hreflang_failures
)

raw_html_ok = root_html.include?("<main") &&
  root_html.include?("<h1") &&
  root_html.include?("Collect") &&
  root_html.include?("Credit-ready")
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

required_sitemap_paths = ["/", "/group-savings", "/diaspora", "/impact", "/privacy", "/terms", "/account-deletion", "/data-deletion"]
missing_sitemap = required_sitemap_paths.reject { |path| sitemap.include?("https://collect.ikanisa.com#{path}") }
check(
  checks,
  "sitemap_routes",
  pass_if(missing_sitemap.empty?),
  missing_sitemap.empty? ? "Sitemap includes required public routes." : "Sitemap is missing required routes.",
  "missing" => missing_sitemap,
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
policy_ok = privacy_text.include?("Account deletion") &&
  privacy_text.include?("Data deletion") &&
  privacy_text.include?("info@ikanisa.com") &&
  privacy_text.include?("+250 795 588 248")
check(
  checks,
  "policy_content",
  pass_if(policy_ok),
  policy_ok ? "Policy route contains Play deletion contact content." : "Policy route lacks required deletion/contact content."
)

self_serve_patterns = [
  "app.cool.mobile",
  "play.google.com",
  "apps.apple.com",
  "type=\"tel\"",
  "type=\"email\"",
  "name=\"phone\"",
  "name=\"email\"",
  "partner inquiry",
  "group setup",
]
whatsapp_links = root_html.scan(/https:\/\/wa\.me\//).length
self_serve = self_serve_patterns.any? { |pattern| root_html.downcase.include?(pattern.downcase) }
check(
  checks,
  "conversion_not_whatsapp_only",
  pass_if(self_serve),
  self_serve ? "Root includes a non-WhatsApp self-serve conversion path." : "Root conversion is still WhatsApp-only.",
  "whatsapp_link_count" => whatsapp_links
)

credit_readiness_ok = root_html.downcase.include?("how credit-readiness works") ||
  root_html.downcase.include?("how credit readiness works")
check(
  checks,
  "credit_readiness_explainer",
  pass_if(credit_readiness_ok),
  credit_readiness_ok ? "Credit-readiness mechanism is explained on the home page." : "Missing near-top credit-readiness explainer."
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
