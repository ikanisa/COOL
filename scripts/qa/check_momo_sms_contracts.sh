#!/usr/bin/env bash
# Local unit/widget and parser contracts. Native receipt capture, direct API
# authorization, SQL finality and concurrency require their separate UAT lanes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
FLUTTER_BIN="${FLUTTER:-flutter}"
DENO_BIN="${DENO:-deno}"

flutter_tests=(
  test/core/play_integrity_service_test.dart
  test/core/revolut_launcher_test.dart
  test/core/rwanda_momo_number_test.dart
  test/core/rwf_amount_input_formatter_test.dart
  test/features/mobile_completion_test.dart
  test/features/device_permission_contract_test.dart
  test/security_hygiene_test.dart
  test/supabase_contract_test.dart
)
deno_tests=(
  supabase/functions/_shared/play_integrity_binding_test.ts
  supabase/functions/_shared/momo_sms_parser_test.ts
  supabase/functions/_shared/momo_sms_hybrid_test.ts
)
for executable in "$FLUTTER_BIN" "$DENO_BIN"; do
  command -v "$executable" >/dev/null || {
    printf 'Required test runtime unavailable: %s\n' "$executable" >&2
    exit 1
  }
done
for file in "${flutter_tests[@]}" "${deno_tests[@]}"; do
  [[ -f "$file" ]] || {
    printf 'Required test file missing: %s\n' "$file" >&2
    exit 1
  }
done

"$FLUTTER_BIN" test --no-pub --concurrency=4 "${flutter_tests[@]}"
"$DENO_BIN" test "${deno_tests[@]}"
printf 'MoMo local contracts passed. SQL/API/device UAT is assessed separately.\n'
