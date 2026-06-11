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

status_json="$(mktemp)"
readiness_json="$(mktemp)"
trap 'rm -f "$status_json" "$readiness_json"' EXIT

project_ref="${SUPABASE_PROJECT_REF:-}"
if [[ -f "$ROOT_DIR/supabase/.temp/project-ref" ]]; then
  linked_project_ref="$(tr -d '[:space:]' <"$ROOT_DIR/supabase/.temp/project-ref")"
  if [[ -n "$linked_project_ref" ]]; then
    project_ref="$linked_project_ref"
  fi
fi

if [[ -n "${SUPABASE_GO_LIVE_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_GO_LIVE_STATUS_JSON" >"$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json >"$status_json"
fi

status_candidate_go="$(
  ruby -r json -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    status_value = data["status"].to_s
    puts(Array(data["blocker_keys"]).empty? && data["decision"].to_s == "GO" && status_value == "pass" ? "1" : "0")
  ' "$status_json"
)"

if [[ "$status_candidate_go" == "1" ]]; then
  if [[ -n "${SUPABASE_GO_LIVE_READINESS_JSON:-}" ]]; then
    printf '%s\n' "$SUPABASE_GO_LIVE_READINESS_JSON" >"$readiness_json"
  elif "$ROOT_DIR/scripts/supabase_production_readiness.sh" >"$readiness_json" 2>&1; then
    ruby -r json -e 'puts JSON.pretty_generate({"status" => "pass"})' >"$readiness_json"
  else
    readiness_output="$(tail -n 80 "$readiness_json" 2>/dev/null || true)"
    READINESS_OUTPUT="$readiness_output" ruby -r json <<'RUBY' >"$readiness_json"
puts JSON.pretty_generate(
  {
    "status" => "blocked",
    "blocker_keys" => ["linked_supabase_production_readiness"],
    "message" => "Linked Supabase production readiness checks failed.",
    "output_tail" => ENV.fetch("READINESS_OUTPUT", "")
  }
)
RUBY
  fi
else
  ruby -r json -e 'puts JSON.pretty_generate({"status" => "not_required"})' >"$readiness_json"
fi

gate_json="$(
  ruby -r json - "$status_json" "$project_ref" "$readiness_json" <<'RUBY'
status_path, project_ref, readiness_path = ARGV
status = JSON.parse(File.read(status_path))
readiness = JSON.parse(File.read(readiness_path))
blocker_keys = Array(status["blocker_keys"])
readiness_blocker_keys = Array(readiness["blocker_keys"])
status_value = status["status"].to_s
strict_pass =
  blocker_keys.empty? &&
  status["decision"].to_s == "GO" &&
  status_value == "pass"
readiness_required = strict_pass
readiness_pass = !readiness_required || readiness["status"].to_s == "pass"
combined_blocker_keys = blocker_keys + (readiness_pass ? [] : readiness_blocker_keys)
combined_blocker_keys = combined_blocker_keys.uniq

actions = []
unless strict_pass
  actions << "Run make record-release-approval ARGS=\"--key product_signoff ... --sanitized-evidence --no-production-customer-data\", then rerun make release-status-json." if blocker_keys.include?("product_signoff")
  actions << "Apply supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql from an allow-listed database network and rerun scripts/collect_linked_uat.sh." if blocker_keys.include?("linked_supabase_sms_first_migration")
  actions << "Run real Android MoMo SMS ingestion/parser/allocation UAT, record sanitized device evidence with make record-android-sms-uat-evidence ARGS=\"--tester '<name>' --tested-at '<ISO-8601 UTC timestamp>' ... --sanitized-evidence --no-production-customer-data --raw-sms-not-public --no-phone-or-momo --no-transaction-ids\", record UAT signoffs with make record-uat-evidence-signoff, then run make record-release-approval ARGS=\"--key android_sms_access_uat ... --sanitized-evidence --no-production-customer-data\"." if blocker_keys.include?("android_sms_access_uat")
  actions << "Rebuild current Android release APK/AAB artifacts and rerun scripts/flutter_mobile_release_gate.sh --json." if blocker_keys.include?("android_release_artifacts")
  actions << "Run make record-release-approval ARGS=\"--key android_release_signing_review ... --sanitized-evidence --no-production-customer-data --no-signing-keys-exposed\", then rerun scripts/flutter_mobile_release_gate.sh --json." if blocker_keys.include?("android_release_signing_review")
  actions << "Run make record-release-approval ARGS=\"--key ios_release_scope ... --sanitized-evidence --no-production-customer-data\" or include --out-of-scope, then rerun scripts/flutter_mobile_release_gate.sh --json." if blocker_keys.include?("ios_release_scope")
  actions << "Deploy Admin PWA and rerun the live gate with ADMIN_PWA_LIVE_URL." if blocker_keys.include?("admin_pwa_live_url")
  actions << "After prerequisite approvals pass, run make record-release-approval ARGS=\"--key release_owner_signoff ... --sanitized-evidence --no-production-customer-data\"." if blocker_keys.include?("release_owner_signoff")
  actions << "Rerun make release-status-json and make supabase-go-live-gate-json." if actions.empty?
end
unless readiness_pass
  actions << "Run scripts/supabase_production_readiness.sh, apply any missing linked migrations or backend fixes through an approved production-change path, then rerun make supabase-go-live-gate-json."
end

decision = strict_pass && readiness_pass ? "GO" : "NO-GO"
puts JSON.pretty_generate(
  {
    decision: decision,
    approval_status: strict_pass && readiness_pass ? "approved" : "blocked",
    go_live_approved: strict_pass && readiness_pass,
    project_ref: project_ref.empty? ? nil : project_ref,
    status: status["status"] || status["supabase_strict"],
    blocker_keys: combined_blocker_keys,
    required_next_actions: actions,
    supabase_readiness: {
      "required" => readiness_required,
      "status" => readiness["status"],
      "blocker_keys" => readiness_blocker_keys,
      "message" => readiness["message"],
      "output_tail" => readiness["output_tail"]
    }.compact
  }
)
RUBY
)"

if [[ "$output_format" == "json" ]]; then
  printf '%s\n' "$gate_json"
else
  GATE_JSON="$gate_json" ruby -r json <<'RUBY'
data = JSON.parse(ENV.fetch("GATE_JSON"))
puts "[supabase-go-live-gate] decision=#{data.fetch("decision")}"
puts "[supabase-go-live-gate] approval_status=#{data.fetch("approval_status")}"
puts "[supabase-go-live-gate] blockers=#{Array(data.fetch("blocker_keys")).join(",")}"
unless data.fetch("go_live_approved")
  puts "[supabase-go-live-gate] required_next_actions:"
  data.fetch("required_next_actions").each { |action| puts "  - #{action}" }
end
RUBY
fi

GATE_JSON="$gate_json" ruby -r json <<'RUBY'
data = JSON.parse(ENV.fetch("GATE_JSON"))
exit(data.fetch("go_live_approved") ? 0 : 1)
RUBY
