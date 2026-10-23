#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! "$ROOT_DIR/scripts/release_approval_evidence_gate.sh" --json >/dev/null; then
  printf '[release-go-preflight][BLOCKED] Current owner and artifact approval evidence is incomplete.\n' >&2
  exit 1
fi

status_json="$("$ROOT_DIR/scripts/release_status.sh" --json)" || {
  printf '[release-go-preflight][BLOCKED] Release status could not be established.\n' >&2
  exit 1
}
if ! RELEASE_STATUS_JSON="$status_json" ruby -r json -e '
  result = JSON.parse(ENV.fetch("RELEASE_STATUS_JSON"))
  exit(result["decision"] == "GO" && Array(result["blocker_keys"]).empty? ? 0 : 1)
'; then
  printf '[release-go-preflight][BLOCKED] Current release decision is not GO.\n' >&2
  exit 1
fi

printf '[release-go-preflight] Current approval evidence and release decision are GO.\n'
