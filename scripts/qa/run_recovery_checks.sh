#!/usr/bin/env bash
# Run only in an SDK-equipped, dependency-resolved full checkout. No deployment.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
DART_BIN="${DART_BIN:-dart}"
blocked() { printf 'BLOCKED: %s; application checks did not complete.\n' "$1" >&2; exit 2; }
command -v "$FLUTTER_BIN" >/dev/null 2>&1 || blocked 'Flutter executable is unavailable'
command -v "$DART_BIN" >/dev/null 2>&1 || blocked 'Dart executable is unavailable'
command -v python3 >/dev/null 2>&1 || blocked 'Python 3 is required to verify the SDK pin'
TARGETS=(
  lib/features/status/connection_recovery_screens.dart
  test/connection_recovery_screen_test.dart
  test/collect_disabled_action_regression_test.dart
)
for path in pubspec.yaml pubspec.lock .fvmrc .dart_tool/package_config.json "${TARGETS[@]}"; do
  [[ -f "$path" ]] || blocked "Required checkout file is missing: $path"
done
VERSION_JSON="$("$FLUTTER_BIN" --version --machine)"
if ! python3 - .fvmrc "$VERSION_JSON" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as stream:
        expected = json.load(stream)['flutter']
    actual = json.loads(sys.argv[2])['frameworkVersion']
    if not isinstance(expected, str) or not expected or actual != expected:
        raise ValueError(f'Flutter pin mismatch: expected {expected}, found {actual}')
    print(f'Flutter pin verified: {actual}')
except (KeyError, TypeError, ValueError, OSError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
PY
then
  blocked 'Flutter SDK does not match the checkout pin'
fi
"$DART_BIN" format --output=none --set-exit-if-changed "${TARGETS[@]}"
"$FLUTTER_BIN" analyze --no-pub "${TARGETS[@]}"
"$FLUTTER_BIN" test --no-pub \
  test/connection_recovery_screen_test.dart \
  test/collect_disabled_action_regression_test.dart
printf 'PASS: recovery formatting, targeted analysis and widget tests completed.\n'
