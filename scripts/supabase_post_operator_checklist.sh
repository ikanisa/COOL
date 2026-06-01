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

project_ref="${SUPABASE_PROJECT_REF:-unknown}"
if [[ -f "$ROOT_DIR/supabase/.temp/project-ref" ]]; then
  linked_project_ref="$(tr -d '[:space:]' <"$ROOT_DIR/supabase/.temp/project-ref")"
  if [[ -n "$linked_project_ref" ]]; then
    project_ref="$linked_project_ref"
  fi
fi

if [[ -n "${SUPABASE_POST_OPERATOR_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_POST_OPERATOR_STATUS_JSON" >"$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json >"$status_json"
fi

ruby -r json -r time - "$output_format" "$project_ref" "$status_json" <<'RUBY'
format, project_ref, path = ARGV
status = JSON.parse(File.read(path))
blockers = Array(status["blocker_keys"])

steps = [
  {
    key: "product_signoff",
    title: "Approve corrected product definition",
    required_when: blockers.include?("product_signoff"),
    verify: "Record product_signoff in docs/release/RELEASE_APPROVALS.json, then make release-status-json"
  },
  {
    key: "linked_supabase_sms_first_migration",
    title: "Apply linked SMS-first migration and rerun rollback UAT",
    required_when: blockers.include?("linked_supabase_sms_first_migration"),
    verify: "scripts/collect_linked_uat.sh"
  },
  {
    key: "android_sms_access_uat",
    title: "Run real Android SMS access UAT",
    required_when: blockers.include?("android_sms_access_uat"),
    verify: "Attach sanitized Android SMS UAT evidence"
  },
  {
    key: "android_release_signing_review",
    title: "Record Android signing review",
    required_when: blockers.include?("android_release_signing_review"),
    verify: "Record android_release_signing_review in docs/release/RELEASE_APPROVALS.json, then ./scripts/flutter_mobile_release_gate.sh --json"
  },
  {
    key: "ios_release_scope",
    title: "Record iOS release scope decision",
    required_when: blockers.include?("ios_release_scope"),
    verify: "Record ios_release_scope in docs/release/RELEASE_APPROVALS.json, then ./scripts/flutter_mobile_release_gate.sh --json"
  },
  {
    key: "admin_pwa_live_url",
    title: "Deploy and verify Admin PWA live URL",
    required_when: blockers.include?("admin_pwa_live_url"),
    verify: "ADMIN_PWA_LIVE_URL=https://... ./scripts/admin_pwa_live_gate.sh --json"
  },
  {
    key: "release_owner_signoff",
    title: "Approve release packet",
    required_when: blockers.include?("release_owner_signoff"),
    verify: "Record release_owner_signoff in docs/release/RELEASE_APPROVALS.json, then make release-status-json"
  }
]

packet = {
  generated_at: Time.now.utc.iso8601,
  project_ref: project_ref == "unknown" ? nil : project_ref,
  current_decision: status["decision"],
  current_status: status["status"] || status["supabase_strict"],
  current_blocker_keys: blockers,
  checklist: steps,
  final_verification: [
    "make release-status-json",
    "make supabase-go-live-gate-json"
  ],
  secret_handling: "Use sanitized SMS/payment evidence only; do not paste secrets or raw customer data into docs."
}

if format == "json"
  puts JSON.pretty_generate(packet)
  exit 0
end

puts "# Collect Post-Operator Verification Checklist"
puts
puts "- Generated at: `#{packet.fetch(:generated_at)}`"
puts "- Project ref: `#{packet[:project_ref] || "unknown"}`"
puts "- Current decision: `#{packet[:current_decision]}`"
puts "- Current blocker keys: `#{blockers.join(", ")}`"
puts "- Secret handling: #{packet.fetch(:secret_handling)}"
puts
puts "## Operator Steps"
steps.each do |step|
  puts
  puts "### #{step.fetch(:title)}"
  puts "- Key: `#{step.fetch(:key)}`"
  puts "- Required now: `#{step.fetch(:required_when)}`"
  puts "- Verify: `#{step.fetch(:verify)}`"
end
puts
puts "## Final Verification"
packet.fetch(:final_verification).each { |command| puts "- `#{command}`" }
RUBY
