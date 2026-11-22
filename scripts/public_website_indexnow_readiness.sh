#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

exec ruby "$ROOT_DIR/scripts/qa/public_website/indexnow.rb" readiness "$@"
