#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ruby -r json -r time -r uri -r fileutils - "$@" <<'RUBY'
root_dir = Dir.pwd

required_keys = %w[
  product_signoff
  android_sms_access_uat
  android_release_signing_review
  ios_release_scope
  release_owner_signoff
]

titles = {
  "product_signoff" => "Product definition approval",
  "android_sms_access_uat" => "Android MoMo SMS UAT approval",
  "android_release_signing_review" => "Android release signing review",
  "ios_release_scope" => "iOS release scope decision",
  "release_owner_signoff" => "Release-owner go/no-go approval"
}

options = {
  "manifest" => File.join(root_dir, "docs/release/RELEASE_APPROVALS.json"),
  "signed_at" => Time.now.utc.iso8601,
  "status" => nil,
  "decision" => nil,
  "sanitized_evidence" => false,
  "contains_production_customer_data" => nil,
  "signing_keys_exposed" => nil,
  "out_of_scope" => false
}

def usage
  warn <<~TEXT
    usage: scripts/record_release_approval.sh --key KEY --reviewer NAME --evidence-reference REF --notes NOTES --sanitized-evidence --no-production-customer-data [options]

    options:
      --manifest PATH                  Approval manifest to update (default docs/release/RELEASE_APPROVALS.json)
      --signed-at ISO8601Z             Signed timestamp (default current UTC)
      --status approved|out_of_scope   Approval status (default approved, or out_of_scope with --out-of-scope)
      --decision GO|OUT_OF_SCOPE       Approval decision (default GO, or OUT_OF_SCOPE with --out-of-scope)
      --out-of-scope                   Shortcut for iOS status=out_of_scope decision=OUT_OF_SCOPE
      --no-signing-keys-exposed        Required for android_release_signing_review
  TEXT
end

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--manifest"
    options["manifest"] = args.shift.to_s
  when "--key"
    options["key"] = args.shift.to_s
  when "--reviewer"
    options["reviewer"] = args.shift.to_s
  when "--evidence-reference", "--evidence"
    options["evidence_reference"] = args.shift.to_s
  when "--notes"
    options["notes"] = args.shift.to_s
  when "--signed-at"
    options["signed_at"] = args.shift.to_s
  when "--status"
    options["status"] = args.shift.to_s
  when "--decision"
    options["decision"] = args.shift.to_s
  when "--sanitized-evidence"
    options["sanitized_evidence"] = true
  when "--no-production-customer-data"
    options["contains_production_customer_data"] = false
  when "--no-signing-keys-exposed"
    options["signing_keys_exposed"] = false
  when "--out-of-scope"
    options["out_of_scope"] = true
  when "--help", "-h"
    usage
    exit 0
  else
    warn "unknown argument: #{arg}"
    usage
    exit 2
  end
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

approval_evidence_patterns = {
  "product_signoff" => [
    %r{\Adocs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW\.md\z},
    %r{\Adocs/release/RELEASE_APPROVAL_PACKET\.md\z}
  ],
  "android_sms_access_uat" => [
    %r{\Adocs/release/UAT_EVIDENCE_MANIFEST\.json\z},
    %r{\Adocs/ANDROID_SMS_ACCESS\.md\z},
    %r{\A\.cache/android_device_uat/[^/]+/summary\.json\z},
    %r{\A\.cache/repo_wide_qa_uat/[^/]+/uat_evidence_gate\.json\z}
  ],
  "android_release_signing_review" => [
    %r{\Adocs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02\.md\z},
    %r{\Adocs/release/BUILD_ARTIFACT_CHECKSUMS_[0-9-]+\.sha256\z},
    %r{\A\.cache/mobile_release_gate/[^/]+/summary\.json\z},
    %r{\A\.cache/android_install/[^/]+/final_release_summary\.json\z}
  ],
  "ios_release_scope" => [
    %r{\Adocs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02\.md\z},
    %r{\Adocs/release/RELEASE_APPROVAL_PACKET\.md\z},
    %r{\A\.cache/mobile_release_gate/[^/]+/summary\.json\z}
  ],
  "release_owner_signoff" => [
    %r{\Adocs/release/RELEASE_APPROVAL_PACKET\.md\z},
    %r{\A\.cache/repo_wide_qa_uat/[^/]+/summary\.json\z},
    %r{\A\.cache/repo_wide_qa_uat/[^/]+/evidence_index\.json\z}
  ]
}

def evidence_reference_in_scope?(key, value, approval_evidence_patterns)
  reference = value.to_s.strip
  return false if reference == ""
  return true if valid_https_url?(reference)
  return false if reference.match?(/\A[a-z][a-z0-9+.-]*:/i)

  normalized = reference.sub(%r{\A\./}, "")
  approval_evidence_patterns.fetch(key, []).any? do |pattern|
    reference.match?(pattern) || normalized.match?(pattern)
  end
end

sensitive_patterns = {
  "supabase_service_role" => /service[_-]?role\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "openai_api_key" => /sk-[A-Za-z0-9_\-]{20,}/,
  "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "rwanda_phone_number" => /\+250\d{9}\b/,
  "raw_momo_sms" => /\b(?:m-pesa|momo|mobile money|transaction id)\b.*\b(?:\+250\d{9}|\d{6,})/i
}

def sensitive_metadata_hits(record, patterns)
  %w[reviewer signed_at evidence_reference suggested_evidence_reference notes].each_with_object([]) do |field, hits|
    text = record[field].to_s
    next if text.strip == ""

    patterns.each do |name, pattern|
      hits << "#{field}:#{name}" if text.match?(pattern)
    end
  end.uniq
end

def placeholder_approval_record?(record)
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

  placeholder_reviewers.include?(record["reviewer"].to_s.strip) ||
    record["signed_at"].to_s.strip == "2026-06-01T00:00:00Z" ||
    placeholder_notes.include?(record["notes"].to_s.strip)
end

def approval_record_valid?(record, key, root_dir, patterns)
  status = record["status"].to_s.strip
  decision = record["decision"].to_s.strip
  acceptable_status =
    if key == "ios_release_scope"
      (status == "approved" && decision == "GO") ||
        (status == "out_of_scope" && decision == "OUT_OF_SCOPE")
    else
      status == "approved" && decision == "GO"
    end

  acceptable_status &&
    !placeholder_approval_record?(record) &&
    sensitive_metadata_hits(record, patterns).empty? &&
    record["reviewer"].to_s.strip.length >= 2 &&
    iso8601_utc?(record["signed_at"]) &&
    evidence_reference_valid?(record["evidence_reference"], root_dir) &&
    record["sanitized_evidence"] == true &&
    record["contains_production_customer_data"] == false &&
    (key != "android_release_signing_review" || record["signing_keys_exposed"] == false)
end

errors = []
key = options["key"].to_s.strip
errors << "--key is required." if key == ""
errors << "--key must be one of: #{required_keys.join(", ")}." if key != "" && !required_keys.include?(key)
errors << "--reviewer is required and must not be a placeholder." if options["reviewer"].to_s.strip.length < 2
errors << "--evidence-reference is required." if options["evidence_reference"].to_s.strip == ""
errors << "--notes is required and must describe the reviewed evidence." if options["notes"].to_s.strip.length < 10
errors << "--sanitized-evidence must be provided." unless options["sanitized_evidence"] == true
errors << "--no-production-customer-data must be provided." unless options["contains_production_customer_data"] == false
errors << "--signed-at must be ISO-8601 UTC ending in Z." unless iso8601_utc?(options["signed_at"])

if key == "android_release_signing_review" && options["signing_keys_exposed"] != false
  errors << "--no-signing-keys-exposed is required for android_release_signing_review."
end

if options["out_of_scope"]
  if key != "ios_release_scope"
    errors << "--out-of-scope is only valid for ios_release_scope."
  end
  options["status"] ||= "out_of_scope"
  options["decision"] ||= "OUT_OF_SCOPE"
end

options["status"] ||= "approved"
options["decision"] ||= "GO"

if key == "ios_release_scope"
  valid_ios_decision =
    (options["status"] == "approved" && options["decision"] == "GO") ||
    (options["status"] == "out_of_scope" && options["decision"] == "OUT_OF_SCOPE")
  errors << "ios_release_scope must be approved/GO or out_of_scope/OUT_OF_SCOPE." unless valid_ios_decision
elsif options["status"] != "approved" || options["decision"] != "GO"
  errors << "#{key} must use status=approved and decision=GO."
end

unless evidence_reference_valid?(options["evidence_reference"], root_dir)
  errors << "--evidence-reference must resolve to an existing repo artifact or HTTPS URL."
end

if key != "" &&
    evidence_reference_valid?(options["evidence_reference"], root_dir) &&
    !evidence_reference_in_scope?(key, options["evidence_reference"], approval_evidence_patterns)
  errors << "--evidence-reference is not an accepted evidence artifact for #{key}."
end

record = {
  "key" => key,
  "title" => titles[key],
  "status" => options["status"],
  "decision" => options["decision"],
  "reviewer" => options["reviewer"].to_s.strip,
  "signed_at" => options["signed_at"].to_s.strip,
  "evidence_reference" => options["evidence_reference"].to_s.strip,
  "sanitized_evidence" => true,
  "contains_production_customer_data" => false,
  "notes" => options["notes"].to_s.strip
}
record["signing_keys_exposed"] = false if key == "android_release_signing_review"

hits = sensitive_metadata_hits(record, sensitive_patterns)
errors << "approval metadata contains sensitive marker(s): #{hits.join(", ")}." unless hits.empty?
errors << "reviewer/notes look like a template placeholder." if placeholder_approval_record?(record)

begin
  manifest_path = File.expand_path(options["manifest"], root_dir)
  manifest = JSON.parse(File.read(manifest_path))
rescue Errno::ENOENT
  errors << "approval manifest is missing: #{options["manifest"]}."
rescue JSON::ParserError => error
  errors << "approval manifest is not valid JSON: #{error.message}."
end

if manifest
  records = Array(manifest["approvals"])
  by_key = records.each_with_object({}) do |existing, memo|
    existing_key = existing["key"].to_s.strip
    memo[existing_key] = existing if existing_key != ""
  end

  if key == "release_owner_signoff"
    missing = %w[
      product_signoff
      android_sms_access_uat
      android_release_signing_review
      ios_release_scope
    ].reject { |prereq| approval_record_valid?(by_key[prereq] || {}, prereq, root_dir, sensitive_patterns) }
    unless missing.empty?
      errors << "release_owner_signoff cannot be recorded until prerequisite approvals are valid: #{missing.join(", ")}."
    end
  end
end

unless errors.empty?
  warn JSON.pretty_generate({
    "status" => "fail",
    "errors" => errors
  })
  exit 1
end

records = Array(manifest["approvals"])
index = records.find_index { |existing| existing["key"].to_s.strip == key }
if index
  records[index] = records[index].merge(record)
else
  records << record
end

manifest["status"] = records.all? { |existing| approval_record_valid?(existing, existing["key"].to_s.strip, root_dir, sensitive_patterns) } ? "approved" : "pending"
manifest["approvals"] = records
manifest["secret_handling"] = "Approval evidence metadata only. Do not add secrets, signing keys, raw SMS bodies, phone/MoMo numbers, service keys, provider tokens, or production customer data."

tmp_path = "#{manifest_path}.tmp.#{$$}"
File.write(tmp_path, JSON.pretty_generate(manifest) + "\n")
FileUtils.mv(tmp_path, manifest_path)

puts JSON.pretty_generate({
  "status" => "pass",
  "manifest" => manifest_path.sub("#{root_dir}/", ""),
  "updated_key" => key,
  "approval_status" => record["status"],
  "decision" => record["decision"],
  "evidence_reference" => record["evidence_reference"]
})
RUBY
