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

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
bundle_dir="${SUPABASE_EVIDENCE_BUNDLE_DIR:-$ROOT_DIR/.cache/supabase_go_live_evidence/$timestamp}"
mkdir -p "$bundle_dir"

COMMANDS_TSV="$bundle_dir/commands.tsv"
: > "$COMMANDS_TSV"

run_capture() {
  local name="$1"
  local outfile="$2"
  shift 2

  local started
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  set +e
  "$@" > "$bundle_dir/$outfile" 2>&1
  local rc=$?
  set -e
  local finished
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$outfile" "$rc" "$started" "$finished" >> "$COMMANDS_TSV"
  return 0
}

release_status_connectivity_only() {
  ruby -r json - "$bundle_dir/release_status.json" <<'RUBY'
path = ARGV.fetch(0)
data = JSON.parse(File.read(path))
keys = Array(data["blocker_keys"])
exit(keys == ["database_connectivity"] ? 0 : 1)
RUBY
}

run_capture "release_status_json" "release_status.json" "$ROOT_DIR/scripts/release_status.sh" --json
if release_status_connectivity_only; then
  run_capture "release_status_json_retry" "release_status.json" "$ROOT_DIR/scripts/release_status.sh" --json
fi
run_capture "go_live_gate_json" "go_live_gate.json" env "SUPABASE_GO_LIVE_STATUS_JSON=$(cat "$bundle_dir/release_status.json")" "$ROOT_DIR/scripts/supabase_go_live_gate.sh" --json
run_capture "platform_packet_json" "platform_packet.json" env "SUPABASE_PLATFORM_PACKET_STATUS_JSON=$(cat "$bundle_dir/release_status.json")" "$ROOT_DIR/scripts/supabase_platform_go_live_packet.sh" --json
run_capture "platform_exception_gate" "platform_exception_gate.txt" env "SUPABASE_PLATFORM_EXCEPTION_STATUS_JSON=$(cat "$bundle_dir/release_status.json")" "$ROOT_DIR/scripts/supabase_platform_exception_gate.sh"
run_capture "post_operator_checklist_json" "post_operator_checklist.json" env "SUPABASE_POST_OPERATOR_STATUS_JSON=$(cat "$bundle_dir/release_status.json")" "$ROOT_DIR/scripts/supabase_post_operator_checklist.sh" --json
run_capture "schema_inventory_json" "schema_inventory.json" "$ROOT_DIR/scripts/supabase_schema_inventory.sh" --json
run_capture "advisor_warning_inventory" "advisor_warnings.txt" "$ROOT_DIR/scripts/supabase_advisors_warning_inventory.sh"
run_capture "operational_report_json" "operational_report.json" "$ROOT_DIR/scripts/supabase_operational_report.sh"
run_capture "edge_auth_contract_uat" "edge_auth_contract_uat.txt" "$ROOT_DIR/scripts/collect_edge_auth_contract_uat.sh"
run_capture "code_owned_readiness" "supabase_ready.txt" "$ROOT_DIR/scripts/supabase_production_readiness.sh"
run_capture "release_secret_scan" "release_secret_scan.txt" "$ROOT_DIR/scripts/release_secret_scan.sh"
run_capture "acceptance_matrix_json" "acceptance_matrix.json" env "SUPABASE_ACCEPTANCE_BUNDLE_DIR=$bundle_dir" "$ROOT_DIR/scripts/supabase_acceptance_matrix.sh" --json

BUNDLE_DIR="$bundle_dir" COMMANDS_TSV="$COMMANDS_TSV" ruby -r json -r time <<'RUBY'
bundle_dir = ENV.fetch("BUNDLE_DIR")
commands_path = ENV.fetch("COMMANDS_TSV")

def read_json(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError, Errno::ENOENT
  nil
end

commands = File.readlines(commands_path, chomp: true).map do |line|
  name, file, exit_code, started_at, finished_at = line.split("\t", 5)
  {
    name: name,
    file: file,
    exit_code: exit_code.to_i,
    started_at: started_at,
    finished_at: finished_at
  }
end

release_status = read_json(File.join(bundle_dir, "release_status.json")) || {}
schema_inventory = read_json(File.join(bundle_dir, "schema_inventory.json")) || {}
platform_packet = read_json(File.join(bundle_dir, "platform_packet.json")) || {}
go_live_gate = read_json(File.join(bundle_dir, "go_live_gate.json")) || {}
post_operator_checklist = read_json(File.join(bundle_dir, "post_operator_checklist.json")) || {}
operational_report = read_json(File.join(bundle_dir, "operational_report.json")) || {}
acceptance_matrix = read_json(File.join(bundle_dir, "acceptance_matrix.json")) || {}
schema_summary = schema_inventory.dig("contract", "summary") || {}
exception_gate = commands.find { |command| command.fetch(:name) == "platform_exception_gate" }

summary = {
  generated_at: Time.now.utc.iso8601,
  project_ref: release_status.dig("project_ref") || schema_inventory["project_ref"] || ENV["SUPABASE_PROJECT_REF"],
  decision: release_status["decision"],
  go_live_gate: {
    decision: go_live_gate["decision"],
    approval_status: go_live_gate["approval_status"],
    go_live_approved: go_live_gate["go_live_approved"],
    file: "go_live_gate.json"
  },
  supabase_strict: release_status["supabase_strict"],
  blocker_keys: release_status["blocker_keys"] || [],
  operator_action_count: Array(platform_packet["operator_actions"]).length,
  post_operator_checklist: {
    file: "post_operator_checklist.json",
    step_count: Array(post_operator_checklist["checklist"]).length,
    final_verification: post_operator_checklist["final_verification"] || []
  },
  platform_exception_gate: {
    file: "platform_exception_gate.txt",
    exit_code: exception_gate && exception_gate.fetch(:exit_code),
    required_before_go_live: true
  },
  acceptance_matrix: {
    file: "acceptance_matrix.json",
    overall_status: acceptance_matrix["overall_status"],
    status_counts: acceptance_matrix["status_counts"] || {}
  },
  schema_contract: {
    expected_objects: schema_summary["expected_objects"],
    remote_objects: schema_summary["remote_objects"],
    extra_objects: schema_summary["extra_objects"],
    missing_objects: schema_summary["missing_objects"],
    tables: schema_summary["tables"],
    rls_enabled_tables: schema_summary["rls_enabled_tables"],
    policies: schema_summary["policies"],
    views: schema_summary["views"],
    functions: schema_summary["functions"],
    functions_with_search_path: schema_summary["functions_with_search_path"]
  },
  operational_report: {
    cache_hit_ratio: operational_report.dig("cache", "hit_ratio"),
    table_count: Array(operational_report["tables"]).length,
    slow_queries_available: operational_report.dig("slow_queries", "available")
  },
  commands: commands,
  secret_handling: "Evidence files are generated by redacted release/Supabase commands and must not include .env values."
}

File.write(File.join(bundle_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")

readme = <<~MARKDOWN
  # Supabase Go-Live Evidence Bundle

  Generated at: `#{summary.fetch(:generated_at)}`
  Project ref: `#{summary[:project_ref]}`
  Decision: `#{summary[:decision]}`
  Strict Supabase gate: `#{summary[:supabase_strict]}`

  ## Files

  - `summary.json`: machine-readable bundle summary
  - `release_status.json`: redacted strict status and blocker keys
  - `go_live_gate.json`: final go-live approval decision
  - `platform_packet.json`: redacted operator remediation packet
  - `platform_exception_gate.txt`: signed platform exception validation result
  - `post_operator_checklist.json`: redacted post-operator remediation verification checklist
  - `acceptance_matrix.json`: requirement-by-requirement acceptance matrix
  - `schema_inventory.json`: live public schema/policy/function inventory
  - `advisor_warnings.txt`: warning-level advisor inventory
  - `operational_report.json`: read-only DB operational report
  - `edge_auth_contract_uat.txt`: local Edge Function auth contract UAT
  - `supabase_ready.txt`: code-owned Supabase readiness transcript
  - `release_secret_scan.txt`: redacted secret scan transcript
  - `commands.tsv`: command exit codes and timestamps

  ## Current Status

  - Decision: `#{summary[:decision]}`
  - Go-live gate: `#{summary.dig(:go_live_gate, :decision)}`
  - Blocker keys: `#{Array(summary[:blocker_keys]).join(", ")}`
  - Platform exception gate exit code: `#{summary.dig(:platform_exception_gate, :exit_code)}`
  - Acceptance matrix: `#{summary.dig(:acceptance_matrix, :overall_status)}`
  - Schema contract: expected `#{summary.dig(:schema_contract, :expected_objects)}`, remote `#{summary.dig(:schema_contract, :remote_objects)}`, extra `#{summary.dig(:schema_contract, :extra_objects)}`, missing `#{summary.dig(:schema_contract, :missing_objects)}`
  - RLS: `#{summary.dig(:schema_contract, :rls_enabled_tables)}/#{summary.dig(:schema_contract, :tables)}`

  #{summary.fetch(:secret_handling)}
MARKDOWN

File.write(File.join(bundle_dir, "README.md"), readme)
puts JSON.pretty_generate(summary)
RUBY

latest_dir="$ROOT_DIR/.cache/supabase_go_live_evidence/latest-test"
if [[ "$bundle_dir" != "$latest_dir" ]]; then
  rm -rf "$latest_dir"
  mkdir -p "$latest_dir"
  cp -R "$bundle_dir"/. "$latest_dir"/
fi

printf '[supabase-evidence] bundle=%s\n' "$bundle_dir" >&2
