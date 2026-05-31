#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="markdown"
case "${1:-}" in
  --json) output_format="json" ;;
  "") ;;
  *)
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

status_json="$(mktemp)"
trap 'rm -f "$status_json"' EXIT

if [[ -n "${SUPABASE_PLATFORM_PACKET_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_PLATFORM_PACKET_STATUS_JSON" >"$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json >"$status_json"
fi

ruby -r json -r time - "$output_format" "${SUPABASE_PROJECT_REF:-unknown}" "$status_json" <<'RUBY'
format, project_ref, path = ARGV
status = JSON.parse(File.read(path))
blocker_keys = Array(status["blocker_keys"])

catalog = {
  "linked_supabase_sms_first_migration" => {
    "title" => "Linked Supabase SMS-first migration",
    "severity" => "P0",
    "owner" => "backend/operator",
    "required_action" => "Apply or dry-run the local migration from an allow-listed database network, then rerun scripts/collect_linked_uat.sh.",
    "verify_command" => "scripts/collect_linked_uat.sh"
  },
  "android_sms_access_uat" => {
    "title" => "Android SMS access UAT",
    "severity" => "P0",
    "owner" => "mobile/release",
    "required_action" => "Run real Android MoMo SMS consent, ingestion, parse, allocation, exception, and ledger scenarios with sanitized evidence.",
    "verify_command" => "Manual Android UAT plus sanitized evidence manifest"
  },
  "admin_pwa_live_url" => {
    "title" => "Admin PWA live deployment",
    "severity" => "P0",
    "owner" => "web/release",
    "required_action" => "Deploy Admin PWA and provide ADMIN_PWA_LIVE_URL.",
    "verify_command" => "ADMIN_PWA_LIVE_URL=https://... ./scripts/admin_pwa_live_gate.sh --json"
  },
  "product_signoff" => {
    "title" => "Product definition signoff",
    "severity" => "P0",
    "owner" => "stakeholders",
    "required_action" => "Approve docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md.",
    "verify_command" => "Attach signed product approval evidence"
  },
  "release_owner_signoff" => {
    "title" => "Release-owner evidence signoff",
    "severity" => "P0",
    "owner" => "release owner",
    "required_action" => "Approve the current release packet and worktree review.",
    "verify_command" => "COLLECT_RELEASE_OWNER_SIGNOFF_APPROVED=1 make release-status-json"
  }
}

items = blocker_keys.map do |key|
  catalog.fetch(key, {
    "title" => key,
    "severity" => "P1",
    "owner" => "release",
    "required_action" => "Investigate current blocker.",
    "verify_command" => "make release-status-json"
  }).merge("key" => key)
end

packet = {
  "generated_at" => Time.now.utc.iso8601,
  "project_ref" => project_ref,
  "decision" => status.fetch("decision", "UNKNOWN"),
  "blocker_keys" => blocker_keys,
  "operator_actions" => items,
  "secret_handling" => "No secret values are printed. Use sanitized SMS/payment evidence only."
}

if format == "json"
  puts JSON.pretty_generate(packet)
  exit 0
end

puts "# Collect SMS-First Go-Live Packet"
puts
puts "- Project ref: `#{packet.fetch("project_ref")}`"
puts "- Decision: `#{packet.fetch("decision")}`"
puts "- Secret handling: #{packet.fetch("secret_handling")}"
puts
puts "## Required Actions"
if items.empty?
  puts
  puts "No release blockers are currently reported by release-status."
else
  items.each do |item|
    puts
    puts "### #{item.fetch("severity")} #{item.fetch("title")}"
    puts
    puts "- Key: `#{item.fetch("key")}`"
    puts "- Owner: #{item.fetch("owner")}"
    puts "- Action: #{item.fetch("required_action")}"
    puts "- Verify: `#{item.fetch("verify_command")}`"
  end
end
RUBY
