#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ruby -r json -r time -r fileutils - "$@" <<'RUBY'
root_dir = Dir.pwd
required_scenarios = %w[
  consent
  foreground_sms
  background_sms
  killed_app_sms
  offline_retry
  parser_allocation
  exception_review
  provider_finality
  ledger_posting
  balance_reconciliation
  privacy
].freeze

options = {
  "manifest" => File.join(root_dir, "docs/release/UAT_EVIDENCE_MANIFEST.json"),
  "output_dir" => File.join(root_dir, ".cache/android_sms_uat_evidence", Time.now.utc.strftime("%Y%m%dT%H%M%SZ")),
  "tested_at" => Time.now.utc.iso8601
}

def usage
  warn <<~TEXT
    usage:
      scripts/record_android_sms_uat_evidence.sh --tester NAME --tested-at ISO8601Z --device-label LABEL --scenarios consent,foreground_sms,background_sms,killed_app_sms,offline_retry,parser_allocation,exception_review,provider_finality,ledger_posting,balance_reconciliation,privacy --evidence-summary TEXT --sanitized-evidence --no-production-customer-data --raw-sms-not-public --no-phone-or-momo --no-transaction-ids --sms-never-used-as-settlement --provider-finality-independently-authenticated --balances-reconciled

    options:
      --manifest PATH       UAT evidence manifest to update
      --output-dir PATH     Evidence directory to create
      --tester NAME         Tester/reviewer name, not a placeholder
      --tested-at ISO8601Z  Scenario completion time
      --device-label LABEL  Sanitized device label, such as Pixel 4a UAT device
      --scenarios LIST      Comma-separated required scenario keys
      --evidence-summary TEXT
      --sanitized-evidence
      --no-production-customer-data
      --raw-sms-not-public
      --no-phone-or-momo
      --no-transaction-ids
      --sms-never-used-as-settlement
      --provider-finality-independently-authenticated
      --balances-reconciled
  TEXT
end

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--manifest"
    options["manifest"] = args.shift.to_s
  when "--output-dir"
    options["output_dir"] = args.shift.to_s
  when "--tester"
    options["tester"] = args.shift.to_s
  when "--tested-at"
    options["tested_at"] = args.shift.to_s
  when "--device-label"
    options["device_label"] = args.shift.to_s
  when "--scenarios"
    options["scenarios"] = args.shift.to_s
  when "--evidence-summary"
    options["evidence_summary"] = args.shift.to_s
  when "--sanitized-evidence"
    options["sanitized_evidence"] = true
  when "--no-production-customer-data"
    options["contains_production_customer_data"] = false
  when "--raw-sms-not-public"
    options["raw_sms_public"] = false
  when "--no-phone-or-momo"
    options["contains_phone_or_momo"] = false
  when "--no-transaction-ids"
    options["contains_transaction_ids"] = false
  when "--sms-never-used-as-settlement"
    options["sms_never_used_as_settlement"] = true
  when "--provider-finality-independently-authenticated"
    options["provider_finality_independently_authenticated"] = true
  when "--balances-reconciled"
    options["balances_reconciled"] = true
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

def placeholder_name?(value)
  [
    "Release Owner",
    "Reviewer",
    "Tester",
    "UAT Reviewer",
    "QA Reviewer"
  ].include?(value.to_s.strip)
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

sensitive_patterns = {
  "supabase_service_role" => /service[_-]?role\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "openai_api_key" => /sk-[A-Za-z0-9_\-]{20,}/,
  "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9._\-]{12,}/i,
  "rwanda_phone_number" => /\+250\d{9}\b/,
  "raw_momo_sms" => /\b(?:m-pesa|momo|mobile money|transaction id)\b.*\b(?:\+250\d{9}|\d{6,})/i
}

errors = []
tester = options["tester"].to_s.strip
device_label = options["device_label"].to_s.strip
summary = options["evidence_summary"].to_s.strip
tested_at = options["tested_at"].to_s.strip
scenarios = options["scenarios"].to_s.split(",").map(&:strip).reject(&:empty?).uniq
missing_scenarios = required_scenarios - scenarios
unknown_scenarios = scenarios - required_scenarios

errors << "--tester is required and must not be a placeholder." if tester.length < 2 || placeholder_name?(tester)
errors << "--device-label is required." if device_label.empty?
errors << "--evidence-summary is required and must be specific." if summary.length < 12
errors << "--tested-at must be ISO-8601 UTC ending in Z." unless iso8601_utc?(tested_at)
errors << "--scenarios is missing required scenario(s): #{missing_scenarios.join(", ")}." unless missing_scenarios.empty?
errors << "--scenarios contains unsupported value(s): #{unknown_scenarios.join(", ")}." unless unknown_scenarios.empty?
errors << "--sanitized-evidence is required." unless options["sanitized_evidence"] == true
errors << "--no-production-customer-data is required." unless options["contains_production_customer_data"] == false
errors << "--raw-sms-not-public is required." unless options["raw_sms_public"] == false
errors << "--no-phone-or-momo is required." unless options["contains_phone_or_momo"] == false
errors << "--no-transaction-ids is required." unless options["contains_transaction_ids"] == false
errors << "--sms-never-used-as-settlement is required." unless options["sms_never_used_as_settlement"] == true
errors << "--provider-finality-independently-authenticated is required." unless options["provider_finality_independently_authenticated"] == true
errors << "--balances-reconciled is required." unless options["balances_reconciled"] == true

{
  "tester" => tester,
  "device_label" => device_label,
  "evidence_summary" => summary
}.each do |field, value|
  sensitive_patterns.each do |name, pattern|
    errors << "#{field} contains sensitive marker: #{name}." if value.match?(pattern)
  end
end

manifest_path = File.expand_path(options["manifest"], root_dir)
manifest = nil
begin
  manifest = JSON.parse(File.read(manifest_path))
rescue Errno::ENOENT
  errors << "UAT evidence manifest is missing: #{options["manifest"]}."
rescue JSON::ParserError => error
  errors << "UAT evidence manifest is not valid JSON: #{error.message}."
end

output_dir = File.expand_path(options["output_dir"], root_dir)
relative_output_dir = repo_relative(output_dir, root_dir)
if relative_output_dir.nil? || !safe_relative_path?(relative_output_dir)
  errors << "--output-dir must stay inside the repo and cannot contain '..'."
end

personas = Array(manifest && manifest["personas"])
android_sms_persona = personas.find { |persona| persona["id"].to_s == "UAT-05" }
errors << "UAT-05 Android SMS device persona is missing from manifest." unless android_sms_persona

unless errors.empty?
  warn JSON.pretty_generate({
    "status" => "fail",
    "errors" => errors.uniq
  })
  exit 1
end

FileUtils.mkdir_p(output_dir)
evidence_path = File.join(output_dir, "android_sms_uat_evidence.json")
relative_evidence_path = repo_relative(evidence_path, root_dir)

evidence = {
  "status" => "recorded",
  "evidence_type" => "android_sms_uat",
  "generated_at" => Time.now.utc.iso8601,
  "tester" => tester,
  "tested_at" => tested_at,
  "device_label" => device_label,
  "scenario_count" => scenarios.length,
  "scenarios" => scenarios,
  "assertions" => {
    "sanitized_evidence" => true,
    "contains_production_customer_data" => false,
    "raw_sms_public" => false,
    "contains_phone_or_momo" => false,
    "contains_transaction_ids" => false,
    "sms_consent_verified" => scenarios.include?("consent"),
    "foreground_background_killed_upload_verified" =>
      %w[foreground_sms background_sms killed_app_sms].all? { |key| scenarios.include?(key) },
    "offline_retry_verified" => scenarios.include?("offline_retry"),
    "parser_allocation_verified" => scenarios.include?("parser_allocation"),
    "exception_review_verified" => scenarios.include?("exception_review"),
    "sms_never_used_as_settlement" => true,
    "provider_finality_verified" => scenarios.include?("provider_finality"),
    "provider_finality_independently_authenticated" => true,
    "ledger_posting_verified" => scenarios.include?("ledger_posting"),
    "balance_reconciliation_verified" => scenarios.include?("balance_reconciliation"),
    "balances_reconciled" => true,
    "privacy_verified" => scenarios.include?("privacy")
  },
  "evidence_summary" => summary,
  "manifest_persona" => "UAT-05",
  "approval_status" => "not_approved_by_recorder",
  "secret_handling" =>
    "This evidence is sanitized metadata only. Do not include raw SMS bodies, phone/MoMo numbers, transaction IDs, tokens, service-role keys, provider secrets, signing keys, or production customer data."
}
File.write(evidence_path, JSON.pretty_generate(evidence) + "\n")

evidence_files = Array(android_sms_persona["evidence_files"])
unless evidence_files.any? { |entry| entry.is_a?(Hash) ? entry["path"] == relative_evidence_path : entry.to_s == relative_evidence_path }
  evidence_files << relative_evidence_path
end
android_sms_persona["evidence_files"] = evidence_files
android_sms_persona["sanitized"] = true
android_sms_persona["production_like"] = true

tmp_path = "#{manifest_path}.tmp.#{$$}"
File.write(tmp_path, JSON.pretty_generate(manifest) + "\n")
FileUtils.mv(tmp_path, manifest_path)

puts JSON.pretty_generate({
  "status" => "pass",
  "manifest" => repo_relative(manifest_path, root_dir),
  "persona" => "UAT-05",
  "evidence" => relative_evidence_path,
  "scenario_count" => scenarios.length,
  "approval_status" => "not_approved_by_recorder"
})
RUBY
