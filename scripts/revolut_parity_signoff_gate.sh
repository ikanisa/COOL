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

checklist_path="${REVOLUT_PARITY_SIGNOFF_CHECKLIST:-docs/design/REVOLUT_PARITY_SIGNOFF_CHECKLIST_2026-06-18.md}"
evidence_path="${REVOLUT_PARITY_EVIDENCE_FILE:-docs/design/REVOLUT_PARITY_EVIDENCE_2026-06-18.md}"
approvals_path="${RELEASE_APPROVALS_JSON:-docs/release/RELEASE_APPROVALS.json}"

OUTPUT_FORMAT="$output_format" \
ROOT_DIR="$ROOT_DIR" \
CHECKLIST_PATH="$checklist_path" \
EVIDENCE_PATH="$evidence_path" \
APPROVALS_PATH="$approvals_path" \
ruby -r json -r time -r uri <<'RUBY'
format = ENV.fetch("OUTPUT_FORMAT")
root_dir = ENV.fetch("ROOT_DIR")
checklist_path = ENV.fetch("CHECKLIST_PATH")
evidence_path = ENV.fetch("EVIDENCE_PATH")
approvals_path = ENV.fetch("APPROVALS_PATH")

required_signoffs = [
  "Revolut reference visual parity",
  "Android TalkBack auditory review",
  "iOS VoiceOver or scope decision",
  "Android release signing / Play App Signing review",
  "Final release-owner parity decision"
]

SENSITIVE_PATTERNS = {
  "supabase_service_role" => /service[_-]?role\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "openai_api_key" => /sk-[A-Za-z0-9_\-]{20,}/,
  "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "rwanda_phone_number" => /\+250\d{9}\b/,
  "raw_momo_sms" => /\b(?:m-pesa|momo|mobile money|transaction id)\b.*\b(?:\+250\d{9}|\d{6,})/i
}

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

def placeholder?(value)
  text = value.to_s.strip
  text == "" ||
    %w[reviewer tester owner signer].include?(text.downcase) ||
    text.match?(/\b(?:todo|pending|template|placeholder|tbd|n\/a)\b/i)
end

def sensitive_hits(fields)
  fields.each_with_object([]) do |(name, value), hits|
    text = value.to_s
    next if text.strip == ""

    SENSITIVE_PATTERNS.each do |key, pattern|
      hits << "#{name}:#{key}" if text.match?(pattern)
    end
  end.uniq
end

def release_record_valid?(record, key, root_dir)
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
    !placeholder?(record["reviewer"]) &&
    iso8601_utc?(record["signed_at"]) &&
    evidence_reference_valid?(record["evidence_reference"], root_dir) &&
    record["sanitized_evidence"] == true &&
    record["contains_production_customer_data"] != true &&
    (key != "android_release_signing_review" || record["signing_keys_exposed"] != true) &&
    sensitive_hits({
      "reviewer" => record["reviewer"],
      "signed_at" => record["signed_at"],
      "evidence_reference" => record["evidence_reference"],
      "notes" => record["notes"]
    }).empty?
end

blockers = []
failure_keys = []
checks = {}
signoffs = {}

unless File.exist?(evidence_path)
  blockers << "Parity evidence report is missing: #{evidence_path}."
else
  evidence = File.read(evidence_path)
  checks["evidence_report"] = {
    "status" => evidence.include?("Status: **NO-GO") ? "pass" : "blocked",
    "path" => evidence_path
  }
  blockers << "Parity evidence report must remain NO-GO until this gate passes." unless evidence.include?("Status: **NO-GO")
end

if !File.exist?(checklist_path)
  blockers << "Parity signoff checklist is missing: #{checklist_path}."
else
  checklist = File.read(checklist_path)
  blockers << "Checklist decision is still explicitly NO-GO." if checklist.include?("Current decision: **NO-GO until signed**")
  checklist.lines(chomp: true).each do |line|
    next unless line.start_with?("| ")
    cells = line.split("|").map(&:strip)
    next unless required_signoffs.include?(cells[1].to_s)

    name = cells[1]
    status = cells[2].to_s
    evidence_reference = cells[4].to_s.delete_prefix("`").delete_suffix("`").strip
    reviewer = cells[5].to_s
    signed_at = cells[6].to_s
    row_hits = sensitive_hits({
      "signoff" => name,
      "status" => status,
      "evidence_reference" => evidence_reference,
      "reviewer" => reviewer,
      "signed_at" => signed_at
    })
    approved = status.match?(/\A(?:Signed|Waived)\z/i) &&
      !placeholder?(reviewer) &&
      iso8601_utc?(signed_at) &&
      evidence_reference_valid?(evidence_reference, root_dir) &&
      row_hits.empty?
    approved = false if name == "Final release-owner parity decision" && !status.match?(/\ASigned\z/i)

    signoffs[name] = {
      "status" => status,
      "reviewer_present" => !placeholder?(reviewer),
      "signed_at" => signed_at,
      "signed_at_valid" => iso8601_utc?(signed_at),
      "evidence_reference" => evidence_reference,
      "evidence_reference_valid" => evidence_reference_valid?(evidence_reference, root_dir),
      "sensitive_metadata_hits" => row_hits,
      "approved" => approved
    }
    failure_keys << "sensitive_parity_signoff_metadata" unless row_hits.empty?
  end

  missing = required_signoffs - signoffs.keys
  blockers << "Required parity signoff rows are missing: #{missing.join(", ")}." unless missing.empty?
  pending = signoffs.select { |_name, row| !row.fetch("approved") }.keys
  blockers << "Parity signoff incomplete: #{pending.join(", ")}." unless pending.empty?
end

approvals = {}
begin
  release_manifest = JSON.parse(File.read(approvals_path))
  Array(release_manifest["approvals"]).each do |record|
    key = record["key"].to_s.strip
    approvals[key] = record if key != ""
  end
rescue Errno::ENOENT
  blockers << "Release approvals manifest is missing: #{approvals_path}."
rescue JSON::ParserError => error
  failure_keys << "release_approvals_json"
  blockers << "Release approvals manifest is not valid JSON: #{error.message}."
end

%w[android_release_signing_review ios_release_scope].each do |key|
  record = approvals[key] || {}
  valid = release_record_valid?(record, key, root_dir)
  checks[key] = {
    "status" => valid ? "pass" : "blocked",
    "approval_status" => record["status"] || "missing",
    "decision" => record["decision"],
    "evidence_reference" => record["evidence_reference"]
  }
  blockers << "Release approval #{key} is not signed for parity completion." unless valid
end

blockers.uniq!
failure_keys.uniq!
status =
  if failure_keys.any?
    "fail"
  elsif blockers.any?
    "blocked"
  else
    "pass"
  end

result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "decision" => status == "pass" ? "GO" : "NO-GO",
  "checklist" => checklist_path,
  "evidence_report" => evidence_path,
  "release_approvals" => approvals_path,
  "blocker_keys" => status == "pass" ? [] : ["human_revolut_parity_signoff"],
  "failure_keys" => failure_keys,
  "blockers" => blockers,
  "signoffs" => signoffs,
  "checks" => checks,
  "secret_handling" => "This gate reads sanitized signoff metadata only. Do not add secrets, signing keys, raw SMS bodies, OTPs, private phone numbers, raw receiver MoMo numbers, provider tokens, or production customer data."
}

if format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[revolut-parity-signoff] status=#{status} decision=#{result.fetch("decision")}"
  blockers.each { |blocker| warn "[revolut-parity-signoff][BLOCKED] #{blocker}" }
  failure_keys.each { |key| warn "[revolut-parity-signoff][FAIL] #{key}" }
end

exit(status == "pass" ? 0 : status == "blocked" ? 99 : 1)
RUBY
