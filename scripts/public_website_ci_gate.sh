#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-static}"
OUT_DIR="${PUBLIC_WEBSITE_CI_OUT_DIR:-build/public_website_ci}"

mkdir -p "$OUT_DIR"

prepare_static() {
  ruby scripts/tests/public_app_media_test.rb
  ruby scripts/tests/public_website_gate_http_test.rb
  ruby scripts/tests/public_website_ci_gate_test.rb
  ruby scripts/tests/public_website_indexnow_test.rb
  bash scripts/public_landing_prepare_build.sh
}

run_indexnow_readiness() {
  bash scripts/public_website_indexnow_readiness.sh --json > "$OUT_DIR/public-indexnow-readiness.json"

  ruby -r json - "$OUT_DIR/public-indexnow-readiness.json" <<'RUBY'
path = ARGV.fetch(0)
payload = JSON.parse(File.read(path))
allowed = ["owner_key_not_provided", "ready"]
unless allowed.include?(payload.fetch("status"))
  abort("Unexpected IndexNow readiness status: #{payload.fetch("status")}")
end
abort("IndexNow URL submission must not happen in CI") unless payload.fetch("not_submitted_by_codex")
RUBY
}

run_live() {
  local completion_rc=0
  PUBLIC_WEBSITE_GATE_RESULTS_DIR="$OUT_DIR" \
    bash scripts/public_website_completion_gate.sh --json > "$OUT_DIR/public-completion-gate.json" ||
    completion_rc=$?

  ruby -r json - "$OUT_DIR/public-completion-gate.json" <<'RUBY'
path = ARGV.fetch(0)
payload = JSON.parse(File.read(path))
failed_code = payload.fetch("code_checks").select { |_id, passed| !passed }
abort("Code-owned completion checks failed: #{failed_code.keys.join(", ")}") unless failed_code.empty?

puts "Strict completion status: #{payload.fetch("status")}"
puts "External missing count: #{payload.fetch("missing_external_count")}"
if payload.fetch("status") != "pass"
  abort("Public website completion gate failed")
end
RUBY

  return "$completion_rc"
}

case "$MODE" in
  static)
    prepare_static
    bash scripts/public_website_quality_gate.sh --json > "$OUT_DIR/public-quality-gate.json"
    run_indexnow_readiness
    ;;
  live)
    run_live
    ;;
  all)
    prepare_static
    run_indexnow_readiness
    run_live
    ;;
  *)
    echo "Usage: $0 [static|live|all]" >&2
    exit 64
    ;;
esac

echo "public_website_ci_gate=$MODE ok out_dir=$OUT_DIR"
