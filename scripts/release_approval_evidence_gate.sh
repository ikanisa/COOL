#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
case "${1:-}" in
  --json) output_format="json" ;;
  "") ;;
  *)
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

manifest_path="${RELEASE_APPROVALS_JSON:-$ROOT_DIR/docs/release/RELEASE_APPROVALS.json}"

OUTPUT_FORMAT="$output_format" MANIFEST_PATH="$manifest_path" ROOT_DIR="$ROOT_DIR" ruby -r json -r time -r uri <<'RUBY'
format = ENV.fetch("OUTPUT_FORMAT")
manifest_path = ENV.fetch("MANIFEST_PATH")
root_dir = ENV.fetch("ROOT_DIR")

required_keys = %w[
  product_signoff
  android_sms_access_uat
  android_release_signing_review
  ios_release_scope
  release_owner_signoff
]

def check(status, message, extra = {})
  {"status" => status, "message" => message}.merge(extra)
end

def iso8601_utc?(value)
  Time.iso8601(value.to_s)
  value.to_s.end_with?("Z")
rescue ArgumentError, TypeError
  false
end

def valid_https_url?(value)
  uri = URI.parse(value.to_s)
  uri.is_a?(URI::HTTPS) && uri.host.to_s.strip != ""
rescue URI::InvalidURIError
  false
end

def evidence_reference_valid?(value, root_dir)
  reference = value.to_s.strip
  return false if reference == ""
  return true if valid_https_url?(reference)
  return false if reference.match?(/\A[a-z][a-z0-9+.-]*:/i)

  expanded_root = File.expand_path(root_dir)
  expanded_path = File.expand_path(reference, expanded_root)
  inside_repo = expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}/")
  inside_repo && File.exist?(expanded_path)
end

def template_manifest?(manifest_path, manifest)
  basename = File.basename(manifest_path).downcase
  basename.include?("example") ||
    manifest["template"] == true ||
    manifest["secret_handling"].to_s.match?(/\btemplate only\b/i)
end

def placeholder_approval_blockers(record)
  blockers = []
  placeholder_reviewers = [
    "Product Reviewer",
    "Mobile UAT Reviewer",
    "Android Release Reviewer",
    "Mobile Release Reviewer",
    "Release Owner"
  ]
  placeholder_notes = [
    "Approved SMS-first Groups product definition.",
    "Approved sanitized Android SMS UAT evidence.",
    "Approved current APK/AAB and Play App Signing review.",
    "Approved Android-only scope for this go-live.",
    "Approved after all prerequisite gates were approved."
  ]

  blockers << "placeholder_reviewer" if placeholder_reviewers.include?(record["reviewer"].to_s.strip)
  blockers << "placeholder_signed_at" if record["signed_at"].to_s.strip == "2026-06-01T00:00:00Z"
  blockers << "placeholder_notes" if placeholder_notes.include?(record["notes"].to_s.strip)
  blockers
end

SENSITIVE_METADATA_PATTERNS = {
  "supabase_service_role" => /service[_-]?role\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "openai_api_key" => /sk-[A-Za-z0-9_\-]{20,}/,
  "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "rwanda_phone_number" => /\+250\d{9}\b/,
  "raw_momo_sms" => /\b(?:m-pesa|momo|mobile money|transaction id)\b.*\b(?:\+250\d{9}|\d{6,})/i
}

def sensitive_metadata_hits(record)
  scanned_fields = %w[reviewer signed_at evidence_reference notes]
  scanned_fields.each_with_object([]) do |field, hits|
    text = record[field].to_s
    next if text.strip == ""

    SENSITIVE_METADATA_PATTERNS.each do |name, pattern|
      hits << "#{field}:#{name}" if text.match?(pattern)
    end
  end.uniq
end

failure_keys = []
blocker_keys = []
checks = {}
manifest = {}

begin
  manifest = JSON.parse(File.read(manifest_path))
rescue Errno::ENOENT
  failure_keys << "release_approvals_manifest_missing"
  checks["manifest"] = check("fail", "Release approvals manifest is missing.", "path" => manifest_path)
rescue JSON::ParserError => error
  failure_keys << "release_approvals_manifest_json"
  checks["manifest"] = check("fail", "Release approvals manifest is not valid JSON.", "error" => error.message)
end

if manifest.any? && template_manifest?(manifest_path, manifest)
  failure_keys << "release_approvals_manifest_template"
  checks["manifest_template"] = check(
    "fail",
    "Release approvals manifest is a template/example and cannot approve production GO.",
    "path" => manifest_path
  )
end

records = Array(manifest["approvals"])
records_by_key = {}
records.each do |record|
  key = record["key"].to_s.strip
  if key == ""
    failure_keys << "release_approvals_key"
    next
  end
  if records_by_key.key?(key)
    failure_keys << "release_approvals_duplicate_key"
  end
  records_by_key[key] = record
end

missing_keys = required_keys - records_by_key.keys
extra_keys = records_by_key.keys - required_keys
unless missing_keys.empty?
  blocker_keys.concat(missing_keys)
  checks["required_keys"] = check("blocked", "Approval manifest is missing required approval records.", "missing_keys" => missing_keys)
end
unless extra_keys.empty?
  failure_keys << "release_approvals_unexpected_key"
  checks["unexpected_keys"] = check("fail", "Approval manifest contains unexpected approval records.", "extra_keys" => extra_keys)
end

%w[approval_packet qa_summary].each do |key|
  reference = manifest[key].to_s.strip
  if reference.length < 3
    blocker_keys << "#{key}_reference"
    checks[key] = check("blocked", "Approval manifest #{key} reference is missing.")
  elsif evidence_reference_valid?(reference, root_dir)
    checks[key] = check("pass", "Approval manifest #{key} reference exists.", "reference" => reference)
  else
    blocker_keys << "#{key}_reference"
    checks[key] = check("blocked", "Approval manifest #{key} reference does not resolve to a repo artifact or HTTPS URL.", "reference" => reference)
  end
end

approvals = {}
required_keys.each do |key|
  record = records_by_key[key] || {}
  status = record["status"].to_s.strip
  decision = record["decision"].to_s.strip
  reviewer = record["reviewer"].to_s.strip
  signed_at = record["signed_at"].to_s.strip
  evidence_reference = record["evidence_reference"].to_s.strip
  sanitized = record["sanitized_evidence"] == true
  contains_production_data = record["contains_production_customer_data"] == true
  signing_keys_exposed = record["signing_keys_exposed"] == true
  evidence_reference_valid = evidence_reference_valid?(evidence_reference, root_dir)
  placeholder_blockers = placeholder_approval_blockers(record)
  sensitive_hits = sensitive_metadata_hits(record)

  acceptable_status =
    if key == "ios_release_scope"
      (status == "approved" && decision == "GO") ||
        (status == "out_of_scope" && decision == "OUT_OF_SCOPE")
    else
      status == "approved" && decision == "GO"
    end

  blockers = []
  blockers << "status_decision" unless acceptable_status
  blockers << "reviewer" if reviewer.length < 2
  blockers << "signed_at" unless iso8601_utc?(signed_at)
  blockers << "evidence_reference" if evidence_reference.length < 3
  blockers << "evidence_reference_missing" if evidence_reference.length >= 3 && !evidence_reference_valid
  blockers << "sanitized_evidence" unless sanitized
  blockers << "production_customer_data" if contains_production_data
  blockers << "signing_keys_exposed" if key == "android_release_signing_review" && signing_keys_exposed
  blockers.concat(placeholder_blockers)
  blockers << "sensitive_metadata" unless sensitive_hits.empty?
  failure_keys << "release_approvals_sensitive_metadata" unless sensitive_hits.empty?

  approved = blockers.empty?
  blocker_keys << key unless approved
  approvals[key] = {
    "approved" => approved,
    "status" => status == "" ? "missing" : status,
    "decision" => decision == "" ? nil : decision,
    "reviewer" => reviewer == "" ? nil : reviewer,
    "signed_at" => signed_at == "" ? nil : signed_at,
    "evidence_reference" => evidence_reference == "" ? nil : evidence_reference,
    "evidence_reference_valid" => evidence_reference_valid,
    "sensitive_metadata_hits" => sensitive_hits,
    "blockers" => blockers
  }
end

owner = approvals.fetch("release_owner_signoff", {})
prerequisites = %w[
  product_signoff
  android_sms_access_uat
  android_release_signing_review
  ios_release_scope
]
missing_prerequisites = prerequisites.reject { |key| approvals.dig(key, "approved") == true }
if owner["approved"] == true && !missing_prerequisites.empty?
  blocker_keys << "release_owner_signoff"
  owner["approved"] = false
  owner["blockers"] = Array(owner["blockers"]) + ["missing_prerequisite_approvals"]
  owner["missing_prerequisites"] = missing_prerequisites
  approvals["release_owner_signoff"] = owner
end

failure_keys.uniq!
blocker_keys = blocker_keys.uniq
status =
  if failure_keys.any?
    "fail"
  elsif blocker_keys.any?
    "blocked"
  else
    "pass"
  end

result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "manifest" => manifest_path,
  "blocker_keys" => blocker_keys,
  "failure_keys" => failure_keys,
  "approvals" => approvals,
  "checks" => checks,
  "secret_handling" => "This gate validates approval metadata and evidence-reference existence only. Do not include secrets, signing keys, raw SMS bodies, phone/MoMo numbers, service-role keys, provider tokens, or production customer data."
}

if format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[release-approval-evidence-gate] status=#{status}"
  blocker_keys.each { |key| warn "[release-approval-evidence-gate][BLOCKED] #{key}" }
  failure_keys.each { |key| warn "[release-approval-evidence-gate][FAIL] #{key}" }
end

exit(status == "pass" ? 0 : status == "blocked" ? 99 : 1)
RUBY
