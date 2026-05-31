#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="markdown"
bundle_dir="${SUPABASE_ACCEPTANCE_BUNDLE_DIR:-${SUPABASE_EVIDENCE_BUNDLE_DIR:-$ROOT_DIR/.cache/supabase_go_live_evidence/latest-test}}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json)
      output_format="json"
      shift
      ;;
    --bundle-dir)
      bundle_dir="${2:?--bundle-dir requires a path}"
      shift 2
      ;;
    -*)
      printf 'usage: %s [--json] [--bundle-dir PATH]\n' "$0" >&2
      exit 2
      ;;
    *)
      bundle_dir="$1"
      shift
      ;;
  esac
done

ruby -r json -r time - "$output_format" "$bundle_dir" <<'RUBY'
format, bundle_dir = ARGV

def read_json(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError, Errno::ENOENT
  nil
end

def read_text(path)
  File.read(path)
rescue Errno::ENOENT
  ""
end

def command_rows(bundle_dir)
  path = File.join(bundle_dir, "commands.tsv")
  return [] unless File.exist?(path)

  File.readlines(path, chomp: true).map do |line|
    name, file, exit_code, started_at, finished_at = line.split("\t", 5)
    {
      "name" => name,
      "file" => file,
      "exit_code" => exit_code.to_i,
      "started_at" => started_at,
      "finished_at" => finished_at
    }
  end
end

def command_exit(commands, name)
  row = commands.reverse.find { |command| command.fetch("name") == name }
  row && row.fetch("exit_code")
end

release_status =
  if ENV["SUPABASE_ACCEPTANCE_STATUS_JSON"].to_s.strip.empty?
    read_json(File.join(bundle_dir, "release_status.json")) || {}
  else
    JSON.parse(ENV.fetch("SUPABASE_ACCEPTANCE_STATUS_JSON"))
  end
go_live_gate = read_json(File.join(bundle_dir, "go_live_gate.json")) || {}
schema_inventory = read_json(File.join(bundle_dir, "schema_inventory.json")) || {}
post_operator_checklist = read_json(File.join(bundle_dir, "post_operator_checklist.json")) || {}
platform_packet = read_json(File.join(bundle_dir, "platform_packet.json")) || {}
operational_report = read_json(File.join(bundle_dir, "operational_report.json")) || {}
commands = command_rows(bundle_dir)
ready_text = read_text(File.join(bundle_dir, "supabase_ready.txt"))
edge_auth_text = read_text(File.join(bundle_dir, "edge_auth_contract_uat.txt"))
advisor_text = read_text(File.join(bundle_dir, "advisor_warnings.txt"))
secret_scan_text = read_text(File.join(bundle_dir, "release_secret_scan.txt"))
schema = schema_inventory.dig("contract", "summary") || {}
current_release_keys = %w[
  product_signoff
  linked_supabase_sms_first_migration
  android_sms_access_uat
  android_release_signing_review
  ios_release_scope
  admin_pwa_live_url
  release_owner_signoff
]
supported_blocker_keys = current_release_keys + %w[database_connectivity]
blocker_keys = Array(release_status["blocker_keys"]) & supported_blocker_keys
go_live_blocker_keys = Array(go_live_gate["blocker_keys"]) & supported_blocker_keys
connectivity_blocked = blocker_keys.include?("database_connectivity")
linked_migration_blocked =
  blocker_keys.include?("linked_supabase_sms_first_migration") ||
  ready_text.include?("MISSING 202605270001")

requirements = []
add = lambda do |id:, area:, requirement:, status:, evidence:, blocker_keys: [], next_action: nil|
  requirements << {
    "id" => id,
    "area" => area,
    "requirement" => requirement,
    "status" => status,
    "evidence" => evidence,
    "blocker_keys" => blocker_keys,
    "next_action" => next_action
  }.compact
end

schema_exact =
  schema["expected_objects"].to_i.positive? &&
  schema["expected_objects"] == schema["remote_objects"] &&
  schema["extra_objects"].to_i == 0 &&
  schema["missing_objects"].to_i == 0
schema_status =
  if schema_exact
    "pass"
  elsif linked_migration_blocked
    "blocked"
  else
    "fail"
  end
add.call(
  id: "SUPA-001",
  area: "Schema",
  requirement: "Remote public schema contains only repo-owned required objects.",
  status: schema_status,
  evidence: "schema_inventory.json contract.summary expected=#{schema["expected_objects"]} remote=#{schema["remote_objects"]} extra=#{schema["extra_objects"]} missing=#{schema["missing_objects"]}",
  blocker_keys: linked_migration_blocked && !schema_exact ? ["linked_supabase_sms_first_migration"] : [],
  next_action: if schema_exact
    nil
  elsif linked_migration_blocked
    "Apply the SMS-first migration, rerun linked UAT, then rerun make supabase-schema-inventory."
  else
    "Run make supabase-schema-inventory and reconcile extra/missing objects."
  end
)

rls_complete = schema["tables"].to_i.positive? && schema["rls_enabled_tables"] == schema["tables"]
add.call(
  id: "SUPA-002",
  area: "RLS",
  requirement: "Every public base table has row-level security enabled.",
  status: rls_complete ? "pass" : "fail",
  evidence: "schema_inventory.json contract.summary rls_enabled_tables=#{schema["rls_enabled_tables"]}/#{schema["tables"]}",
  next_action: rls_complete ? nil : "Enable RLS on every public base table and rerun make supabase-ready."
)

functions_pinned = schema["functions"].to_i.positive? && schema["functions_with_search_path"] == schema["functions"]
add.call(
  id: "SUPA-003",
  area: "Functions",
  requirement: "Every public function has an explicit search_path posture.",
  status: functions_pinned ? "pass" : "fail",
  evidence: "schema_inventory.json contract.summary functions_with_search_path=#{schema["functions_with_search_path"]}/#{schema["functions"]}",
  next_action: functions_pinned ? nil : "Pin function search_path settings and rerun make supabase-ready."
)

advisor_ok = command_exit(commands, "advisor_warning_inventory") == 0
add.call(
  id: "SUPA-004",
  area: "Advisors",
  requirement: "Supabase advisor warning inventory is bounded and performance warnings stay clean.",
  status: advisor_ok ? "pass" : "fail",
  evidence: advisor_ok ? "advisor_warnings.txt exit=0" : "advisor_warnings.txt exit=#{command_exit(commands, "advisor_warning_inventory")}",
  next_action: advisor_ok ? nil : "Inspect advisor_warnings.txt and fix new or increased warning inventory."
)

ready_ok = command_exit(commands, "code_owned_readiness") == 0
readiness_status =
  if ready_ok
    "pass"
  elsif connectivity_blocked || ready_text.include?("EADDRNOTALLOWED") || ready_text.include?("tenant allow_list") || ready_text.include?("failed to connect to postgres")
    "blocked"
  elsif linked_migration_blocked
    "blocked"
  else
    "fail"
  end
add.call(
  id: "SUPA-005",
  area: "Readiness",
  requirement: "Code-owned linked Supabase readiness passes.",
  status: readiness_status,
  evidence: ready_ok ? "supabase_ready.txt exit=0" : "supabase_ready.txt exit=#{command_exit(commands, "code_owned_readiness")}",
  blocker_keys: if readiness_status == "blocked" && linked_migration_blocked
    ["linked_supabase_sms_first_migration"]
  elsif readiness_status == "blocked"
    ["database_connectivity"]
  else
    []
  end,
  next_action: if ready_ok
    nil
  elsif linked_migration_blocked
    "Apply the SMS-first migration, then rerun code-owned readiness."
  elsif readiness_status == "blocked"
    "Restore trusted or allow-listed database connectivity and rerun code-owned readiness."
  else
    "Inspect supabase_ready.txt and fix code-owned readiness failures."
  end
)

edge_auth_contract_ok =
  command_exit(commands, "edge_auth_contract_uat") == 0 &&
  edge_auth_text.include?("Edge Function auth contract UAT passed")
edge_remote_ready =
  ready_ok &&
  ready_text.include?("checking Edge Function auth contract") &&
  ready_text.include?("checking deployed Edge Function endpoints") &&
  ready_text.include?("checking Edge Function secret names")
add.call(
  id: "SUPA-006",
  area: "Edge Functions",
  requirement: "Edge Function auth mode, deployment inventory, and secret-name inventory are checked.",
  status: edge_remote_ready ? "pass" : ((linked_migration_blocked || connectivity_blocked) && edge_auth_contract_ok ? "blocked" : "fail"),
  evidence: if edge_remote_ready
    "supabase_ready.txt includes Edge Function auth, endpoint, and secret-name checks"
  elsif edge_auth_contract_ok && linked_migration_blocked
    "edge_auth_contract_uat.txt exit=0; remote Edge Function readiness is blocked until the SMS-first migration is applied"
  elsif edge_auth_contract_ok && connectivity_blocked
    "edge_auth_contract_uat.txt exit=0; remote endpoint and secret-name probes blocked by database connectivity"
  else
    "supabase_ready.txt missing one or more Edge Function readiness checks"
  end,
  blocker_keys: if edge_remote_ready
    []
  elsif linked_migration_blocked
    ["linked_supabase_sms_first_migration"]
  elsif connectivity_blocked
    ["database_connectivity"]
  else
    []
  end,
  next_action: if edge_remote_ready
    nil
  elsif linked_migration_blocked && edge_auth_contract_ok
    "Apply the SMS-first migration so remote Edge Function deployment and secret-name probes can run."
  elsif connectivity_blocked && edge_auth_contract_ok
    "Restore trusted or allow-listed database connectivity so remote Edge Function deployment and secret-name probes can run."
  else
    "Restore Edge Function readiness probes before release."
  end
)

secret_ok = command_exit(commands, "release_secret_scan") == 0 && !secret_scan_text.empty?
add.call(
  id: "SUPA-007",
  area: "Secrets",
  requirement: "Release evidence includes a redacted secret scan.",
  status: secret_ok ? "pass" : "fail",
  evidence: secret_ok ? "release_secret_scan.txt exit=0" : "release_secret_scan.txt missing or nonzero",
  next_action: secret_ok ? nil : "Run make release-secret-scan and remove committed secret values."
)

operational_ok = command_exit(commands, "operational_report_json") == 0 && !operational_report.empty?
add.call(
  id: "SUPA-008",
  area: "Operations",
  requirement: "Operational report captures read-only DB health and performance signals.",
  status: operational_ok ? "pass" : "fail",
  evidence: operational_ok ? "operational_report.json exit=0 tables=#{Array(operational_report["tables"]).length}" : "operational_report.json missing or nonzero",
  next_action: operational_ok ? nil : "Run make supabase-operational-report and fix report failures."
)

current_release_blocker_keys = blocker_keys & current_release_keys
platform_status = current_release_blocker_keys.any? || connectivity_blocked ? "blocked" : "pass"
add.call(
  id: "SUPA-009",
  area: "SMS-first release",
  requirement: "Linked SMS-first migration, Android SMS access UAT, Android signing/iOS scope, Admin PWA live proof, and signoffs are complete.",
  status: platform_status,
  blocker_keys: connectivity_blocked ? ["database_connectivity"] : current_release_blocker_keys,
  evidence: "release_status.json blocker_keys=#{(connectivity_blocked ? ["database_connectivity"] : current_release_blocker_keys).join(",")}",
  next_action: if platform_status == "pass"
    nil
  elsif connectivity_blocked
    "Restore trusted or allow-listed database connectivity so linked SMS-first migration/UAT can be rechecked."
  else
    "Use make supabase-platform-packet to resolve current SMS-first release blockers."
  end
)

checklist_ok = command_exit(commands, "post_operator_checklist_json") == 0 && !post_operator_checklist.empty?
add.call(
  id: "SUPA-010",
  area: "Operator Handoff",
  requirement: "Operator remediation checklist is generated without secret values.",
  status: checklist_ok ? "pass" : "fail",
  evidence: checklist_ok ? "post_operator_checklist.json present" : "post_operator_checklist.json missing or incomplete",
  next_action: checklist_ok ? nil : "Run make supabase-post-operator-checklist-json."
)

go_live_approved = go_live_gate["go_live_approved"] == true
add.call(
  id: "SUPA-011",
  area: "Go-Live",
  requirement: "Final Supabase go-live gate approves release.",
  status: go_live_approved ? "pass" : "blocked",
  blocker_keys: go_live_blocker_keys.empty? ? blocker_keys : go_live_blocker_keys,
  evidence: "go_live_gate.json decision=#{go_live_gate["decision"]} approval_status=#{go_live_gate["approval_status"]}",
  next_action: if go_live_approved
    nil
  elsif connectivity_blocked
    "Restore trusted linked query mode or an allow-listed Supavisor/direct database path, then rerun make release-status-json and make supabase-go-live-gate-json."
  else
    "Resolve current SMS-first blockers, then rerun make supabase-go-live-gate-json."
  end
)

status_counts = requirements.group_by { |item| item.fetch("status") }.transform_values(&:length)
overall_status =
  if requirements.any? { |item| item.fetch("status") == "fail" }
    "fail"
  elsif requirements.any? { |item| item.fetch("status") == "blocked" }
    "blocked"
  else
    "pass"
  end

matrix = {
  "generated_at" => Time.now.utc.iso8601,
  "bundle_dir" => bundle_dir,
  "overall_status" => overall_status,
  "decision" => go_live_gate["decision"] || release_status["decision"],
  "status_counts" => status_counts,
  "requirements" => requirements,
  "secret_handling" => "Acceptance matrix references redacted evidence files only and does not print .env values."
}

if format == "json"
  puts JSON.pretty_generate(matrix)
  exit(overall_status == "fail" ? 1 : 0)
end

puts "# Supabase Acceptance Matrix"
puts
puts "- Bundle: `#{bundle_dir}`"
puts "- Overall status: `#{overall_status}`"
puts "- Decision: `#{matrix["decision"]}`"
puts "- Secret handling: #{matrix["secret_handling"]}"
puts
puts "| ID | Area | Status | Requirement | Evidence |"
puts "| --- | --- | --- | --- | --- |"
requirements.each do |item|
  puts "| #{item.fetch("id")} | #{item.fetch("area")} | #{item.fetch("status")} | #{item.fetch("requirement")} | #{item.fetch("evidence")} |"
end
puts
blocked = requirements.select { |item| item.fetch("status") == "blocked" }
unless blocked.empty?
  puts "## Blocking Next Actions"
  puts
  blocked.each do |item|
    puts "- `#{item.fetch("id")}`: #{item["next_action"]}"
  end
end

exit(overall_status == "fail" ? 1 : 0)
RUBY
