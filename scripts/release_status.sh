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

output_format="text"
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

presence() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    printf 'present'
  else
    printf 'missing'
  fi
}

strict_output="$(mktemp)"
trap 'rm -f "$strict_output"' EXIT

set +e
if [[ -n "${RELEASE_STATUS_STRICT_COMMAND:-}" ]]; then
  SUPABASE_READY_STRICT_PLATFORM=1 bash -c "$RELEASE_STATUS_STRICT_COMMAND" >"$strict_output" 2>&1
else
  SUPABASE_READY_STRICT_PLATFORM=1 "$ROOT_DIR/scripts/supabase_production_readiness.sh" >"$strict_output" 2>&1
fi
strict_rc=$?
set -e

if [[ "$strict_rc" -eq 0 ]]; then
  decision="GO"
  strict_status="pass"
else
  decision="NO-GO"
  strict_status="fail"
fi

if [[ "$output_format" == "json" ]]; then
  ruby -r json - "$strict_output" "$decision" "$strict_status" \
    "$(presence AUTH_CAPTCHA_SECRET)" \
    "$(presence AUTH_CAPTCHA_PROVIDER)" \
    "$(presence AUTH_CAPTCHA_SITE_KEY)" <<'RUBY'
path, decision, strict_status, captcha_secret, captcha_provider, captcha_site_key = ARGV
lines = File.readlines(path, chomp: true)
fail_index = lines.rindex { |line| line.include?("[supabase-ready][FAIL]") }
candidate_lines = fail_index ? lines[(fail_index + 1)..] : lines
blockers = candidate_lines
  .select { |line| line.match?(/\A\s*-\s+/) }
  .map { |line| line.sub(/\A\s*-\s*/, "") }
connectivity_failure = lines.any? do |line|
  line.include?("psql: error: connection to server") ||
    line.include?("failed to connect to postgres") ||
    line.include?("tenant allow_list") ||
    line.include?("EADDRNOTALLOWED")
end
if blockers.empty? && connectivity_failure
  blockers = [
    "Database readiness check could not reach Postgres. Use linked query mode from a trusted network, or set SUPABASE_READINESS_DATABASE_URL or DATABASE_POOLER_URL to an allowed Dashboard Supavisor pooler URL for this runner."
  ]
end
if blockers.empty? && strict_status != "pass"
  blockers = lines.last(12).reject { |line| line.strip.empty? }
end

classify = lambda do |message|
  case message
  when /HIBP leaked-password protection/i
    "auth_hibp_leaked_password_protection"
  when /CAPTCHA\/bot protection/i
    "auth_captcha_bot_protection"
  when /Free plan|project-pause/i
    "supabase_organization_plan"
  when /PITR/i
    "supabase_pitr"
  when /Database readiness check|Direct database readiness check/i
    "database_connectivity"
  else
    "unknown"
  end
end

blocker_keys = blockers.map { |message| classify.call(message) }.uniq
connectivity_blocked = blocker_keys.include?("database_connectivity")
platform_status = {
  auth_captcha_bot_protection: {
    status: blocker_keys.include?("auth_captcha_bot_protection") ? "blocked" : (connectivity_blocked ? "unknown" : "pass"),
    operator_owned: true,
    input_secret: captcha_secret,
    input_provider: captcha_provider,
    input_site_key: captcha_site_key
  },
  auth_hibp_leaked_password_protection: {
    status: blocker_keys.include?("auth_hibp_leaked_password_protection") ? "blocked" : (connectivity_blocked ? "unknown" : "pass"),
    operator_owned: true,
    requires_paid_plan: true
  },
  supabase_organization_plan: {
    status: blocker_keys.include?("supabase_organization_plan") ? "blocked" : (connectivity_blocked ? "unknown" : "pass"),
    operator_owned: true
  },
  supabase_pitr: {
    status: blocker_keys.include?("supabase_pitr") ? "blocked" : (connectivity_blocked ? "unknown" : "pass"),
    operator_owned: true,
    may_require_billing: true
  }
}

puts JSON.pretty_generate(
  {
    decision: decision,
    supabase_strict: strict_status,
    inputs: {
      auth_captcha_secret: captcha_secret,
      auth_captcha_provider: captcha_provider,
      auth_captcha_site_key: captcha_site_key,
    },
    blocker_keys: blocker_keys,
    platform: platform_status,
    blockers: blockers,
  }
)
RUBY
else
  printf '[release-status] decision=%s\n' "$decision"
  printf '[release-status] supabase_strict=%s\n' "$strict_status"
  printf '[release-status] auth_captcha_secret=%s\n' "$(presence AUTH_CAPTCHA_SECRET)"
  printf '[release-status] auth_captcha_provider=%s\n' "$(presence AUTH_CAPTCHA_PROVIDER)"
  printf '[release-status] auth_captcha_site_key=%s\n' "$(presence AUTH_CAPTCHA_SITE_KEY)"

  if [[ "$strict_rc" -ne 0 ]]; then
    printf '[release-status] blockers:\n'
    ruby - "$strict_output" <<'RUBY'
path = ARGV.fetch(0)
lines = File.readlines(path, chomp: true)
fail_index = lines.rindex { |line| line.include?("[supabase-ready][FAIL]") }
candidate_lines = fail_index ? lines[(fail_index + 1)..] : lines
blockers = []
candidate_lines.each do |line|
  blockers << line.sub(/\A\s*-\s*/, "") if line.match?(/\A\s*-\s+/)
end
connectivity_failure = lines.any? do |line|
  line.include?("psql: error: connection to server") ||
    line.include?("failed to connect to postgres") ||
    line.include?("tenant allow_list") ||
    line.include?("EADDRNOTALLOWED")
end
if blockers.empty? && connectivity_failure
  blockers = [
    "Database readiness check could not reach Postgres. Use linked query mode from a trusted network, or set SUPABASE_READINESS_DATABASE_URL or DATABASE_POOLER_URL to an allowed Dashboard Supavisor pooler URL for this runner."
  ]
end

if blockers.empty?
  lines.last(12).each { |line| puts "  - #{line}" unless line.strip.empty? }
else
  blockers.each { |line| puts "  - #{line}" }
end
RUBY
  fi
fi

exit 0
