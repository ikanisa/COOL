#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
: "${SUPABASE_URL:?SUPABASE_URL is required}"

log() {
  printf '[supabase-auth] %s\n' "$*"
}

if [[ -n "${AUTH_CAPTCHA_SECRET:-}" ]]; then
  : "${AUTH_CAPTCHA_PROVIDER:?AUTH_CAPTCHA_PROVIDER is required when AUTH_CAPTCHA_SECRET is set}"
  : "${AUTH_CAPTCHA_SITE_KEY:?AUTH_CAPTCHA_SITE_KEY is required when AUTH_CAPTCHA_SECRET is set so client builds can pass CAPTCHA tokens}"
  case "$AUTH_CAPTCHA_PROVIDER" in
    hcaptcha|turnstile)
      ;;
    *)
      printf '[supabase-auth][FAIL] AUTH_CAPTCHA_PROVIDER must be hcaptcha or turnstile.\n' >&2
      exit 1
      ;;
  esac
fi

if [[ "${SEND_SMS_HOOK_SECRET:-}" != v1,whsec_* ]]; then
  SEND_SMS_HOOK_SECRET="v1,whsec_$(openssl rand -base64 32 | tr -d '\n')"
  export SEND_SMS_HOOK_SECRET
  if [[ -f .env ]]; then
    ruby -0777 -i -pe 'BEGIN { v=ENV.fetch("SEND_SMS_HOOK_SECRET") }; $_ = $_.sub(/^SEND_SMS_HOOK_SECRET=.*$/, "SEND_SMS_HOOK_SECRET=#{v}")' .env
  fi
  log "rotated SEND_SMS_HOOK_SECRET into Standard Webhooks format"
fi

log "updating Edge Function SEND_SMS_HOOK_SECRET"
SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli secrets set \
  --project-ref "$SUPABASE_PROJECT_REF" \
  SEND_SMS_HOOK_SECRET="$SEND_SMS_HOOK_SECRET" >/dev/null

payload="$(
  ruby -r json -e '
    public_url = ENV["APP_PUBLIC_URL"].to_s
    public_url = "https://easymo.vercel.app" if public_url.empty?
    payload = {
      site_url: public_url,
      uri_allow_list: public_url,
      external_anonymous_users_enabled: false,
      external_email_enabled: false,
      external_phone_enabled: true,
      hook_send_sms_enabled: true,
      hook_send_sms_uri: "#{ENV.fetch("SUPABASE_URL")}/functions/v1/auth-send-whatsapp-otp",
      hook_send_sms_secrets: ENV.fetch("SEND_SMS_HOOK_SECRET"),
      mailer_autoconfirm: false,
      password_hibp_enabled: true,
      password_min_length: 8,
      security_update_password_require_reauthentication: true,
      sms_otp_exp: 600,
      sms_otp_length: 6,
      sms_max_frequency: 30
    }

    if ENV["AUTH_CAPTCHA_SECRET"] && !ENV["AUTH_CAPTCHA_SECRET"].empty?
      payload[:security_captcha_enabled] = true
      payload[:security_captcha_provider] = ENV.fetch("AUTH_CAPTCHA_PROVIDER")
      payload[:security_captcha_secret] = ENV.fetch("AUTH_CAPTCHA_SECRET")
    end

    print JSON.generate(payload)
  '
)"

patch_auth_config() {
  local request_payload="$1"
  local response_file status
  response_file="$(mktemp)"
  status="$(
    curl -sS -o "$response_file" -w "%{http_code}" -X PATCH \
      "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/config/auth" \
      -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$request_payload"
  )"
  printf '%s\n' "$status" >"$response_file.status"
  printf '%s\n' "$response_file"
}

log "patching live Auth config"
response_file="$(patch_auth_config "$payload")"
status="$(cat "$response_file.status")"
if [[ "$status" == "402" && "$payload" == *'"password_hibp_enabled":true'* ]]; then
  log "leaked-password protection may require a paid Supabase plan; applying other Auth hardening without it"
  payload="$(ruby -r json -e 'data = JSON.parse(STDIN.read); data.delete("password_hibp_enabled"); print JSON.generate(data)' <<< "$payload")"
  rm -f "$response_file" "$response_file.status"
  response_file="$(patch_auth_config "$payload")"
  status="$(cat "$response_file.status")"
fi

if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
  printf '[supabase-auth][FAIL] Auth config patch failed with HTTP %s\n' "$status" >&2
  rm -f "$response_file" "$response_file.status"
  exit 1
fi

ruby -r json -e '
    data = JSON.parse(STDIN.read)
    %w[
      site_url
      uri_allow_list
      external_anonymous_users_enabled
      external_email_enabled
      external_phone_enabled
      hook_send_sms_enabled
      hook_send_sms_uri
      mailer_autoconfirm
      password_hibp_enabled
      password_min_length
      security_update_password_require_reauthentication
      security_captcha_enabled
      security_captcha_provider
      sms_otp_exp
      sms_otp_length
      sms_max_frequency
    ].each { |key| puts "#{key}=#{data[key].inspect}" if data.key?(key) }
    puts "hook_send_sms_secrets=<redacted>" if data.key?("hook_send_sms_secrets")
  ' <"$response_file"
rm -f "$response_file" "$response_file.status"
