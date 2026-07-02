#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ruby -r json -r time -r fileutils -r uri - "$@" <<'RUBY'
root_dir = Dir.pwd
options = {
  "checklist" => File.join(root_dir, "docs/release/NATIVE_MOBILE_ACCESSIBILITY_SIGNOFF_CHECKLIST_2026-06-30.md"),
  "evidence_reference" => "docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md",
  "accepted_at" => Time.now.utc.iso8601
}

responsibility_rows = {
  "android_talkback" => "Android TalkBack structural responsibility",
  "ios_voiceover" => "iOS VoiceOver scope responsibility",
  "final_decision" => "Final Codex accessibility responsibility"
}.freeze

def usage
  warn <<~TEXT
    usage:
      scripts/record_native_mobile_accessibility_signoff.sh --responsibility android_talkback|ios_voiceover|final_decision --accepted-at ISO8601Z

    options:
      --checklist PATH            Responsibility checklist to update
      --responsibility KEY        android_talkback, ios_voiceover, or final_decision
      --accepted-at ISO8601Z      UTC timestamp ending in Z
      --evidence-reference PATH   Repo-relative evidence file or HTTPS URL

    compatibility:
      --signoff KEY is accepted as an alias for --responsibility.
      --status accepted is optional.
  TEXT
end

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--checklist"
    options["checklist"] = args.shift.to_s
  when "--responsibility", "--signoff"
    options["responsibility"] = args.shift.to_s
  when "--status"
    options["status"] = args.shift.to_s
  when "--accepted-at", "--signed-at"
    options["accepted_at"] = args.shift.to_s
  when "--evidence-reference"
    options["evidence_reference"] = args.shift.to_s
  when "--reviewer"
    warn "--reviewer is no longer accepted; Codex owns this responsibility."
    exit 2
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
      "owner" => cells[5].to_s,
      "accepted_at" => cells[6].to_s
    }
  end
  rows
end

def row_approved?(row, root_dir)
  row &&
    row.fetch("status").casecmp?("Accepted") &&
    row.fetch("owner").casecmp?("Codex") &&
    iso8601_utc?(row.fetch("accepted_at")) &&
    evidence_reference_valid?(row.fetch("evidence_reference"), root_dir)
end

errors = []
responsibility_key = options["responsibility"].to_s.strip
status = options["status"].to_s.strip.downcase
accepted_at = options["accepted_at"].to_s.strip
evidence_reference = options["evidence_reference"].to_s.strip
checklist_path = File.expand_path(options["checklist"], root_dir)
relative_checklist = repo_relative(checklist_path, root_dir)
target_name = responsibility_rows[responsibility_key]

errors << "--responsibility must be one of: #{responsibility_rows.keys.join(", ")}." unless target_name
errors << "--status, when provided, must be accepted." unless status == "" || status == "accepted"
errors << "--accepted-at must be ISO-8601 UTC ending in Z." unless iso8601_utc?(accepted_at)
errors << "--evidence-reference must be a repo-relative existing file or HTTPS URL." unless evidence_reference_valid?(evidence_reference, root_dir)
errors << "--checklist must stay inside the repo." unless relative_checklist && safe_relative_path?(relative_checklist)

hits = sensitive_hits(
  {
    "accepted_at" => accepted_at,
    "evidence_reference" => evidence_reference
  },
  sensitive_patterns
)
errors << "metadata contains sensitive marker(s): #{hits.join(", ")}." unless hits.empty?

text = nil
begin
  text = File.read(checklist_path)
rescue Errno::ENOENT
  errors << "Responsibility checklist is missing: #{options["checklist"]}."
end

rows = text ? parse_rows(text) : {}
errors << "Target responsibility row is missing: #{target_name}." if target_name && !rows.key?(target_name)

if target_name == responsibility_rows.fetch("final_decision")
  prerequisite_names = [
    responsibility_rows.fetch("android_talkback"),
    responsibility_rows.fetch("ios_voiceover")
  ]
  missing_prerequisites = prerequisite_names.reject { |name| row_approved?(rows[name], root_dir) }
  errors << "Final responsibility cannot be recorded until prerequisite responsibilities pass: #{missing_prerequisites.join(", ")}." unless missing_prerequisites.empty?
end

unless errors.empty?
  warn JSON.pretty_generate({
    "status" => "fail",
    "errors" => errors.uniq
  })
  exit 1
end

updated_text = text.lines.map do |line|
  unless line.start_with?("| ")
    line
  else
    cells = line.split("|").map(&:strip)
    if cells[1].to_s == target_name
      "| #{cells[1]} | Accepted | #{cells[3]} | `#{evidence_reference}` | Codex | #{accepted_at} |\n"
    else
      line
    end
  end
end.join

updated_rows = parse_rows(updated_text)
all_approved = responsibility_rows.values.all? do |name|
  row_approved?(updated_rows[name], root_dir)
end
updated_text = updated_text.sub(
  /Current decision: \*\*[^*]+\*\*/,
  all_approved ? "Current decision: **CODE-OWNED STRUCTURAL PASS; HUMAN AUDITORY SIGNOFF OPEN**" : "Current decision: **NO-GO - Codex responsibility incomplete**"
)

tmp_path = "#{checklist_path}.tmp.#{$$}"
File.write(tmp_path, updated_text)
FileUtils.mv(tmp_path, checklist_path)

puts JSON.pretty_generate({
  "status" => "pass",
  "checklist" => relative_checklist,
  "updated_responsibility" => responsibility_key,
  "updated_row" => target_name,
  "row_status" => "Accepted",
  "all_native_mobile_accessibility_responsibilities_accepted" => all_approved,
  "secret_handling" => "This recorder writes sanitized Codex responsibility metadata only. Do not include secrets, signing keys, raw SMS bodies, OTPs, phone numbers, raw MoMo numbers, provider tokens, or production customer data."
})
RUBY
