#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MANIFEST="${UAT_EVIDENCE_MANIFEST:-docs/release/UAT_EVIDENCE_MANIFEST.json}"
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

ROOT_DIR="$ROOT_DIR" MANIFEST="$MANIFEST" OUTPUT_FORMAT="$output_format" ruby -r json -r time -r digest <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
manifest_path = ENV.fetch("MANIFEST")
output_format = ENV.fetch("OUTPUT_FORMAT")

required_ids = (1..10).map { |n| format("UAT-%02d", n) }
allowed_statuses = %w[signed waived]
text_extensions = %w[
  .json .md .txt .log .csv .tsv .yaml .yml .html
]
forbidden_patterns = {
  "supabase_service_role" => /service[_-]?role/i,
  "openai_api_key" => /sk-[A-Za-z0-9_\-]{20,}/,
  "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9_\-]{12,}/i,
  "rwanda_phone_number" => /\+250\d{9}\b/,
  "raw_momo_sms" => /\b(?:m-pesa|momo|mobile money|transaction id)\b.*\b(?:\+250\d{9}|\d{6,})/i
}

def blocked(message, key, blockers, blocker_keys)
  blockers << message
  blocker_keys << key
end

def iso8601_utc?(value)
  Time.iso8601(value.to_s)
  value.to_s.end_with?("Z")
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

def inside_root?(root, path)
  expanded = File.expand_path(path, root)
  expanded == root || expanded.start_with?(root + File::SEPARATOR)
end

def safe_relative_path?(path)
  !path.start_with?("/") && !path.include?("..")
end

def read_sidecar(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError => error
  { "_json_error" => error.message }
end

blockers = []
blocker_keys = []
failure_keys = []
manifest = {}

if !File.file?(manifest_path)
  blocked("UAT evidence manifest is missing: #{manifest_path}", "uat_evidence_manifest_missing", blockers, blocker_keys)
else
  begin
    manifest = JSON.parse(File.read(manifest_path))
  rescue JSON::ParserError => error
    failure_keys << "uat_evidence_manifest_json"
    blockers << "UAT evidence manifest is not valid JSON: #{error.message}"
  end
end

personas = Array(manifest["personas"])
release_owner = manifest["release_owner"].is_a?(Hash) ? manifest["release_owner"] : {}
staging_only = manifest["staging_only"] == true

blocked("UAT evidence manifest must not be staging-only for production GO.", "uat_evidence_staging_only", blockers, blocker_keys) if staging_only

owner_name = release_owner["name"].to_s.strip
owner_decision = release_owner["decision"].to_s.strip.upcase
owner_signed_at = release_owner["signed_at"].to_s.strip
blocked("Release owner name is missing in UAT evidence manifest.", "uat_evidence_release_owner", blockers, blocker_keys) if owner_name.empty?
blocked("Release owner name is a placeholder in UAT evidence manifest.", "uat_evidence_release_owner", blockers, blocker_keys) if placeholder_name?(owner_name)
blocked("Release owner decision must be GO in UAT evidence manifest.", "uat_evidence_release_owner_decision", blockers, blocker_keys) unless owner_decision == "GO"
blocked("Release owner signed_at is missing in UAT evidence manifest.", "uat_evidence_release_owner_signed_at", blockers, blocker_keys) if owner_signed_at.empty?
blocked("Release owner signed_at must be ISO-8601 UTC in UAT evidence manifest.", "uat_evidence_release_owner_signed_at", blockers, blocker_keys) if !owner_signed_at.empty? && !iso8601_utc?(owner_signed_at)

by_id = personas.each_with_object({}) do |persona, memo|
  id = persona.is_a?(Hash) ? persona["id"].to_s.strip : ""
  memo[id] = persona if id != ""
end

missing_ids = required_ids.reject { |id| by_id.key?(id) }
extra_ids = by_id.keys.reject { |id| required_ids.include?(id) }
blocked("UAT evidence manifest is missing personas: #{missing_ids.join(", ")}.", "uat_evidence_persona_coverage", blockers, blocker_keys) unless missing_ids.empty?
blocked("UAT evidence manifest includes unexpected personas: #{extra_ids.join(", ")}.", "uat_evidence_persona_coverage", blockers, blocker_keys) unless extra_ids.empty?

evidence_items = []
required_ids.each do |id|
  persona = by_id[id]
  next unless persona

  status = persona["status"].to_s.strip.downcase
  signoff = persona["signoff"].to_s.strip
  sanitized = persona["sanitized"] == true
  production_like = persona["production_like"] == true
  evidence_files = Array(persona["evidence_files"]).map do |entry|
    if entry.is_a?(Hash)
      path = entry["path"].to_s.strip
      next if path.empty?

      {
        "path" => path,
        "review_sidecar" => entry["review_sidecar"].to_s.strip
      }
    else
      path = entry.to_s.strip
      next if path.empty?

      {
        "path" => path,
        "review_sidecar" => ""
      }
    end
  end.compact

  blocked("#{id} status must be signed or waived.", "uat_evidence_persona_status", blockers, blocker_keys) unless allowed_statuses.include?(status)
  blocked("#{id} signoff is missing.", "uat_evidence_persona_signoff", blockers, blocker_keys) if signoff.empty?
  blocked("#{id} signoff is too generic or placeholder-like.", "uat_evidence_persona_signoff", blockers, blocker_keys) if !signoff.empty? && weak_signoff?(signoff)
  blocked("#{id} sanitized=true is required.", "uat_evidence_sanitization", blockers, blocker_keys) unless sanitized
  blocked("#{id} production_like=true is required for production GO.", "uat_evidence_production_like", blockers, blocker_keys) unless production_like
  blocked("#{id} has no evidence files.", "uat_evidence_files", blockers, blocker_keys) if evidence_files.empty?

  evidence_files.each do |evidence_entry|
    relative_path = evidence_entry.fetch("path")
    if !safe_relative_path?(relative_path)
      failure_keys << "uat_evidence_path_escape"
      blockers << "#{id} evidence path must be repo-relative and cannot contain '..': #{relative_path}"
      next
    end

    absolute_path = File.expand_path(relative_path, root_dir)
    unless inside_root?(root_dir, absolute_path)
      failure_keys << "uat_evidence_path_escape"
      blockers << "#{id} evidence path escapes repo root: #{relative_path}"
      next
    end

    exists = File.file?(absolute_path)
    item = {
      "persona_id" => id,
      "path" => relative_path,
      "exists" => exists,
      "bytes" => exists ? File.size(absolute_path) : nil,
      "sanitization_scan" => "not_scanned"
    }

    unless exists
      blocked("#{id} evidence file is missing: #{relative_path}", "uat_evidence_files", blockers, blocker_keys)
      evidence_items << item
      next
    end

    if File.size(absolute_path).zero?
      blocked("#{id} evidence file is empty: #{relative_path}", "uat_evidence_files", blockers, blocker_keys)
    end

    if text_extensions.include?(File.extname(absolute_path).downcase)
      text = File.binread(absolute_path).to_s
      hits = forbidden_patterns.select { |_name, pattern| text.match?(pattern) }.keys
      item["sanitization_scan"] = hits.empty? ? "pass" : "fail"
      item["forbidden_markers"] = hits
      unless hits.empty?
        failure_keys << "uat_evidence_sanitization_scan"
        blockers << "#{id} evidence file contains forbidden sensitive marker(s): #{relative_path} -> #{hits.join(", ")}"
      end
    else
      sidecar_path = evidence_entry["review_sidecar"]
      sidecar_path = "#{relative_path}.sanitized.json" if sidecar_path.empty?

      item["sanitization_scan"] = "requires_binary_review_sidecar"
      item["review_sidecar"] = sidecar_path

      if !safe_relative_path?(sidecar_path)
        failure_keys << "uat_evidence_binary_review"
        blockers << "#{id} binary evidence review sidecar path must be repo-relative and cannot contain '..': #{sidecar_path}"
      else
        absolute_sidecar_path = File.expand_path(sidecar_path, root_dir)
        if !inside_root?(root_dir, absolute_sidecar_path)
          failure_keys << "uat_evidence_binary_review"
          blockers << "#{id} binary evidence review sidecar escapes repo root: #{sidecar_path}"
        elsif !File.file?(absolute_sidecar_path)
          blocked("#{id} binary/image evidence requires sanitized review sidecar: #{sidecar_path}", "uat_evidence_binary_review", blockers, blocker_keys)
          item["binary_review"] = "missing"
        else
          sidecar = read_sidecar(absolute_sidecar_path)
          expected_sha = sidecar["sha256"].to_s.strip.downcase
          actual_sha = Digest::SHA256.file(absolute_path).hexdigest
          review_ok =
            sidecar["_json_error"].nil? &&
            sidecar["sanitized"] == true &&
            sidecar["contains_production_data"] == false &&
            sidecar["reviewed_by"].to_s.strip != "" &&
            !placeholder_name?(sidecar["reviewed_by"]) &&
            sidecar["reviewed_at"].to_s.strip != "" &&
            iso8601_utc?(sidecar["reviewed_at"]) &&
            expected_sha == actual_sha

          item["binary_review"] = review_ok ? "pass" : "fail"
          item["sidecar_exists"] = true
          item["sidecar_json_valid"] = sidecar["_json_error"].nil?
          item["sidecar_sanitized"] = sidecar["sanitized"] == true
          item["sidecar_contains_production_data"] = sidecar["contains_production_data"]
          item["sidecar_reviewed_by_present"] = sidecar["reviewed_by"].to_s.strip != ""
          item["sidecar_reviewed_by_placeholder"] = placeholder_name?(sidecar["reviewed_by"])
          item["sidecar_reviewed_at_present"] = sidecar["reviewed_at"].to_s.strip != ""
          item["sidecar_reviewed_at_iso8601_utc"] = iso8601_utc?(sidecar["reviewed_at"])
          item["sha256"] = actual_sha
          item["sidecar_sha256"] = expected_sha
          item["sha256_match"] = expected_sha == actual_sha

          unless review_ok
            failure_keys << "uat_evidence_binary_review"
            if sidecar["_json_error"]
              blockers << "#{id} binary evidence review sidecar is not valid JSON: #{sidecar_path} -> #{sidecar["_json_error"]}"
            else
              blockers << "#{id} binary evidence review sidecar failed sanitized/hash checks: #{sidecar_path}"
            end
          end
        end
      end
    end

    evidence_items << item
  end
end

blocker_keys.uniq!
failure_keys.uniq!
status = if failure_keys.any?
  "fail"
elsif blockers.any?
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
  "blockers" => blockers.uniq,
  "personas_expected" => required_ids,
  "personas_present" => by_id.keys.sort,
  "release_owner" => {
    "present" => !owner_name.empty?,
    "decision" => owner_decision,
    "signed_at_present" => !owner_signed_at.empty?,
    "signed_at_iso8601_utc" => owner_signed_at.empty? ? false : iso8601_utc?(owner_signed_at)
  },
  "evidence_items" => evidence_items,
  "secret_handling" => "This gate validates sanitized UAT evidence metadata, scans text attachments for obvious secret/raw-data markers, and requires reviewed SHA-256 sidecars for binary/image evidence."
}

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[uat-evidence] status=#{status}"
  puts "[uat-evidence] manifest=#{manifest_path}"
  puts "[uat-evidence] personas=#{by_id.keys.length}/#{required_ids.length}"
  blockers.uniq.each { |blocker| warn "[uat-evidence][BLOCKED] #{blocker}" } unless blockers.empty?
end

exit(status == "pass" ? 0 : status == "blocked" ? 99 : 1)
RUBY
