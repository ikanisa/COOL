#!/usr/bin/env bash
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

ROOT_DIR="$ROOT_DIR" OUTPUT_FORMAT="$output_format" ruby -r json -r time <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
output_format = ENV.fetch("OUTPUT_FORMAT")

checks = {
  "buro_reference" => /\bBURO\b|\bBuro\b/,
  "crypto_product" => /\bBitcoin\b|\bBTC\b|\bcrypto\s+(?:trading|asset|wallet|referral)s?\b/i,
  "token_asset_product" => /\btoken\s+(?:asset|mint|holding|balance)s?\b/i,
  "yield_product" => /\bAPY\b|\bstaking\b|\bearn product\b/i,
  "trading_action" => /\b(?:buy|sell|convert)\s+(?:crypto|token|asset|coin|BTC)\b/i,
  "legacy_navigation" => /\bActive goals\b|\bpublic directory\b/i,
  "member_identity_prompt" => /\b(?:enter|provide|choose|set)\s+(?:a\s+)?(?:real name|display name|avatar|anonymity)\b/i,
  "manual_payment_prompt" => /\b(?:paste|enter|submit|report)\s+(?:raw\s+)?(?:SMS|transaction ID|transaction reference)\b/i
}

allowed_matches = [
  {
    "path" => "lib/core/security/hash_utils.dart",
    "check" => "crypto_product",
    "text" => /package:crypto\/crypto\.dart/
  },
  {
    "path" => "lib/admin/core/admin_runtime.dart",
    "check" => "trading_action",
    "text" => /JsonEncoder|dart:convert/
  },
  {
    "path" => "lib/features/status/production_state_screens.dart",
    "check" => "manual_payment_prompt",
    "text" => /does not ask you to paste SMS messages or transaction IDs/
  },
  {
    "path" => "lib/shared/widgets/collect_components.dart",
    "check" => "manual_payment_prompt",
    "text" => /Do not paste SMS or transaction IDs/
  }
]

def allowed_match?(allowed_matches, path, check, line)
  allowed_matches.any? do |entry|
    entry.fetch("path") == path &&
      entry.fetch("check") == check &&
      line.match?(entry.fetch("text"))
  end
end

files = Dir[File.join(root_dir, "lib/**/*.dart")].sort
hits = []

files.each do |absolute_path|
  relative_path = absolute_path.delete_prefix("#{root_dir}/")
  File.readlines(absolute_path, chomp: true).each_with_index do |line, index|
    checks.each do |check, pattern|
      next unless line.match?(pattern)
      next if allowed_match?(allowed_matches, relative_path, check, line)

      hits << {
        "path" => relative_path,
        "line" => index + 1,
        "check" => check,
        "text" => line.strip
      }
    end
  end
end

status = hits.empty? ? "pass" : "fail"
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "scanned_files" => files.length,
  "hit_count" => hits.length,
  "hits" => hits,
  "secret_handling" => "This scan reports source-code lines only for product-boundary terms; it does not inspect environment values."
}

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[collect-product-boundary] status=#{status} scanned_files=#{files.length} hits=#{hits.length}"
  hits.each do |hit|
    warn "[collect-product-boundary][FAIL] #{hit.fetch("path")}:#{hit.fetch("line")} #{hit.fetch("check")}: #{hit.fetch("text")}"
  end
end

exit(status == "pass" ? 0 : 1)
RUBY
