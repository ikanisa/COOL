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
  "stripe-create-customer" => :user,
  "stripe-create-setup-intent" => :user,
  "stripe-create-diaspora-contribution" => :user,
  "stripe-webhook" => :stripe_webhook,
  "verify-play-integrity" => :user,
}

issues = []
config = File.read("supabase/config.toml")
disabled = config.scan(/^\[functions\.([^\]]+)\]\s*\n(?:[^\[]*\n)*?verify_jwt\s*=\s*false/m).flatten.sort
no_verify_functions = ["auth-send-whatsapp-otp", "stripe-webhook"]
unexpected_disabled = disabled - no_verify_functions
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
  when :stripe_webhook
    issues << "#{name} must verify STRIPE_WEBHOOK_SECRET" unless source.include?("STRIPE_WEBHOOK_SECRET")
    issues << "#{name} must verify the stripe-signature header" unless source.include?("stripe-signature")
    issues << "#{name} must write webhook events through the service client" unless source.include?("stripe_webhook_events") && source.include?("serviceClient()")
    issues << "#{name} must not use user JWT auth" if source.include?("requireUser(")
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
unless deploy.include?('NO_VERIFY_JWT_FUNCTIONS=(') && deploy.include?("stripe-webhook") && deploy.include?("--no-verify-jwt")
  issues << "deploy script must deploy auth-send-whatsapp-otp and stripe-webhook with --no-verify-jwt"
end

if issues.any?
  warn "[collect-edge-auth-uat][FAIL]"
  issues.each { |issue| warn "  - #{issue}" }
  exit 1
end

puts "[collect-edge-auth-uat] Edge Function auth contract UAT passed"
RUBY
