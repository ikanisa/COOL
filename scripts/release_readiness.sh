#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test"
flutter test

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
  if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "RUN_MIGRATION_APPLY=1 requires DATABASE_URL" >&2
    exit 1
  fi

  echo "==> supabase db push"
  supabase db push --db-url "$DATABASE_URL"
else
  echo "==> skipping migration apply (set RUN_MIGRATION_APPLY=1 and DATABASE_URL to enable)"
fi

if [[ "${RUN_REMOTE_SMOKE:-0}" == "1" ]]; then
  echo "==> Supabase contract smoke (.env project)"
  bash "$ROOT_DIR/scripts/supabase_contract_smoke.sh"
else
  echo "==> skipping remote Supabase smoke (set RUN_REMOTE_SMOKE=1 to enable)"
fi

echo "==> manual release permission review still required"
