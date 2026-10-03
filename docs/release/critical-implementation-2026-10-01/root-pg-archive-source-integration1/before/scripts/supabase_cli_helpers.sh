#!/usr/bin/env bash

COLLECT_SUPABASE_CLI_PIN_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.supabase-cli-version"

supabase_cli() {
  local required_version candidate actual_version
  if [[ ! -f "$COLLECT_SUPABASE_CLI_PIN_FILE" || -L "$COLLECT_SUPABASE_CLI_PIN_FILE" ]]; then
    printf '[supabase-cli][FAIL] Missing regular repository CLI version pin.\n' >&2
    return 1
  fi
  required_version="$(cat "$COLLECT_SUPABASE_CLI_PIN_FILE")"
  if [[ ! "$required_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '[supabase-cli][FAIL] Repository CLI version pin must be an exact release version.\n' >&2
    return 1
  fi

  if [[ -n "${SUPABASE_BIN:-}" ]]; then
    candidate="$SUPABASE_BIN"
  elif command -v supabase >/dev/null 2>&1; then
    candidate="$(command -v supabase)"
  elif [[ -x /usr/local/bin/supabase ]]; then
    candidate=/usr/local/bin/supabase
  elif [[ -x /opt/homebrew/bin/supabase ]]; then
    candidate=/opt/homebrew/bin/supabase
  else
    printf '[supabase-cli][FAIL] Install Supabase CLI %s on PATH or set SUPABASE_BIN. Automatic downloads are disabled.\n' "$required_version" >&2
    return 1
  fi

  # Check the executable selected by the caller before any project operation.
  # Do not print raw version output: an invalid wrapper may return sensitive data.
  if ! actual_version="$("$candidate" --version 2>/dev/null)"; then
    printf '[supabase-cli][FAIL] Selected CLI does not report its version.\n' >&2
    return 1
  fi
  actual_version="${actual_version%$'\r'}"
  if [[ "$actual_version" != "$required_version" ]]; then
    printf '[supabase-cli][FAIL] Selected CLI does not match repository version %s.\n' "$required_version" >&2
    return 1
  fi
  "$candidate" "$@"
}

# The reviewed PostgreSQL binding chooses one exact local executable. No
# override/PATH/Homebrew/installer fallback is admitted by this helper.
psql_cli() {
  local admission_module
  admission_module="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qa/postgres_admission.py"
  if [[ "$#" == "1" && ( "$1" == "--version" || "$1" == "-V" ) ]]; then
    python3 -B "$admission_module" local
  else
    python3 -B "$admission_module" psql -- "$@"
  fi
}

# curl's -H option exposes bearer and hook secrets in the process argument list.
# Keep the header in a short-lived, owner-only config file; callers must pass
# sensitive request bodies with --data-binary @- rather than as an argument.
collect_curl_secret_header() (
  set -euo pipefail
  local header_name="${1:?secret header name is required}"
  local header_value="${2:?secret header value is required}"
  shift 2
  local LC_ALL=C
  if [[ ! "$header_name" =~ ^[A-Za-z0-9-]+$ ||
        ! "$header_value" =~ ^[[:print:]]+$ ||
        "$header_value" == *\"* || "$header_value" == *\\* ]]; then
    printf '[supabase-curl][FAIL] Secret header contains unsupported characters.\n' >&2
    exit 1
  fi

  umask 077
  local header_config
  header_config="$(mktemp)"
  chmod 600 "$header_config"
  local cleanup_command
  printf -v cleanup_command 'rm -f -- %q' "$header_config"
  trap "$cleanup_command" EXIT
  printf 'header = "%s: %s"\n' "$header_name" "$header_value" >"$header_config"
  curl -q --config "$header_config" "$@"
)

supabase_management_curl() {
  : "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
  collect_curl_secret_header Authorization "Bearer $SUPABASE_ACCESS_TOKEN" "$@"
}

# libpq service and password files keep URI credentials out of client process
# arguments. The URL is parsed as data and both files are removed on every exit.
collect_pg_url_service() (
  set -euo pipefail
  local database_url="${1:?database URL is required}"
  local client="${2:?PostgreSQL client is required}"
  shift 2
  umask 077
  local service_file password_file pg_temp_dir
  pg_temp_dir="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  service_file="$(mktemp "$pg_temp_dir/collect-pg-service.XXXXXXXX")"
  password_file="$(mktemp "$pg_temp_dir/collect-pg-password.XXXXXXXX")"
  chmod 600 "$service_file"
  chmod 600 "$password_file"
  local cleanup_command
  printf -v cleanup_command 'rm -f -- %q %q' "$service_file" "$password_file"
  trap "$cleanup_command" EXIT
  COLLECT_PSQL_URL="$database_url" ruby -r uri - "$service_file" "$password_file" <<'RUBY'
begin
  uri = URI.parse(ENV.fetch('COLLECT_PSQL_URL'))
rescue URI::InvalidURIError, ArgumentError
  abort('[supabase-psql][FAIL] Invalid PostgreSQL URI')
end
abort('[supabase-psql][FAIL] PostgreSQL URI required') unless %w[postgres postgresql].include?(uri.scheme)
abort('[supabase-psql][FAIL] Host and database required') if uri.host.to_s.empty? || uri.path.to_s.sub(%r{\A/}, '').empty?

unescape = ->(value) { URI::DEFAULT_PARSER.unescape(value.to_s) }
host = uri.host.to_s
host = host[1...-1] if host.start_with?('[') && host.end_with?(']')
values = {
  'host' => host,
  'dbname' => unescape.call(uri.path.sub(%r{\A/}, '')),
}
values['port'] = uri.port.to_s if uri.port
values['user'] = unescape.call(uri.user) if uri.user
password = unescape.call(uri.password) if uri.password

allowed_query = %w[sslmode connect_timeout channel_binding application_name options
                   target_session_attrs gssencmode sslrootcert sslcert sslkey
                   keepalives keepalives_idle keepalives_interval keepalives_count]
uri.query.to_s.split('&').reject(&:empty?).each do |item|
  raw_key, raw_value = item.split('=', 2)
  key = unescape.call(raw_key)
  abort('[supabase-psql][FAIL] Unsupported PostgreSQL URI option') unless allowed_query.include?(key)
  values[key] = unescape.call(raw_value)
end

values.each do |key, value|
  abort("[supabase-psql][FAIL] Invalid #{key} value") if value.empty? || value.match?(/[\x00\r\n]/) || value.match?(/\A\s|\s\z/)
end
abort('[supabase-psql][FAIL] Invalid password value') if password && password.match?(/[\x00\r\n]/)
File.open(ARGV.fetch(0), File::WRONLY | File::TRUNC, 0o600) do |file|
  file.puts('[collect_readiness]')
  values.each { |key, value| file.puts("#{key}=#{value}") }
end
if password
  escaped_password = password.gsub(/[\\:]/) { |char| "\\#{char}" }
  File.open(ARGV.fetch(1), File::WRONLY | File::TRUNC, 0o600) do |file|
    file.puts("*:*:*:*:#{escaped_password}")
  end
end
RUBY
  if [[ -s "$password_file" ]]; then
    unset PGPASSWORD
    PGSERVICEFILE="$service_file" PGPASSFILE="$password_file" "$client" 'service=collect_readiness' "$@"
  else
    PGSERVICEFILE="$service_file" "$client" 'service=collect_readiness' "$@"
  fi
)

collect_psql_url_service() {
  local database_url="${1:?database URL is required}"
  shift
  collect_pg_url_service "$database_url" psql_cli "$@"
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
  response="$(printf '%s' "$payload" | supabase_management_curl -sS -w '\n%{http_code}' \
    -X POST "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
    -H "Content-Type: application/json" \
    --data-binary @-)"
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
# Preserve leading line comments while removing the outer transaction wrapper.
sql = sql.sub(/\A((?:\s+|--[^\r\n]*(?:\r?\n|\z))*)begin\s*;\s*/i, '\1')
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
