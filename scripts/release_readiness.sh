#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"

echo "==> flutter analyze"
"$FLUTTER_BIN" analyze --fatal-infos

echo "==> flutter test (unit + widget)"
"$FLUTTER_BIN" test --concurrency=4 --exclude-tags=integration

echo "==> flutter test (integration smoke)"
"$FLUTTER_BIN" test --concurrency=4 test/integration_smoke

echo "==> deep-link release asset validation"
dart tool/deep_link_release_assets.dart --generate --check

echo "==> governance docs sync"
dart tool/governance_docs.dart --check

if [[ "${SKIP_ANDROID_FLAVOR_BUILDS:-0}" == "1" ]]; then
  echo "==> skipping android flavor builds (set SKIP_ANDROID_FLAVOR_BUILDS=0 to enable)"
else
  bash "$ROOT_DIR/scripts/verify_android_flavors.sh"
fi

bash "$ROOT_DIR/scripts/verify_ios_flavors.sh"

echo "==> deno test (edge functions)"
deno test \
  supabase/functions/parse-momo-sms/ai_parser_test.ts \
  supabase/functions/parse-momo-sms/rayon_confirmation_test.ts

echo "==> deno check (edge functions)"
deno_files=()
while IFS= read -r file; do
  deno_files+=("$file")
done < <(find supabase/functions -type f -name '*.ts' | sort)
deno check "${deno_files[@]}"

if [[ "${RUN_MIGRATION_APPLY:-0}" == "1" ]]; then
  echo "==> supabase db push --linked"
  supabase db push --linked
else
  echo "==> skipping migration apply (set RUN_MIGRATION_APPLY=1 to enable linked-project migration apply)"
fi

if [[ "${RUN_REMOTE_SMOKE:-0}" == "1" ]]; then
  echo "==> Supabase contract smoke (linked project)"
  bash "$ROOT_DIR/scripts/supabase_contract_smoke.sh"
else
  echo "==> skipping remote Supabase smoke (set RUN_REMOTE_SMOKE=1 to enable)"
fi

echo "==> manual release permission review still required"
