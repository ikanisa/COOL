# Cool

Cool is a Flutter mobile app for community finance, group savings, mobility, partner ecosystems, and credit visibility across Sub-Saharan Africa.

Primary markets include Rwanda, DRC, Kenya, and neighboring countries. The app is Android-first, English/French, and designed around Mobile Money, WhatsApp OTP, offline-friendly UX, and Supabase-backed data flows.

## Product Scope

Cool combines multiple modules in a single app:

- Group savings and community fundraising
- Mobile Money USSD payments and payment confirmation sync
- Mobility matching, nearby drivers, and scheduled trips
- Partner experiences such as clubs, tickets, and fan programs
- Credit score and profile visibility
- Admin and partner-operations consoles

## Non-Negotiable Payment Rules

Cool does not use payment gateway APIs.

- Critical repository rule: never describe Cool payments or auth as MoMo
  webhook or MoMo API flows. No MoMo webhook exists in this app, no MoMo API
  integration exists in this app, and none should be introduced. Payment
  initiation is payer-owned USSD only. Payment verification is Android SMS
  access limited to approved M-Money sender IDs, then Supabase reconciliation.
  Auth is WhatsApp OTP, not MoMo.
- Uses Mobile Money USSD via `url_launcher`
- Uses on-device Android SMS verification for M-Money financial transaction confirmation
- Uploads matching M-Money confirmation SMS to Supabase for parsing and reconciliation
- Supports WhatsApp OTP for auth
- Does not use Stripe, Flutterwave, DPO, or card gateways
- Does not use server-side payment webhooks or server-side MoMo callbacks

Payment initiation happens on-device. The app opens the dialer with a generated
USSD string, then listens for confirmation SMS on Android and reconciles
against Supabase records.

Mobility subscription payments do not use a build-time recipient number.
Admins configure the receiving MoMo code in the admin panel via
`app_config.mobility_subscription_momo_code`, with optional country-specific
overrides. Group, community, and partner payment flows remain
recipient-driven and do not route through a single Cool collector account.

## MoMo Routing Model

Cool acts as a payment bridge. It launches payer-owned USSD flows toward the
configured recipient and later reconciles confirmation SMS against Supabase
records.

MoMo routing is database-driven through `public.supported_countries` plus the
recipient data attached to the relevant feature flow.

Each country can define:

- `momo_number_ussd_template`
- `momo_code_ussd_template`

This supports two recipient modes:

1. Phone-number route
2. Merchant-code route

Rwanda examples:

```text
*182*1*1*[momo number]*[amount]#
*182*8*1*[momo code]*[amount]#
```

The app selects the correct route dynamically based on:

- selected country
- stored user MoMo metadata
- community group collection route type
- the recipient configured on the relevant group or feature flow

Current recipient sources in this repo:

- Community groups use `public.groups.receiving_momo_code` /
  `public.groups.momo_number`
- Mobility subscriptions use `public.app_config.key = mobility_subscription_momo_code`
- Rayon Sports currently uses a hardcoded MTN MoMo code: `008000`
- Saving groups store a `bank_partner` label, but partner-specific MoMo routing
  is not yet modeled in `public.partners`

## Core UX Principles

- Dark-first UI with a shared `AppColors` design system
- DM Sans for UI text, DM Mono for numbers and financial values
- Riverpod `StateNotifierProvider` pattern per feature
- Repository layer owns all Supabase access
- Widgets never call Supabase directly
- Scrollable screens use safe bottom spacing for the shell nav
- English and French localization via ARB files
- Cached/offline-friendly behavior where possible

## Tech Stack

### App

- Flutter
- Riverpod
- GoRouter
- Google Fonts
- Hive

### Backend

- Supabase Auth
- Supabase Postgres
- Supabase Realtime
- Supabase Edge Functions
- PostGIS

### Payments and Messaging

- WhatsApp Cloud API for OTP
- Mobile Money USSD via `url_launcher`
- Android SMS verification via `another_telephony`

### Maps and Device Features

- `google_maps_flutter`
- `geolocator`
- `permission_handler`
- `flutter_nfc_kit`
- `mobile_scanner`
- Firebase Messaging

## Repository Layout

```text
lib/
  core/
    config/
    l10n/
    providers/
    repositories/
    router/
    services/
    theme/
  features/
    auth/
    basket/
    credit/
    groups/
    home/
    mobility/
    momo/
    partners/
    profile/
  l10n/
  shared/
    widgets/

supabase/
  config.toml
  functions/
  migrations/

assets/
docs/
test/
COOL.html
```

## Key Flutter Entry Points

- App bootstrap: [lib/main.dart](/Volumes/PRO-G40/COOL/lib/main.dart)
- Root app widget: [lib/app.dart](/Volumes/PRO-G40/COOL/lib/app.dart)
- Lifecycle binding: [lib/core/providers/app_lifecycle_providers.dart](/Volumes/PRO-G40/COOL/lib/core/providers/app_lifecycle_providers.dart)
- Router: [lib/core/router/app_router.dart](/Volumes/PRO-G40/COOL/lib/core/router/app_router.dart)
- Theme colors: [lib/core/theme/app_colors.dart](/Volumes/PRO-G40/COOL/lib/core/theme/app_colors.dart)
- Theme config: [lib/core/theme/app_theme.dart](/Volumes/PRO-G40/COOL/lib/core/theme/app_theme.dart)
- Route inventory: [docs/ROUTE_INVENTORY.md](/Volumes/PRO-G40/COOL/docs/ROUTE_INVENTORY.md)
- Screen budgets: [docs/SCREEN_BUDGETS.md](/Volumes/PRO-G40/COOL/docs/SCREEN_BUDGETS.md)

## Deep Links

- Installed app routes handled directly: `/basket`, `/invite/<CODE>`, `/groups/<ID>`, `/home`, `/momo`, `/profile`, `/mobility`
- Group invite share links should use `https://cool.app/invite/<CODE>`
- Direct basket handoff can use `https://cool.app/basket`
- The fallback site and universal-link templates live in [deeplinks/site/README.md](/Volumes/PRO-G40/COOL/deeplinks/site/README.md)

## Main Feature Areas

### Auth

- Onboarding
- WhatsApp OTP
- Profile creation (optional, from Profile screen)
- Country-aware MoMo setup

> **⚠️ CRITICAL ROUTING INVARIANT** — Do not change without updating tests.
>
> After OTP verification, users **always** land on `/home`.
> Profile completion is **optional** and only accessible from the Profile screen.
> The router **must never** force users to `/register`.
> `/register` is **not** in `_authRoutes` — authenticated users can visit it voluntarily.
>
> Regression tests: `test/features/auth_routing_test.dart` (25 tests)

Important files:

- [auth_repository.dart](/Volumes/PRO-G40/COOL/lib/features/auth/repositories/auth_repository.dart)
- [auth_provider.dart](/Volumes/PRO-G40/COOL/lib/features/auth/providers/auth_provider.dart)
- [auth_routing_test.dart](/Volumes/PRO-G40/COOL/test/features/auth_routing_test.dart)

### Groups

- Saving groups
- Community funds
- Private/public visibility
- Group contribution flow
- QR/invite distribution

Important files:

- [group_repository.dart](/Volumes/PRO-G40/COOL/lib/features/groups/repositories/group_repository.dart)
- [create_group_screen.dart](/Volumes/PRO-G40/COOL/lib/features/groups/screens/create_group_screen.dart)

### Mobility

- Nearby drivers
- Driver online/offline state
- Scheduled trips
- Driver subscriptions

Important files:

- [mobility_repository.dart](/Volumes/PRO-G40/COOL/lib/features/mobility/repositories/mobility_repository.dart)
- [subscription_repository.dart](/Volumes/PRO-G40/COOL/lib/features/mobility/repositories/subscription_repository.dart)

### MoMo

- USSD generation
- QR sharing
- M-Money verification status/history
- Payment reconciliation support

Important files:

- [momo_service.dart](/Volumes/PRO-G40/COOL/lib/core/services/momo_service.dart)
- [momo_screen.dart](/Volumes/PRO-G40/COOL/lib/features/momo/screens/momo_screen.dart)
- [momo_statements_screen.dart](/Volumes/PRO-G40/COOL/lib/features/momo/screens/momo_statements_screen.dart)
- [momo_statement_repository.dart](/Volumes/PRO-G40/COOL/lib/features/momo/repositories/momo_statement_repository.dart)

### Partners and Credit

- Partner dashboards
- Fan/ticket/shop surfaces
- Credit score visualization
- Partner discovery and service detail routes

### Admin

- Internal CRUD and configuration surfaces
- Country, partner, service, and quick-action management
- Rayon Sports partner operations

## Navigation Map

The full route registry, screen ownership, and guard notes live in
[docs/ROUTE_INVENTORY.md](/Volumes/PRO-G40/COOL/docs/ROUTE_INVENTORY.md).

Use that document instead of duplicating route lists in feature PRs.

## Design System

The app uses a central theme and shared widgets.

Colors:

- `AppColors.bg`
- `AppColors.surface`
- `AppColors.surface2`
- `AppColors.surface3`
- `AppColors.accent`
- `AppColors.blue`
- `AppColors.orange`
- `AppColors.purple`

Shared widgets live under [lib/shared/widgets](/Volumes/PRO-G40/COOL/lib/shared/widgets) and include:

- `CoolButton`
- `CoolCard`
- `StatusBadge`
- `SectionTitle`
- `TabPill`
- `VehicleChip`
- `GroupCard`
- `DriverCard`
- `TripCard`
- `MemberRow`
- `BalanceCard`
- `QrShareSheet`
- `WaButton`
- `CoolTextField`

## Environment Setup

### Client-Side Flutter Variables

Copy [.env.example](/Volumes/PRO-G40/COOL/.env.example) for local reference.

Expected client-safe values:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `ENABLE_ANDROID_MOMO_SMS_AUTOREAD`
- `COOL_PRIVACY_POLICY_URL`
- `COOL_TERMS_OF_SERVICE_URL`
- `COOL_ACCOUNT_DELETION_URL`

If Android M-Money SMS reconciliation is part of the production release,
`ENABLE_ANDROID_MOMO_SMS_AUTOREAD` should stay enabled and the Play submission
must include the restricted SMS-permission declaration, in-app disclosure, and
matching Data safety answers.

Example:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENABLE_ANDROID_MOMO_SMS_AUTOREAD=true \
  --dart-define=COOL_PRIVACY_POLICY_URL=https://gen-lang-client-0172279957.web.app/privacy \
  --dart-define=COOL_TERMS_OF_SERVICE_URL=https://gen-lang-client-0172279957.web.app/terms \
  --dart-define=COOL_ACCOUNT_DELETION_URL=https://gen-lang-client-0172279957.web.app/account-deletion
```

Mobility subscription recipient codes are managed in Admin > App Config, not
through `--dart-define`.

### Supabase Edge Function Secrets

Copy [supabase/functions/.env.example](/Volumes/PRO-G40/COOL/supabase/functions/.env.example) to `supabase/functions/.env` for local function serving.

Important secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_ACCESS_TOKEN`
- `AI_SMS_PARSE_PROVIDER`
- `OPENAI_API_KEY` or `GEMINI_API_KEY`
- `OTP_CODE_HASH_SECRET`
- `AUTH_PHONE_PASSWORD_SECRET`
- `OTP_TEST_PHONE` optional, for Play review or QA bypass
- `OTP_TEST_CODE` optional, for Play review or QA bypass

## Local Development

### Prerequisites

- Flutter SDK pinned in [.fvmrc](/Volumes/PRO-G40/COOL/.fvmrc)
- Android Studio and Android SDK
- Xcode and CocoaPods for iOS builds
- Deno CLI pinned in [.dvmrc](/Volumes/PRO-G40/COOL/.dvmrc)
- Supabase CLI
- PostgreSQL client tools if you want direct SQL access

### Install Dependencies

```bash
flutter pub get
```

### Run the App

```bash
flutter run
```

With explicit configuration:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENABLE_ANDROID_MOMO_SMS_AUTOREAD=true
```

### Run Supabase Locally

```bash
supabase start
supabase db reset
supabase functions serve --env-file supabase/functions/.env
```

Local Supabase ports are configured in [supabase/config.toml](/Volumes/PRO-G40/COOL/supabase/config.toml).

## Database and Migrations

Migrations live in [supabase/migrations](/Volumes/PRO-G40/COOL/supabase/migrations).

Important migrations:

- `20260310120000_initial_schema.sql`
- `20260310130000_pending_transactions.sql`
- `20260310133000_mobile_integration_alignment.sql`
- `20260310153000_ai_momo_sms_pipeline.sql`
- `20260310170000_supported_countries_catalog.sql`
- `20260310183000_dynamic_momo_ussd_routes.sql`

`public.supported_countries` is the source of truth for:

- dial codes
- currency codes
- MoMo provider IDs
- phone-number USSD templates
- merchant-code USSD templates

## Edge Functions

Implemented under [supabase/functions](/Volumes/PRO-G40/COOL/supabase/functions).

| Function | Purpose |
|---|---|
| `send-otp` | Send WhatsApp OTP |
| `verify-otp` | Verify OTP and return session |
| `parse-momo-sms` | Parse uploaded M-Money confirmation SMS into normalized transaction data |
| `expire-trips` | Expire mobility trips automatically |
| `maps-gateway` | Proxy map and geocoding access with auth and usage logging |
| `rs-scan-ticket` | Verify Rayon Sports ticket QR scans with auth and partner-admin checks |
| `wallet-issuer` | Issue Google Wallet / pass artifacts for supported journeys |
| `delete-account` | Account deletion backend flow |

## SMS and Permissions

Android supports SMS-based M-Money financial transaction verification. iOS does not.

Current app behavior:

- Android can request SMS permission for M-Money transaction verification
- Only approved sender IDs are scanned for inbox recovery: `M-Money` and `MobileMoney`
- Matching payment confirmations can be uploaded to Supabase for reconciliation
- iOS cannot read inbox SMS due to platform restrictions
- Location, camera, NFC, and notifications are declared for relevant features
- The app does not request `SEND_SMS`

This means:

- automatic M-Money SMS verification is Android-only
- USSD payment initiation still works cross-platform where dialing is supported

## Testing and Quality Checks

Run tests:

```bash
flutter test
```

Run targeted static analysis:

```bash
dart analyze
flutter analyze
```

Run the full release-readiness gate:

```bash
bash scripts/release_readiness.sh
```

GitHub Actions runs the same gate on every push and pull request via
[.github/workflows/ci.yml](/Volumes/PRO-G40/COOL/.github/workflows/ci.yml), so
keep `scripts/release_readiness.sh` as the single source of truth for CI checks.
By default that gate now includes Android staging and production flavor builds.
Set `SKIP_ANDROID_FLAVOR_BUILDS=1` only when you intentionally need a faster
local-only run. On macOS it also verifies that the iOS `staging` and
`production` schemes resolve to the expected bundle IDs and display names.

Current tests include:

- auth routing regression tests (25 tests)
- host-side integration smoke tests for boot, auth, deep links, MoMo, tickets, and mobility
- device-backed critical journey tests under `integration_test/`
- group model tests
- user profile tests
- auth provider tests
- groups notifier/provider tests

Files live under [test](/Volumes/PRO-G40/COOL/test).

Governance references:

- Release gates: [docs/qa_release_readiness.md](/Volumes/PRO-G40/COOL/docs/qa_release_readiness.md)
- Release process: [docs/RELEASE_PROCESS.md](/Volumes/PRO-G40/COOL/docs/RELEASE_PROCESS.md)
- Route inventory: [docs/ROUTE_INVENTORY.md](/Volumes/PRO-G40/COOL/docs/ROUTE_INVENTORY.md)
- Screen budgets: [docs/SCREEN_BUDGETS.md](/Volumes/PRO-G40/COOL/docs/SCREEN_BUDGETS.md)

## Build Commands

Android debug APK:

```bash
flutter build apk --debug
```

Android staging / production scripts:

```bash
bash scripts/build_staging.sh
bash scripts/build_production.sh
bash scripts/verify_android_flavors.sh
bash scripts/verify_ios_flavors.sh
```

iOS simulator build:

```bash
flutter build ios --simulator --no-codesign
```

iOS staging / production scripts:

```bash
bash scripts/build_ios_staging.sh
bash scripts/build_ios_production.sh
```

Run the device-backed critical journey suite on a mobile device or emulator:

```bash
bash scripts/run_device_integration.sh
DEVICE=emulator-5554 FLAVOR=production bash scripts/run_device_integration.sh
```

Android flavor-specific Firebase configs live at
[android/app/src/staging/google-services.json](/Volumes/PRO-G40/COOL/android/app/src/staging/google-services.json)
and
[android/app/src/production/google-services.json](/Volumes/PRO-G40/COOL/android/app/src/production/google-services.json).

## Offline and Caching Notes

- Hive is used for local storage and offline support
- Pending MoMo transactions can be cached locally before reconciliation
- Country data can fall back to the local catalog if Supabase is unavailable

## Compatibility Notes

The app is written against a normalized `users` profile model, but the repository layer includes fallback handling for legacy schemas that still use `profiles`. This is intentional and supports projects with partially migrated Supabase databases.

## Reference Prototype

The file [COOL.html](/Volumes/PRO-G40/COOL/COOL.html) contains the original interactive UI prototype used as a visual reference for many screens and shared widgets.

## Security Notes

- Never commit real `.env` files
- Never expose Supabase service-role keys in client code
- Never expose direct Postgres passwords in project documentation
- Rotate any credentials that have been pasted into chat, screenshots, issues, or commits

## Recommended Next Steps

- Remove client-side fallback secrets from `main.dart` and require `--dart-define` in production
- Complete ARB coverage for all user-facing strings
- Expand app-wide multi-currency formatting beyond current core flows
- Expand the device-backed integration suite beyond the current critical journeys
