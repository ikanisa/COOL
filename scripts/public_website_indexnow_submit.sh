#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
PUBLIC_URL="${PUBLIC_WEBSITE_URL:-https://collect.ikanisa.com}"
ENDPOINT="${PUBLIC_INDEXNOW_ENDPOINT:-https://api.indexnow.org/indexnow}"
EVIDENCE_PATH="${PUBLIC_INDEXNOW_EVIDENCE:-output/public_website_evidence/search-console/bing-webmaster.json}"
KEY_SOURCE="${PUBLIC_INDEXNOW_KEY_SOURCE:-content/public_website_indexnow_key.txt}"
KEY="${PUBLIC_INDEXNOW_KEY:-}"

if [[ -z "$KEY" && -f "$KEY_SOURCE" ]]; then
  KEY="$(tr -d '[:space:]' < "$KEY_SOURCE")"
fi

if [[ ! "$KEY" =~ ^[A-Za-z0-9-]{8,128}$ ]]; then
  printf 'IndexNow key is missing or invalid.\n' >&2
  exit 2
fi

PUBLIC_INDEXNOW_KEY="$KEY" ruby scripts/public_static_site_build.rb >/dev/null
PUBLIC_INDEXNOW_KEY="$KEY" scripts/public_website_indexnow_readiness.sh --json >/dev/null

mkdir -p "$(dirname "$EVIDENCE_PATH")"

PUBLIC_URL="$PUBLIC_URL" BUILD_DIR="$BUILD_DIR" KEY="$KEY" ENDPOINT="$ENDPOINT" EVIDENCE_PATH="$EVIDENCE_PATH" ruby -r json -r net/http -r rexml/document -r time -r uri <<'RUBY'
public_url = ENV.fetch("PUBLIC_URL").delete_suffix("/")
build_dir = ENV.fetch("BUILD_DIR")
key = ENV.fetch("KEY")
endpoint = ENV.fetch("ENDPOINT")
evidence_path = ENV.fetch("EVIDENCE_PATH")

doc = REXML::Document.new(File.read(File.join(build_dir, "sitemap.xml")))
urls = REXML::XPath.match(doc, "//*[local-name()='loc']").map { |node| node.text.to_s.strip }.reject(&:empty?)
host = URI(public_url).host
key_location = "#{public_url}/#{key}.txt"

payload = {
  "host" => host,
  "key" => key,
  "keyLocation" => key_location,
  "urlList" => urls,
}

uri = URI(endpoint)
request = Net::HTTP::Post.new(uri)
request["Content-Type"] = "application/json; charset=utf-8"
request.body = JSON.generate(payload)
response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
  http.request(request)
end

accepted = [200, 202].include?(response.code.to_i)
evidence = {
  "checked_at_utc" => Time.now.utc.iso8601,
  "status" => accepted ? "pass" : "fail",
  "submission" => "Bing-recommended IndexNow URL submission",
  "endpoint" => endpoint,
  "host" => host,
  "key_location" => key_location,
  "sitemap" => "#{public_url}/sitemap.xml",
  "url_count" => urls.length,
  "sample_urls" => urls.first(5),
  "http_status" => response.code.to_i,
}

File.write(evidence_path, JSON.pretty_generate(evidence) + "\n")
puts JSON.pretty_generate(evidence)
exit(accepted ? 0 : 1)
RUBY
