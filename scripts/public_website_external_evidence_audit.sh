#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

set +e
scripts/public_website_completion_gate.sh --json > "$TMP_JSON"
GATE_RC=$?
set -e

ruby -r json - "$TMP_JSON" <<'RUBY'
path = ARGV.fetch(0)
payload = JSON.parse(File.read(path))

puts "Collect public website completion audit"
puts "status: #{payload.fetch("status")}"
puts "code checks: #{payload.fetch("code_checks").values.count(true)}/#{payload.fetch("code_checks").length}"
puts "external missing or invalid: #{payload.fetch("missing_external_count")}"
puts

payload.fetch("code_checks").each do |id, passed|
  puts "#{passed ? "PASS" : "FAIL"} code #{id}"
end

puts
payload.fetch("missing_external").each do |id, item|
  puts "MISSING_OR_INVALID #{id} (#{item.fetch("audit_id")})"
  puts "  #{item.fetch("description")}"
  puts "  accepted evidence:"
  item.fetch("paths").each { |accepted| puts "  - #{accepted}" }
  puts
end

if payload.fetch("status") == "pass"
  puts "All code-owned and external evidence requirements are satisfied."
else
  puts "The website code is not necessarily failing; attach the missing external artifacts above, then rerun scripts/public_website_completion_gate.sh --json."
end
RUBY

exit "$GATE_RC"
