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

OUTPUT_FORMAT="$output_format" \
MANIFEST_PATH="$manifest_path" \
ROOT_DIR="$ROOT_DIR" \
COLLECT_ANDROID_RELEASE_APK_PATH="${COLLECT_ANDROID_RELEASE_APK_PATH:-build/app/outputs/flutter-apk/app-production-release.apk}" \
COLLECT_ANDROID_RELEASE_AAB_PATH="${COLLECT_ANDROID_RELEASE_AAB_PATH:-build/app/outputs/bundle/productionRelease/app-production-release.aab}" \
ruby -r json -r time -r uri -r digest <<'RUBY'
format = ENV.fetch("OUTPUT_FORMAT")
manifest_path = ENV.fetch("MANIFEST_PATH")
root_dir = ENV.fetch("ROOT_DIR")
pubspec_path = File.join(root_dir, "pubspec.yaml")

ANDROID_RELEASE_ARTIFACTS = {
  "apk" => ENV.fetch("COLLECT_ANDROID_RELEASE_APK_PATH"),
  "aab" => ENV.fetch("COLLECT_ANDROID_RELEASE_AAB_PATH")
}.freeze

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

APPROVAL_EVIDENCE_PATTERNS = {
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
    %r{\Adocs/release/RELEASE_STATUS\.md\z},
    %r{\Aoutput/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_[0-9-]+\.sha256\z},
    %r{\A\.cache/mobile_release_gate/[^/]+/summary\.json\z},
    %r{\A\.cache/android_install/[^/]+/final_release_summary\.json\z}
  ],
  "ios_release_scope" => [
    %r{\Adocs/release/RELEASE_STATUS\.md\z},
    %r{\Adocs/release/RELEASE_APPROVAL_PACKET\.md\z},
    %r{\A\.cache/mobile_release_gate/[^/]+/summary\.json\z}
  ],
  "release_owner_signoff" => [
    %r{\Adocs/release/RELEASE_APPROVAL_PACKET\.md\z},
    %r{\A\.cache/repo_wide_qa_uat/[^/]+/summary\.json\z},
    %r{\A\.cache/repo_wide_qa_uat/[^/]+/evidence_index\.json\z}
  ]
}

def evidence_reference_in_scope?(key, value)
  reference = value.to_s.strip
  return false if reference == ""
  return true if valid_https_url?(reference)
  return false if reference.match?(/\A[a-z][a-z0-9+.-]*:/i)

  normalized = reference.sub(%r{\A\./}, "")
  APPROVAL_EVIDENCE_PATTERNS.fetch(key, []).any? do |pattern|
    reference.match?(pattern) || normalized.match?(pattern)
  end
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
  scanned_fields = %w[reviewer signed_at evidence_reference suggested_evidence_reference notes]
  scanned_fields.each_with_object([]) do |field, hits|
    text = record[field].to_s
    next if text.strip == ""

    SENSITIVE_METADATA_PATTERNS.each do |name, pattern|
      hits << "#{field}:#{name}" if text.match?(pattern)
    end
  end.uniq
end

def approved_artifact_version(record)
  explicit = record["artifact_version"].to_s.strip
  return explicit unless explicit == ""

  record["notes"].to_s[/\b[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+\b/]
end

def current_android_artifact_evidence(root_dir)
  ANDROID_RELEASE_ARTIFACTS.transform_values do |relative_path|
    path = File.expand_path(relative_path, root_dir)
    next {"path" => relative_path, "exists" => false, "sha256" => nil, "mtime" => nil} unless File.file?(path)

    {
      "path" => relative_path,
      "exists" => true,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "mtime" => File.mtime(path).utc
    }
  end
end

def normalized_android_artifact_digests(record)
  value = record["android_artifact_sha256"]
  return {} unless value.is_a?(Hash)

  value.transform_keys(&:to_s).transform_values { |digest| digest.to_s.strip.downcase }
end

failure_keys = []
blocker_keys = []
checks = {}
manifest = {}
pubspec = File.read(pubspec_path) rescue ""
version_match = pubspec.match(/^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$/)
current_artifact_version = version_match && version_match[1]
current_android_artifacts = current_android_artifact_evidence(root_dir)

if current_artifact_version
  checks["artifact_version"] = check(
    "pass",
    "Current release artifact version was read from pubspec.yaml.",
    "current_artifact_version" => current_artifact_version
  )
else
  failure_keys << "pubspec_artifact_version"
  checks["artifact_version"] = check(
    "fail",
    "pubspec.yaml must define the current release artifact version as MAJOR.MINOR.PATCH+BUILD."
  )
end

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
  suggested_evidence_reference = record["suggested_evidence_reference"].to_s.strip
  sanitized = record["sanitized_evidence"] == true
  contains_production_data = record["contains_production_customer_data"] == true
  signing_keys_exposed = record["signing_keys_exposed"] == true
  evidence_reference_valid = evidence_reference_valid?(evidence_reference, root_dir)
  suggested_evidence_reference_valid =
    suggested_evidence_reference.length >= 3 &&
    evidence_reference_valid?(suggested_evidence_reference, root_dir)
  placeholder_blockers = placeholder_approval_blockers(record)
  sensitive_hits = sensitive_metadata_hits(record)
  approved_artifact_version = approved_artifact_version(record)
  version_bound = %w[
    android_release_signing_review
    release_owner_signoff
  ].include?(key)
  artifact_version_current =
    !version_bound ||
    (
      current_artifact_version &&
      approved_artifact_version == current_artifact_version
    )
  digest_bound = %w[
    android_release_signing_review
    release_owner_signoff
  ].include?(key)
  approved_android_digests = normalized_android_artifact_digests(record)
  android_artifacts_present =
    !digest_bound || current_android_artifacts.values.all? { |item| item["exists"] == true }
  android_artifact_digests_complete =
    !digest_bound || ANDROID_RELEASE_ARTIFACTS.keys.all? do |artifact_key|
      approved_android_digests[artifact_key].to_s.match?(/\A[0-9a-f]{64}\z/)
    end
  android_artifact_digests_current =
    !digest_bound ||
    (
      android_artifacts_present &&
      android_artifact_digests_complete &&
      ANDROID_RELEASE_ARTIFACTS.keys.all? do |artifact_key|
        approved_android_digests[artifact_key] == current_android_artifacts.dig(artifact_key, "sha256")
      end
    )
  signed_time = Time.iso8601(signed_at) rescue nil
  latest_android_artifact_time =
    digest_bound && android_artifacts_present ? current_android_artifacts.values.map { |item| item["mtime"] }.compact.max : nil
  approval_after_artifacts =
    !digest_bound ||
    (
      signed_time &&
      latest_android_artifact_time &&
      signed_time >= latest_android_artifact_time
    )

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
  blockers << "evidence_reference_scope" if evidence_reference_valid && !evidence_reference_in_scope?(key, evidence_reference)
  blockers << "sanitized_evidence" unless sanitized
  blockers << "production_customer_data" if contains_production_data
  blockers << "signing_keys_exposed" if key == "android_release_signing_review" && signing_keys_exposed
  blockers << "artifact_version" if version_bound && approved_artifact_version.to_s.strip == ""
  blockers << "stale_artifact_version" if version_bound && approved_artifact_version.to_s.strip != "" && !artifact_version_current
  blockers << "android_release_artifacts_missing" if digest_bound && !android_artifacts_present
  blockers << "android_artifact_sha256" if digest_bound && !android_artifact_digests_complete
  blockers << "android_artifact_sha256_mismatch" if digest_bound && android_artifact_digests_complete && android_artifacts_present && !android_artifact_digests_current
  blockers << "approval_predates_android_artifacts" if digest_bound && android_artifacts_present && !approval_after_artifacts
  blockers.concat(placeholder_blockers)
  blockers << "sensitive_metadata" unless sensitive_hits.empty?
  failure_keys << "release_approvals_sensitive_metadata" unless sensitive_hits.empty?
  failure_keys << "release_approvals_suggested_evidence_reference" if suggested_evidence_reference.length >= 3 && !suggested_evidence_reference_valid

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
    "evidence_reference_in_scope" => evidence_reference.length >= 3 ? evidence_reference_in_scope?(key, evidence_reference) : nil,
    "suggested_evidence_reference" => suggested_evidence_reference == "" ? nil : suggested_evidence_reference,
    "suggested_evidence_reference_valid" => suggested_evidence_reference == "" ? nil : suggested_evidence_reference_valid,
    "current_artifact_version" => version_bound ? current_artifact_version : nil,
    "approved_artifact_version" => version_bound ? approved_artifact_version : nil,
    "artifact_version_current" => version_bound ? artifact_version_current : nil,
    "approved_android_artifact_sha256" => digest_bound ? approved_android_digests : nil,
    "current_android_artifacts" => digest_bound ? current_android_artifacts.transform_values { |item| item.merge("mtime" => item["mtime"]&.iso8601) } : nil,
    "android_artifact_digests_current" => digest_bound ? android_artifact_digests_current : nil,
    "approval_after_android_artifacts" => digest_bound ? approval_after_artifacts : nil,
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
