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

contract_json="$(ruby scripts/qa/mobile_design_gate.rb --check-contract --json)"
OUTPUT_FORMAT="$output_format" CONTRACT_JSON="$contract_json" ruby -r json <<'RUBY'
contract = JSON.parse(ENV.fetch("CONTRACT_JSON"))
failures = Array(contract["failures"])
result = {
  "status" => failures.empty? ? "pass" : "fail",
  "evidence_source" => "docs/release/mobile-design/mobile-parity-contract.json",
  "design_authority" => "revolut-design",
  "rule" => "MOBILE-DESIGN-100",
  "failures" => failures,
  "secret_handling" => "Reads the product contract and evidence metadata only; it does not inspect secrets or production customer data."
}

if ENV.fetch("OUTPUT_FORMAT") == "json"
  puts JSON.pretty_generate(result)
else
  puts "[mobile-route-artifact-gate] status=#{result.fetch("status")}"
  puts "[mobile-route-artifact-gate] authority=#{result.fetch("design_authority")} rule=#{result.fetch("rule")}"
  failures.each { |failure| warn "[mobile-route-artifact-gate][FAIL] #{failure}" }
end

exit(failures.empty? ? 0 : 1)
RUBY
