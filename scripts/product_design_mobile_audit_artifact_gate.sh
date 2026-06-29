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

OUTPUT_FORMAT="$output_format" ROOT_DIR="$ROOT_DIR" ruby -r json <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")
audit_dir = File.join(root_dir, "docs/release/product_design_mobile_audit_2026-06-26")
manifest_path = File.join(audit_dir, "screenshot_manifest.json")

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

manifest = read_json(manifest_path)
failures = []
routes = manifest ? Array(manifest["routes"]) : []
viewport = manifest && manifest["viewport"].to_s
expected_width, expected_height = viewport.to_s.split("x", 2).map { |value| value.to_i }
audit_root = File.expand_path(audit_dir)

failures << "screenshot_manifest_missing_or_invalid" unless manifest
failures << "viewport_must_be_390x844" unless viewport == "390x844"
failures << "route_count_must_be_46" unless routes.count == 46

items = routes.map do |route|
  file = route["file"].to_s
  expanded_file = File.expand_path(file, root_dir)
  inside_audit_dir = expanded_file.start_with?(audit_root + File::SEPARATOR)
  exists = inside_audit_dir && File.file?(expanded_file)
  header = exists ? png_header(expanded_file) : {"valid" => false, "width" => nil, "height" => nil}
  bytes = exists ? File.size(expanded_file) : 0
  manifest_bytes = route["bytes"].to_i
  console_errors = Array(route["consoleErrors"])
  item_failures = []

  item_failures << "outside_audit_dir" unless inside_audit_dir
  item_failures << "missing_file" unless exists
  item_failures << "not_png" unless header["valid"]
  item_failures << "wrong_dimensions" unless header["width"] == expected_width && header["height"] == expected_height
  item_failures << "empty_or_tiny_file" unless bytes >= 10_000
  item_failures << "console_errors_present" unless console_errors.empty?
  item_failures << "manifest_bytes_stale" unless manifest_bytes == bytes

  {
    "step" => route["step"],
    "route" => route["route"],
    "file" => expanded_file.sub("#{root_dir}/", ""),
    "exists" => exists,
    "bytes" => bytes,
    "manifest_bytes" => manifest_bytes,
    "png_valid" => header["valid"],
    "width" => header["width"],
    "height" => header["height"],
    "console_error_count" => console_errors.count,
    "failures" => item_failures,
    "status" => item_failures.empty? ? "pass" : "fail"
  }
end

failures.concat(items.flat_map { |item| item.fetch("failures") }.uniq)

summary = {
  "status" => failures.empty? ? "pass" : "fail",
  "audit_dir" => audit_dir.sub("#{root_dir}/", ""),
  "manifest" => manifest_path.sub("#{root_dir}/", ""),
  "viewport" => viewport,
  "route_count" => routes.count,
  "failures" => failures.uniq,
  "items" => items,
  "secret_handling" => "This gate reports screenshot paths, dimensions, byte counts, and console-error counts only; it does not inspect secrets or production customer data."
}

if output_format == "json"
  puts JSON.pretty_generate(summary)
else
  puts "[product-design-mobile-audit-artifact-gate] status=#{summary.fetch("status")}"
  puts "[product-design-mobile-audit-artifact-gate] route_count=#{summary.fetch("route_count")} viewport=#{summary.fetch("viewport")}"
  failures.uniq.each { |failure| warn "[product-design-mobile-audit-artifact-gate][FAIL] #{failure}" }
end

exit(summary.fetch("status") == "pass" ? 0 : 1)
RUBY
