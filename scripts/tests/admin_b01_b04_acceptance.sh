#!/usr/bin/env bash
# Collect Admin B01-B04 source verification and Flutter acceptance runner.
# Must execute in a complete git checkout of ikanisa/COOL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

printf '\n== Collect Admin source contracts ==\n'
python3 scripts/tests/admin_revolut_uiux_contract_test.py
python3 scripts/tests/admin_b01_b04_followup_contract_test.py

if ! command -v flutter >/dev/null 2>&1 || ! command -v dart >/dev/null 2>&1; then
  printf 'BLOCKED: Flutter and Dart are required for compilation and widget acceptance.\n' >&2
  exit 2
fi

EXPECTED_FLUTTER="$(python3 - <<'PY'
import json
print(json.load(open('.fvmrc', encoding='utf-8'))['flutter'])
PY
)"
ACTUAL_FLUTTER="$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')"
if [[ "$ACTUAL_FLUTTER" != "$EXPECTED_FLUTTER" ]]; then
  printf 'BLOCKED: Flutter %s is required by .fvmrc; found %s.\n' "$EXPECTED_FLUTTER" "$ACTUAL_FLUTTER" >&2
  exit 2
fi

printf '\n== Pinned dependencies and Dart formatting ==\n'
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed \
  lib/admin/admin_shell.dart \
  lib/admin/admin_shell_navigation.dart \
  lib/admin/core/admin_overview_runtime.dart \
  lib/admin/core/cloudflare_admin_sms_pages.dart \
  lib/admin/core/cloudflare_admin_sms_ui.dart \
  lib/admin/shared/components/admin_data_table.dart \
  lib/admin/shared/components/admin_empty_state.dart \
  lib/admin/shared/components/admin_record_facts_panel.dart \
  test/admin/cloudflare_admin_sms_test.dart \
  test/admin/admin_revolut_receipts_uiux_test.dart

printf '\n== Analyzer and targeted Widget QA ==\n'
flutter analyze --fatal-infos
flutter test test/admin/cloudflare_admin_sms_test.dart \
  test/admin/admin_revolut_receipts_uiux_test.dart --concurrency=1

if [[ "${COLLECT_ADMIN_FULL_UNIT_SUITE:-0}" == "1" ]]; then
  flutter test --concurrency=4 --exclude-tags=integration
else
  printf 'SKIPPED: full unit test suite (set COLLECT_ADMIN_FULL_UNIT_SUITE=1 to run).\n'
fi

if [[ "${COLLECT_ADMIN_PWA_ACCEPTANCE:-0}" == "1" ]]; then
  printf '\n== Shipping Admin PWA build and verification ==\n'
  bash scripts/admin_pwa_release_build.sh
  bash scripts/admin_pwa_manifest_gate.sh
  bash scripts/admin_pwa_hosting_gate.sh --json
  node scripts/tests/admin_pwa_worker_cache_test.mjs
  ruby scripts/tests/admin_pwa_bundle_gate_test.rb
else
  printf 'SKIPPED: PWA build (set COLLECT_ADMIN_PWA_ACCEPTANCE=1 with reviewed build configuration).\n'
fi
printf '\nPASS: requested local acceptance steps completed. Browser/production UAT is still separate.\n'
