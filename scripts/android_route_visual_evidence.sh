#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON="${PYTHON:-python3}"
REFERENCE_DIR="${REVOLUT_REFERENCE_DIR:-/Users/jeanbosco/Downloads/Revolut10}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_ROUTE_VISUAL_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_route_visual_evidence/$timestamp}"
SCREENSHOT_DIR="$EVIDENCE_DIR/screenshots"
DEVICE_UAT_DIR="$EVIDENCE_DIR/android_device_uat"

mkdir -p "$SCREENSHOT_DIR" "$DEVICE_UAT_DIR" "$EVIDENCE_DIR/contact_sheets"

if [[ ! -d "$REFERENCE_DIR" ]]; then
  printf '[android-route-visual][FAIL] reference directory missing: %s\n' "$REFERENCE_DIR" >&2
  exit 1
fi

INTEGRATION_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
ANDROID_UAT_EVIDENCE_DIR="$DEVICE_UAT_DIR" \
ANDROID_UAT_TEST_TARGET="integration_test/mobile_route_matrix_device_uat_test.dart" \
ANDROID_UAT_TIMEOUT_SECONDS="${ANDROID_ROUTE_VISUAL_TIMEOUT_SECONDS:-1800}" \
  "$ROOT_DIR/scripts/android_device_uat.sh"

if [[ ! -s "$SCREENSHOT_DIR/screenshots.jsonl" ]]; then
  printf '[android-route-visual][FAIL] no screenshots were written to %s\n' "$SCREENSHOT_DIR" >&2
  exit 1
fi

ROOT_DIR="$ROOT_DIR" \
EVIDENCE_DIR="$EVIDENCE_DIR" \
SCREENSHOT_DIR="$SCREENSHOT_DIR" \
DEVICE_UAT_SUMMARY="$DEVICE_UAT_DIR/summary.json" \
ruby -r json -r time <<'RUBY'
root = ENV.fetch("ROOT_DIR")
evidence_dir = ENV.fetch("EVIDENCE_DIR")
screenshot_dir = ENV.fetch("SCREENSHOT_DIR")
device_uat_summary = ENV.fetch("DEVICE_UAT_SUMMARY")
test_file = File.join(root, "integration_test/mobile_route_matrix_device_uat_test.dart")
test_source = File.read(test_file)
route_map = {}
test_source.scan(/_RouteSpec\(\s*'([^']+)',\s*'([^']+)'\s*,?\s*\)/m) do |name, route|
  route_map["mobile_route_#{name}"] = route
end

captures = File.readlines(File.join(screenshot_dir, "screenshots.jsonl"), chomp: true)
  .reject(&:empty?)
  .map { |line| JSON.parse(line) }
  .map do |capture|
    name = capture.fetch("name")
    route_name = name.delete_prefix("mobile_route_")
    capture.merge(
      "route_name" => route_name,
      "route" => route_map.fetch(name, nil)
    )
  end

missing = route_map.keys - captures.map { |capture| capture.fetch("name") }
failed = captures.reject { |capture| capture.fetch("status") == "pass" && capture.fetch("bytes").to_i > 8000 }
status = missing.empty? && failed.empty? ? "pass" : "fail"
summary = {
  "status" => status,
  "generated_at" => Time.now.utc.iso8601,
  "runtime" => "physical_android_integration_test",
  "device_uat_summary" => device_uat_summary.delete_prefix("#{root}/"),
  "viewport" => "physical_device",
  "expected_route_count" => route_map.length,
  "route_count" => captures.length,
  "routes" => captures.map { |capture| capture["route"] },
  "screenshots" => captures.map { |capture| capture.fetch("path") },
  "captures" => captures,
  "missing_screenshots" => missing,
  "failed_screenshots" => failed,
	  "secret_handling" => "Physical-device screenshots must not include raw secrets, raw SMS bodies, OTPs, PINs, provider tokens, service-role keys, private phone numbers, raw receiver MoMo numbers, or production customer data."
}
File.write(File.join(screenshot_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")
File.write(File.join(evidence_dir, "summary.json"), JSON.pretty_generate(summary.merge(
  "screenshots_dir" => screenshot_dir.delete_prefix("#{root}/")
)) + "\n")
exit(status == "pass" ? 0 : 1)
RUBY

latest_admin_summary="$(ruby -e 'paths = Dir[ARGV[0]].sort; puts(paths.last || "")' "$ROOT_DIR/.cache/admin_pwa_render_smoke/*/summary.json")"
if [[ -n "$latest_admin_summary" && -f "$latest_admin_summary" ]]; then
  admin_dir="$(dirname "$latest_admin_summary")"
else
  admin_dir="$SCREENSHOT_DIR"
fi

"$PYTHON" "$ROOT_DIR/scripts/generate_visual_evidence_contact_sheets.py" \
  --reference-dir "$REFERENCE_DIR" \
  --mobile-dir "$SCREENSHOT_DIR" \
  --admin-dir "$admin_dir" \
  --output-dir "$EVIDENCE_DIR/contact_sheets" >"$EVIDENCE_DIR/contact_sheets/stdout.json"

printf '[android-route-visual] pass evidence=%s\n' "$EVIDENCE_DIR"
