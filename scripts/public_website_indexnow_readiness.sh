#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
PUBLIC_URL="${PUBLIC_WEBSITE_URL:-https://collect.ikanisa.com}"
MODE="${1:-}"

ruby -r json -r uri -r rexml/document -r time - "$BUILD_DIR" "$PUBLIC_URL" "$MODE" <<'RUBY'
build_dir = ARGV.fetch(0)
public_url = ARGV.fetch(1).delete_suffix("/")
mode = ARGV.fetch(2)

key = ENV.fetch("PUBLIC_INDEXNOW_KEY", "").strip
key_valid = key.match?(/\A[A-Za-z0-9-]{8,128}\z/)
key_path = key.empty? ? nil : File.join(build_dir, "#{key}.txt")
key_file_valid = key_path && File.file?(key_path) && File.read(key_path).strip == key

sitemap_path = File.join(build_dir, "sitemap.xml")
urls = []
if File.file?(sitemap_path)
  doc = REXML::Document.new(File.read(sitemap_path))
  REXML::XPath.each(doc, "//*[local-name()='loc']") { |node| urls << node.text.to_s.strip }
end

same_host_urls = urls.all? do |url|
  uri = URI(url)
  uri.scheme == "https" && "#{uri.scheme}://#{uri.host}" == public_url
rescue URI::InvalidURIError
  false
end

payload = {
  "checked_at_utc" => Time.now.utc.iso8601,
  "status" => key.empty? ? "owner_key_not_provided" : (key_valid && key_file_valid && same_host_urls ? "ready" : "fail"),
  "public_url" => public_url,
  "build_dir" => build_dir,
  "key_provided" => !key.empty?,
  "key_valid" => key_valid,
  "key_file" => key.empty? ? nil : "#{key}.txt",
  "key_file_valid" => key_file_valid,
  "key_location" => key.empty? ? nil : "#{public_url}/#{key}.txt",
  "url_count" => urls.length,
  "same_host_urls" => same_host_urls,
  "sample_urls" => urls.first(5),
  "not_submitted_by_codex" => true,
  "submission_boundary" => "Do not submit IndexNow URLs without explicit recorded owner approval.",
}

if mode == "--json"
  puts JSON.pretty_generate(payload)
else
  puts "#{payload.fetch("status")} key_provided=#{payload.fetch("key_provided")} urls=#{payload.fetch("url_count")} same_host=#{payload.fetch("same_host_urls")}"
end

exit(payload.fetch("status") == "fail" ? 1 : 0)
RUBY
