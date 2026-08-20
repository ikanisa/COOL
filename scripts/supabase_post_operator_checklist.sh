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

def record_command(key:, evidence_reference:, notes:, extra_args: "")
  args = [
    "--key #{key}",
    "--reviewer '<name>'",
    "--evidence-reference #{evidence_reference}",
    "--notes '#{notes}'",
    "--sanitized-evidence",
    "--no-production-customer-data",
    extra_args
  ].reject { |part| part.to_s.strip == "" }.join(" ")
  "make record-release-approval ARGS=\"#{args}\""
end

def android_sms_uat_evidence_command
  args = [
    "--tester '<name>'",
    "--tested-at '<ISO-8601 UTC timestamp>'",
    "--device-label '<Android UAT device label>'",
    "--scenarios consent,foreground_sms,background_sms,killed_app_sms,offline_retry,parser_allocation,exception_review,ledger_posting,balance_reconciliation,privacy",
    "--evidence-summary '<sanitized scenario summary>'",
    "--sanitized-evidence",
    "--no-production-customer-data",
    "--raw-sms-not-public",
    "--no-phone-or-momo",
    "--no-transaction-ids",
    "--balances-reconciled"
  ].join(" ")
  "make record-android-sms-uat-evidence ARGS=\"#{args}\""
end

steps = [
  {
    key: "product_signoff",
    title: "Approve corrected product definition",
    required_when: blockers.include?("product_signoff"),
    record_command: record_command(
      key: "product_signoff",
      evidence_reference: "docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md",
      notes: "<SMS-first Groups product review summary>"
    ),
    verify: "Run the record_command for product_signoff, then make release-status-json"
  },
  {
    key: "linked_supabase_sms_first_migration",
    title: "Apply linked SMS-first migration and rerun rollback UAT",
    required_when: blockers.include?("linked_supabase_sms_first_migration"),
    verify: "Apply supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql, then scripts/collect_linked_uat.sh"
  },
  {
    key: "linked_supabase_production_readiness",
    title: "Verify linked Supabase production readiness",
    required_when: true,
    verify: "Run scripts/supabase_production_readiness.sh. If it reports missing migrations such as 20260607130500 or 20260608090000, apply them through an approved production-change path, then rerun make supabase-go-live-gate-json."
  },
  {
    key: "android_sms_access_uat",
    title: "Run real Android SMS access UAT",
    required_when: blockers.include?("android_sms_access_uat"),
    evidence_record_command: android_sms_uat_evidence_command,
    record_command: record_command(
      key: "android_sms_access_uat",
      evidence_reference: "docs/release/UAT_EVIDENCE_MANIFEST.json",
      notes: "<sanitized real-device SMS UAT review summary>"
    ),
    verify: "Run the evidence_record_command for Android SMS UAT, then record UAT signoffs and run the record_command for android_sms_access_uat"
  },
  {
    key: "android_release_signing_review",
    title: "Record Android signing review",
    required_when: blockers.include?("android_release_signing_review"),
    record_command: record_command(
      key: "android_release_signing_review",
      evidence_reference: "docs/release/RELEASE_STATUS.md",
      notes: "<APK/AAB and Play App Signing review summary>",
      extra_args: "--no-signing-keys-exposed"
    ),
    verify: "Run the record_command for android_release_signing_review, then ./scripts/flutter_mobile_release_gate.sh --json"
  },
  {
    key: "ios_release_scope",
    title: "Record iOS release scope decision",
    required_when: blockers.include?("ios_release_scope"),
    record_command: record_command(
      key: "ios_release_scope",
      evidence_reference: "docs/release/RELEASE_STATUS.md",
      notes: "<iOS contributor-scope review summary>"
    ),
    record_out_of_scope_command: record_command(
      key: "ios_release_scope --out-of-scope",
      evidence_reference: "docs/release/RELEASE_STATUS.md",
      notes: "<Android-only go-live scope rationale>"
    ),
    verify: "Run record_command or record_out_of_scope_command for ios_release_scope, then ./scripts/flutter_mobile_release_gate.sh --json"
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
    record_command: record_command(
      key: "release_owner_signoff",
      evidence_reference: "docs/release/RELEASE_APPROVAL_PACKET.md",
      notes: "<final release-owner decision summary>"
    ),
    verify: "Run the record_command for release_owner_signoff, then make release-status-json"
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
  puts "- Record device evidence: `#{step.fetch(:evidence_record_command)}`" if step[:evidence_record_command]
  puts "- Record: `#{step.fetch(:record_command)}`" if step[:record_command]
  puts "- Record Android-only scope: `#{step.fetch(:record_out_of_scope_command)}`" if step[:record_out_of_scope_command]
  puts "- Verify: `#{step.fetch(:verify)}`"
end
puts
puts "## Final Verification"
packet.fetch(:final_verification).each { |command| puts "- `#{command}`" }
RUBY
