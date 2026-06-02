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
trap 'rm -f "$status_json"' EXIT

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

gate_json="$(
  ruby -r json - "$status_json" "$project_ref" <<'RUBY'
status_path, project_ref = ARGV
status = JSON.parse(File.read(status_path))
blocker_keys = Array(status["blocker_keys"])
status_value = status["status"].to_s
strict_pass =
  blocker_keys.empty? &&
  status["decision"].to_s == "GO" &&
  status_value == "pass"

actions = []
unless strict_pass
  actions << "Run make record-release-approval ARGS=\"--key product_signoff ... --sanitized-evidence --no-production-customer-data\", then rerun make release-status-json." if blocker_keys.include?("product_signoff")
  actions << "Apply supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql from an allow-listed database network and rerun scripts/collect_linked_uat.sh." if blocker_keys.include?("linked_supabase_sms_first_migration")
  actions << "Run real Android MoMo SMS ingestion/parser/allocation UAT, record UAT signoffs with make record-uat-evidence-signoff, then run make record-release-approval ARGS=\"--key android_sms_access_uat ... --sanitized-evidence --no-production-customer-data\"." if blocker_keys.include?("android_sms_access_uat")
  actions << "Rebuild current Android release APK/AAB artifacts and rerun scripts/flutter_mobile_release_gate.sh --json." if blocker_keys.include?("android_release_artifacts")
  actions << "Run make record-release-approval ARGS=\"--key android_release_signing_review ... --sanitized-evidence --no-production-customer-data --no-signing-keys-exposed\", then rerun scripts/flutter_mobile_release_gate.sh --json." if blocker_keys.include?("android_release_signing_review")
  actions << "Run make record-release-approval ARGS=\"--key ios_release_scope ... --sanitized-evidence --no-production-customer-data\" or include --out-of-scope, then rerun scripts/flutter_mobile_release_gate.sh --json." if blocker_keys.include?("ios_release_scope")
  actions << "Deploy Admin PWA and rerun the live gate with ADMIN_PWA_LIVE_URL." if blocker_keys.include?("admin_pwa_live_url")
  actions << "After prerequisite approvals pass, run make record-release-approval ARGS=\"--key release_owner_signoff ... --sanitized-evidence --no-production-customer-data\"." if blocker_keys.include?("release_owner_signoff")
  actions << "Rerun make release-status-json and make supabase-go-live-gate-json." if actions.empty?
end

decision = strict_pass ? "GO" : "NO-GO"
puts JSON.pretty_generate(
  {
    decision: decision,
    approval_status: strict_pass ? "approved" : "blocked",
    go_live_approved: strict_pass,
    project_ref: project_ref.empty? ? nil : project_ref,
    status: status["status"] || status["supabase_strict"],
    blocker_keys: blocker_keys,
    required_next_actions: actions
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
