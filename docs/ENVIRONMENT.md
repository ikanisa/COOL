# Environment

## SDK

Use the isolated Flutter/Dart SDK installed for this project:

- Flutter: `/Volumes/PRO-G40/flutter_3_44/bin/flutter`
- Dart: `/Volumes/PRO-G40/flutter_3_44/bin/dart`
- Verified target: Flutter `3.44.0`, Dart `3.12.0`

Local generated files such as `android/local.properties` should point
`flutter.sdk` to `/Volumes/PRO-G40/flutter_3_44`. CI reads `.fvmrc`, which now
resolves to Flutter `3.44.0` through `subosito/flutter-action`; local scripts
should prefer absolute SDK paths so they do not accidentally use another
Flutter on `PATH`.

Flutter dart defines:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `APP_PUBLIC_URL`
- `APP_ENVIRONMENT`
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
- `SEND_SMS_HOOK_SECRET`
- `INTERNAL_FUNCTION_SECRET`
- `SMS_INGEST_HMAC_SECRET`

Build flavors:

- `dev`: normal development build without restricted SMS permissions.
- `internal_receiver`: internal Android build with SMS permissions and SMS app-access flags.
- `production`: production app without restricted SMS permissions by default.

Local Supabase notes:

- This repo uses non-default local ports in `supabase/config.toml` to avoid conflicts with other local Supabase projects.
- Local database/API/auth are sufficient for migration and RLS verification.
- Storage, Studio, Realtime, Inbucket, and Analytics can be enabled when those local services are needed; they are not required for the current database lint gate.
- Supabase operator scripts use `SUPABASE_BIN` when set, a `supabase` command on `PATH` when available, or `npx -y supabase` as a local fallback.
- Supabase linked database scripts use `PSQL_BIN` when set, `psql` on `PATH` when available, or `/Library/PostgreSQL/15/bin/psql` as a local fallback.
