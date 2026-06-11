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

if [[ -n "${SUPABASE_PLATFORM_PACKET_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_PLATFORM_PACKET_STATUS_JSON" >"$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json >"$status_json"
fi

ruby -r json -r time - "$output_format" "$project_ref" "$status_json" <<'RUBY'
format, project_ref, path = ARGV
status = JSON.parse(File.read(path))
blocker_keys = Array(status["blocker_keys"])

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
    "--scenarios consent,foreground_sms,background_sms,killed_app_sms,offline_retry,parser_allocation,exception_review,ledger_posting,privacy",
    "--evidence-summary '<sanitized scenario summary>'",
    "--sanitized-evidence",
    "--no-production-customer-data",
    "--raw-sms-not-public",
    "--no-phone-or-momo",
    "--no-transaction-ids"
  ].join(" ")
  "make record-android-sms-uat-evidence ARGS=\"#{args}\""
end

catalog = {
  "linked_supabase_sms_first_migration" => {
    "title" => "Linked Supabase SMS-first migration",
    "severity" => "P0",
    "owner" => "backend/operator",
    "required_action" => "Apply or dry-run supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql from an allow-listed database network, then rerun scripts/collect_linked_uat.sh.",
    "verify_command" => "scripts/collect_linked_uat.sh"
  },
  "linked_supabase_production_readiness" => {
    "title" => "Linked Supabase production readiness",
    "severity" => "P0",
    "owner" => "backend/operator",
    "required_action" => "Run scripts/supabase_production_readiness.sh, apply any missing linked migrations or backend fixes through an approved production-change path, then rerun make supabase-go-live-gate-json.",
    "verify_command" => "scripts/supabase_production_readiness.sh && make supabase-go-live-gate-json"
  },
  "android_sms_access_uat" => {
    "title" => "Android SMS access UAT",
    "severity" => "P0",
    "owner" => "mobile/release",
    "required_action" => "Run real Android MoMo SMS consent, ingestion, parse, allocation, exception, and ledger scenarios with sanitized evidence.",
    "evidence_record_command" => android_sms_uat_evidence_command,
    "record_command" => record_command(
      key: "android_sms_access_uat",
      evidence_reference: "docs/release/UAT_EVIDENCE_MANIFEST.json",
      notes: "<sanitized real-device SMS UAT review summary>"
    ),
    "verify_command" => "Run evidence_record_command, record UAT signoffs, then run the record_command for android_sms_access_uat"
  },
  "android_release_signing_review" => {
    "title" => "Android release signing review",
    "severity" => "P0",
    "owner" => "mobile/release",
    "required_action" => "Record Android release signing / Play App Signing review evidence for the current APK/AAB outputs.",
    "record_command" => record_command(
      key: "android_release_signing_review",
      evidence_reference: "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md",
      notes: "<APK/AAB and Play App Signing review summary>",
      extra_args: "--no-signing-keys-exposed"
    ),
    "verify_command" => "Run the record_command for android_release_signing_review, then ./scripts/flutter_mobile_release_gate.sh --json"
  },
  "ios_release_scope" => {
    "title" => "iOS release scope",
    "severity" => "P0",
    "owner" => "mobile/release",
    "required_action" => "Sign off iOS contributor-only scope or mark iOS explicitly out of scope.",
    "record_command" => record_command(
      key: "ios_release_scope",
      evidence_reference: "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md",
      notes: "<iOS contributor-scope review summary>"
    ),
    "record_out_of_scope_command" => record_command(
      key: "ios_release_scope --out-of-scope",
      evidence_reference: "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md",
      notes: "<Android-only go-live scope rationale>"
    ),
    "verify_command" => "Run record_command or record_out_of_scope_command for ios_release_scope, then ./scripts/flutter_mobile_release_gate.sh --json"
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
    "record_command" => record_command(
      key: "product_signoff",
      evidence_reference: "docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md",
      notes: "<SMS-first Groups product review summary>"
    ),
    "verify_command" => "Run the record_command for product_signoff, then make release-status-json"
  },
  "release_owner_signoff" => {
    "title" => "Release-owner evidence signoff",
    "severity" => "P0",
    "owner" => "release owner",
    "required_action" => "Approve the current release packet and worktree review.",
    "record_command" => record_command(
      key: "release_owner_signoff",
      evidence_reference: "docs/release/RELEASE_APPROVAL_PACKET.md",
      notes: "<final release-owner decision summary>"
    ),
    "verify_command" => "Run the record_command for release_owner_signoff, then make release-status-json"
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
    puts "- Record device evidence: `#{item.fetch("evidence_record_command")}`" if item["evidence_record_command"]
    puts "- Record: `#{item.fetch("record_command")}`" if item["record_command"]
    puts "- Record Android-only scope: `#{item.fetch("record_out_of_scope_command")}`" if item["record_out_of_scope_command"]
    puts "- Verify: `#{item.fetch("verify_command")}`"
  end
end
RUBY
