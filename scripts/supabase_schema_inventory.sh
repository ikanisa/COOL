#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"
# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

if [[ -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
: "${DATABASE_URL:?DATABASE_URL is required}"

READINESS_DATABASE_URL="${SUPABASE_READINESS_DATABASE_URL:-${DATABASE_POOLER_URL:-$DATABASE_URL}}"
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

tmp_sql="$(mktemp)"
tmp_err="$(mktemp)"
trap 'rm -f "$tmp_sql" "$tmp_err"' EXIT

cat > "$tmp_sql" <<'SQL'
with public_tables as (
  select
    c.relname as name,
    c.relrowsecurity as rls_enabled,
    c.relforcerowsecurity as rls_forced,
    coalesce(policy_counts.policy_count, 0) as policy_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join (
    select schemaname, tablename, count(*) as policy_count
    from pg_policies
    where schemaname = 'public'
    group by schemaname, tablename
  ) policy_counts
    on policy_counts.schemaname = n.nspname
   and policy_counts.tablename = c.relname
  where n.nspname = 'public'
    and c.relkind = 'r'
),
public_functions as (
  select
    p.proname as name,
    pg_get_function_identity_arguments(p.oid) as arguments,
    p.prosecdef as security_definer,
    p.provolatile as volatility,
    coalesce(array_to_string(p.proconfig, ','), '') as config
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
contract_objects as (
  select 'table|' || name as object_key from public_tables
  union all
  select 'view|' || viewname
    from pg_views
    where schemaname = 'public'
  union all
  select 'function|' || name
    from public_functions
  union all
  select 'type|' || t.typname
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typtype = 'e'
  union all
  select 'policy|' || tablename || '|' || policyname
    from pg_policies
    where schemaname = 'public'
)
select jsonb_build_object(
  'generated_at', now(),
  'contract_objects', coalesce((
    select jsonb_agg(object_key order by object_key)
    from contract_objects
  ), '[]'::jsonb),
  'tables', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'name', name,
        'rls_enabled', rls_enabled,
        'rls_forced', rls_forced,
        'policy_count', policy_count
      )
      order by name
    )
    from public_tables
  ), '[]'::jsonb),
  'views', coalesce((
    select jsonb_agg(viewname order by viewname)
    from pg_views
    where schemaname = 'public'
  ), '[]'::jsonb),
  'functions', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'name', name,
        'arguments', arguments,
        'security_definer', security_definer,
        'volatility', volatility,
        'search_path_pinned', config like '%search_path=%'
      )
      order by name, arguments
    )
    from public_functions
  ), '[]'::jsonb),
  'types', coalesce((
    select jsonb_agg(t.typname order by t.typname)
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typtype = 'e'
  ), '[]'::jsonb),
  'policies', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'table', tablename,
        'name', policyname,
        'command', cmd,
        'roles', roles
      )
      order by tablename, policyname
    )
    from pg_policies
    where schemaname = 'public'
  ), '[]'::jsonb),
  'grants', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'object_type', coalesce(t.table_type, 'UNKNOWN'),
        'object', g.table_name,
        'role', g.grantee,
        'privilege', g.privilege_type
      )
      order by g.table_name, g.grantee, g.privilege_type
    )
    from information_schema.role_table_grants g
    left join information_schema.tables t
      on t.table_schema = g.table_schema
     and t.table_name = g.table_name
    where g.table_schema = 'public'
      and g.grantee in ('anon', 'authenticated', 'service_role')
  ), '[]'::jsonb)
) as inventory;
SQL

run_query() {
  if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" != "direct" ]]; then
    if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" == "linked" ]]; then
      if output="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db query --linked -f "$tmp_sql" -o json --agent=yes 2>"$tmp_err")"; then
        grep -Ev '^(A new version of Supabase CLI is available|We recommend updating regularly)' "$tmp_err" >&2 || true
        printf '%s\n' "$output"
        return 0
      fi
      cat "$tmp_err" >&2
      printf '[schema-inventory][WARN] Linked database query failed; trying the Supabase Management API query path.\n' >&2
    fi
    if supabase_management_query_file "$tmp_sql"; then
      return 0
    fi
    printf '[schema-inventory][WARN] Management API query failed; falling back to READINESS_DATABASE_URL.\n' >&2
  fi

  psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -Atq -f "$tmp_sql"
}

inventory_output="$(run_query)"

INVENTORY_OUTPUT="$inventory_output" ruby -r json - "$output_format" "$SUPABASE_PROJECT_REF" <<'RUBY'
format, project_ref = ARGV
input = ENV.fetch("INVENTORY_OUTPUT")
start = [input.index("["), input.index("{")].compact.min
abort("schema inventory did not return JSON") unless start

stack = []
in_string = false
escape = false
finish = nil
input.chars.each_with_index do |char, index|
  next if index < start

  if in_string
    if escape
      escape = false
    elsif char == "\\"
      escape = true
    elsif char == '"'
      in_string = false
    end
    next
  end

  case char
  when '"'
    in_string = true
  when "{", "["
    stack << char
  when "}", "]"
    expected_open = char == "}" ? "{" : "["
    abort("schema inventory JSON delimiters were invalid") unless stack.pop == expected_open
    if stack.empty?
      finish = index
      break
    end
  end
end

abort("schema inventory JSON was incomplete") unless finish
data = JSON.parse(input[start..finish])
row = if data.is_a?(Array)
  data.first || {}
elsif data.is_a?(Hash) && data["rows"].is_a?(Array)
  data["rows"].first || {}
else
  data
end
inventory = row.fetch("inventory", row)

expected = []
logical_overload_replacements = [
  "function|admin_list_allocations",
  "function|admin_list_payment_events",
  "function|admin_list_unallocated"
]
Dir["supabase/migrations/*.sql"].sort.each do |path|
  sql = File.read(path)
  events = []
  [
    [/^create table(?: if not exists)?\s+([a-zA-Z_][\w.]*)/i, "table"],
    [/^create(?: or replace)? view\s+([a-zA-Z_][\w.]*)/i, "view"],
    [/^create(?: or replace)? function\s+([a-zA-Z_][\w.]*)/i, "function"],
    [/^create type\s+([a-zA-Z_][\w.]*)/i, "type"]
  ].each do |pattern, kind|
    sql.to_enum(:scan, pattern).each do
      match = Regexp.last_match
      events << [match.begin(0), :add, "#{kind}|#{match[1].sub(/^public\./, "")}"]
    end
  end
  [
    [/^drop view(?: if exists)?\s+([a-zA-Z_][\w.]*)/i, "view"],
    [/^drop function(?: if exists)?\s+([a-zA-Z_][\w.]*)/i, "function"],
    [/^drop table(?: if exists)?\s+([a-zA-Z_][\w.]*)/i, "table"]
  ].each do |pattern, kind|
    sql.to_enum(:scan, pattern).each do
      match = Regexp.last_match
      events << [match.begin(0), :delete, "#{kind}|#{match[1].sub(/^public\./, "")}"]
    end
  end
  sql.to_enum(:scan, /^create policy\s+"?([^"\n]+?)"?\s+on\s+([a-zA-Z_][\w.]*)/im).each do
    match = Regexp.last_match
    events << [match.begin(0), :add, "policy|#{match[2].sub(/^public\./, "")}|#{match[1]}"]
  end
  sql.to_enum(:scan, /^drop policy(?: if exists)?\s+"?([^"\n]+?)"?\s+on\s+([a-zA-Z_][\w.]*)/im).each do
    match = Regexp.last_match
    events << [match.begin(0), :delete, "policy|#{match[2].sub(/^public\./, "")}|#{match[1]}"]
  end
  events.sort_by(&:first).each do |_position, action, object_key|
    if action == :add
      expected << object_key
    elsif object_key.start_with?("table|")
      table = object_key.split("|", 2).last
      expected.delete(object_key)
      expected.delete_if { |entry| entry.start_with?("policy|#{table}|") }
    elsif logical_overload_replacements.include?(object_key)
      next
    else
      expected.delete(object_key)
    end
  end
end

expected = expected.uniq.sort
remote = inventory.fetch("contract_objects").uniq.sort
extra = remote - expected
missing = expected - remote
tables = inventory.fetch("tables")
functions = inventory.fetch("functions")
summary = {
  "expected_objects" => expected.length,
  "remote_objects" => remote.length,
  "extra_objects" => extra.length,
  "missing_objects" => missing.length,
  "tables" => tables.length,
  "rls_enabled_tables" => tables.count { |table| table.fetch("rls_enabled") },
  "views" => inventory.fetch("views").length,
  "functions" => functions.length,
  "security_definer_functions" => functions.count { |function| function.fetch("security_definer") },
  "functions_with_search_path" => functions.count { |function| function.fetch("search_path_pinned") },
  "policies" => inventory.fetch("policies").length,
  "types" => inventory.fetch("types").length,
  "app_role_grants" => inventory.fetch("grants").length
}

report = inventory.merge(
  "project_ref" => project_ref,
  "contract" => {
    "summary" => summary,
    "extra_objects" => extra,
    "missing_objects" => missing
  }
)
report.delete("contract_objects")

if format == "json"
  puts JSON.pretty_generate(report)
  exit(extra.empty? && missing.empty? ? 0 : 1)
end

puts "[schema-inventory] project_ref=#{report.fetch("project_ref")}"
puts "[schema-inventory] objects expected=#{summary.fetch("expected_objects")} remote=#{summary.fetch("remote_objects")} extra=#{summary.fetch("extra_objects")} missing=#{summary.fetch("missing_objects")}"
puts "[schema-inventory] tables=#{summary.fetch("tables")} rls_enabled=#{summary.fetch("rls_enabled_tables")}/#{summary.fetch("tables")} policies=#{summary.fetch("policies")}"
puts "[schema-inventory] views=#{summary.fetch("views")} functions=#{summary.fetch("functions")} security_definer=#{summary.fetch("security_definer_functions")} search_path_pinned=#{summary.fetch("functions_with_search_path")}/#{summary.fetch("functions")}"
puts "[schema-inventory] types=#{summary.fetch("types")} app_role_grants=#{summary.fetch("app_role_grants")}"
unless extra.empty? && missing.empty?
  extra.each { |entry| puts "[schema-inventory][EXTRA] #{entry}" }
  missing.each { |entry| puts "[schema-inventory][MISSING] #{entry}" }
  exit 1
end
RUBY
