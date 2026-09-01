#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ruby -E UTF-8:UTF-8 <<'RUBY'
expected = {
  "auth-send-whatsapp-otp" => :webhook,
  "dispatch-notifications" => :internal,
  "ingest-bank-email" => :hmac,
  "ingest-bank-sms" => :user,
  "ingest-bank-statement" => :user,
  "ingest-payment-sms" => :user,
  "parse-payment-sms" => :internal,
  "send-notification" => :internal,
  "verify-play-integrity" => :user,
}

issues = []
config = File.read("supabase/config.toml")
disabled = config.scan(/^\[functions\.([^\]]+)\]\s*\n(?:[^\[]*\n)*?verify_jwt\s*=\s*false/m).flatten.sort
no_verify_functions = [
  "auth-send-whatsapp-otp",
  "dispatch-notifications",
  "ingest-bank-email",
  "parse-payment-sms",
  "send-notification",
]
unexpected_disabled = disabled - no_verify_functions
issues << "JWT verification disabled for unexpected functions: #{unexpected_disabled.join(", ")}" unless unexpected_disabled.empty?
issues << "auth-send-whatsapp-otp must have verify_jwt=false for Supabase Auth hook delivery" unless disabled.include?("auth-send-whatsapp-otp")
%w[dispatch-notifications send-notification].each do |name|
  issues << "#{name} must have verify_jwt=false because custom internal authorization is authoritative" unless disabled.include?(name)
end

shared_cors = File.read("supabase/functions/_shared/cors.ts")
issues << "shared CORS helper must expose authErrorStatus" unless shared_cors.include?("authErrorStatus")
issues << "authErrorStatus must map missing user auth to 401" unless shared_cors.include?("Authentication required")
issues << "authErrorStatus must map internal signature failures to 401" unless shared_cors.include?("Internal function authorization failed")

actual_functions = Dir["supabase/functions/*/index.ts"].map { |path| path.split("/")[-2] }.sort
missing = expected.keys.sort - actual_functions
extra = actual_functions - expected.keys.sort
issues << "Missing expected Edge Functions: #{missing.join(", ")}" unless missing.empty?
issues << "Unexpected Edge Functions: #{extra.join(", ")}" unless extra.empty?

expected.each do |name, mode|
  path = "supabase/functions/#{name}/index.ts"
  next issues << "#{name} source file is missing" unless File.exist?(path)

  source = File.read(path)
  case mode
  when :webhook
    issues << "#{name} must verify SEND_SMS_HOOK_SECRET" unless source.include?("SEND_SMS_HOOK_SECRET")
    issues << "#{name} must verify Standard Webhooks signatures" unless source.include?("standardwebhooks") && source.include?("Webhook")
    issues << "#{name} must return 401 for unauthorized hook delivery" unless source.include?('jsonResponse({ error: "Unauthorized" }, 401)')
  when :hmac
    issues << "#{name} must verify BANK_EMAIL_INGEST_HMAC_SECRET" unless source.include?("BANK_EMAIL_INGEST_HMAC_SECRET")
    issues << "#{name} must verify timestamped request HMAC" unless source.include?("verifyTimestampedHmac")
    issues << "#{name} must use service-role ingestion after HMAC verification" unless source.include?("serviceClient()")
  when :internal
    issues << "#{name} must call requireInternalRequest(req)" unless source.include?("requireInternalRequest(req)")
    issues << "#{name} must import authErrorStatus" unless source.include?("authErrorStatus")
    issues << "#{name} must return authStatus instead of generic 500 for auth failures" unless source.include?("return jsonResponse({ error: safeErrorMessage(error) }, authStatus)")
  when :user
    issues << "#{name} must call requireUser(" unless source.include?("requireUser(")
    user_auth_401 =
      (source.include?('message === "Authentication required"') && source.include?("401")) ||
      (source.include?("authErrorStatus") && source.include?("authStatus"))
    issues << "#{name} must return 401 for missing user auth" unless user_auth_401
  end
end

deploy = File.read("scripts/supabase_deploy.sh")
unless deploy.include?('NO_VERIFY_JWT_FUNCTIONS=(') && deploy.include?("ingest-bank-email") && deploy.include?("--no-verify-jwt")
  issues << "deploy script must deploy webhook and internal endpoints with --no-verify-jwt"
end

if issues.any?
  warn "[collect-edge-auth-uat][FAIL]"
  issues.each { |issue| warn "  - #{issue}" }
  exit 1
end

puts "[collect-edge-auth-uat] Edge Function auth contract UAT passed"
RUBY
