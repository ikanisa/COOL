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
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
: "${DATABASE_URL:?DATABASE_URL is required}"

READINESS_DATABASE_URL="${SUPABASE_READINESS_DATABASE_URL:-${DATABASE_POOLER_URL:-$DATABASE_URL}}"

tmp_sql="$(mktemp)"
tmp_err="$(mktemp)"
trap 'rm -f "$tmp_sql" "$tmp_err"' EXIT

cat > "$tmp_sql" <<'SQL'
create or replace function pg_temp.collect_slow_query_report()
returns jsonb
language plpgsql
stable
as $$
begin
  if to_regclass('pg_stat_statements') is null then
    return jsonb_build_object('available', false, 'rows', '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'available', true,
    'rows', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'queryid', queryid,
          'calls', calls,
          'total_exec_time_ms', round(total_exec_time::numeric, 2),
          'mean_exec_time_ms', round(mean_exec_time::numeric, 2),
          'rows', rows,
          'query', left(regexp_replace(query, '\s+', ' ', 'g'), 240)
        )
        order by total_exec_time desc
      )
      from (
        select queryid, calls, total_exec_time, mean_exec_time, rows, query
        from pg_stat_statements
        where dbid = (select oid from pg_database where datname = current_database())
        order by total_exec_time desc
        limit 10
      ) slow
    ), '[]'::jsonb)
  );
exception
  when insufficient_privilege or undefined_table then
    return jsonb_build_object('available', false, 'error', sqlerrm, 'rows', '[]'::jsonb);
end;
$$;

select jsonb_build_object(
  'generated_at', now(),
  'database', current_database(),
  'extensions', coalesce((
    select jsonb_agg(jsonb_build_object('name', extname, 'version', extversion) order by extname)
    from pg_extension
    where extname in ('pg_stat_statements', 'pgcrypto', 'uuid-ossp')
  ), '[]'::jsonb),
  'cache', (
    select jsonb_build_object(
      'heap_blks_read', coalesce(sum(heap_blks_read), 0),
      'heap_blks_hit', coalesce(sum(heap_blks_hit), 0),
      'hit_ratio', case
        when coalesce(sum(heap_blks_hit + heap_blks_read), 0) = 0 then null
        else round((sum(heap_blks_hit)::numeric / sum(heap_blks_hit + heap_blks_read)::numeric), 4)
      end
    )
    from pg_statio_user_tables
    where schemaname = 'public'
  ),
  'tables', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'table', relname,
        'live_rows_estimate', n_live_tup,
        'dead_rows_estimate', n_dead_tup,
        'dead_row_ratio', case
          when (n_live_tup + n_dead_tup) = 0 then 0
          else round((n_dead_tup::numeric / (n_live_tup + n_dead_tup)::numeric), 4)
        end,
        'last_autovacuum', last_autovacuum,
        'last_autoanalyze', last_autoanalyze
      )
      order by n_live_tup desc, relname
    )
    from pg_stat_user_tables
    where schemaname = 'public'
  ), '[]'::jsonb),
  'indexes_without_scans', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'table', relname,
        'index', indexrelname,
        'idx_scan', idx_scan
      )
      order by relname, indexrelname
    )
    from (
      select relname, indexrelname, idx_scan
      from pg_stat_user_indexes
      where schemaname = 'public'
        and idx_scan = 0
        and indexrelname not like '%_pkey'
      order by relname, indexrelname
      limit 25
    ) unused_indexes
  ), '[]'::jsonb),
  'most_scanned_indexes', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'table', relname,
        'index', indexrelname,
        'idx_scan', idx_scan,
        'idx_tup_read', idx_tup_read,
        'idx_tup_fetch', idx_tup_fetch
      )
      order by idx_scan desc, relname, indexrelname
    )
    from (
      select relname, indexrelname, idx_scan, idx_tup_read, idx_tup_fetch
      from pg_stat_user_indexes
      where schemaname = 'public'
      order by idx_scan desc, relname, indexrelname
      limit 25
    ) scanned_indexes
  ), '[]'::jsonb),
  'slow_queries', pg_temp.collect_slow_query_report()
) as report;
SQL

if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" != "direct" ]]; then
  if ! output="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db query --linked -f "$tmp_sql" -o json --agent=yes 2>"$tmp_err")"; then
    cat "$tmp_err" >&2
    exit 1
  fi
  grep -Ev '^(A new version of Supabase CLI is available|We recommend updating regularly)' "$tmp_err" >&2 || true
else
  output="$(psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -Atq -f "$tmp_sql")"
fi

REPORT_OUTPUT="$output" ruby -r json <<'RUBY'
input = ENV.fetch("REPORT_OUTPUT")
start = input.index("{")
abort("operational report did not return JSON") unless start

depth = 0
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
  when "{"
    depth += 1
  when "}"
    depth -= 1
    if depth == 0
      finish = index
      break
    end
  end
end

data = JSON.parse(input[start..finish])
row = data.fetch("rows").first || {}
report = row.fetch("report", row)
puts JSON.pretty_generate(report)
RUBY
