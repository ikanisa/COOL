#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ruby -r json -r time -r fileutils -r uri - "$@" <<'RUBY'
root_dir = Dir.pwd
options = {
  "checklist" => File.join(root_dir, "docs/release/NATIVE_MOBILE_ACCESSIBILITY_SIGNOFF_CHECKLIST_2026-06-30.md"),
  "evidence_reference" => "docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md",
  "signed_at" => Time.now.utc.iso8601
}

signoff_rows = {
  "android_talkback" => "Android TalkBack auditory traversal",
  "ios_voiceover" => "iOS VoiceOver traversal or scoped waiver",
  "final_decision" => "Final native mobile accessibility decision"
}.freeze

def usage
  warn <<~TEXT
    usage:
      scripts/record_native_mobile_accessibility_signoff.sh --signoff android_talkback|ios_voiceover|final_decision --status signed|waived --reviewer NAME --signed-at ISO8601Z

    options:
      --checklist PATH            Signoff checklist to update
      --signoff KEY               android_talkback, ios_voiceover, or final_decision
      --status STATUS             signed or waived; only ios_voiceover can be waived
      --reviewer NAME             Human reviewer name, not a placeholder
      --signed-at ISO8601Z        UTC timestamp ending in Z
      --evidence-reference PATH   Repo-relative evidence file or HTTPS URL
  TEXT
end

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--checklist"
    options["checklist"] = args.shift.to_s
  when "--signoff"
    options["signoff"] = args.shift.to_s
  when "--status"
    options["status"] = args.shift.to_s
  when "--reviewer"
    options["reviewer"] = args.shift.to_s
  when "--signed-at"
    options["signed_at"] = args.shift.to_s
  when "--evidence-reference"
    options["evidence_reference"] = args.shift.to_s
  when "--help", "-h"
    usage
    exit 0
  else
    warn "unknown argument: #{arg}"
    usage
    exit 2
  end
end

sensitive_patterns = {
  "supabase_service_role" => /service[_-]?role\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "openai_api_key" => /sk-[A-Za-z0-9_\-]{20,}/,
  "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "rwanda_phone_number" => /\+250\d{9}\b/,
  "raw_momo_sms" => /\b(?:m-pesa|momo|mobile money|transaction id)\b.*\b(?:\+250\d{9}|\d{6,})/i
}.freeze

def iso8601_utc?(value)
  Time.iso8601(value.to_s)
  value.to_s.end_with?("Z")
rescue ArgumentError, TypeError
  false
end

def placeholder?(value)
  text = value.to_s.strip
  text == "" ||
    text.match?(/\A(?:reviewer|tester|owner|signer|pending(?: .*)?|todo|tbd|template|placeholder|n\/a)\z/i)
end

def safe_relative_path?(path)
  path.to_s.strip != "" && !path.start_with?("/") && !path.include?("..")
end

def repo_relative(path, root_dir)
  expanded = File.expand_path(path, root_dir)
  root = File.expand_path(root_dir)
  return nil unless expanded == root || expanded.start_with?("#{root}/")

  expanded.sub("#{root}/", "")
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
  return false unless safe_relative_path?(reference)

  path = File.expand_path(reference, root_dir)
  root = File.expand_path(root_dir)
  inside_repo = path == root || path.start_with?("#{root}/")
  inside_repo && File.exist?(path)
end

def sensitive_hits(fields, patterns)
  fields.each_with_object([]) do |(field, value), hits|
    text = value.to_s
    next if text.strip == ""

    patterns.each do |name, pattern|
      hits << "#{field}:#{name}" if text.match?(pattern)
    end
  end.uniq
end

def parse_rows(text)
  rows = {}
  text.lines.each do |line|
    next unless line.start_with?("| ")
    cells = line.split("|").map(&:strip)
    name = cells[1].to_s
    next if name == "" || cells.length < 7

    rows[name] = {
      "line" => line,
      "status" => cells[2].to_s,
      "action" => cells[3].to_s,
      "evidence_reference" => cells[4].to_s.delete_prefix("`").delete_suffix("`").strip,
      "reviewer" => cells[5].to_s,
      "signed_at" => cells[6].to_s
    }
  end
  rows
end

def row_approved?(row, name, root_dir)
  return false unless row

  allowed = name == "iOS VoiceOver traversal or scoped waiver" ? %w[Signed Waived] : %w[Signed]
  allowed.any? { |status| row.fetch("status").casecmp?(status) } &&
    !placeholder?(row.fetch("reviewer")) &&
    iso8601_utc?(row.fetch("signed_at")) &&
    evidence_reference_valid?(row.fetch("evidence_reference"), root_dir)
end

errors = []
signoff_key = options["signoff"].to_s.strip
status = options["status"].to_s.strip.downcase
reviewer = options["reviewer"].to_s.strip
signed_at = options["signed_at"].to_s.strip
evidence_reference = options["evidence_reference"].to_s.strip
checklist_path = File.expand_path(options["checklist"], root_dir)
relative_checklist = repo_relative(checklist_path, root_dir)
target_name = signoff_rows[signoff_key]

errors << "--signoff must be one of: #{signoff_rows.keys.join(", ")}." unless target_name
errors << "--status must be signed or waived." unless %w[signed waived].include?(status)
errors << "Only ios_voiceover can be waived." if status == "waived" && signoff_key != "ios_voiceover"
errors << "--reviewer is required and must not be a placeholder." if reviewer.length < 2 || placeholder?(reviewer)
errors << "--signed-at must be ISO-8601 UTC ending in Z." unless iso8601_utc?(signed_at)
errors << "--evidence-reference must be a repo-relative existing file or HTTPS URL." unless evidence_reference_valid?(evidence_reference, root_dir)
errors << "--checklist must stay inside the repo." unless relative_checklist && safe_relative_path?(relative_checklist)

hits = sensitive_hits(
  {
    "reviewer" => reviewer,
    "signed_at" => signed_at,
    "evidence_reference" => evidence_reference
  },
  sensitive_patterns
)
errors << "metadata contains sensitive marker(s): #{hits.join(", ")}." unless hits.empty?

text = nil
begin
  text = File.read(checklist_path)
rescue Errno::ENOENT
  errors << "Signoff checklist is missing: #{options["checklist"]}."
end

rows = text ? parse_rows(text) : {}
errors << "Target signoff row is missing: #{target_name}." if target_name && !rows.key?(target_name)

if target_name == signoff_rows.fetch("final_decision")
  prerequisite_names = [
    signoff_rows.fetch("android_talkback"),
    signoff_rows.fetch("ios_voiceover")
  ]
  missing_prerequisites = prerequisite_names.reject { |name| row_approved?(rows[name], name, root_dir) }
  errors << "Final decision cannot be recorded until prerequisite signoffs pass: #{missing_prerequisites.join(", ")}." unless missing_prerequisites.empty?
end

unless errors.empty?
  warn JSON.pretty_generate({
    "status" => "fail",
    "errors" => errors.uniq
  })
  exit 1
end

display_status = status == "signed" ? "Signed" : "Waived"
updated_text = text.lines.map do |line|
  unless line.start_with?("| ")
    line
  else
    cells = line.split("|").map(&:strip)
    if cells[1].to_s == target_name
      "| #{cells[1]} | #{display_status} | #{cells[3]} | `#{evidence_reference}` | #{reviewer} | #{signed_at} |\n"
    else
      line
    end
  end
end.join

updated_rows = parse_rows(updated_text)
all_approved = signoff_rows.values.all? do |name|
  row_approved?(updated_rows[name], name, root_dir)
end
updated_text = updated_text.sub(
  /Current decision: \*\*[^*]+\*\*/,
  all_approved ? "Current decision: **GO after signed review**" : "Current decision: **NO-GO until signed**"
)

tmp_path = "#{checklist_path}.tmp.#{$$}"
File.write(tmp_path, updated_text)
FileUtils.mv(tmp_path, checklist_path)

puts JSON.pretty_generate({
  "status" => "pass",
  "checklist" => relative_checklist,
  "updated_signoff" => signoff_key,
  "updated_row" => target_name,
  "row_status" => display_status,
  "all_native_mobile_accessibility_signoffs_approved" => all_approved,
  "secret_handling" => "This recorder writes sanitized signoff metadata only. Do not include secrets, signing keys, raw SMS bodies, OTPs, phone numbers, raw MoMo numbers, provider tokens, or production customer data."
})
RUBY
