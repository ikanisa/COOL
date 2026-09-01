#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"
# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

if [[ -f .env && "${COLLECT_SKIP_DOTENV:-0}" != "1" ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"

advisor_json() {
  local type="$1"
  local out_file err_file
  out_file="$(mktemp)"
  err_file="$(mktemp)"

  if ! SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db advisors \
    --linked \
    --type "$type" \
    --level warn \
    --fail-on none \
    -o json \
    --agent=yes >"$out_file" 2>"$err_file"; then
    cat "$out_file"
    cat "$err_file" >&2
    rm -f "$out_file" "$err_file"
    return 1
  fi

  if grep -Eq '^No issues found$' "$out_file" "$err_file"; then
    printf '[]'
  else
    cat "$out_file"
  fi
  rm -f "$out_file" "$err_file"
}

security_json="$(advisor_json security)"
performance_json="$(advisor_json performance)"

ruby -r json - "$security_json" "$performance_json" <<'RUBY'
security = JSON.parse(ARGV.fetch(0))
performance = JSON.parse(ARGV.fetch(1))

performance_counts = performance.group_by { |item| item.fetch("name") }.transform_values(&:length)
unless performance_counts.empty?
  warn "[supabase-advisor-warnings][FAIL] warning-level performance advisors are no longer clean: #{performance_counts}"
  exit 1
end

allowed_security_max = {
  # Public runtime metadata tables are intentionally available through PostgREST
  # and GraphQL with RLS-limited published/enabled rows.
  "pg_graphql_anon_table_exposed" => 20,
  # The post-20260804 increases are the two authenticated, own-row request
  # tables and notification_events. The post-20260812080000 restoration adds
  # notification_preferences because the mobile client reads and upserts only
  # the signed-in user's RLS-scoped row. Service-only notification delivery and
  # attempt tables remain explicitly revoked.
  "pg_graphql_authenticated_table_exposed" => 36,
  # get_active_policy_document(), list_account_request_reasons(), and
  # collection_is_public_approved() are public read-only helpers. The latter
  # returns one public-approval boolean for RLS policy evaluation; all run with
  # pinned search paths.
  "anon_security_definer_function_executable" => 5,
  # The post-20260815062536 admin-control-plane and post-20260815082500 group
  # hardening migrations brought the reviewed schema to 70 callable
  # signatures. The 20260820162240 bank-transfer cutover retires the legacy
  # Stripe/MoMo control plane and leaves a net 16 additional reviewed
  # signatures: member functions bind auth.uid() to the caller's own intents,
  # groups, and contributions; evidence/reconciliation functions require the
  # service role or an explicit bank permission; and every bank admin function
  # calls assert_admin_permission(). Public-facing reads remain RLS-scoped.
  # Keep this exact reviewed ceiling so any later callable signature fails the
  # gate.
  # Existing reviewed examples remain admin_runtime_config(), which filters by
  # signed-in admin permissions; get_active_policy_document(), which returns
  # published content; and record_policy_acceptance(), which writes only the
  # signed-in user's acceptance event. The 20260828100000 profile-country
  # migration adds update_current_profile(), which is bound to auth.uid(),
  # validates country/name inputs, and writes an audit event for that same
  # profile. The 20260831084646 hybrid migration restores 14 previously
  # reviewed Rwanda Admin signatures and adds three auth.uid()-bound profile /
  # private-group signatures. The 20260831095454 Admin consolidation adds six
  # explicit-permission RPCs plus the filtered overview and queue-SLA readers.
  # All 25 additions pin search_path; Admin functions call
  # assert_admin_permission(), and member functions bind auth.uid(). This
  # brings the exact reviewed ceiling to 112.
  "authenticated_security_definer_function_executable" => 112,
  "auth_leaked_password_protection" => 1
}

security_counts = security.group_by { |item| item.fetch("name") }.transform_values(&:length)
unknown = security_counts.keys - allowed_security_max.keys
over_max = security_counts.select { |name, count| count > allowed_security_max.fetch(name, -1) }

unless unknown.empty? && over_max.empty?
  warn "[supabase-advisor-warnings][FAIL] unexpected warning-level security advisor inventory"
  warn "unknown=#{unknown.sort}" unless unknown.empty?
  warn "over_max=#{over_max}" unless over_max.empty?
  exit 1
end

puts "[supabase-advisor-warnings] performance warnings=0"
puts "[supabase-advisor-warnings] security warning inventory=#{security_counts.sort.to_h}"
RUBY
