#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ruby -r json -r time -r fileutils - "$@" <<'RUBY'
root_dir = Dir.pwd

options = {
  "manifest" => File.join(root_dir, "docs/release/UAT_EVIDENCE_MANIFEST.json"),
  "signed_at" => Time.now.utc.iso8601
}

def usage
  warn <<~TEXT
    usage:
      scripts/record_uat_evidence_signoff.sh --persona-id UAT-01 --status signed|waived --signoff "Reviewed by Name 2026-06-02T12:00:00Z"
      scripts/record_uat_evidence_signoff.sh --release-owner NAME --decision GO --signed-at 2026-06-02T12:00:00Z

    options:
      --manifest PATH       UAT evidence manifest to update (default docs/release/UAT_EVIDENCE_MANIFEST.json)
      --persona-id ID       Persona row to update, UAT-01 through UAT-10
      --status STATUS       signed or waived
      --signoff TEXT        Strong signoff text containing an ISO-8601 UTC timestamp
      --release-owner NAME  Release owner name
      --decision GO         Release owner decision
      --signed-at ISO8601Z  Release owner signed timestamp
  TEXT
end

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--manifest"
    options["manifest"] = args.shift.to_s
  when "--persona-id"
    options["persona_id"] = args.shift.to_s
  when "--status"
    options["status"] = args.shift.to_s
  when "--signoff"
    options["signoff"] = args.shift.to_s
  when "--release-owner"
    options["release_owner"] = args.shift.to_s
  when "--decision"
    options["decision"] = args.shift.to_s
  when "--signed-at"
    options["signed_at"] = args.shift.to_s
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

def timestamp_from(value)
  value.to_s[/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/]
end

def placeholder_name?(value)
  [
    "Release Owner",
    "Reviewer",
    "Tester",
    "UAT Reviewer",
    "QA Reviewer"
  ].include?(value.to_s.strip)
end

def weak_signoff?(value)
  text = value.to_s.strip
  text = text.sub(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/, "").strip
  generic_values = %w[
    approved
    ok
    pass
    passed
    signed
    waived
    todo
    pending
    n/a
    na
  ]
  text.length < 5 ||
    generic_values.include?(text.downcase) ||
    placeholder_name?(text) ||
    text.match?(/\btemplate\b/i)
end

sensitive_patterns = {
  "supabase_service_role" => /service[_-]?role\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "openai_api_key" => /sk-[A-Za-z0-9_\-]{20,}/,
  "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "rwanda_phone_number" => /\+250\d{9}\b/,
  "raw_momo_sms" => /\b(?:m-pesa|momo|mobile money|transaction id)\b.*\b(?:\+250\d{9}|\d{6,})/i
}

def sensitive_hits(values, patterns)
  values.each_with_object([]) do |(field, value), hits|
    text = value.to_s
    next if text.strip == ""

    patterns.each do |name, pattern|
      hits << "#{field}:#{name}" if text.match?(pattern)
    end
  end.uniq
end

def safe_relative_path?(path)
  path.to_s.strip != "" && !path.start_with?("/") && !path.include?("..")
end

def evidence_files_valid?(persona, root_dir)
  Array(persona["evidence_files"]).all? do |entry|
    path = entry.is_a?(Hash) ? entry["path"].to_s : entry.to_s
    next false unless safe_relative_path?(path)

    expanded = File.expand_path(path, root_dir)
    expanded_root = File.expand_path(root_dir)
    inside_repo = expanded == expanded_root || expanded.start_with?("#{expanded_root}/")
    inside_repo && File.file?(expanded) && !File.zero?(expanded)
  end
end

def persona_approved?(persona, root_dir)
  status = persona["status"].to_s.strip.downcase
  signoff = persona["signoff"].to_s.strip
  timestamp = timestamp_from(signoff)
  %w[signed waived].include?(status) &&
    signoff != "" &&
    !weak_signoff?(signoff) &&
    !timestamp.to_s.empty? &&
    iso8601_utc?(timestamp) &&
    persona["sanitized"] == true &&
    persona["production_like"] == true &&
    evidence_files_valid?(persona, root_dir)
end

errors = []
manifest_path = File.expand_path(options["manifest"], root_dir)

begin
  manifest = JSON.parse(File.read(manifest_path))
rescue Errno::ENOENT
  errors << "UAT evidence manifest is missing: #{options["manifest"]}."
rescue JSON::ParserError => error
  errors << "UAT evidence manifest is not valid JSON: #{error.message}."
end

persona_mode = options.key?("persona_id")
owner_mode = options.key?("release_owner") || options.key?("decision")
if persona_mode == owner_mode
  errors << "Record exactly one mode: persona signoff or release-owner decision."
end

if manifest
  personas = Array(manifest["personas"])
  by_id = personas.each_with_object({}) do |persona, memo|
    id = persona["id"].to_s.strip
    memo[id] = persona if id != ""
  end

  if persona_mode
    persona_id = options["persona_id"].to_s.strip
    status = options["status"].to_s.strip.downcase
    signoff = options["signoff"].to_s.strip
    timestamp = timestamp_from(signoff)
    persona = by_id[persona_id]

    errors << "--persona-id must be UAT-01 through UAT-10." unless by_id.key?(persona_id)
    errors << "--status must be signed or waived." unless %w[signed waived].include?(status)
    errors << "--signoff is required and must be specific." if signoff == "" || weak_signoff?(signoff)
    errors << "--signoff must include an ISO-8601 UTC timestamp ending in Z." if timestamp.to_s.empty? || !iso8601_utc?(timestamp)

    hits = sensitive_hits({"signoff" => signoff}, sensitive_patterns)
    errors << "signoff contains sensitive marker(s): #{hits.join(", ")}." unless hits.empty?

    if persona && !evidence_files_valid?(persona, root_dir)
      errors << "#{persona_id} evidence files must all exist, be non-empty, and be repo-relative before signoff."
    end

    unless errors.any?
      persona["status"] = status
      persona["signoff"] = signoff
      persona["sanitized"] = true
      persona["production_like"] = true
    end
  end

  if owner_mode
    owner_name = options["release_owner"].to_s.strip
    decision = options["decision"].to_s.strip.upcase
    signed_at = options["signed_at"].to_s.strip

    errors << "--release-owner is required and must not be a placeholder." if owner_name.length < 2 || placeholder_name?(owner_name)
    errors << "--decision must be GO." unless decision == "GO"
    errors << "--signed-at must be ISO-8601 UTC ending in Z." unless iso8601_utc?(signed_at)

    hits = sensitive_hits(
      {
        "release_owner" => owner_name,
        "signed_at" => signed_at
      },
      sensitive_patterns
    )
    errors << "release-owner metadata contains sensitive marker(s): #{hits.join(", ")}." unless hits.empty?

    missing = personas.reject { |persona| persona_approved?(persona, root_dir) }.map { |persona| persona["id"] }
    errors << "release owner cannot sign until every persona is signed or waived: #{missing.join(", ")}." unless missing.empty?

    unless errors.any?
      manifest["release_owner"] = {
        "name" => owner_name,
        "decision" => decision,
        "signed_at" => signed_at
      }
      manifest["status"] = "signed"
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

tmp_path = "#{manifest_path}.tmp.#{$$}"
File.write(tmp_path, JSON.pretty_generate(manifest) + "\n")
FileUtils.mv(tmp_path, manifest_path)

puts JSON.pretty_generate({
  "status" => "pass",
  "manifest" => manifest_path.sub("#{root_dir}/", ""),
  "updated_persona" => options["persona_id"],
  "release_owner_recorded" => owner_mode
})
RUBY
