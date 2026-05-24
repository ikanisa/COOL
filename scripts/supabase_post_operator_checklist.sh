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

if [[ -n "${SUPABASE_POST_OPERATOR_STATUS_JSON:-}" ]]; then
  printf '%s\n' "$SUPABASE_POST_OPERATOR_STATUS_JSON" > "$status_json"
else
  "$ROOT_DIR/scripts/release_status.sh" --json > "$status_json"
fi

ruby -r json -r time - "$output_format" "${SUPABASE_PROJECT_REF:-unknown}" "$status_json" <<'RUBY'
format, project_ref, path = ARGV
status = JSON.parse(File.read(path))
blockers = Array(status["blocker_keys"])
inputs = status["inputs"] || {}

steps = [
  {
    key: "auth_captcha_bot_protection",
    title: "Enable Supabase CAPTCHA/bot protection",
    required_when: blockers.include?("auth_captcha_bot_protection"),
    operator_inputs: [
      "AUTH_CAPTCHA_PROVIDER=hcaptcha or turnstile",
      "AUTH_CAPTCHA_SITE_KEY=<provider public site key>",
      "AUTH_CAPTCHA_SECRET=<provider secret key>"
    ],
    apply: [
      "AUTH_CAPTCHA_PROVIDER=<hcaptcha|turnstile> AUTH_CAPTCHA_SITE_KEY=<provider-site-key> AUTH_CAPTCHA_SECRET=<provider-secret> make supabase-auth-harden",
      "Build the Flutter auth client with AUTH_CAPTCHA_ENABLED=true, AUTH_CAPTCHA_PROVIDER, and AUTH_CAPTCHA_SITE_KEY."
    ],
    verify: [
      "make release-status-json",
      "make supabase-ready-strict"
    ],
    pass_condition: "auth_captcha_bot_protection is absent from blocker_keys and CAPTCHA client inputs are present for the release build.",
    docs: ["https://supabase.com/docs/guides/auth/auth-captcha"]
  },
  {
    key: "auth_hibp_leaked_password_protection",
    title: "Enable HIBP leaked-password protection",
    required_when: blockers.include?("auth_hibp_leaked_password_protection"),
    operator_inputs: ["Paid Supabase organization plan"],
    apply: ["make supabase-auth-harden"],
    verify: [
      "make release-status-json",
      "make supabase-ready-strict"
    ],
    pass_condition: "auth_hibp_leaked_password_protection is absent from blocker_keys.",
    docs: ["https://supabase.com/docs/guides/auth/password-security"]
  },
  {
    key: "supabase_organization_plan",
    title: "Upgrade Supabase organization plan or sign accepted project-pause risk",
    required_when: blockers.include?("supabase_organization_plan"),
    operator_inputs: [
      "Paid Supabase plan approval, or a signed docs/release/SUPABASE_PLATFORM_EXCEPTIONS.json entry"
    ],
    apply: [
      "Upgrade the organization in Supabase Dashboard, or add a signed supabase_organization_plan exception."
    ],
    verify: [
      "make release-status-json",
      "make supabase-platform-exception-gate"
    ],
    pass_condition: "supabase_organization_plan is absent from blocker_keys, or it is the only remaining plan blocker covered by a valid signed exception.",
    docs: ["https://supabase.com/docs/guides/platform/billing-on-supabase"]
  },
  {
    key: "supabase_pitr",
    title: "Enable PITR or sign accepted recovery objective risk",
    required_when: blockers.include?("supabase_pitr"),
    operator_inputs: [
      "PITR_ADDON_VARIANT=pitr_7, pitr_14, or pitr_28",
      "Billing approval, or a signed docs/release/SUPABASE_PLATFORM_EXCEPTIONS.json entry"
    ],
    apply: [
      "PITR_ADDON_VARIANT=pitr_7 CONFIRM_ENABLE_PITR=\"$SUPABASE_PROJECT_REF:pitr_7\" make supabase-pitr-enable"
    ],
    verify: [
      "make release-status-json",
      "make supabase-platform-exception-gate"
    ],
    pass_condition: "supabase_pitr is absent from blocker_keys, or it is the only remaining recovery blocker covered by a valid signed exception.",
    docs: [
      "https://supabase.com/docs/guides/platform/backups",
      "https://supabase.com/docs/guides/platform/manage-your-usage/point-in-time-recovery"
    ]
  }
]

final_verification = [
  "make supabase-ready-strict",
  "make supabase-platform-exception-gate",
  "make supabase-go-live-gate",
  "make supabase-go-live-evidence"
]

packet = {
  generated_at: Time.now.utc.iso8601,
  project_ref: project_ref == "unknown" ? nil : project_ref,
  current_decision: status["decision"],
  current_supabase_strict: status["supabase_strict"],
  current_blocker_keys: blockers,
  redacted_inputs: inputs,
  checklist: steps,
  final_verification: final_verification,
  secret_handling: "This checklist reports only presence/missing flags and placeholder commands. Do not paste provider secrets into docs or commits."
}

if format == "json"
  puts JSON.pretty_generate(packet)
  exit 0
end

puts "# Supabase Post-Operator Verification Checklist"
puts
puts "- Generated at: `#{packet.fetch(:generated_at)}`"
puts "- Project ref: `#{packet[:project_ref] || "unknown"}`"
puts "- Current decision: `#{packet[:current_decision]}`"
puts "- Strict Supabase gate: `#{packet[:current_supabase_strict]}`"
puts "- Current blocker keys: `#{blockers.join(", ")}`"
puts "- Secret handling: #{packet.fetch(:secret_handling)}"
puts
puts "## Redacted Input Presence"
puts
inputs.sort.each { |name, presence| puts "- `#{name}`: `#{presence}`" }
puts
puts "## Operator Steps"
puts
steps.each do |step|
  puts "### #{step.fetch(:title)}"
  puts
  puts "- Key: `#{step.fetch(:key)}`"
  puts "- Required now: `#{step.fetch(:required_when)}`"
  puts "- Operator inputs: #{step.fetch(:operator_inputs).join("; ")}"
  puts "- Apply:"
  step.fetch(:apply).each { |command| puts "  - `#{command}`" }
  puts "- Verify:"
  step.fetch(:verify).each { |command| puts "  - `#{command}`" }
  puts "- Pass condition: #{step.fetch(:pass_condition)}"
  puts "- Docs: #{step.fetch(:docs).join(", ")}"
  puts
end

puts "## Final Verification"
puts
final_verification.each { |command| puts "- `#{command}`" }
RUBY
