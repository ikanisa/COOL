#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
case "${1:-}" in
  --json) output_format="json" ;;
  "") ;;
  *)
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

summary_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/collect-mobile-route-gate.XXXXXX")"
summary_path="$summary_tmp_dir/universal-contract-audit.json"
cleanup() {
  rm -f "$summary_path"
  rmdir "$summary_tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT
if ! bash ./scripts/universal_contract_audit.sh --json >"$summary_path"; then
  exit 1
fi

OUTPUT_FORMAT="$output_format" SUMMARY_JSON_PATH="$summary_path" ruby -r json <<'INNER_RUBY'
summary = JSON.parse(File.read(ENV.fetch("SUMMARY_JSON_PATH")))
failed = Array(summary.fetch("checks", [])).select { |check| check.fetch("status") != "pass" }
result = {
  "status" => failed.empty? ? "pass" : "fail",
  "evidence_source" => "DESIGN.md",
  "design_contract" => summary.fetch("design_contract", "DESIGN.md"),
  "checks" => summary.fetch("checks", []),
  "failures" => failed.flat_map { |check| Array(check["failures"]) }.uniq,
  "secret_handling" => "Reads DESIGN.md and generated route evidence metadata only, and does not inspect secrets or production customer data."
}

if ENV.fetch("OUTPUT_FORMAT") == "json"
  puts JSON.pretty_generate(result)
else
  puts "[mobile-route-artifact-gate] status=#{result.fetch("status")}"
  puts "[mobile-route-artifact-gate] design_contract=#{result.fetch("design_contract")}"
  result.fetch("failures").each { |failure| warn "[mobile-route-artifact-gate][FAIL] #{failure}" }
end

exit(result.fetch("status") == "pass" ? 0 : 1)
INNER_RUBY
