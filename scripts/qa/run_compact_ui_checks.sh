#!/usr/bin/env bash
# Run from a dependency-resolved Collect checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
NPM_BIN="${NPM_BIN:-npm}"
if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  printf '%s\n' 'BLOCKED: Flutter SDK is unavailable. No application checks ran.' >&2
  exit 2
fi
if ! command -v "$NPM_BIN" >/dev/null 2>&1; then
  printf '%s\n' 'BLOCKED: npm is unavailable.' >&2
  exit 2
fi
if [[ ! -f pubspec.yaml || ! -f .dart_tool/package_config.json || ! -f admin-web/package-lock.json ]]; then
  printf '%s\n' 'BLOCKED: use a complete Collect checkout and resolve its locked dependencies first.' >&2
  exit 2
fi
"$FLUTTER_BIN" --version
"$FLUTTER_BIN" analyze --no-pub
"$FLUTTER_BIN" test --no-pub --reporter expanded \
  test/collect_form_viewport_test.dart \
  test/features/member_roster_screen_test.dart \
  test/features/contribution_amount_accessibility_test.dart
"$NPM_BIN" --prefix admin-web test -- tests/foundation/shell.test.tsx tests/core/transaction-reverse.test.tsx
