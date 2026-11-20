#!/usr/bin/env bash
# Full-checkout validation only. Never deploys, installs packages, or rewrites code.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
DART_BIN="${DART_BIN:-dart}"
NODE_BIN="${NODE_BIN:-node}"
NPM_BIN="${NPM_BIN:-npm}"
blocked() { printf 'BLOCKED: %s; full application checks did not complete.\n' "$1" >&2; exit 2; }
command -v "$FLUTTER_BIN" >/dev/null 2>&1 || blocked 'Flutter executable is unavailable'
command -v "$DART_BIN" >/dev/null 2>&1 || blocked 'Dart executable is unavailable'
command -v "$NODE_BIN" >/dev/null 2>&1 || blocked 'Node.js is unavailable'
command -v "$NPM_BIN" >/dev/null 2>&1 || blocked 'npm is unavailable'
command -v python3 >/dev/null 2>&1 || blocked 'Python 3 is required for SDK verification'
TARGETS=(
  lib/features/payments/contribute_entry_screen.dart
  lib/features/payments/contribution_flow_screen.dart
  lib/features/status/connection_recovery_screens.dart
  lib/shared/widgets/collect_foundation.dart
  lib/shared/widgets/collect_group_cards.dart
  lib/shared/widgets/collect_form_viewport.dart
  test/connection_recovery_screen_test.dart
  test/connection_recovery_screens_test.dart
  test/collect_disabled_action_regression_test.dart
  test/collect_lazy_group_list_test.dart
  test/form_viewport_namespace_test.dart
  test/collect_form_viewport_test.dart
  test/features/member_roster_screen_test.dart
  test/features/contribution_amount_accessibility_test.dart
  test/features/contribution_command_recovery_test.dart
  test/actual_member_history_sql_receipts_test.dart
)
for path in pubspec.yaml pubspec.lock .fvmrc .dart_tool/package_config.json admin-web/package.json admin-web/package-lock.json "${TARGETS[@]}"; do
  [[ -f "$path" ]] || blocked "Required checkout file is missing: $path"
done
VERSION_JSON="$("$FLUTTER_BIN" --version --machine)" || blocked 'Flutter version query failed'
DART_VERSION="$("$DART_BIN" --version 2>&1)" || blocked 'Dart version query failed'
if ! python3 - .fvmrc "$VERSION_JSON" "$DART_VERSION" <<'PY'
import json, re, sys
try:
    with open(sys.argv[1], encoding='utf-8') as stream:
        expected = json.load(stream)['flutter']
    versions = json.loads(sys.argv[2])
    actual = versions['frameworkVersion']
    if not isinstance(expected, str) or not expected or actual != expected:
        raise ValueError('Flutter does not match the checked-in SDK pin')
    bundled = versions['dartSdkVersion']
    if not isinstance(bundled, str) or not bundled.strip():
        raise ValueError('Flutter did not report its bundled Dart version')
    executable = re.search(r'Dart SDK version:\s+(\S+)', sys.argv[3])
    if executable is None or executable.group(1) != bundled.split()[0]:
        raise ValueError('Dart executable does not match Flutter bundled Dart')
    print(f'SDK pins verified: Flutter {actual}, Dart {executable.group(1)}')
except (OSError, TypeError, ValueError, KeyError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
PY
then
  blocked 'SDK identity verification failed'
fi
"$DART_BIN" format --output=none --set-exit-if-changed "${TARGETS[@]}"
# Whole-checkout analysis catches import conflicts outside the partial overlay.
"$FLUTTER_BIN" analyze --no-pub --fatal-infos
"$FLUTTER_BIN" test --no-pub --concurrency=1 --exclude-tags=integration --reporter=expanded
"$NPM_BIN" --prefix admin-web run typecheck
"$NPM_BIN" --prefix admin-web run lint
"$NPM_BIN" --prefix admin-web test
"$NODE_BIN" --test admin-web/tests/pwa/package-pwa.test.mjs
"$NODE_BIN" scripts/tests/admin_pwa_worker_cache_test.mjs
printf 'PASS: Flutter formatting, analysis, member unit/widget tests, and React Admin and PWA checks finished.\n'
