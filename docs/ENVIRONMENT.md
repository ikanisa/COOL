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
- `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` (non-secret Google Cloud project number
  linked to Collect under Play Integrity API settings)

Android production builds set both SMS switches to `true`, but receipt access
remains off until an authenticated Rwanda member explicitly consents. Diaspora
profiles do not use the SMS path. The app never requests `READ_SMS`. The
production Android build fails closed unless the linked Play Integrity project
number is present; do not substitute the Firebase project number unless Play
Console confirms that it is the linked project.

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

Android device verification:

- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` for server-side Play Integrity decoding
  before a user can create an Android-only private group

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

- `dev`: development with the same Android-native bridges; runtime use still
  requires an authenticated Rwanda profile and explicit consent.
- `internal_receiver`: retained for controlled compatibility testing.
- `production`: Android member build with `RECEIVE_SMS` and `CALL_PHONE` for
  Rwanda MoMo only; it has no `READ_SMS`, `SEND_SMS`, or Call Log permission.

No flavor embeds payment-provider credentials. Rwanda members approve a
pre-filled MTN MoMo request or the Airtel merchant menu in USSD and enter their
PIN only there. Diaspora members use the approved beneficiary and reference,
then open Revolut through its application link or web fallback.

## Local Supabase

The repository uses non-default ports in `supabase/config.toml`. Local database,
API, and Auth are sufficient for migrations, RLS, SQL lint, and rollback UAT.
Operator scripts resolve `SUPABASE_BIN` first, then a local CLI. Linked-database
scripts similarly resolve `PSQL_BIN` before their documented fallback.
