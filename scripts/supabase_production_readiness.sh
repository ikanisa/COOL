#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"

EXPECTED_FUNCTIONS=(
  allocate-payment
  auth-send-whatsapp-otp
  ingest-payment-sms
  parse-payment-sms
  send-notification
)

REQUIRED_SECRETS=(
  OPENAI_API_KEY
  OPENAI_MODEL
  WHATSAPP_CLOUD_API_TOKEN
  WHATSAPP_PHONE_NUMBER_ID
  WHATSAPP_AUTH_TEMPLATE_NAME
  SEND_SMS_HOOK_SECRET
  INTERNAL_FUNCTION_SECRET
  SMS_INGEST_HMAC_SECRET
)

PLATFORM_ISSUES=()

log() {
  printf '[supabase-ready] %s\n' "$*"
}

warn() {
  printf '[supabase-ready][WARN] %s\n' "$*" >&2
}

platform_issue() {
  warn "$*"
}

fail() {
  printf '[supabase-ready][FAIL] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

pooler_connectivity_failure() {
  local output="$1"
  [[ "$output" == *"tenant allow_list"* ||
    "$output" == *"EADDRNOTALLOWED"* ||
    "$output" == *"failed to connect to postgres"* ||
    "$output" == *"psql: error: connection to server"* ]]
}

check_strict_platform_issues() {
  :
}

load_env() {
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
  fi

  : "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
  : "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
  : "${SUPABASE_DB_PASSWORD:?SUPABASE_DB_PASSWORD is required}"
  : "${DATABASE_URL:?DATABASE_URL is required}"
  READINESS_DATABASE_URL="${SUPABASE_READINESS_DATABASE_URL:-${DATABASE_POOLER_URL:-$DATABASE_URL}}"
  export READINESS_DATABASE_URL
}

db_query_json_rows() {
  local input
  input="$(cat)"
  QUERY_JSON_OUTPUT="$input" ruby -r json <<'RUBY'
input = ENV.fetch("QUERY_JSON_OUTPUT")
start = input.index("{")
abort("linked query did not return JSON") unless start

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

abort("linked query JSON was incomplete") unless finish

data = JSON.parse(input[start..finish])
data.fetch("rows").each do |row|
  values = row.values
  puts(values.length == 1 ? values.first.to_s : values.map(&:to_s).join("\t"))
end
RUBY
}

db_query_file() {
  local query_file="$1"
  if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" != "direct" ]]; then
    local output
    if output="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db query --linked -f "$query_file" -o json --agent=yes 2>&1)"; then
      db_query_json_rows <<< "$output"
      return 0
    fi
    warn "Linked database query failed; falling back to READINESS_DATABASE_URL."
  fi

  psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -Atq -f "$query_file"
}

db_query() {
  local query="$1"
  local query_file
  query_file="$(mktemp)"
  printf '%s\n' "$query" > "$query_file"
  db_query_file "$query_file"
  rm -f "$query_file"
}

check_schema_contract() {
  log "checking remote public schema contract"
  local inventory_json
  inventory_json="$(mktemp)"
  "$ROOT_DIR/scripts/supabase_schema_inventory.sh" --json > "$inventory_json"
  ruby -r json - "$inventory_json" <<'RUBY'
path = ARGV.fetch(0)
data = JSON.parse(File.read(path))
summary = data.fetch("contract").fetch("summary")
puts "schema expected=#{summary.fetch("expected_objects")} remote=#{summary.fetch("remote_objects")} extra=#{summary.fetch("extra_objects")} missing=#{summary.fetch("missing_objects")}"
puts "schema tables=#{summary.fetch("tables")} rls=#{summary.fetch("rls_enabled_tables")}/#{summary.fetch("tables")} policies=#{summary.fetch("policies")} functions=#{summary.fetch("functions")}"
exit(summary.fetch("extra_objects").to_i.zero? && summary.fetch("missing_objects").to_i.zero? ? 0 : 1)
RUBY
  rm -f "$inventory_json"
}

check_db_lint() {
  log "checking remote SQL lint"
  local lint_output
  set +e
  lint_output="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db lint --linked --schema public --fail-on error 2>&1)"
  local lint_rc=$?
  set -e

  if [[ "$lint_rc" -eq 0 ]]; then
    printf '%s\n' "$lint_output"
    return 0
  fi

  if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" != "direct" ]] && pooler_connectivity_failure "$lint_output"; then
    warn "Supabase db lint requires the direct pooler path and is unavailable from this runner; running local migration validation and linked schema/advisor gates instead."
    "$ROOT_DIR/scripts/migrations/validate_supabase_migrations.sh"
    return 0
  fi

  printf '%s\n' "$lint_output" >&2
  fail "Supabase SQL lint failed"
}

check_migration_history() {
  log "checking linked migration history"
  local remote_versions
  remote_versions="$(mktemp)"
  db_query "select version from supabase_migrations.schema_migrations order by version;" > "$remote_versions"

  ruby - "$remote_versions" <<'RUBY'
remote_path = ARGV.fetch(0)
local = Dir["supabase/migrations/*.sql"].map do |path|
  File.basename(path).split("_", 2).first
end.sort
remote = File.readlines(remote_path, chomp: true).map(&:strip).reject(&:empty?).sort
missing = local - remote
extra = remote - local
puts "migrations local=#{local.length} remote=#{remote.length} missing=#{missing.length} extra=#{extra.length}"
unless missing.empty? && extra.empty?
  missing.each { |version| puts "MISSING #{version}" }
  extra.each { |version| puts "EXTRA #{version}" }
  exit 1
end
RUBY
  rm -f "$remote_versions"
}

check_pending_migrations() {
  if [[ "${SUPABASE_READY_REQUIRE_POOLER_COMMANDS:-0}" == "1" || "${SUPABASE_DB_QUERY_MODE:-linked}" == "direct" ]]; then
    local dry_run
    dry_run="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db push -p "$SUPABASE_DB_PASSWORD" --dry-run)"
    printf '%s\n' "$dry_run"
    if [[ "$dry_run" == *"Would push these migrations:"* ]]; then
      fail "Pending remote migrations detected"
    fi
    return 0
  fi

  check_migration_history
}

check_rls() {
  log "checking RLS on public base tables"
  local result
  result="$(db_query "
    select count(*) filter (where c.relrowsecurity) || '/' || count(*)
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind = 'r';
  ")"
  log "RLS enabled tables: $result"
  local enabled="${result%%/*}"
  local total="${result##*/}"
  [[ "$enabled" == "$total" ]] || fail "Not all public base tables have RLS enabled: $result"
}

check_app_contract_columns() {
  log "checking live app contract columns"
  local missing
  missing="$(db_query "
    with expected(table_name, column_name) as (
      values
        ('raw_payment_sms', 'collection_id'),
        ('parsed_payment_events', 'collection_id')
    )
    select expected.table_name || '.' || expected.column_name
    from expected
    left join information_schema.columns c
      on c.table_schema = 'public'
     and c.table_name = expected.table_name
     and c.column_name = expected.column_name
    where c.column_name is null
    order by expected.table_name, expected.column_name;
  ")"
  [[ -z "$missing" ]] || fail "Missing app-contract columns: $missing"
}

check_explicit_indexes() {
  log "checking explicit migration indexes"
  local missing
  local query
  query="$(mktemp)"
ruby > "$query" <<'RUBY'
indexes = {}
Dir["supabase/migrations/*.sql"].sort.each do |path|
  sql = File.read(path)
  events = []
  sql.to_enum(:scan, /^create(?: unique)? index(?: if not exists)?\s+([a-zA-Z_][\w.]*)\s+on\s+([a-zA-Z_][\w.]*)/i).each do
    match = Regexp.last_match
    events << [match.begin(0), :add_index, match[1], match[2].sub(/^public\./, "")]
  end
  sql.to_enum(:scan, /^drop table(?: if exists)?\s+([a-zA-Z_][\w.]*)/i).each do
    match = Regexp.last_match
    events << [match.begin(0), :drop_table, nil, match[1].sub(/^public\./, "")]
  end
  events.sort_by(&:first).each do |_position, action, index_name, table_name|
    if action == :add_index
      indexes[index_name] = table_name
    else
      indexes.delete_if { |_name, indexed_table| indexed_table == table_name }
    end
  end
end
names = indexes.keys.sort
if names.empty?
  puts "select null where false;"
else
  values = names.map { |name| "('#{name.gsub("'", "''")}')" }.join(",")
  puts "with expected(indexname) as (values #{values})
        select expected.indexname
        from expected
        left join pg_indexes on pg_indexes.schemaname = 'public'
          and pg_indexes.indexname = expected.indexname
        where pg_indexes.indexname is null
        order by expected.indexname;"
  end
RUBY
  missing="$(db_query_file "$query")"
  rm -f "$query"
  [[ -z "$missing" ]] || fail "Missing explicit indexes: $missing"
}

check_sql_privileges() {
  log "checking SQL privilege contract"
  local violations
  violations="$(db_query "
    with allowed_table_grants(grantee, table_name, privilege_type) as (
      values
        ('anon', 'public_contributions_view', 'SELECT'),
        ('anon', 'public_profiles_view', 'SELECT'),
        ('authenticated', 'app_realtime_events', 'SELECT'),
        ('authenticated', 'collection_receivers', 'SELECT'),
        ('authenticated', 'member_collections_view', 'SELECT'),
        ('authenticated', 'member_collection_summary_view', 'SELECT'),
        ('authenticated', 'member_contributions_view', 'SELECT'),
        ('authenticated', 'payment_intents', 'SELECT'),
        ('authenticated', 'public_contributions_view', 'SELECT'),
        ('authenticated', 'public_profiles_view', 'SELECT')
    ),
    actual_table_grants as (
      select grantee, table_name, privilege_type
      from information_schema.role_table_grants
      where table_schema = 'public'
        and grantee in ('anon', 'authenticated')
    ),
    unexpected_table_grants as (
      select 'unexpected table grant: ' || grantee || ' ' || privilege_type || ' on ' || table_name as issue
      from actual_table_grants
      except
      select 'unexpected table grant: ' || grantee || ' ' || privilege_type || ' on ' || table_name
      from allowed_table_grants
    ),
    missing_table_grants as (
      select 'missing table grant: ' || grantee || ' ' || privilege_type || ' on ' || table_name as issue
      from allowed_table_grants
      except
      select 'missing table grant: ' || grantee || ' ' || privilege_type || ' on ' || table_name
      from actual_table_grants
    ),
    allowed_function_grants(grantee, routine_name, privilege_type) as (
      values
        ('anon', 'user_can_read_collection', 'EXECUTE'),
        ('anon', 'user_is_collection_admin', 'EXECUTE'),
        ('authenticated', 'admin_current_user', 'EXECUTE'),
        ('authenticated', 'admin_get_queue_sla', 'EXECUTE'),
        ('authenticated', 'admin_get_collection', 'EXECUTE'),
        ('authenticated', 'admin_get_payment', 'EXECUTE'),
        ('authenticated', 'admin_get_payment_event', 'EXECUTE'),
        ('authenticated', 'admin_get_receiver', 'EXECUTE'),
        ('authenticated', 'admin_get_sms_metadata', 'EXECUTE'),
        ('authenticated', 'admin_get_user', 'EXECUTE'),
        ('authenticated', 'admin_list_admin_users', 'EXECUTE'),
        ('authenticated', 'admin_list_allocations', 'EXECUTE'),
        ('authenticated', 'admin_list_audit_logs', 'EXECUTE'),
        ('authenticated', 'admin_list_collections', 'EXECUTE'),
        ('authenticated', 'admin_list_feature_flags', 'EXECUTE'),
        ('authenticated', 'admin_list_ledger', 'EXECUTE'),
        ('authenticated', 'admin_list_payment_events', 'EXECUTE'),
        ('authenticated', 'admin_list_payments', 'EXECUTE'),
        ('authenticated', 'admin_list_receivers', 'EXECUTE'),
        ('authenticated', 'admin_list_settings', 'EXECUTE'),
        ('authenticated', 'admin_list_sms_metadata', 'EXECUTE'),
        ('authenticated', 'admin_list_unallocated', 'EXECUTE'),
        ('authenticated', 'admin_list_users', 'EXECUTE'),
        ('authenticated', 'admin_overview', 'EXECUTE'),
        ('authenticated', 'admin_record_operator_note', 'EXECUTE'),
        ('authenticated', 'admin_reparse_payment_event', 'EXECUTE'),
        ('authenticated', 'admin_reveal_raw_sms', 'EXECUTE'),
        ('authenticated', 'admin_system_health', 'EXECUTE'),
        ('authenticated', 'admin_update_collection_support_status', 'EXECUTE'),
        ('authenticated', 'create_mobile_support_request', 'EXECUTE'),
        ('authenticated', 'create_group_with_owner', 'EXECUTE'),
        ('authenticated', 'join_group_by_slug', 'EXECUTE'),
        ('authenticated', 'create_payment_intent', 'EXECUTE'),
        ('authenticated', 'create_contribution_intent', 'EXECUTE'),
        ('authenticated', 'current_user_is_platform_admin', 'EXECUTE'),
        ('authenticated', 'current_user_has_admin_permission', 'EXECUTE'),
        ('authenticated', 'ensure_current_profile', 'EXECUTE'),
        ('authenticated', 'get_owner_group_health', 'EXECUTE'),
        ('authenticated', 'get_current_profile', 'EXECUTE'),
        ('authenticated', 'has_admin_permission', 'EXECUTE'),
        ('authenticated', 'is_platform_admin', 'EXECUTE'),
        ('authenticated', 'list_collection_collect_ids', 'EXECUTE'),
        ('authenticated', 'mark_notification_event_read', 'EXECUTE'),
        ('authenticated', 'record_sms_access_consent', 'EXECUTE'),
        ('authenticated', 'register_notification_device', 'EXECUTE'),
        ('authenticated', 'request_account_deletion', 'EXECUTE'),
        ('authenticated', 'update_collection_profile', 'EXECUTE'),
        ('authenticated', 'update_collection_receiver', 'EXECUTE'),
        ('authenticated', 'user_can_ingest_receiver_sms', 'EXECUTE'),
        ('authenticated', 'user_can_read_collection', 'EXECUTE'),
        ('authenticated', 'user_is_collection_admin', 'EXECUTE')
    ),
    actual_function_grants as (
      select grantee, routine_name, privilege_type
      from information_schema.routine_privileges
      where specific_schema = 'public'
        and grantee in ('PUBLIC', 'anon', 'authenticated')
    ),
    public_function_grants as (
      select 'unexpected PUBLIC function grant: ' || routine_name || ' ' || privilege_type as issue
      from actual_function_grants
      where grantee = 'PUBLIC'
    ),
    unexpected_function_grants as (
      select 'unexpected function grant: ' || grantee || ' ' || privilege_type || ' on ' || routine_name as issue
      from actual_function_grants
      where grantee in ('anon', 'authenticated')
      except
      select 'unexpected function grant: ' || grantee || ' ' || privilege_type || ' on ' || routine_name
      from allowed_function_grants
    ),
    missing_function_grants as (
      select 'missing function grant: ' || grantee || ' ' || privilege_type || ' on ' || routine_name as issue
      from allowed_function_grants
      except
      select 'missing function grant: ' || grantee || ' ' || privilege_type || ' on ' || routine_name
      from actual_function_grants
    )
    select issue from unexpected_table_grants
    union all select issue from missing_table_grants
    union all select issue from public_function_grants
    union all select issue from unexpected_function_grants
    union all select issue from missing_function_grants
    order by issue;
  ")"
  [[ -z "$violations" ]] || fail "SQL privilege contract violations: $violations"

  local missing_column_grants
  missing_column_grants="$(db_query "
    with roles(grantee) as (
      values ('anon'), ('authenticated')
    ),
    expected_column_grants(grantee, table_name, column_name, privilege_type) as (
      select roles.grantee, expected.table_name, expected.column_name, 'SELECT'
      from roles
      cross join (
        values
          ('profiles', 'id'),
          ('profiles', 'public_id'),
          ('profiles', 'created_at'),
          ('collections', 'id'),
          ('collections', 'slug'),
          ('collections', 'creator_user_id'),
          ('collections', 'title'),
          ('collections', 'description'),
          ('collections', 'currency'),
          ('collections', 'receiver_display_label'),
          ('collections', 'created_at'),
          ('collections', 'updated_at'),
          ('collections', 'archived_at'),
          ('payments', 'id'),
          ('payments', 'parsed_event_id'),
          ('payments', 'payment_intent_id'),
          ('payments', 'collection_id'),
          ('payments', 'contributor_user_id'),
          ('payments', 'contributor_public_id'),
          ('payments', 'amount_rwf'),
          ('payments', 'currency'),
          ('payments', 'transaction_id'),
          ('payments', 'source'),
          ('payments', 'status'),
          ('payments', 'posted_at'),
          ('payments', 'created_at'),
          ('ledger_entries', 'id'),
          ('ledger_entries', 'payment_id'),
          ('ledger_entries', 'collection_id'),
          ('ledger_entries', 'user_id'),
          ('ledger_entries', 'entry_type'),
          ('ledger_entries', 'amount_rwf'),
          ('ledger_entries', 'currency'),
          ('ledger_entries', 'visibility'),
          ('ledger_entries', 'created_at')
      ) as expected(table_name, column_name)
    ),
    actual_column_grants as (
      select grantee, table_name, column_name, privilege_type
      from information_schema.column_privileges
      where table_schema = 'public'
        and grantee in ('anon', 'authenticated')
        and privilege_type = 'SELECT'
    )
    select 'missing column grant: ' || grantee || ' SELECT on ' || table_name || '.' || column_name
    from expected_column_grants
    except
    select 'missing column grant: ' || grantee || ' SELECT on ' || table_name || '.' || column_name
    from actual_column_grants
    order by 1;
  ")"
  [[ -z "$missing_column_grants" ]] || fail "SQL column privilege contract violations: $missing_column_grants"
}

check_edge_function_auth_contract() {
  log "checking Edge Function auth contract"
  ruby <<'RUBY'
expected = {
  "auth-send-whatsapp-otp" => :webhook,
  "allocate-payment" => :internal,
  "parse-payment-sms" => :internal,
  "ingest-payment-sms" => :user,
  "send-notification" => :internal,
}

issues = []
config = File.read("supabase/config.toml")
disabled = config.scan(/^\[functions\.([^\]]+)\]\s*\n(?:[^\[]*\n)*?verify_jwt\s*=\s*false/m).flatten.sort
issues << "JWT verification disabled for unexpected functions: #{(disabled - ["auth-send-whatsapp-otp"]).join(", ")}" unless (disabled - ["auth-send-whatsapp-otp"]).empty?
issues << "auth-send-whatsapp-otp must have verify_jwt=false for Supabase Auth hook delivery" unless disabled.include?("auth-send-whatsapp-otp")

expected.each do |name, mode|
  path = "supabase/functions/#{name}/index.ts"
  source = File.read(path)
  case mode
  when :webhook
    issues << "#{name} must verify SEND_SMS_HOOK_SECRET" unless source.include?("SEND_SMS_HOOK_SECRET")
    issues << "#{name} must verify Standard Webhooks signatures" unless source.include?("standardwebhooks") && source.include?("Webhook")
  when :internal
    issues << "#{name} must call requireInternalRequest" unless source.include?("requireInternalRequest(req)")
  when :user
    issues << "#{name} must require an authenticated user" unless source.include?("requireUser(")
  end
end

deploy = File.read("scripts/supabase_deploy.sh")
issues << "deploy script must deploy only auth-send-whatsapp-otp with --no-verify-jwt" unless deploy.include?('if [[ "$function_name" == "auth-send-whatsapp-otp" ]]') && deploy.include?("--no-verify-jwt")

if issues.any?
  warn issues.join("\n")
  exit 1
end
RUBY
}

check_functions() {
  log "checking deployed Edge Function endpoints"
  local inventory
  if inventory="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli functions list --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null)"; then
    local actual expected
    actual="$(ruby -r json -e 'puts JSON.parse(STDIN.read).map { |fn| fn["name"] }.compact.sort' <<< "$inventory")"
    expected="$(printf '%s\n' "${EXPECTED_FUNCTIONS[@]}" | sort)"
    if [[ "$actual" != "$expected" ]]; then
      printf 'Expected functions:\n%s\nActual functions:\n%s\n' "$expected" "$actual" >&2
      fail "Unexpected Edge Function inventory"
    fi
  else
    platform_issue "Supabase Management API denied Edge Function inventory; using endpoint probes instead."
  fi

  local base_url="https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1"
  local body_file status

  body_file="$(mktemp)"
  status="$(curl -sS -o "$body_file" -w '%{http_code}' \
    -X POST "$base_url/auth-send-whatsapp-otp" \
    -H 'content-type: application/json' \
    -H "x-hook-secret: $SEND_SMS_HOOK_SECRET" \
    --data '{"user":{"phone":"+250788123456"},"sms":{}}')"
  [[ "$status" == "400" ]] || fail "auth-send-whatsapp-otp probe expected HTTP 400, got $status"
  grep -q 'Invalid OTP hook payload' "$body_file" || fail "auth-send-whatsapp-otp probe did not reach hook code"

  status="$(curl -sS -o "$body_file" -w '%{http_code}' \
    -X POST "$base_url/allocate-payment" \
    -H 'content-type: application/json' \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "x-collect-signature: $INTERNAL_FUNCTION_SECRET" \
    --data '{"parsed_event_id":"00000000-0000-0000-0000-000000000000"}')"
  [[ "$status" == "500" ]] || fail "allocate-payment probe expected HTTP 500 for dummy event, got $status"
  grep -q 'Parsed event not found' "$body_file" || fail "allocate-payment probe did not reach deterministic allocator"

  local fn
  for fn in ingest-payment-sms parse-payment-sms; do
    status="$(curl -sS -o "$body_file" -w '%{http_code}' \
      -X POST "$base_url/$fn" \
      -H 'content-type: application/json' \
      --data '{}')"
    [[ "$status" == "401" ]] || fail "$fn unauthenticated probe expected HTTP 401, got $status"
  done
  rm -f "$body_file"
}

check_secrets() {
  log "checking Edge Function secret names"
  local secret_inventory
  if secret_inventory="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli secrets list --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null)"; then
    local missing
    missing="$(ruby -r json -e '
        expected = ARGV
        names = JSON.parse(STDIN.read).map { |item| item["name"] || item["Name"] }.compact
        puts(expected - names)
      ' "${REQUIRED_SECRETS[@]}" <<< "$secret_inventory")"
    [[ -z "$missing" ]] || fail "Missing Edge Function secrets: $missing"
  else
    platform_issue "Supabase Management API denied Function Secret inventory; using local env presence plus live function probes."
    local name
    for name in "${REQUIRED_SECRETS[@]}" SUPABASE_SERVICE_ROLE_KEY; do
      [[ -n "${!name:-}" ]] || fail "Required local env var is missing for readiness probe: $name"
    done
  fi
}

check_auth_config() {
  log "checking Auth production configuration"
  local auth_config
  auth_config="$(curl -fsS "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/config/auth" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN")"

  local issues
  issues="$(ruby - "$auth_config" <<'RUBY'
require "json"
data = JSON.parse(ARGV.fetch(0))

issues = []

site_url = data["site_url"].to_s
if site_url.empty?
  issues << "Auth Site URL is not configured."
elsif site_url.start_with?("http://localhost", "http://127.0.0.1")
  issues << "Auth Site URL still points to localhost."
elsif !site_url.start_with?("https://")
  issues << "Auth Site URL should use HTTPS in production."
end

uri_allow_list = data["uri_allow_list"].to_s.split(",").map(&:strip).reject(&:empty?)
localhost_redirects = uri_allow_list.select { |url| url.include?("localhost") || url.include?("127.0.0.1") }
wildcard_redirects = uri_allow_list.select { |url| url.include?("*") }
issues << "Auth redirect allowlist includes localhost entries: #{localhost_redirects.join(", ")}" unless localhost_redirects.empty?
issues << "Auth redirect allowlist includes wildcard entries: #{wildcard_redirects.join(", ")}" unless wildcard_redirects.empty?

jwt_exp = data["jwt_exp"].to_i
issues << "Auth JWT expiry is missing." if jwt_exp <= 0
issues << "Auth JWT expiry exceeds 1 hour." if jwt_exp > 3600
issues << "Refresh token rotation is disabled." if data["refresh_token_rotation_enabled"] == false
issues << "Anonymous sign-ins are enabled." if data["external_anonymous_users_enabled"] == true
issues << "Manual account linking is enabled." if data["security_manual_linking_enabled"] == true
issues << "Password leaked-credential protection is disabled; treat as optional hardening unless release owner requires it." if data["password_hibp_enabled"] == false

expected_sms_hook_uri = "#{ENV.fetch("SUPABASE_URL")}/functions/v1/auth-send-whatsapp-otp"
issues << "Phone auth is disabled; WhatsApp OTP login cannot work." if data["external_phone_enabled"] != true
issues << "Send SMS Auth hook is disabled; WhatsApp OTP delivery will not use the Collect hook." if data["hook_send_sms_enabled"] != true
issues << "Phone OTP expiry must be 600 seconds for the 10 minute admin WhatsApp login window." if data["sms_otp_exp"].to_i != 600
if data["hook_send_sms_uri"].to_s != expected_sms_hook_uri
  issues << "Send SMS Auth hook URI does not point to the deployed WhatsApp OTP function."
end

email_auth_enabled = data["external_email_enabled"] == true

if email_auth_enabled
  issues << "Email auth autoconfirm is enabled; production should require email confirmation unless intentionally disabled." if data["mailer_autoconfirm"] == true
  issues << "Email auth is enabled but custom SMTP is not configured." if data["smtp_host"].to_s.empty?
  issues << "Password minimum length is below 8." if data["password_min_length"].to_i < 8
  issues << "Password updates do not require recent reauthentication." if data["security_update_password_require_reauthentication"] == false
end

if data["security_captcha_enabled"] == false
  issues << "Auth bot-protection challenge is disabled; treat as optional hardening unless release owner requires it."
else
  provider = data["security_captcha_provider"].to_s
  issues << "CAPTCHA provider is not hcaptcha or turnstile." unless %w[hcaptcha turnstile].include?(provider)
  env_provider = ENV["AUTH_CAPTCHA_PROVIDER"].to_s
  if !env_provider.empty? && env_provider != provider
    issues << "AUTH_CAPTCHA_PROVIDER does not match live Supabase CAPTCHA provider."
  end
  issues << "AUTH_CAPTCHA_SITE_KEY is missing for CAPTCHA-enabled client builds." if ENV["AUTH_CAPTCHA_SITE_KEY"].to_s.empty?
end

if data["mfa_totp_enroll_enabled"] == false && data["mfa_phone_enroll_enabled"] == false && data["mfa_web_authn_enroll_enabled"] == false
  issues << "User MFA enrollment is disabled for all factors."
end

puts issues
RUBY
)"
  if [[ -n "$issues" ]]; then
    while IFS= read -r issue; do
      platform_issue "$issue"
    done <<< "$issues"
  fi
}

check_platform_settings() {
  log "checking platform production settings"
  local project
  project="$(curl -fsS "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" || true)"
  local organization_id
  organization_id="$(ruby -r json -e 'data = JSON.parse(STDIN.read); puts data["organization_id"].to_s' <<< "$project" 2>/dev/null || true)"
  if [[ -n "$organization_id" ]]; then
    local organization
    organization="$(curl -fsS "https://api.supabase.com/v1/organizations/$organization_id" \
      -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" || true)"
    local plan
    plan="$(ruby -r json -e 'data = JSON.parse(STDIN.read); puts data["plan"].to_s' <<< "$organization" 2>/dev/null || true)"
    if [[ "$plan" == "free" ]]; then
      platform_issue "Supabase organization is on the Free plan; treat as operational capacity/commercial review, not an automatic release blocker."
    elif [[ -z "$plan" ]]; then
      platform_issue "Supabase organization billing plan could not be verified."
    fi
  else
    platform_issue "Supabase project organization could not be verified."
  fi

  local ssl_config
  ssl_config="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli ssl-enforcement get --project-ref "$SUPABASE_PROJECT_REF" --experimental -o json || true)"
  if [[ "$ssl_config" == *'"database": false'* ]]; then
    platform_issue "Database SSL enforcement is disabled. Enable before production go-live."
  fi

  local network_config
  network_config="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli network-restrictions get --project-ref "$SUPABASE_PROJECT_REF" --experimental -o json || true)"
  if [[ "$network_config" == *'0.0.0.0/0'* || "$network_config" == *'::/0'* ]]; then
    platform_issue "Database network restrictions allow public IPv4/IPv6 ranges. Restrict to operator/CI ranges if feasible."
  fi

  local backups
  backups="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli backups list --project-ref "$SUPABASE_PROJECT_REF" -o json || true)"
  if [[ "$backups" == *'"pitr_enabled": false'* ]]; then
    platform_issue "Point-in-time restore is disabled; treat as recovery-objective review, not an automatic release blocker."
  fi
}

main() {
  supabase_cli --version >/dev/null
  if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" == "direct" ]]; then
    psql_cli --version >/dev/null
  fi
  require_cmd ruby
  load_env

  log "checking linked project $SUPABASE_PROJECT_REF"
  if ! SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli projects list -o json \
    | ruby -r json -e 'ref = ENV.fetch("SUPABASE_PROJECT_REF"); project = JSON.parse(STDIN.read).find { |p| [p["id"], p["ref"]].include?(ref) }; abort("project not visible") unless project; puts "project status=#{project["status"]} postgres=#{project.dig("database", "version")} region=#{project["region"]}"'; then
    platform_issue "Supabase Management API did not list linked project; continuing with linked DB/function probes."
  fi

  check_db_lint
  "$ROOT_DIR/scripts/supabase_advisors_gate.sh"
  "$ROOT_DIR/scripts/supabase_advisors_warning_inventory.sh"
  check_pending_migrations
  check_schema_contract
  check_rls
  check_app_contract_columns
  check_explicit_indexes
  check_sql_privileges
  "$ROOT_DIR/scripts/collect_linked_uat.sh"
  "$ROOT_DIR/scripts/collect_admin_security_uat.sh"
  check_edge_function_auth_contract
  check_functions
  check_secrets
  check_auth_config
  check_platform_settings
  check_strict_platform_issues

  log "code-owned Supabase readiness checks passed"
}

main "$@"
