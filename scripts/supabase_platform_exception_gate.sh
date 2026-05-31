#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

status_json="$(mktemp)"
trap 'rm -f "$status_json"' EXIT

if [[ -n "${SUPABASE_PLATFORM_EXCEPTION_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_PLATFORM_EXCEPTION_STATUS_JSON" >"$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json >"$status_json"
fi

ruby -r json - "$status_json" <<'RUBY'
status_path = ARGV.fetch(0)
status = JSON.parse(File.read(status_path))
blocker_keys = Array(status["blocker_keys"])

if blocker_keys.empty?
  puts "[platform-exceptions] no current SMS-first release blockers require exceptions"
  exit 0
end

warn "[platform-exceptions][FAIL] Current release blockers cannot be cleared by legacy platform exception: #{blocker_keys.join(", ")}"
warn "[platform-exceptions] Resolve current SMS-first blockers and rerun release-status."
exit 1
RUBY
