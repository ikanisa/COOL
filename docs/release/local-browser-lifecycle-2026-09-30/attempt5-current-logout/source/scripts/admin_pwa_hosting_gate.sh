#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ADMIN_PWA_BUILD_DIR:-$ROOT_DIR/build/web}"
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

BUILD_DIR="$BUILD_DIR" OUTPUT_FORMAT="$output_format" ruby -r json -r time <<'RUBY'
build_dir = ENV.fetch("BUILD_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")

headers_path = File.join(build_dir, "_headers")
robots_path = File.join(build_dir, "robots.txt")
failures = []

headers = File.file?(headers_path) ? File.read(headers_path) : ""
robots = File.file?(robots_path) ? File.read(robots_path) : ""

failures << "missing build/web/_headers" unless File.file?(headers_path)
failures << "missing build/web/robots.txt" unless File.file?(robots_path)

required_global_headers = {
  "X-Frame-Options" => "DENY",
  "X-Content-Type-Options" => "nosniff",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=(), usb=(), fullscreen=(self)",
  "X-Robots-Tag" => "noindex, nofollow"
}

required_global_headers.each do |name, value|
  failures << "_headers must set #{name}: #{value}" unless headers.include?("#{name}: #{value}")
end

csp_required = [
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "connect-src 'self' https://*.supabase.co wss://*.supabase.co",
  "worker-src 'self'",
  "object-src 'none'",
  "frame-ancestors 'none'",
  "upgrade-insecure-requests"
]
csp_required.each do |directive|
  failures << "_headers Content-Security-Policy must include #{directive}" unless headers.include?(directive)
end

cache_rules = {
  "/" => "Cache-Control: no-store",
  "/index.html" => "Cache-Control: no-store",
  "/flutter_bootstrap.js" => "Cache-Control: no-cache",
  "/custom-sw.js" => "Cache-Control: no-cache",
  "/manifest.json" => "Cache-Control: no-cache",
  "/main.dart.js" => "Cache-Control: public, max-age=31536000, immutable",
  "/assets/*" => "Cache-Control: public, max-age=31536000, immutable",
  "/icons/*" => "Cache-Control: public, max-age=31536000, immutable"
}

cache_rules.each do |route, rule|
  route_index = headers.index(/^#{Regexp.escape(route)}$/)
  if route_index.nil?
    failures << "_headers must include route #{route}"
    next
  end

  next_headers = headers[route_index..]
  next_route = next_headers.lines.drop(1).index { |line| line.start_with?("/") }
  route_block = next_route ? next_headers.lines.first(next_route + 1).join : next_headers
  failures << "_headers route #{route} must include #{rule}" unless route_block.include?(rule)
end

if headers.match?(/Access-Control-Allow-Origin:\s*\*/i)
  failures << "_headers must not allow wildcard cross-origin access for the Admin PWA"
end

unless robots.include?("User-agent: *") && robots.include?("Disallow: /")
  failures << "robots.txt must block crawler indexing for the private Admin PWA"
end

status = failures.empty? ? "pass" : "fail"
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "build_dir" => build_dir,
  "files" => {
    "_headers" => {
      "path" => headers_path,
      "exists" => File.file?(headers_path),
      "bytes" => File.file?(headers_path) ? File.size(headers_path) : nil
    },
    "robots.txt" => {
      "path" => robots_path,
      "exists" => File.file?(robots_path),
      "bytes" => File.file?(robots_path) ? File.size(robots_path) : nil
    }
  },
  "failure_keys" => failures.empty? ? [] : ["admin_pwa_hosting_policy"],
  "failures" => failures,
  "secret_handling" => "This gate validates static hosting policy files only; it must not print environment values or secrets."
}

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[admin-pwa-hosting] status=#{status} build_dir=#{build_dir}"
  failures.each { |failure| warn "[admin-pwa-hosting][FAIL] #{failure}" }
end

exit(status == "pass" ? 0 : 1)
RUBY
