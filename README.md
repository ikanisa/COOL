# Cool

Cool is a Flutter mobile app for community finance, group savings, partner ecosystems, and credit visibility in Rwanda.

The app is Android-first, English-only, and designed around Mobile Money (MTN Rwanda), WhatsApp OTP, offline-friendly UX, and Supabase-backed data flows.

## Product Scope

Cool combines multiple modules in a single app:

- Group savings and community fundraising
- Mobile Money USSD payments and payment confirmation sync
- Partner experiences such as clubs, tickets, and fan programs
- Admin and partner-operations consoles

## Non-Negotiable Payment Rules

Cool does not use payment gateway APIs.

- Critical repository rule: never describe Cool payments or auth as MoMo
  webhook or MoMo API flows. No MoMo webhook exists in this app, no MoMo API
  integration exists in this app, and none should be introduced. Payment
  initiation is payer-owned USSD only. Payment verification is Android SMS
  access limited to approved M-Money sender IDs, then Supabase reconciliation.
  Auth is WhatsApp OTP, not MoMo.
- Android SMS read/access is a core payment requirement. If `READ_SMS` /
  `RECEIVE_SMS` or the MoMo SMS autoread flow are removed, automatic Mobile
  Money payment verification and transaction recording stop working.
- Uses Mobile Money USSD via `url_launcher`
- Uses on-device Android SMS verification for M-Money financial transaction confirmation
- Uploads matching M-Money confirmation SMS to Supabase for parsing and reconciliation
- Supports WhatsApp OTP for auth
- Does not use Stripe, Flutterwave, DPO, or card gateways
- Does not use server-side payment webhooks or server-side MoMo callbacks

Payment initiation happens on-device. The app opens the dialer with a generated
USSD string, then listens for confirmation SMS on Android and reconciles
against Supabase records.

The canonical architecture guide for this gateway lives in
[`docs/MOMO_SMS_PAYMENT_GATEWAY_GUIDE.md`](/Volumes/PRO-G40/COOL/docs/MOMO_SMS_PAYMENT_GATEWAY_GUIDE.md).
Use it when changing SMS permissions, parsing, allocation, manual review,
wallet statement handling, or payment ledgers.

## MoMo Routing Model

Cool acts as a payment bridge. It launches payer-owned USSD flows toward the
configured recipient and later reconciles confirmation SMS against Supabase
records.

MoMo routing is database-driven through `public.supported_countries` plus the
recipient data attached to the relevant feature flow.

Rwanda uses the following USSD templates (from `public.supported_countries`):

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

- stored user MoMo metadata
- community group collection route type
- the recipient configured on the relevant group or feature flow

Current recipient sources in this repo:

- Community groups use `public.groups.receiving_momo_code` /
  `public.groups.momo_number`
- Rayon Sports currently uses a hardcoded MTN MoMo code: `008000`

Authoritative payment design notes:

- SMS is payment evidence, not a posted ledger entry.
- Matching must start from the receiving account or receiving code.
- Personal receiver accounts may fall back to wallet statement recording.
- Shared receiver codes must fall back to exception review, not wallet.
- Wallet history is statement-only and must not be treated as stored-value balance.


## Core UX Principles

- Dual-theme UI with semantic tokens in
  [`lib/core/theme/cool_foundations.dart`](/Volumes/PRO-G40/COOL/lib/core/theme/cool_foundations.dart)
- `Manrope` is the default interface font; `DM Mono` and Rayon brand fonts are
  controlled exceptions, not the base system
- One authoritative redesign guide:
  [`DESIGN_SYSTEM.md`](/Volumes/PRO-G40/COOL/DESIGN_SYSTEM.md)
- Riverpod `StateNotifierProvider` pattern per feature
- Repository layer owns all Supabase access
- Widgets never call Supabase directly
- Scrollable screens use safe bottom spacing for the shell nav
- English localization via ARB files
- Cached/offline-friendly behavior where possible

## Critical UI Copy Guardrail

This rule is mandatory for every user-facing screen, widget, sheet, dialog,
state view, and partner/admin surface.

- The repository guard enforces a 16-word maximum for visible UI copy.
- High-frequency actions, labels, and status surfaces should still target 4 words or fewer.
- Applies to titles, headings, labels, hints, helper text, descriptions,
  button text, toasts, banners, empty states, and error messages.
- Longer copy is reserved for onboarding, trust, and explanatory surfaces where short labels are not enough.
- The repository enforces this with `dart tool/ui_copy_guard.dart` and
  `test/docs/ui_copy_guard_test.dart`.

## Critical Layout Guardrail

This rule is the default for every non-home screen.

- Prefer one primary card.
- Supporting cards are acceptable for operational state, blockers, or trust messaging.
- Merge tabs, filters, stats, and actions when the screen stays readable.
- Use sections inside one card when the content is tightly related.
- Sheets and QR pages must expose a clear back or close path.

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

### Location and Device Features

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
    groups/
    home/
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
- Redesign guide: [DESIGN_SYSTEM.md](/Volumes/PRO-G40/COOL/DESIGN_SYSTEM.md)
- Semantic tokens: [lib/core/theme/cool_foundations.dart](/Volumes/PRO-G40/COOL/lib/core/theme/cool_foundations.dart)
- Typography scale: [lib/core/theme/app_theme_text.dart](/Volumes/PRO-G40/COOL/lib/core/theme/app_theme_text.dart)
- Component theming: [lib/core/theme/app_theme_components.dart](/Volumes/PRO-G40/COOL/lib/core/theme/app_theme_components.dart)
- Theme config: [lib/core/theme/app_theme.dart](/Volumes/PRO-G40/COOL/lib/core/theme/app_theme.dart)
- Legacy compatibility palette: [lib/core/theme/app_colors.dart](/Volumes/PRO-G40/COOL/lib/core/theme/app_colors.dart)
- Redesign rollout gate: [lib/core/providers/production_redesign_provider.dart](/Volumes/PRO-G40/COOL/lib/core/providers/production_redesign_provider.dart)
- Route inventory: [docs/ROUTE_INVENTORY.md](/Volumes/PRO-G40/COOL/docs/ROUTE_INVENTORY.md)
- Screen budgets: [docs/SCREEN_BUDGETS.md](/Volumes/PRO-G40/COOL/docs/SCREEN_BUDGETS.md)

## Deep Links

- Installed app routes handled directly: `/basket`, `/invite/<CODE>`, `/groups/<ID>`, `/home`, `/momo`, `/profile`
- Group invite share links should use `https://cool.app/invite/<CODE>`
- Direct basket handoff can use `https://cool.app/basket`
- The fallback site and universal-link templates live in [deeplinks/site/README.md](/Volumes/PRO-G40/COOL/deeplinks/site/README.md)

## Main Feature Areas

### Auth

- Onboarding
- WhatsApp OTP
- Profile creation (optional, from Profile screen)
- MoMo setup (Rwanda MTN)

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

### Partners

- Partner dashboards
- Fan/ticket/shop surfaces
- Partner discovery and service detail routes

### Banking Partner Services Guardrail

Every bank partner page displays exactly 2 standard CTA cards:

1. **Open a Bank Account** — `internal:open_account`
2. **Create Group Saving** — `internal:group_savings`

These are managed dynamically in the `partner_services` Supabase table and
administered via the platform admin. No other services may be added to bank
partner pages. Non-bank partner pages (Prisma AI services, Radiant insurance,
Rayon football) have their own service schemas and are not subject to this rule.

Do not invent additional bank services, descriptions, or CTAs. Any
modification to bank partner services must be reviewed against this guardrail.

### Group MoMo Routing Rules

- **Community groups**: the creator's MoMo number or merchant code is
  automatically captured as the group's collection receiver at creation time.
- **Savings groups**: the receiving MoMo code comes from the selected banking
  partner and is read-only — no user may edit it after creation. When multiple
  banking partners exist, the creator must select which bank to work with.

### Admin

- Internal CRUD and configuration surfaces
- Partner, service, and quick-action management
- Rayon Sports partner operations

## Navigation Map

The full route registry, screen ownership, and guard notes live in
[docs/ROUTE_INVENTORY.md](/Volumes/PRO-G40/COOL/docs/ROUTE_INVENTORY.md).

Use that document instead of duplicating route lists in feature PRs.

## Design System

The app now has one active redesign source of truth:

- [DESIGN_SYSTEM.md](/Volumes/PRO-G40/COOL/DESIGN_SYSTEM.md)

That file governs:

- visual direction
- light and dark theme behavior
- typography hierarchy
- component families
- role and product adaptation
- migration sequencing for the production redesign

Theme implementation is grounded in:

- [cool_foundations.dart](/Volumes/PRO-G40/COOL/lib/core/theme/cool_foundations.dart)
- [app_theme_text.dart](/Volumes/PRO-G40/COOL/lib/core/theme/app_theme_text.dart)
- [app_theme_components.dart](/Volumes/PRO-G40/COOL/lib/core/theme/app_theme_components.dart)
The complete design system lives in
[DESIGN_SYSTEM.md](/Volumes/PRO-G40/COOL/DESIGN_SYSTEM.md). That document is
the sole authority for color tokens, typography, spacing, surface language,
components, screen composition rules, simplification standards, motion,
accessibility, trust design, module-specific UX, partner sub-brand rules,
and migration planning.

Quick reference:

- Colors: `AppColors.bg`, `surface`, `surface2`, `surface3`, `accent`, `blue`, `orange`, `purple`
- Font: Manrope (UI), DM Mono (financial values)
- Shared widgets: [lib/shared/widgets](/Volumes/PRO-G40/COOL/lib/shared/widgets)
  — `CoolButton`, `CoolCard`, `StatusBadge`, `SectionTitle`, `TabPill`,
  `CoolTextField`, `BalanceCard`, `QrShareSheet`, and others

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

`ENABLE_ANDROID_MOMO_SMS_AUTOREAD` is a core Android payment flag and should
remain enabled for real app builds. If it is turned off, COOL loses automatic
M-Money SMS verification and MoMo transaction recording. Any Play submission
must include the restricted SMS-permission declaration, in-app disclosure, and
matching Data safety answers.

Example:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENABLE_ANDROID_MOMO_SMS_AUTOREAD=true \
  --dart-define=COOL_PRIVACY_POLICY_URL=https://cool.ikanisa.com/privacy \
  --dart-define=COOL_TERMS_OF_SERVICE_URL=https://cool.ikanisa.com/terms \
  --dart-define=COOL_ACCOUNT_DELETION_URL=https://cool.ikanisa.com/account-deletion
```

For full mobile feature parity, prefer `--dart-define-from-file=.env.json`.
That file should include the platform `FIREBASE_*` values from
[.env.example](/Volumes/PRO-G40/COOL/.env.example); the staging and production
build scripts now fail fast when those platform Firebase defines are missing.

MoMo recipient codes are managed in Admin > App Config, not
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
| `maps-gateway` | Proxy Google Places (New), geocoding, and routes access with auth and usage logging |
| `rs-scan-ticket` | Verify Rayon Sports ticket QR scans with auth and partner-admin checks |
| `wallet-issuer` | Deployed placeholder only. Google Wallet issuance is deferred until production go-live. |
| `delete-account` | Account deletion backend flow |

Critical release note: Google Wallet is deferred. `wallet-issuer` stays
deployed so the contract surface exists, but pre-production releases must not
be blocked on `GOOGLE_WALLET_ISSUER_ID` or
`GOOGLE_WALLET_SERVICE_ACCOUNT_JSON`. Those secrets become mandatory only in
the production go-live phase when wallet support is actually activated.

`maps-gateway` uses `GOOGLE_MAPS_SERVER_API_KEY` when present and falls back to
`GEMINI_API_KEY` for place autocomplete, place details, text geocoding, and
reverse geocoding if that shared Google credential already has the required
Maps Platform APIs enabled.

## SMS and Permissions

Android SMS read/access is a core part of COOL. iOS does not support inbox SMS
reading.

Current app behavior:

- Android requests `READ_SMS` and `RECEIVE_SMS` so COOL can detect approved
  M-Money confirmation messages after user-initiated USSD payments
- Only approved sender IDs are scanned for inbox recovery and live listening:
  `M-Money`, `M Money`, `MobileMoney`, and `Mobile Money`
- COOL narrows ingestion further to transaction-like payment confirmations and
  does not treat every message from those senders as a ledger event
- Matching payment confirmations are uploaded to Supabase for parsing,
  reconciliation, and ledger recording
- iOS cannot read inbox SMS due to platform restrictions
- Location, camera, NFC, and notifications are declared for relevant features
- The app does not request `SEND_SMS`

This means:

- automatic M-Money SMS verification and transaction recording are Android-only
- disabling Android SMS access makes the Mobile Money payment product incomplete
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
- host-side integration smoke tests for boot, auth, deep links, MoMo, and tickets
- device-backed critical journey tests under `integration_test/`
- group model tests
- user profile tests
- auth provider tests
- groups notifier/provider tests

Files live under [test](/Volumes/PRO-G40/COOL/test).

Governance references:

- Design system: [DESIGN_SYSTEM.md](/Volumes/PRO-G40/COOL/DESIGN_SYSTEM.md)
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
- Country data uses the local Rwanda-only catalog (`CoolCountryCatalog`)

## Compatibility Notes

The app is written against a normalized `users` profile model, but the repository layer includes fallback handling for legacy schemas that still use `profiles`. This is intentional and supports projects with partially migrated Supabase databases.

## Reference Prototype

The file [COOL.html](/Volumes/PRO-G40/COOL/COOL.html) contains the original interactive UI prototype used as a visual reference for many screens and shared widgets.

## Security Notes

- Never commit real `.env` files
- Never expose Supabase service-role keys in client code
- Never expose direct Postgres passwords in project documentation
- Rotate any credentials that have been pasted into chat, screenshots, issues, or commits

## Google Play Submission History

> **IMPORTANT FOR AI AGENTS:** This section is the source of truth for what has
> been submitted and published on Google Play. Do NOT treat this repo as a
> first-time submission. Check the latest entry below before planning any
> release work.

### Current Live Version

| Field | Value |
|---|---|
| Package ID | `app.cool.mobile` |
| Play Console status | **Published** |
| Privacy policy | `https://cool.ikanisa.com/privacy` |
| Terms of service | `https://cool.ikanisa.com/terms` |
| Account deletion | `https://cool.ikanisa.com/account-deletion` (in-app + web) |
| SMS declaration | Approved (restricted `READ_SMS` / `RECEIVE_SMS` for M-Money verification) |
| Data Safety | Completed |
| Content Rating | Completed |
| Ad ID declaration | Completed |
| Reviewer access | OTP test bypass via `OTP_TEST_PHONE` / `OTP_TEST_CODE` Supabase secrets |

### Release Log

#### v1.0.0+2 — Initial Release

- **Date:** March 2026
- **Status:** ✅ Published on Google Play
- **Key features:** Auth (WhatsApp OTP), MoMo payments (USSD + SMS verification),
  Groups (savings, community funds), Partners (Rayon Sports tickets/shop/membership, Prisma, bank
  partners), Profile (delete account), Admin workspaces
- **Permissions:** `READ_SMS`, `RECEIVE_SMS`, `CAMERA`, `NFC`,
  `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `READ_CONTACTS`,
  `POST_NOTIFICATIONS`
- **Play Console items completed:** Store listing, Data Safety, Content Rating,
  SMS restricted-permission declaration, Ad ID, privacy policy, reviewer access

#### v1.1.0+3 — Update (in progress)

- **Date:** March 17, 2026
- **Status:** ✅ AAB built (`app-production-release.aab`, 74.4MB), ready to upload
- **Changes since v1.0.0+2:**
  - Fixed compilation error in admin bank baskets tab (`bank_baskets_tab.dart`)
  - Applied 60 const/final lint fixes across 22 source files
  - Multiple Supabase migration hardening passes (RLS, audit triggers, admin
    roles, gamification, MoMo dedup, rate limiting)
  - Groups refactoring (extracted contribute sheet, settings sheet, helpers)
  - SMS sync improvements (manual sync, onboarding CTA, dedup guards)
  - Visual audit and dark-mode fixes for Rayon Sport screens
  - Localization error fixes across multiple features
  - Micro-frontend ADK integration in portal
  - Test suite: 767 passing, 49 pre-existing failures (governance sync,
    widget copy, smoke test drift)
- **Play Console updates needed:** "What's new" release notes only. No new
  permissions, no Data Safety changes, no new SMS scope.

### Build and Upload Workflow

```bash
# 1. Rebuild signed AAB
SUPABASE_URL="https://..." \
SUPABASE_ANON_KEY="..." \
bash scripts/build_play_release.sh

# 2. Upload to Play Console → Production track
# 3. Add "What's new" release notes
# 4. Submit for review
```

## Recommended Next Steps

- Migrate Rayon Sports MoMo code from hardcoded `008000` to dynamic Supabase routing
- Move Android signing keys (`upload-keystore.jks`, `key.properties`) to CI vault
- Clean up root-level utility scripts (`auto_l10n.dart`, `fix_errors.dart`, `update_profile.dart`)
- Expand device-backed integration suite beyond current critical journeys
- Fix remaining 49 pre-existing test failures (governance sync, widget copy drift)
