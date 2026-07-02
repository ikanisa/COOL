#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
if [[ "${1:-}" == "--json" ]]; then
  output_format="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

latest_json() {
  ruby -e 'paths = Dir[ARGV[0]].sort; puts(paths.last || "")' "$1"
}

route_summary="${MOBILE_ROUTE_RENDER_SUMMARY:-$(latest_json "$ROOT_DIR/.cache/mobile_route_render_smoke/*/summary.json")}"

OUTPUT_FORMAT="$output_format" ROOT_DIR="$ROOT_DIR" ROUTE_SUMMARY="$route_summary" ruby -r json <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")
summary_path = ENV.fetch("ROUTE_SUMMARY")

def read_json(path)
  JSON.parse(File.read(path))
rescue Errno::ENOENT, JSON::ParserError
  nil
end

def png_header(path)
  bytes = File.binread(path, 33)
  signature = "\x89PNG\r\n\x1a\n".b
  valid =
    bytes.bytesize >= 33 &&
    bytes.start_with?(signature) &&
    bytes[8, 4].unpack1("N") == 13 &&
    bytes[12, 4] == "IHDR"
  {
    "valid" => valid,
    "width" => valid ? bytes[16, 4].unpack1("N") : nil,
    "height" => valid ? bytes[20, 4].unpack1("N") : nil
  }
rescue Errno::ENOENT
  {
    "valid" => false,
    "width" => nil,
    "height" => nil
  }
end

summary = read_json(summary_path)
failures = []
captures = summary ? Array(summary["captures"]) : []
viewport = summary && summary["viewport"].to_s
expected_width, expected_height = viewport.to_s.split("x", 2).map { |value| value.to_i }
evidence_dir = summary_path.to_s.empty? ? "" : File.dirname(summary_path)
evidence_root = evidence_dir.to_s.empty? ? "" : File.expand_path(evidence_dir)

failures << "mobile_route_render_summary_missing_or_invalid" unless summary
failures << "route_render_status_must_pass" unless summary && summary["status"].to_s == "pass"
failures << "viewport_must_be_390x844" unless viewport == "390x844"
failures << "route_count_must_be_at_least_30" unless captures.count >= 30
failures << "product_screen_count_must_be_at_least_27" unless summary && summary["product_screen_count"].to_i >= 27

items = captures.map do |capture|
  file = capture["path"].to_s
  expanded_file = File.expand_path(file, evidence_root)
  inside_evidence_dir = !evidence_root.empty? && expanded_file.start_with?(evidence_root + File::SEPARATOR)
  exists = inside_evidence_dir && File.file?(expanded_file)
  header = exists ? png_header(expanded_file) : {"valid" => false, "width" => nil, "height" => nil}
  bytes = exists ? File.size(expanded_file) : 0
  console_error_count = capture["console_error_count"].to_i
  item_failures = []

  item_failures << "capture_status_not_pass" unless capture["status"].to_s == "pass"
  item_failures << "outside_evidence_dir" unless inside_evidence_dir
  item_failures << "missing_file" unless exists
  item_failures << "not_png" unless header["valid"]
  item_failures << "wrong_dimensions" unless header["width"] == expected_width && header["height"] == expected_height
  item_failures << "empty_or_tiny_file" unless bytes >= 10_000
  item_failures << "console_errors_present" unless console_error_count.zero?
  item_failures << "pixel_check_failed" unless capture["distinct_rgb"].to_i >= 20 && capture["non_background_pixels"].to_i >= 1_000

  {
    "name" => capture["name"],
    "route" => capture["route"],
    "file" => expanded_file.sub("#{root_dir}/", ""),
    "exists" => exists,
    "bytes" => bytes,
    "png_valid" => header["valid"],
    "width" => header["width"],
    "height" => header["height"],
    "console_error_count" => console_error_count,
    "distinct_rgb" => capture["distinct_rgb"],
    "non_background_pixels" => capture["non_background_pixels"],
    "failures" => item_failures,
    "status" => item_failures.empty? ? "pass" : "fail"
  }
end

failures.concat(items.flat_map { |item| item.fetch("failures") }.uniq)

result = {
  "status" => failures.empty? ? "pass" : "fail",
  "evidence_source" => "mobile_route_render_smoke",
  "summary" => summary_path.to_s.empty? ? "" : summary_path.sub("#{root_dir}/", ""),
  "evidence_dir" => evidence_dir.to_s.empty? ? "" : evidence_dir.sub("#{root_dir}/", ""),
  "viewport" => viewport,
  "route_count" => captures.count,
  "product_screen_count" => summary ? summary["product_screen_count"].to_i : 0,
  "failures" => failures.uniq,
  "items" => items,
  "secret_handling" => "This gate reports current route-render screenshot paths, dimensions, byte counts, pixel checks, and console-error counts only; it does not inspect secrets or production customer data."
}

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[product-design-mobile-audit-artifact-gate] status=#{result.fetch("status")}"
  puts "[product-design-mobile-audit-artifact-gate] route_count=#{result.fetch("route_count")} viewport=#{result.fetch("viewport")}"
  failures.uniq.each { |failure| warn "[product-design-mobile-audit-artifact-gate][FAIL] #{failure}" }
end

exit(result.fetch("status") == "pass" ? 0 : 1)
RUBY
