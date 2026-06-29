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
  "pg_graphql_anon_table_exposed" => 9,
  "pg_graphql_authenticated_table_exposed" => 18,
  "anon_security_definer_function_executable" => 2,
  "authenticated_security_definer_function_executable" => 50,
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
