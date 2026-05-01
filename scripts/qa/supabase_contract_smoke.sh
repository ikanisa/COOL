#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command curl
require_command jq
require_command python3
require_command supabase

PROJECT_REF="${PROJECT_REF:-}"
if [[ -z "$PROJECT_REF" ]]; then
  PROJECT_REF_FILE="$ROOT_DIR/supabase/.temp/project-ref"
  if [[ ! -f "$PROJECT_REF_FILE" ]]; then
    echo "Missing linked project ref at $PROJECT_REF_FILE and PROJECT_REF is unset." >&2
    exit 1
  fi

  PROJECT_REF="$(tr -d '\r\n' < "$PROJECT_REF_FILE")"
  if [[ -z "$PROJECT_REF" ]]; then
    echo "Linked project ref is empty." >&2
    exit 1
  fi
fi

SUPABASE_URL="https://${PROJECT_REF}.supabase.co"
API_KEYS_JSON="$(supabase projects api-keys --project-ref "$PROJECT_REF" --output json)"
SUPABASE_ANON_KEY="$(
  printf '%s' "$API_KEYS_JSON" |
    jq -r '.[] | select(.name == "anon" and .type == "legacy") | .api_key' |
    head -n 1
)"

if [[ -z "$SUPABASE_ANON_KEY" || "$SUPABASE_ANON_KEY" == "null" ]]; then
  echo "Unable to resolve the legacy anon key for linked project $PROJECT_REF." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

REQUIRE_WALLET_ISSUER_SECRETS="${REQUIRE_WALLET_ISSUER_SECRETS:-0}"

file_has_exact_line() {
  local file="$1"
  local value="$2"
  grep -Fxq "$value" "$file"
}

bundle_has_secret() {
  local bundle="$1"
  local file="$2"
  local alternatives=()
  local option

  IFS='|' read -r -a alternatives <<< "$bundle"
  for option in "${alternatives[@]}"; do
    if file_has_exact_line "$file" "$option"; then
      return 0
    fi
  done
  return 1
}

required_secret_bundles_for() {
  case "$1" in
    allocate-contributions)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY"
      ;;
    biopay-create-payment-intent)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY FIREBASE_SERVICE_ACCOUNT_JSON"
      ;;
    biopay-enroll)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY FIREBASE_SERVICE_ACCOUNT_JSON"
      ;;
    biopay-match)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY FIREBASE_SERVICE_ACCOUNT_JSON"
      ;;
    biopay-revoke)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY FIREBASE_SERVICE_ACCOUNT_JSON"
      ;;
    evaluate-transfer-risk)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY GEMINI_API_KEY"
      ;;
    record-operational-health)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY"
      ;;
    send-otp)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY OTP_CODE_HASH_SECRET|SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY WHATSAPP_PHONE_NUMBER_ID WHATSAPP_ACCESS_TOKEN"
      ;;
    sms-ingest)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY"
      ;;
    verify-otp)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY AUTH_PHONE_PASSWORD_SECRET|SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY"
      ;;
    delete-account)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY"
      ;;
    generate-ai-content)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY GEMINI_API_KEY GENERATE_AI_CONTENT_CRON_SECRET|CRON_JOB_SECRET"
      ;;
    maps-gateway)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY GOOGLE_MAPS_SERVER_API_KEY|GEMINI_API_KEY"
      ;;
    parse-member-list)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY GEMINI_API_KEY"
      ;;
    parse-momo-sms)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY AI_SMS_PARSE_PROVIDER OPENAI_API_KEY|GEMINI_API_KEY"
      ;;
    rs-scan-ticket)
      echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY TICKET_QR_HMAC_SECRET"
      ;;
    wallet-issuer)
      if [[ "$REQUIRE_WALLET_ISSUER_SECRETS" == "1" ]]; then
        echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY GOOGLE_WALLET_ISSUER_ID GOOGLE_WALLET_SERVICE_ACCOUNT_JSON TICKET_QR_HMAC_SECRET"
      else
        echo "SUPABASE_URL|COOL_PROJECT_SUPABASE_URL SUPABASE_ANON_KEY|COOL_PROJECT_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY|COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

smoke_body_for() {
  case "$1" in
    allocate-contributions) echo '{"partner_id":"00000000-0000-0000-0000-000000000000"}' ;;
    biopay-create-payment-intent) echo '{}' ;;
    biopay-enroll) echo '{}' ;;
    biopay-match) echo '{}' ;;
    biopay-revoke) echo '{}' ;;
    evaluate-transfer-risk) echo '{}' ;;
    record-operational-health) echo '{"service":"sms_ingest","component":"android_sms_autoread","message":"smoke"}' ;;
    send-otp) echo '{}' ;;
    sms-ingest) echo '{}' ;;
    verify-otp) echo '{}' ;;
    delete-account) echo '{"confirm":true}' ;;
    generate-ai-content) echo '{}' ;;
    maps-gateway) echo '{}' ;;
    parse-member-list) echo '{}' ;;
    parse-momo-sms) echo '{"rawSmsId":"00000000-0000-0000-0000-000000000000"}' ;;
    rs-scan-ticket) echo '{"qrData":"smoke"}' ;;
    wallet-issuer) echo '{"action":"health"}' ;;
    *)
      return 1
      ;;
  esac
}

allowed_statuses_for() {
  case "$1" in
    allocate-contributions) echo "401" ;;
    biopay-create-payment-intent) echo "401" ;;
    biopay-enroll) echo "401" ;;
    biopay-match) echo "401" ;;
    biopay-revoke) echo "401" ;;
    evaluate-transfer-risk) echo "401" ;;
    record-operational-health) echo "401" ;;
    send-otp) echo "400" ;;
    sms-ingest) echo "401" ;;
    verify-otp) echo "400" ;;
    delete-account) echo "401" ;;
    generate-ai-content) echo "401" ;;
    maps-gateway) echo "401" ;;
    parse-member-list) echo "401" ;;
    parse-momo-sms) echo "401" ;;
    rs-scan-ticket) echo "401" ;;
    wallet-issuer) echo "200 401" ;;
    *)
      return 1
      ;;
  esac
}

echo "==> linked project: $PROJECT_REF"
if [[ "$REQUIRE_WALLET_ISSUER_SECRETS" != "1" ]]; then
  echo "==> wallet-issuer Google Wallet secrets are deferred until production go-live"
fi

echo "==> migration parity: local vs linked project"
migration_output="$tmp_dir/migrations.txt"
if ! supabase migration list --linked >"$migration_output" 2>&1; then
  cat "$migration_output" >&2
  exit 1
fi
cat "$migration_output"
python3 - "$migration_output" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
drift = []
for line in path.read_text().splitlines():
    if "|" not in line:
        continue
    parts = [part.strip() for part in line.split("|")]
    if len(parts) < 3:
        continue
    local, remote = parts[0], parts[1]
    if not re.fullmatch(r"\d{14}", local or ""):
        continue
    if local != remote:
        drift.append((local, remote))

if drift:
    print("Migration drift detected between local files and linked project:", file=sys.stderr)
    for local, remote in drift:
        print(f"  local={local or '<missing>'} remote={remote or '<missing>'}", file=sys.stderr)
    sys.exit(1)
PY

echo "==> REST smoke: groups select"
groups_http="$(
  curl -sS \
    -o "$tmp_dir/groups.json" \
    -w "%{http_code}" \
    "$SUPABASE_URL/rest/v1/groups?select=id,name,invite_code&limit=1" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY"
)"
if [[ "$groups_http" != "200" ]]; then
  echo "groups select failed with HTTP $groups_http" >&2
  cat "$tmp_dir/groups.json" >&2
  exit 1
fi

echo "==> RPC smoke: get_group_invite_preview"
invite_http="$(
  curl -sS \
    -o "$tmp_dir/invite_preview.json" \
    -w "%{http_code}" \
    "$SUPABASE_URL/rest/v1/rpc/get_group_invite_preview" \
    -X POST \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    --data '{"p_invite_code":"SMOKETST"}'
)"
if [[ "$invite_http" != "200" ]]; then
  echo "get_group_invite_preview failed with HTTP $invite_http" >&2
  cat "$tmp_dir/invite_preview.json" >&2
  exit 1
fi

echo "==> discovering frontend-invoked edge functions"
frontend_functions_file="$tmp_dir/frontend_functions.txt"
python3 - "$ROOT_DIR/lib" >"$frontend_functions_file" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
pattern = re.compile(r"functions\.invoke\(\s*['\"]([^'\"]+)['\"]", re.S)
names = set()

for path in root.rglob("*.dart"):
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        text = path.read_text(encoding="utf-8", errors="ignore")
    names.update(pattern.findall(text))

for name in sorted(names):
    print(name)
PY

if [[ ! -s "$frontend_functions_file" ]]; then
  echo "No frontend Edge Function invocations were discovered under lib/." >&2
  exit 1
fi

functions_json="$tmp_dir/functions.json"
secrets_json="$tmp_dir/secrets.json"
supabase functions list --project-ref "$PROJECT_REF" --output json >"$functions_json"
supabase secrets list --project-ref "$PROJECT_REF" --output json >"$secrets_json"

deployed_functions_file="$tmp_dir/deployed_functions.txt"
secret_names_file="$tmp_dir/secret_names.txt"
jq -r '.[] | select((.status // "") == "ACTIVE") | .name' "$functions_json" | sort -u >"$deployed_functions_file"
jq -r '.[].name' "$secrets_json" | sort -u >"$secret_names_file"

echo "==> frontend/backend function parity"
failure=0
while IFS= read -r function_name; do
  [[ -n "$function_name" ]] || continue
  echo "   -> $function_name"

  if ! file_has_exact_line "$deployed_functions_file" "$function_name"; then
    echo "Missing deployed Edge Function for frontend invocation: $function_name" >&2
    failure=1
    continue
  fi

  if ! bundles="$(required_secret_bundles_for "$function_name")"; then
    echo "No required-secret contract defined for $function_name." >&2
    failure=1
    continue
  fi

  for bundle in $bundles; do
    if ! bundle_has_secret "$bundle" "$secret_names_file"; then
      echo "Missing required secret for $function_name: one of [$bundle]" >&2
      failure=1
    fi
  done

  if ! smoke_body="$(smoke_body_for "$function_name")"; then
    echo "No smoke request body defined for $function_name." >&2
    failure=1
    continue
  fi

  if ! allowed_statuses="$(allowed_statuses_for "$function_name")"; then
    echo "No allowed smoke statuses defined for $function_name." >&2
    failure=1
    continue
  fi

  http_code="$(
    curl -sS \
      -o "$tmp_dir/${function_name}.json" \
      -w "%{http_code}" \
      "$SUPABASE_URL/functions/v1/$function_name" \
      -X POST \
      -H "apikey: $SUPABASE_ANON_KEY" \
      -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
      -H "Content-Type: application/json" \
      --data "$smoke_body"
  )"

  smoke_ok=0
  for allowed_status in $allowed_statuses; do
    if [[ "$http_code" == "$allowed_status" ]]; then
      smoke_ok=1
      break
    fi
  done

  if [[ "$smoke_ok" -ne 1 ]]; then
    echo "Edge Function smoke failed for $function_name with HTTP $http_code" >&2
    cat "$tmp_dir/${function_name}.json" >&2
    failure=1
  fi
done <"$frontend_functions_file"

if [[ "$failure" -ne 0 ]]; then
  exit 1
fi

if [[ -n "${DATABASE_URL:-}" ]]; then
  require_command psql
  echo "==> DB smoke: create_group_atomic + join_group_via_invite (rollback only)"
  psql "$DATABASE_URL" <<'SQL'
\set ON_ERROR_STOP on
begin;

do $$
declare
  v_user_one uuid := gen_random_uuid();
  v_user_two uuid := gen_random_uuid();
  v_phone_one text := '+2507' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_phone_two text := '+2507' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_create jsonb;
  v_join jsonb;
  v_group_id uuid;
begin
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user_one::text, true);

  insert into auth.users (
    id,
    aud,
    role,
    phone,
    phone_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  )
  values
    (
      v_user_one,
      'authenticated',
      'authenticated',
      v_phone_one,
      now(),
      now(),
      now(),
      jsonb_build_object(),
      jsonb_build_object()
    ),
    (
      v_user_two,
      'authenticated',
      'authenticated',
      v_phone_two,
      now(),
      now(),
      now(),
      jsonb_build_object(),
      jsonb_build_object()
    );

  insert into public.users (
    id,
    phone,
    full_name,
    country,
    language_code,
    momo_provider,
    is_admin
  )
  values
    (v_user_one, v_phone_one, 'Smoke User One', 'RW', 'en', '', false),
    (v_user_two, v_phone_two, 'Smoke User Two', 'RW', 'en', '', false);

  v_create := public.create_group_atomic(
    'Smoke Group',
    'private',
    'saving',
    null,
    'RW',
    1000,
    100,
    30,
    null,
    null,
    null,
    null
  );

  if coalesce(v_create->>'status', '') <> 'success' then
    raise exception 'create_group_atomic failed: %', coalesce(v_create->>'message', '<no message>');
  end if;

  v_group_id := nullif(v_create->>'group_id', '')::uuid;
  if v_group_id is null then
    raise exception 'create_group_atomic did not return a group id';
  end if;

  if nullif(v_create->>'invite_code', '') is null then
    raise exception 'create_group_atomic did not return an invite code';
  end if;

  perform set_config('request.jwt.claim.sub', v_user_two::text, true);
  v_join := public.join_group_via_invite(v_create->>'invite_code');

  if coalesce(v_join->>'status', '') not in ('joined', 'already_member') then
    raise exception 'join_group_via_invite failed: %', coalesce(v_join->>'message', '<no message>');
  end if;

  if (select count(*) from public.group_members where group_id = v_group_id) <> 2 then
    raise exception 'expected 2 group_members rows after join smoke';
  end if;
end
$$;

rollback;
SQL
else
  echo "==> skipping direct DB smoke (set DATABASE_URL to enable transactional SQL smoke)"
fi

echo "==> Supabase contract smoke passed"
