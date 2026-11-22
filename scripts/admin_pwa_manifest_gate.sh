#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec node admin-web/scripts/build-admin.mjs verify "$@"
