#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ruby <<'RUBY'
expected = {
  "auth-send-whatsapp-otp" => :webhook,
  "allocate-payment" => :internal,
  "parse-payment-sms" => :internal,
  "ingest-payment-sms" => :user,
  "send-notification" => :internal,
}

issues = []
config = File.read("supabase/config.toml")
disabled = config.scan(/^\[functions\.([^\]]+)\]\s*\n(?:[^\[]*\n)*?verify_jwt\s*=\s*false/m).flatten.sort
unexpected_disabled = disabled - ["auth-send-whatsapp-otp"]
issues << "JWT verification disabled for unexpected functions: #{unexpected_disabled.join(", ")}" unless unexpected_disabled.empty?
issues << "auth-send-whatsapp-otp must have verify_jwt=false for Supabase Auth hook delivery" unless disabled.include?("auth-send-whatsapp-otp")

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
  when :internal
    issues << "#{name} must call requireInternalRequest(req)" unless source.include?("requireInternalRequest(req)")
    issues << "#{name} must import authErrorStatus" unless source.include?("authErrorStatus")
    issues << "#{name} must return authStatus instead of generic 500 for auth failures" unless source.include?("return jsonResponse({ error: safeErrorMessage(error) }, authStatus)")
  when :user
    issues << "#{name} must call requireUser(" unless source.include?("requireUser(")
    issues << "#{name} must import authErrorStatus" unless source.include?("authErrorStatus")
    issues << "#{name} must return authStatus instead of generic 500 for auth failures" unless source.include?("return jsonResponse({ error: safeErrorMessage(error) }, authStatus)")
  end
end

deploy = File.read("scripts/supabase_deploy.sh")
unless deploy.include?('if [[ "$function_name" == "auth-send-whatsapp-otp" ]]') && deploy.include?("--no-verify-jwt")
  issues << "deploy script must deploy only auth-send-whatsapp-otp with --no-verify-jwt"
end

if issues.any?
  warn "[collect-edge-auth-uat][FAIL]"
  issues.each { |issue| warn "  - #{issue}" }
  exit 1
end

puts "[collect-edge-auth-uat] Edge Function auth contract UAT passed"
RUBY
