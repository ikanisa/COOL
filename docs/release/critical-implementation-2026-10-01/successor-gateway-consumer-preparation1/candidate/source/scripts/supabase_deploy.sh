#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Validate reviewed source, scope and target before any project operation.
# Release credentials come from the environment, never a worktree .env.
exec python3 -B "$ROOT_DIR/scripts/qa/backend_release_delivery.py" run --launcher-root "$ROOT_DIR"
