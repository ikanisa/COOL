#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

exception_file="${SUPABASE_PLATFORM_EXCEPTION_FILE:-docs/release/SUPABASE_PLATFORM_EXCEPTIONS.json}"

status_json="$(mktemp)"
trap 'rm -f "$status_json"' EXIT

if [[ -n "${SUPABASE_PLATFORM_EXCEPTION_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_PLATFORM_EXCEPTION_STATUS_JSON" > "$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json > "$status_json"
fi

ruby -r json -r date - "$status_json" "$exception_file" <<'RUBY'
status_path, exception_path = ARGV
status = JSON.parse(File.read(status_path))
blocker_keys = Array(status["blocker_keys"]).uniq

verification_blockers = blocker_keys & ["database_connectivity"]
if verification_blockers.any?
  warn "[platform-exceptions][FAIL] Release verification blockers remain: #{verification_blockers.join(", ")}"
  warn "[platform-exceptions] Restore trusted linked query mode or an allow-listed Supavisor/direct database path before evaluating platform exceptions."
  exit 1
end

exceptionable = {
  "supabase_organization_plan" => "Free-plan project-pause risk",
  "supabase_pitr" => "PITR/recovery objective risk"
}
non_exceptionable = blocker_keys - exceptionable.keys

if non_exceptionable.any?
  warn "[platform-exceptions][FAIL] Non-exceptionable strict blockers remain: #{non_exceptionable.join(", ")}"
  exit 1
end

if blocker_keys.empty?
  puts "[platform-exceptions] no strict blockers require exceptions"
  exit 0
end

unless File.file?(exception_path)
  warn "[platform-exceptions][FAIL] Missing exception file: #{exception_path}"
  warn "[platform-exceptions] Copy docs/release/SUPABASE_PLATFORM_EXCEPTIONS.example.json to #{exception_path} and complete it only after release-owner approval."
  exit 1
end

data = JSON.parse(File.read(exception_path))
project_ref = data.fetch("project_ref")
expected_ref = ENV["SUPABASE_PROJECT_REF"].to_s
if !expected_ref.empty? && project_ref != expected_ref
  warn "[platform-exceptions][FAIL] project_ref mismatch: expected #{expected_ref}, got #{project_ref}"
  exit 1
end

exceptions = Array(data.fetch("exceptions"))
by_key = exceptions.each_with_object({}) do |entry, memo|
  memo[entry.fetch("blocker_key")] = entry
end

errors = []
today = Date.today
blocker_keys.each do |key|
  entry = by_key[key]
  unless entry
    errors << "#{key}: missing approved exception"
    next
  end

  if entry["status"] != "accepted"
    errors << "#{key}: status must be accepted"
  end
  required_string_fields = %w[
    risk_owner
    approved_by
    approved_at
    expires_at
    rationale
    mitigation
    evidence_reference
  ]
  required_string_fields.each do |field|
    value = entry[field].to_s.strip
    errors << "#{key}: #{field} is required" if value.empty? || value.include?("<")
  end

  begin
    approved_at = Date.iso8601(entry["approved_at"].to_s)
    errors << "#{key}: approved_at cannot be in the future" if approved_at > today
  rescue ArgumentError
    errors << "#{key}: approved_at must be YYYY-MM-DD"
  end

  begin
    expires_at = Date.iso8601(entry["expires_at"].to_s)
    errors << "#{key}: expires_at must be in the future" if expires_at <= today
  rescue ArgumentError
    errors << "#{key}: expires_at must be YYYY-MM-DD"
  end

  acknowledged = Array(entry["accepted_conditions"])
  %w[release_owner_accepts_risk mitigation_owner_assigned expiry_date_set].each do |condition|
    errors << "#{key}: accepted_conditions missing #{condition}" unless acknowledged.include?(condition)
  end
end

unknown_keys = by_key.keys - exceptionable.keys
errors << "unsupported exception key(s): #{unknown_keys.join(", ")}" if unknown_keys.any?

if errors.any?
  warn "[platform-exceptions][FAIL] #{errors.length} validation error(s):"
  errors.each { |error| warn "  - #{error}" }
  exit 1
end

puts "[platform-exceptions] accepted exception(s): #{blocker_keys.join(", ")}"
RUBY
