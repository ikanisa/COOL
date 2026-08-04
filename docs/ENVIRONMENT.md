# Environment

## SDK

Use the stable Flutter/Dart SDK pinned for this project:

- Flutter: `/Users/jeanbosco/Developer/flutter/bin/flutter`
- Dart: `/Users/jeanbosco/Developer/flutter/bin/dart`
- Verified target: Flutter `3.44.4`, Dart `3.12.2`

Local generated files such as `android/local.properties` should point
`flutter.sdk` to `/Users/jeanbosco/Developer/flutter`. CI reads `.fvmrc`, which
resolves to Flutter `3.44.4` through `subosito/flutter-action`; local scripts
should prefer absolute SDK paths so they do not accidentally use another
Flutter on `PATH`.

Flutter dart defines:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `APP_PUBLIC_URL`
- `APP_ENVIRONMENT`
- `APNS_ENVIRONMENT` (`sandbox` for development/staging, `production` only for
  the App Store production Release build)
- `ENABLE_SMS_READER`
- `ENABLE_ANDROID_SMS_ACCESS`

Supabase function secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `WHATSAPP_CLOUD_API_TOKEN`
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_AUTH_TEMPLATE_NAME`
- `WHATSAPP_GRAPH_API_VERSION` (optional; defaults to `v25.0`)
- `WHATSAPP_AUTH_TEMPLATE_LANGUAGE` (optional; defaults to `en_US`)
- `WHATSAPP_CLOUD_DRY_RUN` (optional; `true` skips Meta delivery in non-production smoke tests)
- `WHATSAPP_CLOUD_OTP_AUTH_BUTTON` (optional; set to `false` for legacy templates without OTP buttons)
- `WHATSAPP_CLOUD_OTP_BUTTON_SUB_TYPE` (optional; defaults to `url`)
- `SEND_SMS_HOOK_SECRET`
- `INTERNAL_FUNCTION_SECRET`
- `SMS_INGEST_HMAC_SECRET`
- `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON` (server-only)
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (server-only fallback for Play Integrity)
- `APNS_KEY_ID` (server-only Apple push key identifier)
- `APNS_TEAM_ID` (server-only Apple Developer team identifier)
- `APNS_BUNDLE_ID` (`app.cool.mobile` in production)
- `APNS_PRIVATE_KEY_BASE64` (server-only base64 encoding of the complete Apple
  `.p8` private-key PEM file)

The WhatsApp hook also accepts the Mobi/Memories-compatible aliases
`WHATSAPP_CLOUD_ACCESS_TOKEN`, `WHATSAPP_CLOUD_PHONE_NUMBER_ID`,
`WHATSAPP_CLOUD_OTP_TEMPLATE_NAME`, `WHATSAPP_CLOUD_API_VERSION`,
`WHATSAPP_CLOUD_TEMPLATE_LANGUAGE_CODE`, `WABA_ACCESS_TOKEN`,
`WABA_PHONE_NUMBER_ID`, and `WABA_OTP_TEMPLATE_NAME`.

Build flavors:

- `dev`: normal development build without restricted SMS permissions.
- `internal_receiver`: internal Android build with SMS permissions and SMS app-access flags.
- `production`: production app without restricted SMS permissions by default.

Local Supabase notes:

- This repo uses non-default local ports in `supabase/config.toml` to avoid
  conflicts with other local Supabase projects.
- Local database/API/auth are sufficient for migration and RLS verification.
- Storage, Studio, Realtime, Inbucket, and Analytics can be enabled when those
  local services are needed; they are not required for the current database lint
  gate.
- Supabase operator scripts use `SUPABASE_BIN` when set, a `supabase` command
  on `PATH` when available, or `npx -y supabase` as a local fallback.
- Supabase linked database scripts use `PSQL_BIN` when set, `psql` on `PATH`
  when available, or `/Library/PostgreSQL/15/bin/psql` as a local fallback.
