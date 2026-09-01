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
  elif command -v pnpm >/dev/null 2>&1; then
    pnpm --silent dlx supabase@latest "$@"
  else
    printf '[supabase-cli][FAIL] Missing required command: supabase. Install the Supabase CLI, expose npx/pnpm, or provide SUPABASE_BIN.\n' >&2
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
  supabase_management_query "$(<"$query_file")"
}

supabase_management_query() {
  local query="$1"
  : "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
  : "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"

  local payload response http_status body
  payload="$(QUERY_SQL="$query" ruby -r json <<'RUBY'
print JSON.generate(query: ENV.fetch("QUERY_SQL"), parameters: [])
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

supabase_management_query_rows() {
  local query="$1"
  local output
  output="$(supabase_management_query "$query")" || return $?
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

supabase_management_query_rows_file() {
  local query_file="$1"
  supabase_management_query_rows "$(<"$query_file")"
}

supabase_management_apply_pending_migrations() {
  local migration_dir="${1:-supabase/migrations}"
  [[ -d "$migration_dir" ]] || {
    printf '[supabase-management-migrations][FAIL] Migration directory not found: %s\n' "$migration_dir" >&2
    return 1
  }

  local remote_json plan
  remote_json="$(supabase_management_query \
    'select version, name from supabase_migrations.schema_migrations order by version;')" || return $?

  plan="$(REMOTE_MIGRATIONS_JSON="$remote_json" MIGRATION_DIR="$migration_dir" ruby -r json <<'RUBY'
remote_rows = JSON.parse(ENV.fetch("REMOTE_MIGRATIONS_JSON"))
abort("Remote migration history was not a row array") unless remote_rows.is_a?(Array)

remote = remote_rows.map { |row| row.fetch("version").to_s }
abort("Remote migration history contains duplicate versions") unless remote.uniq.length == remote.length

local = Dir[File.join(ENV.fetch("MIGRATION_DIR"), "*.sql")].sort.map do |path|
  basename = File.basename(path)
  match = basename.match(/\A(\d+)_([^\/]+)\.sql\z/)
  abort("Invalid migration filename: #{basename}") unless match
  [match[1], match[2], path]
end
local_versions = local.map(&:first)
abort("Local migration history contains duplicate versions") unless local_versions.uniq.length == local_versions.length

extra = remote - local_versions
abort("Remote migration history has versions absent locally: #{extra.join(", ")}") unless extra.empty?

pending = local.reject { |version, _name, _path| remote.include?(version) }
max_remote = remote.max
history_holes = pending.select { |version, _name, _path| max_remote && version < max_remote }
unless history_holes.empty?
  abort("Refusing Management API deployment with migration history holes: #{history_holes.map(&:first).join(", ")}")
end

pending.each { |version, name, path| puts [version, name, path].join("\t") }
RUBY
)" || return $?

  if [[ -z "$plan" ]]; then
    printf '[supabase-management-migrations] Remote migration history already matches local.\n'
    return 0
  fi

  local version name migration_path body transaction_sql applied
  while IFS=$'\t' read -r version name migration_path; do
    [[ -n "$version" && -n "$name" && -f "$migration_path" ]] || {
      printf '[supabase-management-migrations][FAIL] Invalid pending migration plan entry.\n' >&2
      return 1
    }

    body="$(ruby - "$migration_path" <<'RUBY'
path = ARGV.fetch(0)
sql = File.read(path, mode: "r:BOM|UTF-8")
sql = sql.sub(/\Abegin\s*;\s*/i, "")
sql = sql.sub(/\s*commit\s*;\s*\z/i, "")
abort("Migration still contains a transaction terminator after normalization: #{path}") if sql.match?(/(^|\n)\s*(begin|commit)\s*;/i)
print sql.rstrip
RUBY
)" || return $?

    transaction_sql="$(MIGRATION_BODY="$body" MIGRATION_VERSION="$version" MIGRATION_NAME="$name" ruby -e '
      def quote(value)
        "\x27#{value.gsub("\x27", "\x27\x27")}\x27"
      end
      body = ENV.fetch("MIGRATION_BODY")
      version = ENV.fetch("MIGRATION_VERSION")
      name = ENV.fetch("MIGRATION_NAME")
      puts "begin;"
      puts body
      puts ";" unless body.end_with?(";")
      puts "insert into supabase_migrations.schema_migrations (version, statements, name, created_by) values (#{quote(version)}, array[\x27Applied transactionally through the Supabase Management API\x27], #{quote(name)}, \x27codex-management-api\x27);"
      puts "commit;"
    ')" || return $?

    printf '[supabase-management-migrations] Applying %s_%s transactionally.\n' "$version" "$name"
    supabase_management_query "$transaction_sql" >/dev/null || return $?

    applied="$(supabase_management_query_rows \
      "select count(*) from supabase_migrations.schema_migrations where version = '$version' and name = '$name';")" || return $?
    [[ "$applied" == "1" ]] || {
      printf '[supabase-management-migrations][FAIL] Remote readback failed for %s_%s.\n' "$version" "$name" >&2
      return 1
    }
  done <<< "$plan"

  remote_json="$(supabase_management_query \
    'select version, name from supabase_migrations.schema_migrations order by version;')" || return $?
  REMOTE_MIGRATIONS_JSON="$remote_json" MIGRATION_DIR="$migration_dir" ruby -r json <<'RUBY'
  remote = JSON.parse(ENV.fetch("REMOTE_MIGRATIONS_JSON")).map do |row|
    row.fetch("version").to_s
  end
  local = Dir[File.join(ENV.fetch("MIGRATION_DIR"), "*.sql")].sort.map do |path|
    basename = File.basename(path)
    match = basename.match(/\A(\d+)_([^\/]+)\.sql\z/) or abort("Invalid migration filename: #{basename}")
    match[1]
  end
  abort("Remote migration version history does not exactly match local after deployment") unless remote == local
puts "[supabase-management-migrations] Remote migration history matches all #{local.length} local migrations."
RUBY
}
