#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/dev/flutterw}"
source "$ROOT_DIR/scripts/lib/_backend_env.sh"

load_client_env_files "$ROOT_DIR" \
  SUPABASE_URL \
  SUPABASE_ANON_KEY \
  SUPABASE_STAGING_URL \
  SUPABASE_STAGING_ANON_KEY \
  SUPABASE_PRODUCTION_URL \
  SUPABASE_PRODUCTION_ANON_KEY
require_distinct_staging_and_production_supabase_projects

echo "==> flutter analyze"
"$FLUTTER_BIN" analyze --fatal-infos

echo "==> backend config contract"
bash "$ROOT_DIR/scripts/qa/validate_backend_config.sh"

echo "==> flutter test (unit + widget)"
"$FLUTTER_BIN" test --concurrency=4 --exclude-tags=integration

echo "==> flutter test (integration smoke)"
"$FLUTTER_BIN" test --concurrency=4 test/integration_smoke

echo "==> deep-link release asset validation"
dart tool/deep_link_release_assets.dart --generate --check

echo "==> Supabase migration validation"
bash "$ROOT_DIR/scripts/migrations/validate_supabase_migrations.sh"

echo "==> BioPay model contract validation"
if [ ! -f assets/models/biopay/mobilefacenet_int8.tflite ]; then
  echo "ERROR: BioPay production model asset not found at assets/models/biopay/mobilefacenet_int8.tflite"
  echo "       Cannot release without the production model bundle."
  exit 1
fi
dart tool/biopay_model_contract.dart --check

echo "==> governance docs sync"
dart tool/governance_docs.dart --check

if [[ "${SKIP_ANDROID_FLAVOR_BUILDS:-0}" == "1" ]]; then
  echo "==> skipping android flavor builds (set SKIP_ANDROID_FLAVOR_BUILDS=0 to enable)"
else
  bash "$ROOT_DIR/scripts/qa/verify_android_flavors.sh"
fi

if [[ "${RUN_ANDROID_MINIFY_CANARY:-0}" == "1" ]]; then
  echo "==> Android production minify canary"
  bash "$ROOT_DIR/scripts/deploy/build_production_minified_canary.sh"
else
  echo "==> skipping Android production minify canary (set RUN_ANDROID_MINIFY_CANARY=1 to enable)"
fi

bash "$ROOT_DIR/scripts/qa/verify_ios_flavors.sh"

echo "==> deno test (edge functions)"
deno_test_files=()
while IFS= read -r file; do
  deno_test_files+=("$file")
done < <(find supabase/functions -type f -name '*_test.ts' | sort)

if [[ "${#deno_test_files[@]}" -eq 0 ]]; then
  echo "ERROR: no Deno test files found under supabase/functions" >&2
  exit 1
fi

deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY,AUTH_PHONE_PASSWORD_SECRET,OTP_CODE_HASH_SECRET,OTP_TEST_PHONE,OTP_TEST_CODE,GOOGLE_SERVICE_ACCOUNT_EMAIL,GOOGLE_PRIVATE_KEY,AI_AUDIT_SHEET_ID \
  "${deno_test_files[@]}"

echo "==> deno check (edge functions)"
deno_files=()
while IFS= read -r file; do
  deno_files+=("$file")
done < <(find supabase/functions -type f -name '*.ts' | sort)
deno check "${deno_files[@]}"

if [[ "${RUN_MIGRATION_APPLY:-0}" == "1" ]]; then
  if [[ -n "${DATABASE_URL:-${SUPABASE_DB_URL:-}}" ]]; then
    echo "==> supabase db push --db-url"
    supabase db push --db-url "${DATABASE_URL:-${SUPABASE_DB_URL}}" --yes
  else
    echo "==> supabase db push --linked"
    supabase db push --linked --yes
  fi
else
  echo "==> skipping migration apply (set RUN_MIGRATION_APPLY=1 to enable remote or linked-project migration apply)"
fi

if [[ "${RUN_REMOTE_SMOKE:-0}" == "1" ]]; then
  echo "==> Supabase contract smoke (linked project)"
  bash "$ROOT_DIR/scripts/qa/supabase_contract_smoke.sh"
else
  echo "==> skipping remote Supabase smoke (set RUN_REMOTE_SMOKE=1 to enable)"
fi

if [[ "${RUN_MOMO_SMS_ROLLOUT_VERIFY:-0}" == "1" ]]; then
  echo "==> M-Money SMS Supabase rollout verification"
  bash "$ROOT_DIR/scripts/qa/verify_momo_sms_supabase_rollout.sh"
else
  echo "==> skipping M-Money SMS rollout verification (set RUN_MOMO_SMS_ROLLOUT_VERIFY=1 and DATABASE_URL or SUPABASE_DB_URL to enable)"
fi

echo "==> manual release permission review still required"
