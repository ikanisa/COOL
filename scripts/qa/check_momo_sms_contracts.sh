#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/dev/flutterw}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command bash
require_command ruby
require_command deno
if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Missing executable Flutter wrapper: $FLUTTER_BIN" >&2
  exit 1
fi

echo "==> shell syntax"
bash -n scripts/qa/release_readiness.sh
bash -n scripts/qa/verify_momo_sms_supabase_rollout.sh
bash -n scripts/qa/seed_android_momo_sms_test_inbox.sh
bash -n scripts/qa/run_momo_sms_device_integration.sh

echo "==> workflow yaml syntax"
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ci.yml'); YAML.load_file('.github/workflows/release.yml'); YAML.load_file('.github/workflows/momo-sms-rollout-verify.yml'); YAML.load_file('.github/workflows/momo-sms-device-integration.yml')"

echo "==> flutter test (M-Money SMS contracts)"
"$FLUTTER_BIN" test \
  test/core/services/app_access_service_test.dart \
  test/features/momo/models/momo_sms_sync_status_test.dart \
  test/features/momo/momo_sms_autoread_service_test.dart \
  test/features/momo/momo_sms_sync_support_test.dart \
  test/features/admin/operational_dashboard_screen_test.dart

echo "==> deno test (M-Money SMS reconciliation)"
deno test supabase/functions/parse-momo-sms/reconciliation_test.ts
