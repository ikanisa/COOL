#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
MODE="${1:-}"

exec ruby "$ROOT_DIR/scripts/qa/public_website_static_gate.rb" "$BUILD_DIR" "$MODE"
