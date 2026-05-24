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

output_format="text"
case "${1:-}" in
  --json)
    output_format="json"
    ;;
  "" )
    ;;
  * )
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

status_json="$(mktemp)"
trap 'rm -f "$status_json"' EXIT

if [[ -n "${SUPABASE_GO_LIVE_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_GO_LIVE_STATUS_JSON" > "$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json > "$status_json"
fi

set +e
exception_output="$(
  SUPABASE_PLATFORM_EXCEPTION_STATUS_JSON="$(cat "$status_json")" \
    "$ROOT_DIR/scripts/supabase_platform_exception_gate.sh" 2>&1
)"
exception_rc=$?
set -e

gate_json="$(
  ruby -r json - "$status_json" "$exception_rc" "$exception_output" "${SUPABASE_PROJECT_REF:-}" <<'RUBY'
status_path, exception_rc, exception_output, project_ref = ARGV
status = JSON.parse(File.read(status_path))
blocker_keys = Array(status["blocker_keys"])
exceptionable_keys = %w[supabase_organization_plan supabase_pitr]
verification_blockers = blocker_keys & %w[database_connectivity]
non_exceptionable_blockers = blocker_keys - exceptionable_keys - verification_blockers
exceptionable_blockers = blocker_keys & exceptionable_keys
strict_pass = status["supabase_strict"] == "pass"
exception_pass = exception_rc.to_i == 0

decision =
  if strict_pass
    "GO"
  elsif exception_pass
    "GO-WITH-EXCEPTIONS"
  else
    "NO-GO"
  end

approval_status =
  case decision
  when "GO"
    "approved"
  when "GO-WITH-EXCEPTIONS"
    "approved_with_signed_exceptions"
  else
    "blocked"
  end

puts JSON.pretty_generate(
  {
    decision: decision,
    approval_status: approval_status,
    go_live_approved: decision != "NO-GO",
    project_ref: project_ref.empty? ? nil : project_ref,
    supabase_strict: status["supabase_strict"],
    blocker_keys: blocker_keys,
    exception_gate: {
      exit_code: exception_rc.to_i,
      passed: exception_pass,
      output: exception_output,
    },
    required_next_actions: if decision == "NO-GO"
      actions = []
      if verification_blockers.any?
        actions << "Restore trusted linked query mode or an allow-listed Supavisor/direct database path."
        actions << "Rerun make release-status-json and make supabase-go-live-gate-json from that trusted path."
      end
      if non_exceptionable_blockers.any?
        actions << "Resolve non-exceptionable strict blockers: #{non_exceptionable_blockers.join(", ")}."
      end
      if exceptionable_blockers.any?
        actions << "For remaining exceptionable platform risks, provide a valid signed docs/release/SUPABASE_PLATFORM_EXCEPTIONS.json or resolve the platform setting."
      end
      actions << "Rerun make supabase-go-live-gate-json." if actions.empty?
      actions
    else
      []
    end
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
puts "[supabase-go-live-gate] supabase_strict=#{data.fetch("supabase_strict")}"
puts "[supabase-go-live-gate] blockers=#{Array(data.fetch("blocker_keys")).join(",")}"
puts "[supabase-go-live-gate] exception_gate_exit=#{data.fetch("exception_gate").fetch("exit_code")}"
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
