#!/usr/bin/env bash
# Compatibility entrypoint: the reconciled candidate owns the complete scope.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/scripts/qa/verify_candidate.py" --repo "$ROOT" --run "$@"
