#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"
# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

if [[ "${COLLECT_SKIP_ENV_FILE:-0}" != "1" && -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is required}"
: "${INTERNAL_FUNCTION_SECRET:?INTERNAL_FUNCTION_SECRET is required}"

PARSER_UAT_DB_MODE="${COLLECT_LIVE_PARSER_DB_MODE:-management}"
PARSER_UAT_FUNCTION_URL="${COLLECT_PARSER_FUNCTION_URL:-https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1/parse-payment-sms}"

case "$PARSER_UAT_DB_MODE" in
  management)
    : "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required for management database mode}"
    ;;
  direct)
    : "${DATABASE_URL:?DATABASE_URL is required for direct database mode}"
    PARSER_UAT_DATABASE_URL="${COLLECT_LIVE_PARSER_DATABASE_URL:-${DATABASE_POOLER_URL:-$DATABASE_URL}}"
    ;;
  *)
    printf '[collect-parser-uat][FAIL] COLLECT_LIVE_PARSER_DB_MODE must be management or direct\n' >&2
    exit 1
    ;;
esac

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[collect-parser-uat][FAIL] missing command: %s\n' "$1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd ruby

if [[ "$PARSER_UAT_DB_MODE" == "direct" ]]; then
  psql_cli --version >/dev/null
else
  SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
    supabase_cli db query --linked 'select 1 as live_parser_uat_probe' \
    -o json --agent=yes >/dev/null
fi

parser_db_exec() {
  local compact_output=0
  local sql rendered variables_json query_output
  local -a variable_specs=()
  local -a direct_args=()

  while (($#)); do
    case "$1" in
      -v)
        [[ $# -ge 2 ]] || {
          printf '[collect-parser-uat][FAIL] missing value after -v\n' >&2
          return 1
        }
        variable_specs+=("$2")
        direct_args+=("$1" "$2")
        shift 2
        ;;
      -Atq|-Aqt|-A|-t)
        compact_output=1
        direct_args+=("$1")
        shift
        ;;
      *)
        direct_args+=("$1")
        shift
        ;;
    esac
  done

  if [[ "$PARSER_UAT_DB_MODE" == "direct" ]]; then
    psql_cli "$PARSER_UAT_DATABASE_URL" "${direct_args[@]}"
    return
  fi

  sql="$(cat)"
  variables_json="$(ruby -r json -e '
    variables = {}
    ARGV.each do |spec|
      key, value = spec.split("=", 2)
      abort("invalid psql variable: #{spec}") if key.to_s.empty? || value.nil?
      variables[key] = value
    end
    print JSON.generate(variables)
  ' -- "${variable_specs[@]}")"
  rendered="$(PARSER_SQL="$sql" PARSER_SQL_VARIABLES="$variables_json" ruby -r json -e '
    sql = ENV.fetch("PARSER_SQL")
    variables = JSON.parse(ENV.fetch("PARSER_SQL_VARIABLES"))
    quote = 39.chr
    variables.each do |key, value|
      literal = quote + value.gsub(quote, quote * 2) + quote
      sql = sql.gsub(":" + quote + key + quote, literal)
    end
    unresolved_pattern = Regexp.new(":" + quote + "[A-Za-z_][A-Za-z0-9_]*" + quote)
    unresolved = sql.scan(unresolved_pattern).uniq
    abort("unresolved psql variables: #{unresolved.join(", ")}") unless unresolved.empty?
    print sql
  ')"

  query_output="$(SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
    supabase_cli db query --linked "$rendered" -o json --agent=yes)"
  if [[ "$compact_output" == "1" ]]; then
    QUERY_OUTPUT="$query_output" ruby -r json -e '
      rows = JSON.parse(ENV.fetch("QUERY_OUTPUT")).fetch("rows")
      rows.each { |row| puts row.values.first }
    '
  fi
}

tag="collect_live_parser_uat_$(date +%s)_$$"
txn_id="TX$(ruby -e 'print rand(100000..999999).to_s')$(date +%S)"
owner_phone="+25079$(ruby -e 'print rand(1000000..9999999).to_s')"
contributor_phone="+25078$(ruby -e 'print rand(1000000..9999999).to_s')"
receiver_phone="+250788123456"
amount="4321"

raw_body="created in SQL after the contributor Collect ID exists"

owner_id=""
contributor_id=""
collection_id=""
intent_id=""
raw_sms_id=""

cleanup() {
  if [[ -z "$tag" ]]; then
    return
  fi
  parser_db_exec -v ON_ERROR_STOP=1 \
    -v tag="$tag" \
    -v owner_phone="$owner_phone" \
    -v contributor_phone="$contributor_phone" \
    -q <<'SQL' >/dev/null
with target_collections as (
  select id from collections where slug = :'tag'
),
target_users as (
  select id from auth.users where phone in (:'owner_phone', :'contributor_phone')
),
target_payments as (
  select p.id
  from payments p
  where p.collection_id in (select id from target_collections)
),
delete_audit as (
  delete from audit_logs
  where actor_user_id in (select id from target_users)
     or entity_id in (select id from target_collections)
     or entity_id in (select id from target_payments)
)
select 1;

alter table ledger_entries disable trigger ledger_entries_prevent_delete;
delete from ledger_entries
where collection_id in (select id from collections where slug = :'tag');
alter table ledger_entries enable trigger ledger_entries_prevent_delete;

with target_collections as (
  select id from collections where slug = :'tag'
),
target_users as (
  select id from auth.users where phone in (:'owner_phone', :'contributor_phone')
),
target_payments as (
  select p.id
  from payments p
  where p.collection_id in (select id from target_collections)
),
delete_allocations as (
  delete from payment_allocations where collection_id in (select id from target_collections)
),
delete_payments as (
  delete from payments where collection_id in (select id from target_collections)
),
delete_events as (
delete from parsed_payment_events
where collection_id in (select id from target_collections)
   or receiver_user_id in (select id from target_users)
),
delete_raw as (
  delete from raw_payment_sms
  where collection_id in (select id from target_collections)
     or receiver_user_id in (select id from target_users)
),
delete_intents as (
  delete from payment_intents where collection_id in (select id from target_collections)
),
delete_receivers as (
  delete from collection_receivers where collection_id in (select id from target_collections)
),
delete_members as (
  delete from collection_members where collection_id in (select id from target_collections)
),
delete_periods as (
  delete from recurring_periods where collection_id in (select id from target_collections)
),
delete_reports as (
  delete from collection_reports where collection_id in (select id from target_collections)
),
delete_collections as (
  delete from collections where id in (select id from target_collections)
),
delete_profiles as (
  delete from profiles where id in (select id from target_users)
)
delete from auth.users where id in (select id from target_users);
SQL
}
trap cleanup EXIT

owner_id="$(ruby -r securerandom -e 'print SecureRandom.uuid')"
contributor_id="$(ruby -r securerandom -e 'print SecureRandom.uuid')"
collection_id="$(ruby -r securerandom -e 'print SecureRandom.uuid')"
intent_id="$(ruby -r securerandom -e 'print SecureRandom.uuid')"
raw_sms_id="$(ruby -r securerandom -e 'print SecureRandom.uuid')"

parser_db_exec -v ON_ERROR_STOP=1 \
  -v owner_id="$owner_id" \
  -v contributor_id="$contributor_id" \
  -v collection_id="$collection_id" \
  -v intent_id="$intent_id" \
  -v raw_sms_id="$raw_sms_id" \
  -v tag="$tag" \
  -v txn_id="$txn_id" \
  -v owner_phone="$owner_phone" \
  -v contributor_phone="$contributor_phone" \
  -v receiver_phone="$receiver_phone" \
  -v raw_body="$raw_body" \
  -v amount="$amount" <<'SQL'
insert into auth.users (
  id,
  aud,
  role,
  phone,
  phone_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (:'owner_id', 'authenticated', 'authenticated', :'owner_phone', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  (:'contributor_id', 'authenticated', 'authenticated', :'contributor_phone', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

update profiles
  set momo_number = :'receiver_phone',
      momo_number_hash = encode(extensions.digest(:'receiver_phone', 'sha256'), 'hex')
  where id = :'owner_id';

update profiles
  set momo_number = :'contributor_phone',
      momo_number_hash = encode(extensions.digest(:'contributor_phone', 'sha256'), 'hex')
  where id = :'contributor_id';

insert into collections (
  id,
  slug,
  creator_user_id,
  title,
  description,
  receiver_display_label
)
values (
  :'collection_id',
  :'tag',
  :'owner_id',
  'Collect live parser UAT',
  'Temporary parser UAT row',
  'Parser UAT receiver'
);

insert into collection_members (collection_id, user_id, role, status)
values
  (:'collection_id', :'owner_id', 'owner', 'active'),
  (:'collection_id', :'contributor_id', 'member', 'active');

insert into collection_receivers (
  collection_id,
  receiver_user_id,
  momo_number,
  momo_number_hash,
  network,
  label,
  is_active
)
values (
  :'collection_id',
  :'owner_id',
  :'receiver_phone',
  encode(extensions.digest(:'receiver_phone', 'sha256'), 'hex'),
  'mtn_momo',
  'Parser UAT receiver',
  true
);

insert into payment_intents (
  id,
  collection_id,
  contributor_user_id,
  contributor_public_id,
  expected_amount_rwf,
  receiver_momo_number_hash,
  sender_phone_hash,
  status
)
values (
  :'intent_id',
  :'collection_id',
  :'contributor_id',
  (select public_id from profiles where id = :'contributor_id'),
  :'amount'::bigint,
  encode(extensions.digest(:'receiver_phone', 'sha256'), 'hex'),
  encode(extensions.digest(:'contributor_phone', 'sha256'), 'hex'),
  'pending'
);

insert into raw_payment_sms (
  id,
  collection_id,
  receiver_user_id,
  raw_sender,
  raw_body,
  body_hash,
  receiver_momo_number_hash,
  received_at_device,
  parse_status
)
values (
  :'raw_sms_id',
  null,
  :'owner_id',
  'MTN MOMO',
  'You have received 4,321 RWF from COLLECT UAT (' || :'contributor_phone' || ') Collect ID ' ||
    (select public_id from profiles where id = :'contributor_id') ||
    '. Financial Transaction Id: ' || :'txn_id' ||
    '. New balance is 900,000 RWF.',
  encode(extensions.digest(
    'You have received 4,321 RWF from COLLECT UAT (' || :'contributor_phone' || ') Collect ID ' ||
      (select public_id from profiles where id = :'contributor_id') ||
      '. Financial Transaction Id: ' || :'txn_id' ||
      '. New balance is 900,000 RWF.',
    'sha256'
  ), 'hex'),
  null,
  now(),
  'pending'
);
SQL

if [[ -z "$raw_sms_id" || -z "$collection_id" || -z "$intent_id" ]]; then
  printf '[collect-parser-uat][FAIL] setup did not return required IDs\n%s\n' "$setup_output" >&2
  exit 1
fi

body_file="$(mktemp)"
trap 'rm -f "$body_file"; cleanup' EXIT

status="$(
  curl -sS -o "$body_file" -w '%{http_code}' \
    -X POST "$PARSER_UAT_FUNCTION_URL" \
    -H 'content-type: application/json' \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "x-collect-signature: ${INTERNAL_FUNCTION_SECRET}" \
    --data "{\"raw_sms_id\":\"${raw_sms_id}\"}"
)"

if [[ "$status" != "200" ]]; then
  printf '[collect-parser-uat][FAIL] parse-payment-sms returned HTTP %s\n' "$status" >&2
  sed -n '1,20p' "$body_file" >&2
  exit 1
fi

ruby -r json -e '
  body = JSON.parse(File.read(ARGV.fetch(0)))
  abort("parse response missing ok=true") unless body["ok"] == true
  abort("SMS was not allocated by the standalone pipeline: #{body.inspect}") unless body["allocation_status"] == "allocated"
' "$body_file"

replay_status="$(
  curl -sS -o "$body_file" -w '%{http_code}' \
    -X POST "$PARSER_UAT_FUNCTION_URL" \
    -H 'content-type: application/json' \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "x-collect-signature: ${INTERNAL_FUNCTION_SECRET}" \
    --data "{\"raw_sms_id\":\"${raw_sms_id}\"}"
)"
if [[ "$replay_status" != "200" ]]; then
  printf '[collect-parser-uat][FAIL] parser replay returned HTTP %s\n' "$replay_status" >&2
  sed -n '1,20p' "$body_file" >&2
  exit 1
fi
ruby -r json -e '
  body = JSON.parse(File.read(ARGV.fetch(0)))
  abort("parser replay did not reuse the stored event") unless body["replay"] == true
  abort("parser replay changed allocation status") unless body["allocation_status"] == "allocated"
' "$body_file"

parser_db_exec -v ON_ERROR_STOP=1 \
  -v collection_id="$collection_id" \
  -v raw_sms_id="$raw_sms_id" \
  -v intent_id="$intent_id" \
  -v amount="$amount" \
  -Atq <<'SQL' | ruby -e '
values = STDIN.read.lines(chomp: true)
  .select { |line| line.include?("=") }
  .map { |line| line.split("=", 2) }
  .to_h
amount = ARGV.fetch(0)
required = {
  "event_count" => "1",
  "event_status" => "allocated",
  "schema_version" => "collect.sms_parser.openai.v2",
  "raw_sender_phone_leaked" => "false",
  "raw_receiver_phone_leaked" => "false",
  "payment_count" => "1",
  "allocation_method" => "auto_native_sms",
  "ledger_count" => "2",
  "group_balance" => amount,
  "payer_balance" => amount,
  "notification_count" => "1",
  "intent_status" => "matched",
  "collect_id_public_count" => "1"
}
required.each do |key, expected|
  actual = values[key]
  abort("[collect-parser-uat][FAIL] #{key} expected #{expected}, got #{actual.inspect}") unless actual == expected
end
abort("[collect-parser-uat][FAIL] parser_model missing") if values["parser_model"].to_s.empty?
' "$amount"
with event as (
  select *
  from parsed_payment_events
  where raw_sms_id = :'raw_sms_id'
)
select 'event_count=' || count(*) from event
union all
select 'event_status=' || allocation_status from event
union all
select 'parser_model=' || coalesce(parser_model, '') from event
union all
select 'schema_version=' || coalesce(parser_schema_version, '') from event
union all
select 'raw_sender_phone_leaked=' || coalesce(((parsed_json->>'sender_phone') not in ('[hashed]'))::text, 'false') from event
union all
select 'raw_receiver_phone_leaked=' || coalesce(((parsed_json->>'receiver_phone') not in ('[hashed]'))::text, 'false') from event
union all
select 'payment_count=' || count(*)
from payments p
join event e on e.id = p.parsed_event_id
where p.payment_intent_id = :'intent_id'
  and p.collection_id = :'collection_id'
  and p.amount_rwf = :'amount'::bigint
  and p.status = 'posted'
union all
select 'allocation_method=' || allocation_method
from payment_allocations
where payment_intent_id = :'intent_id'
  and collection_id = :'collection_id'
union all
select 'ledger_count=' || count(*)
from ledger_entries le
join payments p on p.id = le.payment_id
join event e on e.id = p.parsed_event_id
where le.amount_rwf = :'amount'::bigint
  and le.entry_type in ('collection_credit', 'member_credit')
union all
select 'group_balance=' || coalesce(sum(le.amount_rwf), 0)
from ledger_entries le
where le.collection_id = :'collection_id'
  and le.entry_type = 'collection_credit'
union all
select 'payer_balance=' || coalesce(sum(le.amount_rwf), 0)
from ledger_entries le
where le.collection_id = :'collection_id'
  and le.entry_type = 'member_credit'
  and le.user_id = (
    select contributor_user_id from payment_intents where id = :'intent_id'
  )
union all
select 'notification_count=' || count(*)
from notification_events event
where event.collection_id = :'collection_id'
  and event.user_id = (
    select contributor_user_id from payment_intents where id = :'intent_id'
  )
union all
select 'intent_status=' || status
from payment_intents
where id = :'intent_id'
union all
select 'collect_id_public_count=' || count(*)
from public_contributions_view
where collection_id = :'collection_id'
  and supporter_label = 'Collect ID ' || (
    select contributor_public_id from payment_intents where id = :'intent_id'
  );
SQL

# Simulate an outage after OpenAI output was saved but before allocation. The
# parser retry must reuse that stored result, allocate exactly once, and restore
# the raw evidence status without making a second model request.
recovery_intent_id="$(ruby -r securerandom -e 'print SecureRandom.uuid')"
recovery_raw_sms_id="$(ruby -r securerandom -e 'print SecureRandom.uuid')"
recovery_event_id="$(ruby -r securerandom -e 'print SecureRandom.uuid')"
recovery_txn_id="RECOVERY$(date +%s)$$"
recovery_amount="4322"

parser_db_exec -v ON_ERROR_STOP=1 \
  -v collection_id="$collection_id" \
  -v owner_id="$owner_id" \
  -v contributor_id="$contributor_id" \
  -v contributor_phone="$contributor_phone" \
  -v receiver_phone="$receiver_phone" \
  -v intent_id="$recovery_intent_id" \
  -v raw_sms_id="$recovery_raw_sms_id" \
  -v event_id="$recovery_event_id" \
  -v txn_id="$recovery_txn_id" \
  -v amount="$recovery_amount" <<'SQL'
insert into payment_intents (
  id,
  collection_id,
  contributor_user_id,
  contributor_public_id,
  expected_amount_rwf,
  receiver_momo_number_hash,
  sender_phone_hash,
  status
)
values (
  :'intent_id',
  :'collection_id',
  :'contributor_id',
  (select public_id from profiles where id = :'contributor_id'),
  :'amount'::bigint,
  encode(extensions.digest(:'receiver_phone', 'sha256'), 'hex'),
  encode(extensions.digest(:'contributor_phone', 'sha256'), 'hex'),
  'pending'
);

insert into raw_payment_sms (
  id,
  collection_id,
  receiver_user_id,
  raw_sender,
  raw_body,
  body_hash,
  receiver_momo_number_hash,
  received_at_device,
  parse_status
)
values (
  :'raw_sms_id',
  null,
  :'owner_id',
  'MTN MOMO',
  'Stored OpenAI UAT result ' || :'txn_id',
  encode(extensions.digest('Stored OpenAI UAT result ' || :'txn_id', 'sha256'), 'hex'),
  null,
  now(),
  'failed'
);

insert into parsed_payment_events (
  id,
  raw_sms_id,
  collection_id,
  receiver_user_id,
  is_mobile_money_payment,
  network,
  direction,
  amount_rwf,
  currency,
  transaction_id,
  sender_phone_hash,
  receiver_phone_hash,
  transaction_time,
  detected_user_public_id,
  confidence,
  parser_model,
  parser_schema_version,
  parsed_json,
  allocation_status
)
values (
  :'event_id',
  :'raw_sms_id',
  null,
  :'owner_id',
  true,
  'mtn_momo',
  'incoming',
  :'amount'::bigint,
  'RWF',
  :'txn_id',
  encode(extensions.digest(:'contributor_phone', 'sha256'), 'hex'),
  null,
  now(),
  (select public_id from profiles where id = :'contributor_id'),
  0.99,
  'uat-stored-openai-result',
  'collect.sms_parser.openai.v2',
  jsonb_build_object('sender_phone', '[hashed]', 'receiver_phone', null),
  'unallocated'
);
SQL

recovery_status="$(
  curl -sS -o "$body_file" -w '%{http_code}' \
    -X POST "$PARSER_UAT_FUNCTION_URL" \
    -H 'content-type: application/json' \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "x-collect-signature: ${INTERNAL_FUNCTION_SECRET}" \
    --data "{\"raw_sms_id\":\"${recovery_raw_sms_id}\"}"
)"
if [[ "$recovery_status" != "200" ]]; then
  printf '[collect-parser-uat][FAIL] unallocated-event retry returned HTTP %s\n' "$recovery_status" >&2
  sed -n '1,20p' "$body_file" >&2
  exit 1
fi
ruby -r json -e '
  body = JSON.parse(File.read(ARGV.fetch(0)))
  abort("unallocated-event retry did not reuse the stored OpenAI result") unless body["replay"] == true
  abort("unallocated-event retry did not allocate the stored OpenAI result: #{body.inspect}") unless body["allocation_status"] == "allocated"
  abort("unallocated-event retry changed the parser model") unless body["parser_model"] == "uat-stored-openai-result"
' "$body_file"

parser_db_exec -v ON_ERROR_STOP=1 \
  -v intent_id="$recovery_intent_id" \
  -v raw_sms_id="$recovery_raw_sms_id" \
  -v event_id="$recovery_event_id" \
  -Atq <<'SQL' | ruby -e '
values = STDIN.read.lines(chomp: true).map { |line| line.split("=", 2) }.to_h
required = {
  "raw_status" => "parsed",
  "event_status" => "allocated",
  "intent_status" => "matched",
  "payment_count" => "1",
  "ledger_count" => "2"
}
required.each do |key, expected|
  abort("[collect-parser-uat][FAIL] recovery #{key} expected #{expected}, got #{values[key].inspect}") unless values[key] == expected
end
'
select 'raw_status=' || parse_status from raw_payment_sms where id = :'raw_sms_id'
union all
select 'event_status=' || allocation_status from parsed_payment_events where id = :'event_id'
union all
select 'intent_status=' || status from payment_intents where id = :'intent_id'
union all
select 'payment_count=' || count(*) from payments where payment_intent_id = :'intent_id'
union all
select 'ledger_count=' || count(*)
from ledger_entries entry
join payments payment on payment.id = entry.payment_id
where payment.payment_intent_id = :'intent_id';
SQL

printf '[collect-parser-uat] live parser UAT passed for raw_sms_id=%s collection_id=%s\n' "$raw_sms_id" "$collection_id"
