#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SIGNOFF_FILE="${UAT_SIGNOFF_FILE:-.cache/uat_signoff/CHECKLIST.md}"
EVIDENCE_MANIFEST="${UAT_EVIDENCE_MANIFEST:-docs/release/UAT_EVIDENCE_MANIFEST.json}"
output_format="text"

case "${1:-}" in
  --json)
    output_format="json"
    ;;
  "")
    ;;
  *)
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

gate_json="$(
  ruby -r json -r time - "$SIGNOFF_FILE" "$EVIDENCE_MANIFEST" <<'RUBY'
path = ARGV.fetch(0)
manifest_path = ARGV.fetch(1)
blockers = []
personas = []
release_owner = nil
decision_rationale = nil
evidence_location = nil
decision_datetime = nil
decision_go_checked = false
decision_no_go_checked = false
minimum_go_total = 0
minimum_go_checked = 0
precondition_total = 0
precondition_checked = 0
manifest = nil
manifest_personas_by_id = {}
manifest_consistency = {
  "checked" => false,
  "manifest" => manifest_path,
  "mismatches" => []
}

def iso8601?(value)
  Time.iso8601(value)
  true
rescue ArgumentError, TypeError
  false
end

def placeholder_name?(value)
  placeholders = [
    "Release Owner",
    "Reviewer",
    "Tester",
    "UAT Reviewer",
    "QA Reviewer"
  ]
  placeholders.include?(value.to_s.strip)
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

def timestamp_from(value)
  value.to_s[/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/]
end

if File.exist?(manifest_path)
  begin
    manifest = JSON.parse(File.read(manifest_path))
    manifest_consistency["checked"] = true
    Array(manifest["personas"]).each do |persona|
      id = persona["id"].to_s.strip
      manifest_personas_by_id[id] = persona if id != ""
    end
  rescue JSON::ParserError => error
    blockers << "UAT evidence manifest is not valid JSON: #{error.message}"
  end
else
  blockers << "UAT evidence manifest is missing: #{manifest_path}"
end

unless File.exist?(path)
  blockers << "UAT signoff checklist is missing: #{path}"
else
  text = File.read(path)
  lines = text.lines(chomp: true)
  blockers << "Checklist status is still PENDING SIGNOFF." if text.include?("Status: **PENDING SIGNOFF**")

  section = nil
  lines.each do |line|
    case line
    when /^## Preconditions/
      section = :preconditions
      next
    when /^## Persona Signoff Matrix/
      section = :personas
      next
    when /^## Release Owner Decision/
      section = :decision
      next
    when /^## Minimum GO Conditions/
      section = :minimum_go
      next
    when /^## /
      section = nil
      next
    end

    if section == :preconditions && line.match?(/^- \[[ xX]\]/)
      precondition_total += 1
      precondition_checked += 1 if line.match?(/^- \[[xX]\]/)
    end

    if section == :minimum_go && line.match?(/^- \[[ xX]\]/)
      minimum_go_total += 1
      minimum_go_checked += 1 if line.match?(/^- \[[xX]\]/)
    end

    if section == :decision
      release_owner = line.sub("Release owner:", "").strip if line.start_with?("Release owner:")
      decision_rationale = line.sub("Decision rationale:", "").strip if line.start_with?("Decision rationale:")
      evidence_location = line.sub("Evidence location:", "").strip if line.start_with?("Evidence location:")
      decision_datetime = line.sub("Date/time:", "").strip if line.start_with?("Date/time:")
      decision_go_checked = true if line.match?(/^- \[[xX]\] GO\s*$/)
      decision_no_go_checked = true if line.match?(/^- \[[xX]\] NO-GO\s*$/)
    end

    next unless line.start_with?("| UAT-")

    cells = line.split("|").map(&:strip)
    id = cells[1]
    persona = cells[2]
    status = cells[4]
    signoff = cells[5]
    signoff_timestamp = timestamp_from(signoff)
    signoff_timestamp_valid = !signoff_timestamp.to_s.empty? && iso8601?(signoff_timestamp)
    signoff_strong = !signoff.to_s.strip.empty? && !weak_signoff?(signoff)
    approved = status.match?(/\A(signed|waived)\z/i) && signoff_strong && signoff_timestamp_valid
    personas << {
      "id" => id,
      "persona" => persona,
      "status" => status,
      "signoff_present" => !signoff.to_s.strip.empty?,
      "signoff_text" => signoff,
      "signoff_strong" => signoff_strong,
      "signoff_timestamp" => signoff_timestamp,
      "signoff_timestamp_valid" => signoff_timestamp_valid,
      "approved" => approved
    }
  end
end

if manifest
  manifest_ids = manifest_personas_by_id.keys.sort
  checklist_ids = personas.map { |persona| persona.fetch("id") }.sort
  missing_in_checklist = manifest_ids - checklist_ids
  missing_in_manifest = checklist_ids - manifest_ids

  unless missing_in_checklist.empty?
    manifest_consistency.fetch("mismatches") << "Manifest personas missing from checklist: #{missing_in_checklist.join(", ")}."
  end
  unless missing_in_manifest.empty?
    manifest_consistency.fetch("mismatches") << "Checklist personas missing from manifest: #{missing_in_manifest.join(", ")}."
  end

  personas.each do |persona|
    manifest_persona = manifest_personas_by_id[persona.fetch("id")]
    next unless manifest_persona

    checklist_status = persona.fetch("status").to_s.strip.downcase
    manifest_status = manifest_persona["status"].to_s.strip.downcase
    if checklist_status != manifest_status
      manifest_consistency.fetch("mismatches") << "#{persona.fetch("id")} status differs: checklist=#{checklist_status} manifest=#{manifest_status}."
    end

    checklist_signoff = persona.fetch("signoff_text").to_s.strip
    manifest_signoff = manifest_persona["signoff"].to_s.strip
    if checklist_signoff != manifest_signoff
      manifest_consistency.fetch("mismatches") << "#{persona.fetch("id")} signoff differs between checklist and manifest."
    end
  end

  manifest_owner = manifest["release_owner"].is_a?(Hash) ? manifest["release_owner"] : {}
  if release_owner.to_s.strip != manifest_owner["name"].to_s.strip
    manifest_consistency.fetch("mismatches") << "Release owner differs between checklist and manifest."
  end
  if decision_datetime.to_s.strip != manifest_owner["signed_at"].to_s.strip
    manifest_consistency.fetch("mismatches") << "Release owner signed_at differs between checklist and manifest."
  end
  if decision_go_checked && manifest_owner["decision"].to_s.strip.upcase != "GO"
    manifest_consistency.fetch("mismatches") << "Checklist GO decision is checked but manifest release owner decision is not GO."
  end

  unless manifest_consistency.fetch("mismatches").empty?
    blockers << "UAT signoff checklist and evidence manifest are inconsistent."
  end
end

if personas.length != 10
  blockers << "Expected 10 persona signoff rows, found #{personas.length}."
end

pending = personas.reject { |persona| persona.fetch("approved") }
unless pending.empty?
  blockers << "Persona signoff incomplete: #{pending.map { |persona| persona.fetch("id") }.join(", ")}."
end

invalid_timestamps = personas.select do |persona|
  persona.fetch("signoff_present") && !persona.fetch("signoff_timestamp_valid")
end
unless invalid_timestamps.empty?
  blockers << "Persona signoff timestamps invalid or missing: #{invalid_timestamps.map { |persona| persona.fetch("id") }.join(", ")}."
end

if precondition_total.zero?
  blockers << "No precondition checklist items found."
elsif precondition_checked != precondition_total
  blockers << "Preconditions incomplete: #{precondition_checked}/#{precondition_total} checked."
end

if minimum_go_total.zero?
  blockers << "No minimum GO checklist items found."
elsif minimum_go_checked != minimum_go_total
  blockers << "Minimum GO conditions incomplete: #{minimum_go_checked}/#{minimum_go_total} checked."
end

blockers << "Release owner is missing." if release_owner.to_s.empty?
blockers << "Release owner is a placeholder." if placeholder_name?(release_owner)
blockers << "Release owner GO decision is not checked." unless decision_go_checked
blockers << "Release owner NO-GO decision is checked." if decision_no_go_checked
blockers << "Release owner decision rationale is missing." if decision_rationale.to_s.length < 12
blockers << "Release owner evidence location is missing." if evidence_location.to_s.empty?
blockers << "Release owner decision date/time must be ISO-8601 UTC." unless iso8601?(decision_datetime) && decision_datetime.to_s.end_with?("Z")

decision = blockers.empty? ? "pass" : "blocked"

puts JSON.pretty_generate(
  {
    "decision" => decision,
    "status" => decision,
    "signoff_approved" => decision == "pass",
    "file" => path,
    "blocker_keys" => decision == "pass" ? [] : ["human_uat_signoff"],
    "blockers" => blockers,
    "preconditions" => {
      "checked" => precondition_checked,
      "total" => precondition_total
    },
    "minimum_go_conditions" => {
      "checked" => minimum_go_checked,
      "total" => minimum_go_total
    },
    "release_owner_present" => !release_owner.to_s.empty?,
    "release_owner_placeholder" => placeholder_name?(release_owner),
    "release_owner_go_checked" => decision_go_checked,
    "release_owner_decision" => {
      "rationale_present" => decision_rationale.to_s.length >= 12,
      "evidence_location_present" => !evidence_location.to_s.empty?,
      "datetime" => decision_datetime,
      "datetime_valid" => iso8601?(decision_datetime) && decision_datetime.to_s.end_with?("Z")
    },
    "manifest_consistency" => manifest_consistency,
    "personas" => personas,
    "secret_handling" => "Signoff evidence must remain sanitized; this gate reads checklist status only."
  }
)
RUBY
)"

if [[ "$output_format" == "json" ]]; then
  printf '%s\n' "$gate_json"
else
  SIGNOFF_JSON="$gate_json" ruby -r json <<'RUBY'
data = JSON.parse(ENV.fetch("SIGNOFF_JSON"))
puts "[uat-signoff] decision=#{data.fetch("decision")}"
puts "[uat-signoff] file=#{data.fetch("file")}"
puts "[uat-signoff] personas=#{data.fetch("personas").count { |persona| persona.fetch("approved") }}/#{data.fetch("personas").length}"
puts "[uat-signoff] preconditions=#{data.fetch("preconditions").fetch("checked")}/#{data.fetch("preconditions").fetch("total")}"
puts "[uat-signoff] minimum_go=#{data.fetch("minimum_go_conditions").fetch("checked")}/#{data.fetch("minimum_go_conditions").fetch("total")}"
unless data.fetch("signoff_approved")
  puts "[uat-signoff] blockers:"
  data.fetch("blockers").each { |blocker| puts "  - #{blocker}" }
end
RUBY
fi

SIGNOFF_JSON="$gate_json" ruby -r json <<'RUBY'
data = JSON.parse(ENV.fetch("SIGNOFF_JSON"))
exit(data.fetch("signoff_approved") ? 0 : 99)
RUBY
