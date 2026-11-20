#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mode=production
case "${1:-}" in
  --qualification) mode=qualification; shift ;;
  --fixture) mode=fixture; shift ;;
esac
if [[ "$#" -ne 0 ]]; then
  printf 'usage: %s [--qualification|--fixture]\n' "$0" >&2
  exit 2
fi
exec node admin-web/scripts/build-admin.mjs "$mode"
