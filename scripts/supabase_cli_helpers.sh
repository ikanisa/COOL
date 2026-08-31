#!/usr/bin/env bash

supabase_cli() {
  if [[ -n "${SUPABASE_BIN:-}" ]]; then
    "$SUPABASE_BIN" "$@"
  elif command -v supabase >/dev/null 2>&1; then
    supabase "$@"
  elif [[ -x /usr/local/bin/supabase ]]; then
    /usr/local/bin/supabase "$@"
  elif [[ -x /opt/homebrew/bin/supabase ]]; then
    /opt/homebrew/bin/supabase "$@"
  elif command -v npx >/dev/null 2>&1; then
    npx -y supabase "$@"
  else
    printf '[supabase-cli][FAIL] Missing required command: supabase. Install the Supabase CLI or provide SUPABASE_BIN.\n' >&2
    exit 1
  fi
}

psql_cli() {
  local pgconnect_timeout="${PGCONNECT_TIMEOUT:-15}"
  if [[ -n "${PSQL_BIN:-}" ]]; then
    PGCONNECT_TIMEOUT="$pgconnect_timeout" "$PSQL_BIN" "$@"
  elif command -v psql >/dev/null 2>&1; then
    PGCONNECT_TIMEOUT="$pgconnect_timeout" psql "$@"
  elif [[ -x /usr/local/bin/psql ]]; then
    PGCONNECT_TIMEOUT="$pgconnect_timeout" /usr/local/bin/psql "$@"
  elif [[ -x /opt/homebrew/bin/psql ]]; then
    PGCONNECT_TIMEOUT="$pgconnect_timeout" /opt/homebrew/bin/psql "$@"
  elif [[ -x /Library/PostgreSQL/15/bin/psql ]]; then
    PGCONNECT_TIMEOUT="$pgconnect_timeout" /Library/PostgreSQL/15/bin/psql "$@"
  else
    printf '[supabase-cli][FAIL] Missing required command: psql. Install PostgreSQL client tools or provide PSQL_BIN.\n' >&2
    exit 1
  fi
}

supabase_management_query_file() {
  local query_file="$1"
  : "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
  : "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"

  local payload response http_status body
  payload="$(ruby -r json - "$query_file" <<'RUBY'
path = ARGV.fetch(0)
print JSON.generate(query: File.read(path), parameters: [])
RUBY
)"
  response="$(curl -sS -w '\n%{http_code}' \
    -X POST "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "$payload")"
  http_status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_status" != "200" && "$http_status" != "201" ]]; then
    printf '[supabase-management-query][FAIL] Management API database query returned HTTP %s.\n' "$http_status" >&2
    return 1
  fi

  printf '%s\n' "$body"
}

supabase_management_query_rows_file() {
  local query_file="$1"
  local output
  output="$(supabase_management_query_file "$query_file")" || return $?
  QUERY_JSON_OUTPUT="$output" ruby -r json <<'RUBY'
rows = JSON.parse(ENV.fetch("QUERY_JSON_OUTPUT"))
abort("Management API database query did not return a row array") unless rows.is_a?(Array)
rows.each do |row|
  abort("Management API database query returned a non-object row") unless row.is_a?(Hash)
  values = row.values
  puts(values.length == 1 ? values.first.to_s : values.map(&:to_s).join("\t"))
end
RUBY
}
