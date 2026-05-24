#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

output_format="markdown"
case "${1:-}" in
  --json)
    output_format="json"
    ;;
  "" )
    ;;
  * )
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

status_json="$(mktemp)"
trap 'rm -f "$status_json"' EXIT

if [[ -n "${SUPABASE_PLATFORM_PACKET_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_PLATFORM_PACKET_STATUS_JSON" >"$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json >"$status_json"
fi

ruby -r json -r time - "$output_format" "${SUPABASE_PROJECT_REF:-unknown}" "$status_json" <<'RUBY'
format, project_ref, path = ARGV
status = JSON.parse(File.read(path))
platform = status.fetch("platform", {})
inputs = status.fetch("inputs", {})
blocker_keys = status.fetch("blocker_keys", [])

catalog = {
  "auth_captcha_bot_protection" => {
    "title" => "Supabase CAPTCHA/bot protection",
    "severity" => "P0",
    "owner" => "operator",
    "billing" => "No Supabase billing change expected; provider account required.",
    "required_inputs" => [
      "AUTH_CAPTCHA_PROVIDER=hcaptcha or turnstile",
      "AUTH_CAPTCHA_SITE_KEY=<provider public site key>",
      "AUTH_CAPTCHA_SECRET=<provider secret key>"
    ],
    "apply_command" => "AUTH_CAPTCHA_PROVIDER=<hcaptcha|turnstile> AUTH_CAPTCHA_SITE_KEY=<provider-site-key> AUTH_CAPTCHA_SECRET=<provider-secret> make supabase-auth-harden",
    "client_build" => "Build the Flutter auth client with AUTH_CAPTCHA_ENABLED=true, AUTH_CAPTCHA_PROVIDER, and AUTH_CAPTCHA_SITE_KEY.",
    "verify_command" => "make supabase-ready-strict && make release-status-json",
    "docs" => [
      "https://supabase.com/docs/guides/auth/auth-captcha"
    ]
  },
  "auth_hibp_leaked_password_protection" => {
    "title" => "Supabase HIBP leaked-password protection",
    "severity" => "P0",
    "owner" => "operator",
    "billing" => "Requires Supabase Pro plan or above.",
    "required_inputs" => [
      "Paid Supabase organization plan"
    ],
    "apply_command" => "make supabase-auth-harden",
    "client_build" => "No client secret required; rerun after the plan upgrade.",
    "verify_command" => "make supabase-ready-strict && make release-status-json",
    "docs" => [
      "https://supabase.com/docs/guides/auth/password-security"
    ]
  },
  "supabase_organization_plan" => {
    "title" => "Supabase organization production plan",
    "severity" => "P0",
    "owner" => "operator",
    "billing" => "Upgrade the organization plan or record a signed project-pause risk exception.",
    "required_inputs" => [
      "Paid plan approval or signed Free-plan risk exception"
    ],
    "apply_command" => "Upgrade the Supabase organization in the Dashboard; no repository secret is required.",
    "client_build" => "No client build change.",
    "verify_command" => "make release-status-json",
    "docs" => [
      "https://supabase.com/docs/guides/platform/billing-on-supabase"
    ]
  },
  "supabase_pitr" => {
    "title" => "Supabase PITR/restore posture",
    "severity" => "P0",
    "owner" => "operator",
    "billing" => "PITR is a paid add-on and may require at least Small compute.",
    "required_inputs" => [
      "PITR retention decision: pitr_7, pitr_14, or pitr_28",
      "Billing approval, or signed recovery objective exception"
    ],
    "apply_command" => "PITR_ADDON_VARIANT=pitr_7 CONFIRM_ENABLE_PITR=\"$SUPABASE_PROJECT_REF:pitr_7\" make supabase-pitr-enable",
    "client_build" => "No client build change.",
    "verify_command" => "make supabase-ready-strict && make release-status-json",
    "docs" => [
      "https://supabase.com/docs/guides/platform/backups",
      "https://supabase.com/docs/guides/platform/manage-your-usage/point-in-time-recovery"
    ]
  }
}

ordered_keys = catalog.keys
items = ordered_keys.map do |key|
  meta = catalog.fetch(key)
  live = platform.fetch(key, {})
  meta.merge(
    "key" => key,
    "status" => live.fetch("status", blocker_keys.include?(key) ? "blocked" : "pass"),
    "live" => live
  )
end

packet = {
  "generated_at" => Time.now.utc.iso8601,
  "project_ref" => project_ref,
  "decision" => status.fetch("decision", "UNKNOWN"),
  "supabase_strict" => status.fetch("supabase_strict", "unknown"),
  "redacted_inputs" => inputs,
  "blocker_keys" => blocker_keys,
  "operator_actions" => items,
  "secret_handling" => "No secret values are printed. Pass provider secrets only as environment variables at command execution time."
}

if format == "json"
  puts JSON.pretty_generate(packet)
  exit 0
end

puts "# Supabase Platform Go-Live Packet"
puts
puts "- Project ref: `#{packet.fetch("project_ref")}`"
puts "- Decision: `#{packet.fetch("decision")}`"
puts "- Strict Supabase gate: `#{packet.fetch("supabase_strict")}`"
puts "- Secret handling: #{packet.fetch("secret_handling")}"
puts
puts "## Redacted Inputs"
puts
inputs.sort.each do |name, presence|
  puts "- `#{name}`: `#{presence}`"
end
puts
puts "## Operator Actions"
puts
items.each do |item|
  puts "### #{item.fetch("severity")} #{item.fetch("title")}"
  puts
  puts "- Key: `#{item.fetch("key")}`"
  puts "- Current status: `#{item.fetch("status")}`"
  puts "- Owner: `#{item.fetch("owner")}`"
  puts "- Billing/platform note: #{item.fetch("billing")}"
  puts "- Required inputs: #{item.fetch("required_inputs").join("; ")}"
  puts "- Apply: `#{item.fetch("apply_command")}`"
  puts "- Client/app follow-up: #{item.fetch("client_build")}"
  puts "- Verify: `#{item.fetch("verify_command")}`"
  puts "- Docs: #{item.fetch("docs").join(", ")}"
  puts
end
RUBY
