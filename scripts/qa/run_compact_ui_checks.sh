#!/usr/bin/env bash
# Run only from a complete, dependency-resolved COOL checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  printf '%s\n' 'BLOCKED: Flutter SDK is unavailable. No application checks ran.' >&2
  exit 2
fi
if [[ ! -f pubspec.yaml || ! -f .dart_tool/package_config.json ]]; then
  printf '%s\n' 'BLOCKED: use a complete COOL checkout and resolve its locked dependencies first.' >&2
  exit 2
fi
"$FLUTTER_BIN" --version
"$FLUTTER_BIN" analyze --no-pub
"$FLUTTER_BIN" test --no-pub --reporter expanded \
  test/admin_filter_bar_responsive_test.dart \
  test/collect_form_viewport_test.dart \
  test/admin_reason_dialog_focus_test.dart
