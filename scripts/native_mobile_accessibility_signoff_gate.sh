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

checklist_path="${NATIVE_MOBILE_ACCESSIBILITY_SIGNOFF_CHECKLIST:-docs/release/NATIVE_MOBILE_ACCESSIBILITY_SIGNOFF_CHECKLIST_2026-06-30.md}"
evidence_path="${NATIVE_MOBILE_DEVICE_EVIDENCE_FILE:-docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md}"

OUTPUT_FORMAT="$output_format" \
ROOT_DIR="$ROOT_DIR" \
CHECKLIST_PATH="$checklist_path" \
EVIDENCE_PATH="$evidence_path" \
ruby -r json -r time -r uri <<'RUBY'
format = ENV.fetch("OUTPUT_FORMAT")
root_dir = ENV.fetch("ROOT_DIR")
checklist_path = ENV.fetch("CHECKLIST_PATH")
evidence_path = ENV.fetch("EVIDENCE_PATH")

required_items = [
  "Android TalkBack structural responsibility",
  "iOS VoiceOver scope responsibility",
  "Final Codex accessibility responsibility"
]

required_human_signoffs = [
  "Android TalkBack auditory traversal",
  "iOS VoiceOver traversal or scoped waiver",
  "Final native mobile accessibility decision"
]

sensitive_patterns = {
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

def sensitive_hits(fields, patterns)
  fields.each_with_object([]) do |(name, value), hits|
    text = value.to_s
    next if text.strip == ""

    patterns.each do |key, pattern|
      hits << "#{name}:#{key}" if text.match?(pattern)
    end
  end.uniq
end

def placeholder?(value)
  text = value.to_s.strip
  text == "" ||
    text.match?(/\A(?:reviewer|tester|owner|signer|pending(?: .*)?|todo|tbd|template|placeholder|n\/a)\z/i)
end

blockers = []
failure_keys = []
responsibilities = {}
human_signoffs = {}
checks = {}

if !File.exist?(evidence_path)
  blockers << "Native mobile device evidence report is missing: #{evidence_path}."
else
  evidence = File.read(evidence_path)
  evidence_markers = [
    "Android structural accessibility",
    "iOS simulator smoke",
    "Code-owned structural accessibility responsibility",
    "Human auditory signoff still required",
    "native_mobile_accessibility_signoff_gate.sh"
  ]
  missing_markers = evidence_markers.reject { |marker| evidence.include?(marker) }
  blockers << "Native mobile device evidence report is missing marker(s): #{missing_markers.join(", ")}." unless missing_markers.empty?
  checks["evidence_report"] = {
    "status" => missing_markers.empty? ? "pass" : "blocked",
    "path" => evidence_path,
    "missing_markers" => missing_markers
  }
end

if !File.exist?(checklist_path)
  blockers << "Native mobile accessibility responsibility checklist is missing: #{checklist_path}."
else
  checklist = File.read(checklist_path)
  blockers << "Checklist decision must keep human auditory signoff open." unless checklist.include?("Current decision: **CODE-OWNED STRUCTURAL PASS; HUMAN AUDITORY SIGNOFF OPEN**")

  checklist.lines(chomp: true).each do |line|
    next unless line.start_with?("| ")
    cells = line.split("|").map(&:strip)
    name = cells[1].to_s
    next unless required_items.include?(name)

    status = cells[2].to_s
    evidence_reference = cells[4].to_s.delete_prefix("`").delete_suffix("`").strip
    owner = cells[5].to_s
    accepted_at = cells[6].to_s
    row_hits = sensitive_hits(
      {
        "responsibility" => name,
        "status" => status,
        "evidence_reference" => evidence_reference,
        "owner" => owner,
        "accepted_at" => accepted_at
      },
      sensitive_patterns
    )

    approved = status.casecmp?("Accepted") &&
      owner.casecmp?("Codex") &&
      iso8601_utc?(accepted_at) &&
      evidence_reference_valid?(evidence_reference, root_dir) &&
      row_hits.empty?

    responsibilities[name] = {
      "status" => status,
      "owner" => owner,
      "owner_is_codex" => owner.casecmp?("Codex"),
      "accepted_at" => accepted_at,
      "accepted_at_valid" => iso8601_utc?(accepted_at),
      "evidence_reference" => evidence_reference,
      "evidence_reference_valid" => evidence_reference_valid?(evidence_reference, root_dir),
      "sensitive_metadata_hits" => row_hits,
      "approved" => approved
    }
    failure_keys << "sensitive_native_mobile_accessibility_responsibility_metadata" unless row_hits.empty?
  end

  missing = required_items - responsibilities.keys
  blockers << "Required native mobile accessibility responsibility rows are missing: #{missing.join(", ")}." unless missing.empty?
  pending = responsibilities.select { |_name, row| !row.fetch("approved") }.keys
  blockers << "Native mobile accessibility responsibility incomplete: #{pending.join(", ")}." unless pending.empty?

  checklist.lines(chomp: true).each do |line|
    next unless line.start_with?("| ")
    cells = line.split("|").map(&:strip)
    name = cells[1].to_s
    next unless required_human_signoffs.include?(name)

    status = cells[2].to_s
    evidence_reference = cells[4].to_s.delete_prefix("`").delete_suffix("`").strip
    reviewer = cells[5].to_s
    signed_at = cells[6].to_s
    row_hits = sensitive_hits(
      {
        "signoff" => name,
        "status" => status,
        "evidence_reference" => evidence_reference,
        "reviewer" => reviewer,
        "signed_at" => signed_at
      },
      sensitive_patterns
    )

    allowed_statuses =
      if name == "iOS VoiceOver traversal or scoped waiver"
        %w[Signed Waived]
      else
        %w[Signed]
      end

    approved = allowed_statuses.any? { |allowed| status.casecmp?(allowed) } &&
      !placeholder?(reviewer) &&
      iso8601_utc?(signed_at) &&
      evidence_reference_valid?(evidence_reference, root_dir) &&
      row_hits.empty?

    human_signoffs[name] = {
      "status" => status,
      "reviewer_present" => !placeholder?(reviewer),
      "signed_at" => signed_at,
      "signed_at_valid" => iso8601_utc?(signed_at),
      "evidence_reference" => evidence_reference,
      "evidence_reference_valid" => evidence_reference_valid?(evidence_reference, root_dir),
      "sensitive_metadata_hits" => row_hits,
      "approved" => approved
    }
    failure_keys << "sensitive_native_mobile_accessibility_signoff_metadata" unless row_hits.empty?
  end

  missing_human = required_human_signoffs - human_signoffs.keys
  blockers << "Required native mobile accessibility signoff rows are missing: #{missing_human.join(", ")}." unless missing_human.empty?
  pending_human = human_signoffs.select { |_name, row| !row.fetch("approved") }.keys
  blockers << "Native mobile accessibility human signoff incomplete: #{pending_human.join(", ")}." unless pending_human.empty?
end

blockers.uniq!
failure_keys.uniq!
blocker_keys = []
if blockers.any? { |blocker| blocker.include?("responsibility") || blocker.include?("Checklist decision") }
  blocker_keys << "codex_native_mobile_accessibility_responsibility"
end
if blockers.any? { |blocker| blocker.include?("human signoff") || blocker.include?("signoff rows") }
  blocker_keys << "human_native_mobile_accessibility_signoff"
end
blocker_keys = ["native_mobile_accessibility_signoff"] if blockers.any? && blocker_keys.empty?
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
  "blocker_keys" => status == "pass" ? [] : blocker_keys,
  "failure_keys" => failure_keys,
  "blockers" => blockers,
  "responsibilities" => responsibilities,
  "human_signoffs" => human_signoffs,
  "checks" => checks,
  "secret_handling" => "This gate reads sanitized Codex ownership metadata only. Do not add secrets, signing keys, raw SMS bodies, OTPs, private phone numbers, raw receiver MoMo numbers, provider tokens, or production customer data."
}

if format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[native-mobile-accessibility-signoff] status=#{status} decision=#{result.fetch("decision")}"
  blockers.each { |blocker| warn "[native-mobile-accessibility-signoff][BLOCKED] #{blocker}" }
  failure_keys.each { |key| warn "[native-mobile-accessibility-signoff][FAIL] #{key}" }
end

exit(status == "pass" ? 0 : status == "blocked" ? 99 : 1)
RUBY
