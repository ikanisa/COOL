# Environment

## SDK

Use the project Flutter/Dart SDK:

- Flutter: `/Users/jeanbosco/Developer/flutter/bin/flutter`
- Dart: `/Users/jeanbosco/Developer/flutter/bin/dart`
- Pinned target: Flutter `3.44.4`, Dart `3.12.2`

Local generated files such as `android/local.properties` point `flutter.sdk` to
that SDK. CI resolves the same version from `.fvmrc`.

## Flutter runtime values

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `APP_PUBLIC_URL`
- `APP_ENVIRONMENT`
- `APNS_ENVIRONMENT`
- `ENABLE_ADMIN_PANEL`
- `ENABLE_ADMIN_DEV_TOOLS`
- `ENABLE_SMS_READER`
- `ENABLE_ANDROID_SMS_ACCESS`

Public production builds set both SMS switches to `false`. Only the controlled
`internal_receiver` Android flavor may set them to `true`; it collects candidate
bank-notification evidence and can never confirm settlement or post a ledger.

## Supabase function secrets

Core:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `INTERNAL_FUNCTION_SECRET`
- `WHATSAPP_CLOUD_API_TOKEN`
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_AUTH_TEMPLATE_NAME`
- `SEND_SMS_HOOK_SECRET`

Bank evidence:

- `BANK_EMAIL_INGEST_HMAC_SECRET` for the controlled email-ingestion adapter
- `BANK_SMS_INGEST_HMAC_SECRET` only when an external SMS relay is enabled

Push delivery:

- `FCM_SERVICE_ACCOUNT_JSON` containing the dedicated Firebase service-account
  JSON for Android FCM HTTP v1
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID` (`app.cool.mobile` in production)
- `APNS_PRIVATE_KEY_BASE64`

Optional WhatsApp aliases and tuning values remain supported by
`auth-send-whatsapp-otp`; see the function source. Do not place service-role,
HMAC, WhatsApp, FCM, or APNs secrets in Flutter dart-defines or committed files.

## Build flavors

- `dev`: development without restricted SMS permissions.
- `internal_receiver`: controlled operator build with `RECEIVE_SMS`; new bank
  messages are encrypted locally and uploaded only from an authenticated
  operator session.
- `production`: public member/admin build with no `RECEIVE_SMS`, `READ_SMS`,
  `SEND_SMS`, or `CALL_PHONE` permission.

No flavor embeds payment-provider credentials. Collect does not call Stripe,
Revolut, a bank payment-initiation API, or a mobile-money API. The member copies
the approved beneficiary details and reference, then opens Revolut through its
documented application link or web fallback.

## Local Supabase

The repository uses non-default ports in `supabase/config.toml`. Local database,
API, and Auth are sufficient for migrations, RLS, SQL lint, and rollback UAT.
Operator scripts resolve `SUPABASE_BIN` first, then a local CLI. Linked-database
scripts similarly resolve `PSQL_BIN` before their documented fallback.
