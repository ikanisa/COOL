#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
MODE="${1:-}"

ruby -r json -r uri -r time -r cgi -r digest - "$BUILD_DIR" "$MODE" <<'RUBY'
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

def tag_text(html, tag)
  html[%r{<#{tag}\b[^>]*>(.*?)</#{tag}>}m, 1].to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
end

def css_hex_vars(stylesheet)
  stylesheet.scan(/--([a-z0-9-]+):\s*(#[0-9a-fA-F]{6})/).to_h
end

def srgb(value)
  value /= 255.0
  value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
end

def luminance(hex)
  red, green, blue = hex.delete("#").scan(/../).map { |pair| pair.to_i(16) }
  0.2126 * srgb(red) + 0.7152 * srgb(green) + 0.0722 * srgb(blue)
end

def contrast_ratio(foreground, background)
  lighter, darker = [luminance(foreground), luminance(background)].sort.reverse
  ((lighter + 0.05) / (darker + 0.05)).round(2)
end

headers_path = File.join(build_dir, "_headers")
headers = read(headers_path)
root_index = route_index(build_dir, "/")
root_html = read(root_index)
robots_path = File.join(build_dir, "robots.txt")
robots = read(robots_path)
sitemap_path = File.join(build_dir, "sitemap.xml")
sitemap = read(sitemap_path)
manifest_path = File.join(build_dir, "manifest.json")
manifest_text = read(manifest_path)
collect_icon_path = File.join(build_dir, "icons", "collect.png")
stylesheet = read(File.join(build_dir, "styles.css")) + "\n" + read(File.join(build_dir, "sections.css"))
design_contract_path = File.join(Dir.pwd, "DESIGN.md")

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

group_share_path = File.join(build_dir, "c", "index.html")
app_share_path = File.join(build_dir, "app", "index.html")
redirects_path = File.join(build_dir, "_redirects")
group_share_html = read(group_share_path)
app_share_html = read(app_share_path)
redirects = read(redirects_path)
share_routes_ok =
  group_share_html.include?("Open this Collect group") &&
  group_share_html.include?('data-share-landing="group"') &&
  group_share_html.include?("collect://group/shared-group") &&
  group_share_html.include?("Expired, revoked or invalid links cannot join a group.") &&
  group_share_html.include?('name="robots" content="noindex, nofollow"') &&
  app_share_html.include?("Open Collect") &&
  app_share_html.include?('data-share-landing="app"') &&
  app_share_html.include?("collect://app") &&
  redirects.include?("/c/* /c/index.html 200") &&
  redirects.include?("/invite/* /app/index.html 200")
check(
  checks,
  "native_share_link_fallbacks",
  pass_if(share_routes_ok),
  share_routes_ok ? "Group and app share URLs have native-open and public-web fallbacks." : "Group or app share-link fallback output is incomplete.",
  "group_path" => group_share_path,
  "app_path" => app_share_path,
  "redirects_path" => redirects_path
)

retired_routes = ["/impact/", "/rw/", "/rw/group-savings/", "/rw/community-groups/", "/subprocessors/", "/privacy-request/", "/cookies/"]
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

rw_route_files = Dir.glob(File.join(build_dir, "rw", "**", "index.html"))
french_route_files = Dir.glob(File.join(build_dir, "fr", "**", "index.html"))
english_only_decision_ok = rw_route_files.empty? &&
  french_route_files.empty? &&
  root_html.include?('<html lang="en">') &&
  root_html.include?('property="og:locale" content="en_US"') &&
  root_html.include?('hreflang="x-default"') &&
  root_html.include?('hreflang="en"') &&
  !root_html.include?('hreflang="rw"') &&
  !root_html.include?('hreflang="fr"') &&
  !root_html.include?('class="language-switcher"')
check(
  checks,
  "english_only_language_decision",
  pass_if(english_only_decision_ok),
  english_only_decision_ok ? "English is the only published language; no unsupported language route or switcher is emitted." : "The English-only product decision is incomplete or an unsupported language route/switcher remains.",
  "rw_route_files" => rw_route_files,
  "french_route_files" => french_route_files
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

official_asset_hashes = {
  collect_icon_path => "c6942d8bac7e860df1993e977277a47121340666b3f44a4f7cff63e079614209",
}
official_asset_hash_failures = official_asset_hashes.reject do |path, expected_hash|
  File.file?(path) && Digest::SHA256.file(path).hexdigest == expected_hash
end
brand_assets_match_baseline = official_asset_hash_failures.empty? &&
  root_html.include?('<link rel="icon" href="/icons/collect.png" type="image/png">') &&
  root_html.include?('<img src="/icons/collect.png" alt="" width="42" height="42">') &&
  root_html.include?('<meta property="og:image" content="https://collect.ikanisa.com/icons/collect.png">') &&
  !root_html.include?('class="brand-mark"') &&
  manifest_text.include?('"src": "/icons/collect.png"') &&
  manifest_text.include?('"sizes": "512x512"') &&
  manifest_text.include?('"type": "image/png"')
check(
  checks,
  "pre_audit_brand_assets",
  pass_if(brand_assets_match_baseline),
  brand_assets_match_baseline ? "Official header logo, PNG favicon, social image, and manifest icon match the governed immutable asset hash." : "A governed website brand asset differs from its immutable hash.",
  "path" => collect_icon_path,
  "bytes" => file_size(collect_icon_path),
  "hash_failures" => official_asset_hash_failures
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
retired_sitemap_paths = ["/impact", "/rw/", "/rw/group-savings", "/rw/community-groups", "/subprocessors", "/privacy-request", "/cookies"]
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
  root_html.include?("Create Group Saving") &&
  root_html.include?("Get in Touch") &&
  root_html.include?('aria-label="Get Collect by IKANISA for Android on Google Play"') &&
  !root_html.include?("WhatsApp support options") &&
  !root_html.include?("Partner Inquiry") &&
  !root_html.include?("Privacy or Deletion") &&
  !root_html.include?("WhatsApp for app access") &&
  !root_html.include?("Ask for app access") &&
  !root_html.include?('type="email"') &&
  !root_html.include?('name="email"')
check(
  checks,
  "public_app_and_whatsapp_support_conversion",
  pass_if(public_app_and_whatsapp_support),
  public_app_and_whatsapp_support ? "Root exposes public app download and lean WhatsApp support CTAs with no support panel or email form." : "Root support path is missing public app download, WhatsApp support CTA, or still exposes wrong support content.",
  "whatsapp_link_count" => whatsapp_links
)

privacy_semantic_links = {
  "/subprocessors/" => ["/subprocessors", "View subprocessor information"],
  "/privacy-request/" => ["/privacy-request", "Submit a privacy request"],
  "/account-deletion/" => ["/account-deletion", "Open the account-deletion page"],
  "/cookies/" => ["/cookies", "Read the cookie and website technology notice"],
}
missing_privacy_links = privacy_semantic_links.reject do |href, (visible_text, accessible_label)|
  privacy_text.match?(%r{<a[^>]+href="#{Regexp.escape(href)}"[^>]+aria-label="#{Regexp.escape(accessible_label)}"[^>]*>#{Regexp.escape(visible_text)}</a>})
end
semantic_privacy_links_ok = missing_privacy_links.empty?
check(
  checks,
  "privacy_semantic_links",
  pass_if(semantic_privacy_links_ok),
  semantic_privacy_links_ok ? "Privacy policy preserves baseline visible copy while exposing accessible destination links." : "Privacy policy changed baseline reference copy or is missing an accessible destination link.",
  "missing_links" => missing_privacy_links
)

all_html_paths = Dir.glob(File.join(build_dir, "**", "*.html")).select { |path| File.file?(path) }
stray_brace_files = all_html_paths.select do |path|
  read(path).lines.any? { |line| line.match?(/\A\s*}\s*\z/) }
end
check(
  checks,
  "no_stray_template_brace",
  pass_if(stray_brace_files.empty?),
  stray_brace_files.empty? ? "Generated public HTML has no visible standalone template brace." : "Generated public HTML contains standalone template brace text.",
  "files" => stray_brace_files.map { |path| path.delete_prefix(build_dir + "/") }
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
  "/privacy/" => "4f5c059da1c7c87ef1a6e98cc4b2d811e16c5225a19186784e4beea26a761510",
  "/protection/" => "2ff3af315af909e6a654fe58151f2ece90b9fdc3cfcaeaf2005be1ced46ec306",
  "/security/" => "75386bfd0766d5ad2ec4bc19f635a5eba2605d3513e5ec76fd0c6597c2bff8fa",
  "/terms/" => "0789ed2e6df4d5cbb333840ef9468a7cfa3f25ba8cf01c30ad75aefc8927065c",
  "/trust/" => "5f6b11b13e3464a9d73b44a43864e0e25c04e9a62dda9b5f1cbb6e202821472a",
}
generated_routes = all_html_paths.map do |path|
  relative = path.delete_prefix(build_dir).delete_suffix("index.html")
  relative.empty? ? "/" : relative
end.reject { |route| ["/app/", "/c/"].include?(route) }.sort
content_hash_failures = baseline_content_hashes.each_with_object([]) do |(route, expected_hash), failures|
  html = read(route_index(build_dir, route)).gsub(/<script\b.*?<\/script>/mi, " ").gsub(/<style\b.*?<\/style>/mi, " ")
  visible_text = CGI.unescapeHTML(html.gsub(/<[^>]+>/, "\n")).lines.map { |line| line.gsub(/\s+/, " ").strip }.reject(&:empty?).join("\n").gsub(/© \d{4}/, "© YEAR")
  actual_hash = Digest::SHA256.hexdigest(visible_text)
  failures << { "route" => route, "expected" => expected_hash, "actual" => actual_hash } unless actual_hash == expected_hash
end
baseline_content_ok = generated_routes == baseline_content_hashes.keys.sort && content_hash_failures.empty?
check(
  checks,
  "pre_audit_content_parity",
  pass_if(baseline_content_ok),
  baseline_content_ok ? "All 16 routes match the pre-audit visible-content baseline exactly." : "Public route content differs from the pre-audit baseline.",
  "expected_routes" => baseline_content_hashes.keys.sort,
  "generated_routes" => generated_routes,
  "hash_failures" => content_hash_failures
)

trust_text = read(route_index(build_dir, "/trust/"))
trust_page_ok = trust_text.include?("How Collect protects customer information") &&
  trust_text.include?("What Collect will not do") &&
  trust_text.include?("Partner and regulated-product boundary") &&
  trust_text.include?("Customer rights and deletion support") &&
  !trust_text.include?("13. Security and trust") &&
  !trust_text.include?("9. AI and automated processing") &&
  !trust_text.include?("Recommended Trust Commitment Subject To Technical Confirmation")
check(
  checks,
  "trust_center_standalone",
  pass_if(trust_page_ok),
  trust_page_ok ? "Trust route is a standalone trust center, not a Privacy Policy duplicate." : "Trust route still duplicates numbered Privacy Policy sections or lacks trust-center content."
)

trust_sidebar_removed_ok = trust_text.include?('class="legal-layout no-sidebar"') &&
  !trust_text.include?('class="legal-sidebar"') &&
  !trust_text.include?('class="legal-toc"') &&
  !trust_text.include?("On this page") &&
  stylesheet.include?(".legal-layout.no-sidebar")
check(
  checks,
  "trust_sidebar_removed",
  pass_if(trust_sidebar_removed_ok),
  trust_sidebar_removed_ok ? "Trust route omits the legal sidebar/table-of-contents requested for deletion." : "Trust route still exposes the legal sidebar/table-of-contents or lacks the no-sidebar layout.",
  "has_no_sidebar_class" => trust_text.include?('class="legal-layout no-sidebar"'),
  "has_legal_sidebar" => trust_text.include?('class="legal-sidebar"'),
  "has_legal_toc" => trust_text.include?('class="legal-toc"')
)

privacy_text = read(route_index(build_dir, "/privacy/"))
privacy_sidebar_removed_ok = privacy_text.include?('class="legal-layout no-sidebar"') &&
  !privacy_text.include?('class="legal-sidebar"') &&
  !privacy_text.include?('class="legal-toc"') &&
  !privacy_text.include?("On this page") &&
  stylesheet.include?(".legal-layout.no-sidebar")
check(
  checks,
  "privacy_sidebar_removed",
  pass_if(privacy_sidebar_removed_ok),
  privacy_sidebar_removed_ok ? "Privacy route omits the legal sidebar/table-of-contents requested for deletion." : "Privacy route still exposes the legal sidebar/table-of-contents or lacks the no-sidebar layout.",
  "has_no_sidebar_class" => privacy_text.include?('class="legal-layout no-sidebar"'),
  "has_legal_sidebar" => privacy_text.include?('class="legal-sidebar"'),
  "has_legal_toc" => privacy_text.include?('class="legal-toc"')
)

terms_text = read(route_index(build_dir, "/terms/"))
terms_sidebar_removed_ok = terms_text.include?('class="legal-layout no-sidebar"') &&
  !terms_text.include?('class="legal-sidebar"') &&
  !terms_text.include?('class="legal-toc"') &&
  !terms_text.include?("On this page") &&
  stylesheet.include?(".legal-layout.no-sidebar")
check(
  checks,
  "terms_sidebar_removed",
  pass_if(terms_sidebar_removed_ok),
  terms_sidebar_removed_ok ? "Terms route omits the legal sidebar/table-of-contents requested for deletion." : "Terms route still exposes the legal sidebar/table-of-contents or lacks the no-sidebar layout.",
  "has_no_sidebar_class" => terms_text.include?('class="legal-layout no-sidebar"'),
  "has_legal_sidebar" => terms_text.include?('class="legal-sidebar"'),
  "has_legal_toc" => terms_text.include?('class="legal-toc"')
)

partners_text = read(route_index(build_dir, "/our-partners/"))
deleted_partner_phrases = [
  "Mobile app and USSD access",
  "Member and group accounts",
  "Purpose-based savings",
  "Automated ledger reconciliation",
  "National community mobilisation",
  "Monthly repayment structures often do not match informal-sector cash flow",
  "Automated split between repayment and savings",
  "Reduced branch and collection-agent dependence",
  "Up to 365 repayment data points per borrower annually",
  "More accurate portfolio monitoring",
  "regulated country partner bank",
  "Daily repayment visibility",
  "Contribution history",
  "Group accountability",
  "The addressable Rwandan diaspora market is 300,000+ people",
  "Initial eligibility and requirement mapping",
  "Business-document and financial-record checklist",
  "Contribution, savings and repayment-history packaging",
  "Gap closure before formal bank review",
  "Cleaner applicant summary for credit teams",
  "Less rework between customer, adviser and bank",
  "Statements and contribution records",
  "Group savings collateral workflow",
  "Loan application preparation",
  "Savings mobilisation support",
  "Transaction reconciliation",
  "Collections and recovery",
  "Final loan approval",
  "Regulatory reporting",
  "Collateral documentation",
  "Account and product approval",
  "Green and productive-asset finance",
  "Net interest income",
  "Lower application rework",
  "Insurance-premium financing",
  "Purpose-controlled loan disbursement",
]
deleted_partner_phrase_hits = deleted_partner_phrases.select { |phrase| partners_text.include?(phrase) }
partner_specific_content_removed_ok = deleted_partner_phrase_hits.empty? &&
  partners_text.include?("Growth Engines for Banks") &&
  partners_text.include?("What each side brings") &&
  partners_text.include?("partner-market-section") &&
  partners_text.include?("partner-operating-section") &&
  !partners_text.include?("content-grid content-grid-our-partners")
check(
  checks,
  "partners_specific_content_removed",
  pass_if(partner_specific_content_removed_ok),
  partner_specific_content_removed_ok ? "Partners sections are restored and the copied phrases are absent." : "Partners sections are missing or still render copied phrases marked for deletion.",
  "hits" => deleted_partner_phrase_hits
)

cta_hierarchy_ok = partners_text.include?("Get the App") &&
  partners_text.include?("Create Group Saving") &&
  partners_text.include?("Get in Touch") &&
  !partners_text.include?("Talk to our team") &&
  !partners_text.include?("Get Support") &&
  partners_text.include?("Get the App") &&
  !partners_text.include?("Talk to us about starting a group") &&
  !partners_text.include?(">Create Group<")
footer_trust_ok = root_html.include?("<strong>Collect by IKANISA</strong>") &&
  root_html.include?("IKANISA Ltd.") &&
  root_html.include?("Support:") &&
  root_html.include?("info@ikanisa.com") &&
  root_html.match?(/<a class="whatsapp-contact" href="https:\/\/wa\.me\/250795588248\?text=[^"]+">/) &&
  root_html.include?('<span class="sr-only">WhatsApp</span>') &&
  !root_html.include?("whatsapp-mark") &&
  !root_html.include?("· WhatsApp") &&
  !root_html.include?("No financial institution is presented on this website as a live Collect partner") &&
  root_html.include?("©")
check(
  checks,
  "cta_and_footer_trust_hierarchy",
  pass_if(cta_hierarchy_ok && footer_trust_ok),
  cta_hierarchy_ok && footer_trust_ok ? "CTA hierarchy and footer trust signals match the current public-site audit fixes." : "CTA hierarchy or footer trust signals are incomplete.",
  "cta_hierarchy_ok" => cta_hierarchy_ok,
  "footer_trust_ok" => footer_trust_ok
)

cta_routes = ["/", "/group-savings/", "/diaspora/", "/insurance/", "/craas/", "/community-groups/", "/our-partners/", "/trust/"]
cta_failures = cta_routes.reject do |route|
  html = read(route_index(build_dir, route))
  File.file?(route_index(build_dir, route)) &&
    html.scan(">Get the App<").length >= 2 &&
    html.scan(">Create Group Saving<").length >= 2 &&
    html.scan(">Get in Touch<").length >= 2 &&
    html.scan(%r{class="[^"]*cta-group[^"]*" href="#{Regexp.escape(app_download_url)}"}).length >= 2 &&
    !html.include?("faq-section") &&
    !html.include?("Questions visitors ask")
end
check(
  checks,
  "consistent_ctas_without_disclaimer_labels",
  pass_if(cta_failures.empty?),
  cta_failures.empty? ? "CTA trio is consistent without redundant availability labels." : "CTA trio is incomplete on one or more routes.",
  "failures" => cta_failures
)

partner_status_disclaimer_absent = !partners_text.include?("Current public status") &&
  !partners_text.include?("No institution is presented here as a live Collect partner yet.") &&
  !partners_text.include?("No financial institution is presented on this website as a live Collect partner yet.") &&
  !partners_text.include?("Partner names, regulators, and licence references will be published only after") &&
  !partners_text.include?("It is not presented here as a bank, deposit taker, lender or insurer") &&
  !root_html.include?("No financial institution is presented on this website as a live Collect partner until")
public_evidence_disclaimer_absent = [root_html, partners_text].all? do |html|
  !html.include?("Evidence boundary") &&
    !html.include?("Public evidence and market context") &&
    !html.include?("Collect-specific traction figures and named institutional partnerships are not yet published")
end
fee_disclaimer_absent = !root_html.include?("Fee clarity") &&
  !root_html.include?("How Collect makes money") &&
  !root_html.include?("When Collect describes microsavings as zero-fee")
platform_neutral_mockup_ok = stylesheet.include?(".phone-notch,.phone-status{display:none}")
check(checks, "partner_status_disclaimer_absent", pass_if(partner_status_disclaimer_absent), partner_status_disclaimer_absent ? "The internal partner-status disclaimer is absent from public routes." : "The removed partner-status disclaimer is still present.")
check(checks, "public_evidence_disclaimer_absent", pass_if(public_evidence_disclaimer_absent), public_evidence_disclaimer_absent ? "The redundant public-evidence disclaimer block is absent." : "The removed public-evidence disclaimer block is still present.")
check(checks, "fee_disclaimer_absent", pass_if(fee_disclaimer_absent), fee_disclaimer_absent ? "The redundant fee disclaimer block is absent." : "The removed fee disclaimer block is still present.")
check(checks, "platform_neutral_mockup", pass_if(platform_neutral_mockup_ok), platform_neutral_mockup_ok ? "Decorative device UI no longer presents iOS-specific status chrome." : "Device mockups still present iOS-specific status chrome.")

css_vars = css_hex_vars(stylesheet)
design_contract_source = read(design_contract_path)
design_contract_failures = [
  "Universal App Design Standard 2026",
  "Universal Token Model",
  "Admin Panel Standard",
  "Native Flutter TV Standard",
  "Flutter Implementation Standard",
  "native TV packaging"
].reject { |term| design_contract_source.include?(term) }
old_public_color_tokens = %w[
  #5f5ce6 #168447 #a7465c #5f67e8 #35d071 #0a8f5b
  #ff6148 #d63b2e #f59bb3 #b4576d #b04b7a
]
old_public_color_hits = old_public_color_tokens.select { |hex| stylesheet.downcase.include?(hex) }
hex_css_var_count = css_vars.values.count { |value| value.to_s.match?(/\A#[0-9A-Fa-f]{6}\z/) }
css_var_failures = []
css_var_failures << "Public CSS must expose a complete runtime color variable set without a generated token JSON." if hex_css_var_count < 8
single_source_color_contract_ok = css_var_failures.empty? &&
  design_contract_failures.empty? &&
  old_public_color_hits.empty? &&
  !stylesheet.include?("--cta-mint") &&
  !stylesheet.include?("--cta-rose")
check(
  checks,
  "single_source_color_contract",
  pass_if(single_source_color_contract_ok),
  single_source_color_contract_ok ? "Public site CSS exposes runtime color variables while DESIGN.md remains the only design authority and generated token JSON is absent." : "Public CSS variables, DESIGN.md terms, or old one-off public colors are not clean.",
  "contract_path" => design_contract_path,
  "css_var_failures" => css_var_failures,
  "hex_css_var_count" => hex_css_var_count,
  "design_contract_failures" => design_contract_failures,
  "old_public_color_hits" => old_public_color_hits
)

cta_contrast = {
  "cta-app" => contrast_ratio("#ffffff", css_vars.fetch("black", "#000000")),
  "cta-group" => contrast_ratio("#ffffff", css_vars.fetch("black", "#000000")),
  "cta-touch" => contrast_ratio("#ffffff", css_vars.fetch("black", "#000000")),
}
cta_contrast_ok = cta_contrast.values.all? { |ratio| ratio >= 4.5 } &&
  stylesheet.include?(".button.cta-app,.button.cta-group,.button.cta-touch{background:var(--black);color:#fff;border-color:var(--black)")
check(
  checks,
  "cta_white_label_contrast",
  pass_if(cta_contrast_ok),
  cta_contrast_ok ? "Approved white CTA labels meet AA contrast against CTA button fills." : "One or more white CTA labels does not meet AA contrast against its button fill.",
  "ratios" => cta_contrast
)

legal_layout_routes = ["/privacy/", "/terms/", "/account-deletion/", "/data-deletion/"]
legal_layout_failures = legal_layout_routes.reject do |route|
  html = read(route_index(build_dir, route))
  has_layout = html.match?(/class="legal-layout(?: no-sidebar)?"/)
  sidebar_required = [].include?(route)
  sidebar_ok = sidebar_required ? html.include?('class="legal-sidebar"') : true
  toc_ok = sidebar_required ? html.include?('class="legal-toc"') : true
  File.file?(route_index(build_dir, route)) &&
    has_layout &&
    sidebar_ok &&
    html.include?('class="legal-main"') &&
    html.include?('class="legal-priority"') &&
    toc_ok
end
legal_css_ok = stylesheet.include?(".legal-layout") &&
  stylesheet.include?(".legal-toc") &&
  stylesheet.include?(".legal-priority") &&
  stylesheet.include?(".legal-hero") &&
  stylesheet.include?(".legal-start-section")
check(
  checks,
  "legal_task_first_layout",
  pass_if(legal_layout_failures.empty? && legal_css_ok),
  legal_layout_failures.empty? && legal_css_ok ? "Legal and deletion routes use a calmer task-first layout with navigation aids where sections exist." : "Legal/deletion task-first layout or CSS is missing.",
  "failures" => legal_layout_failures,
  "legal_css_ok" => legal_css_ok
)

routes_for_duplicate_check = sitemap.scan(%r{<loc>https://collect\.ikanisa\.com([^<]*)</loc>}).flatten
route_identity = routes_for_duplicate_check.map do |route|
  route = "/" if route.empty?
  html = read(route_index(build_dir, route))
  {
    "route" => route,
    "title" => tag_text(html, "title"),
    "h1" => tag_text(html, "h1"),
  }
end
duplicate_titles = route_identity.group_by { |item| item["title"] }.select { |title, items| !title.empty? && items.length > 1 }
duplicate_h1s = route_identity.group_by { |item| item["h1"] }.select { |h1, items| !h1.empty? && items.length > 1 }
alias_identity_ok = duplicate_titles.empty? && duplicate_h1s.empty? &&
  read(route_index(build_dir, "/protection/")).include?("Protection support for daily earners.") &&
  read(route_index(build_dir, "/credit-readiness/")).include?("Credit-readiness support for bank-ready files.") &&
  read(route_index(build_dir, "/partners/")).include?("Partner operating model for Collect.") &&
  read(route_index(build_dir, "/security/")).include?("Security, privacy and trust controls.")
check(
  checks,
  "alias_route_identity",
  pass_if(alias_identity_ok),
  alias_identity_ok ? "Alias routes have deliberate unique title/H1 identities." : "Alias routes still duplicate title/H1 identity or lack explicit differentiation.",
  "duplicate_titles" => duplicate_titles.transform_values { |items| items.map { |item| item["route"] } },
  "duplicate_h1s" => duplicate_h1s.transform_values { |items| items.map { |item| item["route"] } }
)

mobile_hero_css_ok = stylesheet.match?(/max-height:306px/) &&
  stylesheet.match?(/scale\(\.49\)/) &&
  stylesheet.match?(/route-craas \.hero-device[^}]*max-height:356px/) &&
  stylesheet.match?(/route-community-groups \.hero-device[^}]*max-height:356px/) &&
  stylesheet.match?(/route-craas \.phone-shell[^}]*scale\(\.56\)/) &&
  stylesheet.include?(".legal-page .hero-actions .button") &&
  stylesheet.match?(/\.site-footer a\{[^}]*min-height:40px/) &&
  stylesheet.match?(/\.site-footer a\{[^}]*min-height:44px[^}]*background:rgba\(250,248,245,\.06\)/)
route_class_ok = route_identity.all? do |item|
  read(route_index(build_dir, item["route"])).include?(%(<body class="route-))
end
route_variation_ok = root_html.include?('class="route-home"') &&
  read(route_index(build_dir, "/diaspora/")).include?("content-grid-diaspora") &&
  read(route_index(build_dir, "/craas/")).include?("content-grid-craas") &&
  read(route_index(build_dir, "/community-groups/")).include?("content-grid-community-groups") &&
  stylesheet.include?(".content-grid-diaspora") &&
  stylesheet.include?(".content-grid-craas") &&
  stylesheet.include?(".content-grid-insurance") &&
  stylesheet.include?(".content-grid-community-groups")
compact_card_css_ok = stylesheet.match?(/\.use-case-grid\{[^}]*grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/) &&
  stylesheet.match?(/\.problem-list\.compact\{grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/) &&
  stylesheet.match?(/\.supported-groups-grid\{display:grid;grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/) &&
  stylesheet.include?(".supported-group-index") &&
  stylesheet.include?(".supported-group-card p") &&
  stylesheet.match?(/\.story-grid\{display:grid;grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/) &&
  stylesheet.match?(/\.partner-engine-grid\{display:grid;grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/) &&
  stylesheet.match?(/\.problem-list\.compact,.use-case-grid,.craas-service-grid\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/) &&
  stylesheet.include?(".problem-list.compact article:nth-child(5n+1)") &&
  stylesheet.include?(".use-case-grid article:nth-child(5n+5)") &&
  stylesheet.include?(".craas-service-grid article:nth-child(5n+5)") &&
  stylesheet.include?(".infographic-step:nth-child(4n+1)") &&
  stylesheet.include?(".story-grid article:nth-child(4n+4)") &&
  stylesheet.include?(".content-grid .section-card:nth-of-type(4n+1)") &&
  stylesheet.include?(".journey-rail article:nth-child(5n+5)") &&
  stylesheet.include?(".insurance-step-grid article:nth-child(5n+5)") &&
  stylesheet.include?(".partner-engine-grid article:nth-child(4n+4)") &&
  stylesheet.include?("background:var(--black)") &&
  stylesheet.match?(/\.content-grid,.infographic-grid,.supported-groups-grid,.story-grid,.story-grid\.four,.story-grid\.five,.story-grid\.six,.story-grid\.problem-grid,.journey-rail,.journey-rail\.group-journey,.insurance-step-grid,.partner-metric-grid\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/) &&
  stylesheet.match?(/\.supported-groups-grid\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/) &&
  stylesheet.match?(/\.partner-engine-grid,.partner-market-grid,.partner-operating-grid\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/) &&
  !stylesheet.include?("var(--g5)") &&
  !stylesheet.include?("var(--g6)") &&
  stylesheet.include?("box-shadow:0 16px 34px rgba(37,32,68,.14)") &&
  stylesheet.include?("color:var(--white)")
check(
  checks,
  "responsive_layout_and_route_variation",
  pass_if(mobile_hero_css_ok && route_class_ok && route_variation_ok && compact_card_css_ok),
  mobile_hero_css_ok && route_class_ok && route_variation_ok && compact_card_css_ok ? "Mobile hero, footer tap targets, compact colorful card grids, and route-specific classes are present for responsive layout refinement." : "Responsive layout, compact card grid, or route-variation implementation is incomplete.",
  "mobile_hero_css_ok" => mobile_hero_css_ok,
  "route_class_ok" => route_class_ok,
  "route_variation_ok" => route_variation_ok,
  "compact_card_css_ok" => compact_card_css_ok
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

craas_text = read(route_index(build_dir, "/craas/"))
craas_bank_benefit_cleanup_ok = !craas_text.include?("Cleaner application pipeline") &&
  craas_text.include?("Less administrative rework") &&
  craas_text.include?("More consistent files")
check(
  checks,
  "craas_bank_benefit_cleanup",
  pass_if(craas_bank_benefit_cleanup_ok),
  craas_bank_benefit_cleanup_ok ? "CRaaS bank-benefit list no longer includes the deleted first bullet." : "CRaaS bank-benefit list still includes the deleted bullet or lost adjacent benefits."
)

legal_route_prefixes = %w[
  privacy terms account-deletion data-deletion trust security subprocessors privacy-request cookies
]
public_html_paths = Dir.glob(File.join(build_dir, "**", "*.html")).select { |path| File.file?(path) }.reject do |path|
  relative = path.delete_prefix(build_dir + "/")
  legal_route_prefixes.any? { |prefix| relative == "#{prefix}/index.html" }
end
banned_public_claim_patterns = {
  "consent" => /consent/i,
  "email_form_or_unapproved_contact" => /type=["']email["']|name=["']email["']|\b(?:privacy|support|complaints|partnerships)@ikanisa\.com\b/i,
  "projection_or_scenario" => /projection|scenario|estimate/i,
  "unsupported_partner_names" => /Malta|three Rwanda banks/i,
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
