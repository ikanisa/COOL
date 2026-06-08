#!/usr/bin/env bash
set -euo pipefail

output_format="text"
case "${1:-}" in
  --json)
    output_format="json"
    ;;
  "")
    ;;
  *)
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${ADMIN_PWA_LIVE_URL:-}" && -f "$ROOT_DIR/docs/release/LIVE_DEPLOYMENTS.json" ]]; then
  ADMIN_PWA_LIVE_URL="$(
    ruby -r json -e 'data = JSON.parse(File.read(ARGV.fetch(0))); puts(data.dig("deployments", "admin_pwa", "url").to_s)' \
      "$ROOT_DIR/docs/release/LIVE_DEPLOYMENTS.json"
  )"
fi

ADMIN_PWA_LIVE_URL="${ADMIN_PWA_LIVE_URL:-}" ADMIN_PWA_LIVE_FIXTURE="${ADMIN_PWA_LIVE_FIXTURE:-0}" OUTPUT_FORMAT="$output_format" ruby -r json -r net/http -r uri -r time <<'RUBY'
target = ENV.fetch("ADMIN_PWA_LIVE_URL", "").strip
fixture_mode = ENV.fetch("ADMIN_PWA_LIVE_FIXTURE", "0") == "1"
output_format = ENV.fetch("OUTPUT_FORMAT")

def emit(result, output_format)
  if output_format == "json"
    puts JSON.pretty_generate(result)
  else
    puts "[admin-pwa-live] status=#{result.fetch("status")}"
    puts "[admin-pwa-live] url=#{result.fetch("url")}" if result["url"]
    Array(result["blockers"]).each { |blocker| warn "[admin-pwa-live][BLOCKED] #{blocker}" }
    Array(result["failures"]).each { |failure| warn "[admin-pwa-live][FAIL] #{failure}" }
  end
end

if target.empty?
  result = {
    "generated_at" => Time.now.utc.iso8601,
    "status" => "blocked",
    "fixture_mode" => fixture_mode,
    "url" => nil,
    "blocker_keys" => ["admin_pwa_live_url_missing"],
    "failure_keys" => [],
    "blockers" => ["ADMIN_PWA_LIVE_URL is required to prove deployed Admin PWA readiness."],
    "failures" => [],
    "secret_handling" => "This gate records response metadata only; it must not print credentials, cookies, or tokens."
  }
  emit(result, output_format)
  exit 99
end

begin
  base = URI.parse(target)
rescue URI::InvalidURIError => error
  result = {
    "generated_at" => Time.now.utc.iso8601,
    "status" => "fail",
    "fixture_mode" => fixture_mode,
    "url" => target,
    "blocker_keys" => [],
    "failure_keys" => ["admin_pwa_live_url_invalid"],
    "blockers" => [],
    "failures" => ["ADMIN_PWA_LIVE_URL is not a valid URL: #{error.message}"],
    "secret_handling" => "This gate records response metadata only; it must not print credentials, cookies, or tokens."
  }
  emit(result, output_format)
  exit 1
end

failures = []
requests = {}

loopback_hosts = ["127.0.0.1", "::1", "localhost"]
fixture_loopback_http = fixture_mode && base.is_a?(URI::HTTP) && loopback_hosts.include?(base.host)

if fixture_mode && !loopback_hosts.include?(base.host)
  failures << "Admin PWA live fixture mode may only target localhost or loopback."
end

unless base.is_a?(URI::HTTPS) || fixture_loopback_http
  failures << "Admin PWA live URL must use HTTPS."
end

def join_uri(base, path)
  uri = base.dup
  uri.path = path
  uri.query = nil
  uri.fragment = nil
  uri
end

def fetch(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 8
  http.read_timeout = 12
  request = Net::HTTP::Get.new(uri)
  request["User-Agent"] = "CollectAdminPwaLiveGate/1.0"
  response = http.request(request)
  {
    "url" => uri.to_s,
    "code" => response.code.to_i,
    "headers" => response.each_header.to_h,
    "body" => response.body.to_s
  }
rescue StandardError => error
  {
    "url" => uri.to_s,
    "code" => nil,
    "headers" => {},
    "body" => "",
    "error" => error.message
  }
end

def parse_json(text)
  JSON.parse(text)
rescue JSON::ParserError => error
  { "_json_error" => error.message }
end

def header_includes?(headers, name, expected)
  headers.fetch(name, "").downcase.include?(expected.downcase)
end

{
  "index" => "/",
  "flutter_bootstrap" => "/flutter_bootstrap.js",
  "manifest" => "/manifest.json",
  "service_worker" => "/custom-sw.js",
  "main_bundle" => "/main.dart.js",
  "robots" => "/robots.txt"
}.each do |name, path|
  requests[name] = fetch(join_uri(base, path))
end

requests.each do |name, item|
  if item["error"]
    failures << "#{name} request failed: #{item["error"]}"
  elsif item["code"] != 200
    failures << "#{name} must return HTTP 200, got #{item["code"]}."
  end
end

index_headers = requests.dig("index", "headers") || {}
index_body = requests.dig("index", "body").to_s
bootstrap_body = requests.dig("flutter_bootstrap", "body").to_s
manifest_body = requests.dig("manifest", "body").to_s
manifest = parse_json(manifest_body)
sw_body = requests.dig("service_worker", "body").to_s
robots_body = requests.dig("robots", "body").to_s
bundle_headers = requests.dig("main_bundle", "headers") || {}
bootstrap_headers = requests.dig("flutter_bootstrap", "headers") || {}
sw_headers = requests.dig("service_worker", "headers") || {}
manifest_headers = requests.dig("manifest", "headers") || {}
robots_headers = requests.dig("robots", "headers") || {}

required_index_headers = {
  "x-frame-options" => "DENY",
  "x-content-type-options" => "nosniff",
  "referrer-policy" => "strict-origin-when-cross-origin",
  "x-robots-tag" => "noindex, nofollow"
}
required_index_headers.each do |name, expected|
  actual = index_headers.fetch(name, "")
  failures << "index response must include #{name}: #{expected}." unless actual.downcase.include?(expected.downcase)
end

content_type_expectations = {
  "index" => [index_headers, "text/html"],
  "flutter_bootstrap.js" => [bootstrap_headers, "javascript"],
  "manifest.json" => [manifest_headers, "json"],
  "custom-sw.js" => [sw_headers, "javascript"],
  "main.dart.js" => [bundle_headers, "javascript"],
  "robots.txt" => [robots_headers, "text/plain"]
}
content_type_expectations.each do |label, (headers, expected)|
  failures << "#{label} response Content-Type must include #{expected}." unless header_includes?(headers, "content-type", expected)
end

csp = index_headers.fetch("content-security-policy", "")
[
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval'",
  "connect-src 'self' https://*.supabase.co wss://*.supabase.co",
  "worker-src 'self'",
  "object-src 'none'",
  "frame-ancestors 'none'",
  "upgrade-insecure-requests"
].each do |directive|
  failures << "index CSP must include #{directive}." unless csp.include?(directive)
end

permissions = index_headers.fetch("permissions-policy", "")
%w[camera=() microphone=() geolocation=() payment=()].each do |directive|
  failures << "index Permissions-Policy must include #{directive}." unless permissions.include?(directive)
end

index_cache = index_headers.fetch("cache-control", "")
failures << "index response must be no-store or no-cache." unless index_cache.downcase.include?("no-store") || index_cache.downcase.include?("no-cache")
failures << "flutter_bootstrap.js response must be no-cache." unless bootstrap_headers.fetch("cache-control", "").downcase.include?("no-cache")
failures << "custom-sw.js response must be no-cache." unless sw_headers.fetch("cache-control", "").downcase.include?("no-cache")
failures << "manifest.json response must be no-cache." unless manifest_headers.fetch("cache-control", "").downcase.include?("no-cache")

bundle_cache = bundle_headers.fetch("cache-control", "").downcase
unless bundle_cache.include?("max-age=31536000") && bundle_cache.include?("immutable")
  failures << "main.dart.js response must be immutable long-cache."
end

failures << "index body must identify Collect Admin." unless index_body.include?("Collect Admin")
failures << "index body must load flutter_bootstrap.js." unless index_body.include?("flutter_bootstrap.js")
failures << "index body must not register the service worker inline under strict CSP." if index_body.include?("navigator.serviceWorker.register")
failures << "flutter_bootstrap.js must register custom-sw.js." unless bootstrap_body.include?("navigator.serviceWorker.register('custom-sw.js?v=collect-admin-")
failures << "flutter_bootstrap.js must not contain an unreplaced Admin PWA service-worker placeholder." if bootstrap_body.include?("__COLLECT_ADMIN_SW_VERSION__")
bootstrap_invocation = bootstrap_body.split("_flutter.buildConfig", 2).last || bootstrap_body
if bootstrap_invocation.include?("_coolServiceWorkerVersion") || bootstrap_invocation.include?("serviceWorkerUrl:") || bootstrap_invocation.include?("flutter_service_worker.js?v=")
  failures << "flutter_bootstrap.js must not register the Admin PWA service worker through deprecated Flutter service-worker settings."
end
if manifest["_json_error"]
  failures << "manifest.json must be valid JSON: #{manifest["_json_error"]}."
else
  expected_manifest = {
    "name" => "Collect Admin",
    "short_name" => "Collect Admin",
    "display" => "standalone",
    "start_url" => ".",
    "description" => "Collect platform operations console."
  }
  expected_manifest.each do |name, expected|
    failures << "manifest #{name} must be #{expected.inspect}." unless manifest[name] == expected
  end
  icons = Array(manifest["icons"])
  failures << "manifest icons must include icons/collect-admin.png." unless icons.any? do |icon|
    icon.is_a?(Hash) &&
      icon["src"].to_s == "icons/collect-admin.png" &&
      icon["type"].to_s == "image/png"
  end
end
service_worker_required = {
  "versioned Collect Admin cache" => "CACHE_NAME",
  "app shell cache manifest" => "CACHE_URLS",
  "precache open" => "caches.open(CACHE_NAME)",
  "install skip waiting" => "self.skipWaiting()",
  "activate clients claim" => "self.clients.claim()",
  "fetch handler" => "self.addEventListener('fetch'",
  "navigation fallback" => "request.mode === 'navigate'",
  "Admin PWA shell" => "./index.html",
  "Admin PWA bootstrap" => "./flutter_bootstrap.js",
  "Admin PWA bundle" => "./main.dart.js",
  "Admin PWA manifest" => "./manifest.json",
  "Admin PWA icon" => "./icons/collect-admin.png"
}
service_worker_required.each do |label, marker|
  failures << "custom-sw.js must include #{label}." unless sw_body.include?(marker)
end
failures << "custom-sw.js must not unregister itself." if sw_body.match?(/registration\.unregister|unregister\(\)/)
failures << "robots.txt must disallow crawler indexing." unless robots_body.include?("User-agent: *") && robots_body.include?("Disallow: /")

status = failures.empty? ? "pass" : "fail"
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "fixture_mode" => fixture_mode,
  "url" => base.to_s,
  "blocker_keys" => [],
  "failure_keys" => failures.empty? ? [] : ["admin_pwa_live_deployment"],
  "blockers" => [],
  "failures" => failures,
  "responses" => requests.transform_values do |item|
    allowed_headers = [
      "cache-control",
      "content-security-policy",
      "content-type",
      "permissions-policy",
      "referrer-policy",
      "x-content-type-options",
      "x-frame-options",
      "x-robots-tag"
    ]
    {
      "url" => item["url"],
      "code" => item["code"],
      "error" => item["error"],
      "headers" => item["headers"].select { |name, _value| allowed_headers.include?(name) }
    }
  end,
  "secret_handling" => "This gate records response metadata only; it must not print credentials, cookies, or tokens."
}

emit(result, output_format)
exit(status == "pass" ? 0 : 1)
RUBY
