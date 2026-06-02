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

summary_path="${QA_UAT_SUMMARY_JSON:-}"
if [[ -z "$summary_path" ]]; then
  summary_path="$(
    ROOT_DIR="$ROOT_DIR" ruby -r json <<'RUBY'
root = ENV.fetch("ROOT_DIR")
paths = Dir[File.join(root, ".cache/repo_wide_qa_uat/*/summary.json")].sort.reverse
selected = paths.find do |path|
  data = JSON.parse(File.read(path)) rescue {}
  surfaces = data["surfaces"].is_a?(Hash) ? data["surfaces"] : {}
  surfaces["admin_pwa_live_deployment"] == "pass" &&
    surfaces["release_evidence_index"] == "pass" &&
    surfaces["android_release_artifacts"] == "pass" &&
    surfaces["release_artifact_manifest"] == "pass"
end
puts(selected || paths.first || "")
RUBY
  )"
fi

status_json="$(mktemp)"
trap 'rm -f "$status_json"' EXIT
admin_pwa_live_url="${ADMIN_PWA_LIVE_URL:-https://cool-admin-212.pages.dev}"

if [[ -n "${RELEASE_APPROVAL_PACKET_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$RELEASE_APPROVAL_PACKET_STATUS_JSON" >"$status_json"
else
  ADMIN_PWA_LIVE_URL="$admin_pwa_live_url" "$ROOT_DIR/scripts/release_status.sh" --json >"$status_json"
fi

ROOT_DIR="$ROOT_DIR" OUTPUT_FORMAT="$output_format" SUMMARY_PATH="$summary_path" STATUS_JSON="$status_json" ADMIN_PWA_LIVE_URL="$admin_pwa_live_url" ruby -r json -r time <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
format = ENV.fetch("OUTPUT_FORMAT")
summary_path = ENV.fetch("SUMMARY_PATH", "")
admin_pwa_live_url = ENV.fetch("ADMIN_PWA_LIVE_URL")
status = JSON.parse(File.read(ENV.fetch("STATUS_JSON")))

summary = {}
if summary_path != "" && File.file?(summary_path)
  summary = JSON.parse(File.read(summary_path))
end

def rel(root_dir, path)
  return nil if path.nil? || path == ""
  path.start_with?(root_dir) ? path.delete_prefix("#{root_dir}/") : path
end

def file_item(root_dir, path)
  absolute = File.join(root_dir, path)
  {
    "path" => path,
    "exists" => File.file?(absolute),
    "bytes" => File.file?(absolute) ? File.size(absolute) : nil
  }
end

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

blocker_keys = Array(status["blocker_keys"])
surfaces = summary.fetch("surfaces", {})
bundle_dir = rel(root_dir, summary["bundle_dir"])
latest_summary = rel(root_dir, summary_path)
latest_android_device_summary = Dir[File.join(root_dir, ".cache/android_device_uat/*/summary.json")]
  .sort
  .last
latest_android_device_summary = rel(root_dir, latest_android_device_summary)
latest_android_device_log =
  if latest_android_device_summary
    File.join(File.dirname(latest_android_device_summary), "android_device_uat.txt")
  end
latest_supabase_evidence_summary = Dir[File.join(root_dir, ".cache/supabase_go_live_evidence/[0-9]*Z/summary.json")]
  .sort
  .last
latest_supabase_evidence_summary = rel(root_dir, latest_supabase_evidence_summary)
latest_mobile_release_gate_summary = Dir[File.join(root_dir, ".cache/mobile_release_gate/[0-9]*Z/summary.json")]
  .sort
  .last
latest_mobile_release_gate_summary = rel(root_dir, latest_mobile_release_gate_summary)
latest_android_install_summary = Dir[File.join(root_dir, ".cache/android_install/[0-9]*Z/final_release_summary.json")]
  .sort
  .last
latest_android_install_summary = rel(root_dir, latest_android_install_summary)

approval_manifest_path = File.join(root_dir, "docs/release/RELEASE_APPROVALS.json")
approval_manifest = JSON.parse(File.read(approval_manifest_path)) rescue {}
suggested_evidence_references = Array(approval_manifest["approvals"]).each_with_object({}) do |record, memo|
  key = record["key"].to_s.strip
  suggested = record["suggested_evidence_reference"].to_s.strip
  memo[key] = suggested if key != "" && suggested != ""
end

def suggested_evidence_reference(suggested_evidence_references, key, fallback)
  suggested_evidence_references.fetch(key, fallback)
end

approval_records = [
  {
    "key" => "product_signoff",
    "title" => "Product definition approval",
    "status" => blocker_keys.include?("product_signoff") ? "pending" : "approved",
    "required_now" => blocker_keys.include?("product_signoff"),
    "owner" => "product/stakeholder",
    "decision_needed" => "Approve the SMS-first Groups product definition, including Collect ID-only identity, Android-only group creation, and automated MoMo SMS allocation.",
    "evidence_to_review" => [
      "docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md",
      "docs/design/COLLECT_ASSET_SCREEN_UI_UX_UPDATE_REPORT_2026-05-31.md",
      "scripts/collect_product_boundary_scan.sh",
      bundle_dir && File.join(bundle_dir, "collect_product_boundary_scan.json"),
      latest_summary
    ].compact,
    "required_signoff_fields" => [
      "reviewer",
      "decision=GO",
      "signed_at ISO-8601 UTC",
      "evidence reference"
    ],
    "suggested_evidence_reference" => suggested_evidence_reference(
      suggested_evidence_references,
      "product_signoff",
      "docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md"
    ),
    "record_command" => record_command(
      key: "product_signoff",
      evidence_reference: "docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md",
      notes: "<SMS-first Groups product review summary>"
    ),
    "verify_command" => "Run the record_command for product_signoff, then ADMIN_PWA_LIVE_URL=#{admin_pwa_live_url} make release-status-json"
  },
  {
    "key" => "android_sms_access_uat",
    "title" => "Android MoMo SMS UAT approval",
    "status" => blocker_keys.include?("android_sms_access_uat") ? "pending" : "approved",
    "required_now" => blocker_keys.include?("android_sms_access_uat"),
    "owner" => "mobile/release",
    "decision_needed" => "Approve real Android device UAT for SMS consent, MoMo SMS ingestion, parser output, allocation, exception handling, offline retry, and ledger update.",
    "evidence_to_review" => [
      "docs/ANDROID_SMS_ACCESS.md",
      "docs/release/UAT_EVIDENCE_MANIFEST.json",
      latest_android_device_summary,
      latest_android_device_log,
      bundle_dir && File.join(bundle_dir, "android_device_uat.txt"),
      bundle_dir && File.join(bundle_dir, "uat_evidence_gate.json"),
      latest_supabase_evidence_summary,
      bundle_dir && File.join(bundle_dir, "supabase/summary.json")
    ].compact,
    "required_signoff_fields" => [
      "tester/reviewer",
      "all SMS evidence sanitized",
      "persona UAT rows signed or waived",
      "signed_at ISO-8601 UTC"
    ],
    "suggested_evidence_reference" => suggested_evidence_reference(
      suggested_evidence_references,
      "android_sms_access_uat",
      "docs/release/UAT_EVIDENCE_MANIFEST.json"
    ),
    "record_command" => record_command(
      key: "android_sms_access_uat",
      evidence_reference: "docs/release/UAT_EVIDENCE_MANIFEST.json",
      notes: "<sanitized real-device SMS UAT review summary>"
    ),
    "verify_command" => "Run the record_command for android_sms_access_uat, then ADMIN_PWA_LIVE_URL=#{admin_pwa_live_url} make release-status-json"
  },
  {
    "key" => "android_release_signing_review",
    "title" => "Android release signing review",
    "status" => blocker_keys.include?("android_release_signing_review") ? "pending" : "approved",
    "required_now" => blocker_keys.include?("android_release_signing_review"),
    "owner" => "mobile/release",
    "decision_needed" => "Approve the current production APK/AAB outputs and Play App Signing configuration without exposing signing keys.",
    "evidence_to_review" => [
      "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md",
      "docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256",
      latest_mobile_release_gate_summary,
      latest_android_install_summary,
      "build/app/outputs/flutter-apk/app-production-release.apk",
      "build/app/outputs/bundle/productionRelease/app-production-release.aab",
      bundle_dir && File.join(bundle_dir, "mobile_release_gate.json")
    ].compact,
    "required_signoff_fields" => [
      "reviewer",
      "decision=GO",
      "signed_at ISO-8601 UTC",
      "evidence reference",
      "signing_keys_exposed=false"
    ],
    "suggested_evidence_reference" => suggested_evidence_reference(
      suggested_evidence_references,
      "android_release_signing_review",
      "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md"
    ),
    "record_command" => record_command(
      key: "android_release_signing_review",
      evidence_reference: "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md",
      notes: "<APK/AAB and Play App Signing review summary>",
      extra_args: "--no-signing-keys-exposed"
    ),
    "verify_command" => "Run the record_command for android_release_signing_review, then ./scripts/flutter_mobile_release_gate.sh --json"
  },
  {
    "key" => "ios_release_scope",
    "title" => "iOS release scope decision",
    "status" => blocker_keys.include?("ios_release_scope") ? "pending" : "approved",
    "required_now" => blocker_keys.include?("ios_release_scope"),
    "owner" => "mobile/release",
    "decision_needed" => "Either approve iOS contributor-only release evidence or explicitly scope iOS out of this go-live.",
    "evidence_to_review" => [
      "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md",
      "ios/Runner/Info.plist",
      "ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme",
      "ios/Flutter/Release-production.xcconfig",
      latest_mobile_release_gate_summary,
      bundle_dir && File.join(bundle_dir, "mobile_release_gate.json")
    ].compact,
    "required_signoff_fields" => [
      "reviewer",
      "decision=GO or OUT_OF_SCOPE",
      "signed_at ISO-8601 UTC",
      "evidence reference",
      "status=approved or status=out_of_scope"
    ],
    "suggested_evidence_reference" => suggested_evidence_reference(
      suggested_evidence_references,
      "ios_release_scope",
      "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md"
    ),
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
  {
    "key" => "release_owner_signoff",
    "title" => "Release-owner go/no-go approval",
    "status" => blocker_keys.include?("release_owner_signoff") ? "pending" : "approved",
    "required_now" => blocker_keys.include?("release_owner_signoff"),
    "owner" => "release owner",
    "decision_needed" => "Approve the current release evidence packet only after all product, SMS UAT, signing, iOS scope, security, and worktree checks are acceptable.",
    "evidence_to_review" => [
      latest_summary,
      ".cache/admin_pwa_render_smoke/20260602T081408Z/summary.json",
      ".cache/mobile_route_render_smoke/20260602T210133Z/summary.json",
      latest_android_device_summary,
      latest_supabase_evidence_summary,
      "docs/release/UAT_GO_LIVE_PACKET_2026-05-24.md",
      "docs/release/GO_NO_GO_DECISION.md",
      "docs/release/RELEASE_BLOCKERS.md",
      bundle_dir && File.join(bundle_dir, "evidence_index.json"),
      bundle_dir && File.join(bundle_dir, "worktree_review.json")
    ].compact,
    "required_signoff_fields" => [
      "release owner name",
      "decision=GO",
      "signed_at ISO-8601 UTC",
      "evidence packet reference"
    ],
    "suggested_evidence_reference" => suggested_evidence_reference(
      suggested_evidence_references,
      "release_owner_signoff",
      "docs/release/RELEASE_APPROVAL_PACKET.md"
    ),
    "record_command" => record_command(
      key: "release_owner_signoff",
      evidence_reference: "docs/release/RELEASE_APPROVAL_PACKET.md",
      notes: "<final release-owner decision summary>"
    ),
    "verify_command" => "Run the record_command for release_owner_signoff, then ADMIN_PWA_LIVE_URL=#{admin_pwa_live_url} make release-status-json"
  }
]

packet = {
  "generated_at" => Time.now.utc.iso8601,
  "decision" => status["decision"],
  "status" => status["status"] || status["supabase_strict"],
  "qa_summary" => latest_summary,
  "qa_bundle" => bundle_dir,
  "surfaces" => surfaces,
  "blocker_keys" => blocker_keys,
  "approval_records" => approval_records,
  "required_final_commands" => [
    "ADMIN_PWA_LIVE_URL=#{admin_pwa_live_url} make release-status-json",
    "make release-approval-evidence-gate-json",
    "ADMIN_PWA_LIVE_URL=#{admin_pwa_live_url} make supabase-go-live-gate-json",
    "ADMIN_PWA_LIVE_URL=#{admin_pwa_live_url} ./scripts/repo_wide_qa_uat.sh --json"
  ],
  "file_checks" => [
    file_item(root_dir, "docs/release/RELEASE_APPROVALS.json"),
    file_item(root_dir, "docs/release/UAT_EVIDENCE_MANIFEST.json"),
    file_item(root_dir, ".cache/admin_pwa_render_smoke/20260602T081408Z/summary.json"),
    file_item(root_dir, ".cache/mobile_route_render_smoke/20260602T210133Z/summary.json"),
    latest_android_device_summary && file_item(root_dir, latest_android_device_summary),
    latest_supabase_evidence_summary && file_item(root_dir, latest_supabase_evidence_summary),
    latest_mobile_release_gate_summary && file_item(root_dir, latest_mobile_release_gate_summary),
    latest_android_install_summary && file_item(root_dir, latest_android_install_summary),
    file_item(root_dir, "docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md"),
    file_item(root_dir, "docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256"),
    file_item(root_dir, "docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md"),
    file_item(root_dir, "scripts/collect_product_boundary_scan.sh")
  ].compact,
  "secret_handling" => "No secrets, signing keys, raw SMS bodies, phone/MoMo numbers, service-role keys, provider tokens, or production customer data may be pasted into approval records."
}

if format == "json"
  puts JSON.pretty_generate(packet)
  exit 0
end

puts "# Collect Release Approval Packet"
puts
puts "- Generated at: `#{packet.fetch("generated_at")}`"
puts "- Decision: `#{packet.fetch("decision")}`"
puts "- Status: `#{packet.fetch("status")}`"
puts "- QA summary: `#{packet.fetch("qa_summary") || "missing"}`"
puts "- QA bundle: `#{packet.fetch("qa_bundle") || "missing"}`"
puts "- Secret handling: #{packet.fetch("secret_handling")}"
puts
puts "## Surface Status"
if surfaces.empty?
  puts
  puts "No repo-wide QA summary was found."
else
  surfaces.each do |name, surface_status|
    puts "- `#{name}`: `#{surface_status}`"
  end
end
puts
puts "## Pending Approval Records"
approval_records.each do |record|
  puts
  puts "### #{record.fetch("title")}"
  puts
  puts "- Key: `#{record.fetch("key")}`"
  puts "- Status: `#{record.fetch("status")}`"
  puts "- Required now: `#{record.fetch("required_now")}`"
  puts "- Owner: #{record.fetch("owner")}"
  puts "- Decision needed: #{record.fetch("decision_needed")}"
  puts "- Suggested evidence reference: `#{record.fetch("suggested_evidence_reference")}`" if record["suggested_evidence_reference"]
  puts "- Record: `#{record.fetch("record_command")}`" if record["record_command"]
  puts "- Record Android-only scope: `#{record.fetch("record_out_of_scope_command")}`" if record["record_out_of_scope_command"]
  puts "- Verify: `#{record.fetch("verify_command")}`"
  puts "- Evidence to review:"
  record.fetch("evidence_to_review").each { |item| puts "  - `#{item}`" }
  puts "- Required signoff fields:"
  record.fetch("required_signoff_fields").each { |item| puts "  - #{item}" }
end
puts
puts "## Required Final Commands"
packet.fetch("required_final_commands").each { |command| puts "- `#{command}`" }
RUBY
