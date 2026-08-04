#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
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
  # tables and notification_events. Each remains RLS-scoped; the service-only
  # notification delivery and attempt tables are explicitly revoked.
  "pg_graphql_authenticated_table_exposed" => 35,
  # get_active_policy_document(), list_account_request_reasons(), and
  # collection_is_public_approved() are public read-only helpers. The latter
  # returns one public-approval boolean for RLS policy evaluation; all run with
  # pinned search paths.
  "anon_security_definer_function_executable" => 5,
  # The post-20260703 increases are ensure_developer_account_data(), which
  # seeds protected developer-owned data after verifying the signed-in
  # developer phone number; admin_runtime_config(), which filters metadata rows
  # through the signed-in admin's permissions; get_active_policy_document() and
  # list_account_request_reasons(), which return published policy content and
  # enabled request reasons; record_policy_acceptance(), which writes the
  # signed-in user's policy acceptance event; collection_is_public_approved(),
  # which supports scoped public reads; and unregister_notification_device(),
  # which can disable only the signed-in user's hashed APNs token.
  "authenticated_security_definer_function_executable" => 57,
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
