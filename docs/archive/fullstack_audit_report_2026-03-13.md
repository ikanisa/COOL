# Fullstack Audit Report

Updated: 2026-03-13

## Scope

This audit covered the Flutter mobile app, Supabase database and Edge Functions,
release/governance docs, mobile platform configuration, and test/release
readiness.

Relevant skills used for this audit:

- `skills` to select the minimal applicable skill set for the request
- `security-best-practices` for security and hardening review
- `security-threat-model` for risk framing across trust boundaries
- `security-ownership-map` for contributor concentration and bus-factor analysis

Not all installed skills were used because most are unrelated to repository
auditing and would add noise rather than signal.

## Method

Commands run:

- `flutter analyze`
- `flutter test`
- `deno check supabase/functions/**/*.ts`
- `deno test supabase/functions/parse-momo-sms/ai_parser_test.ts supabase/functions/parse-momo-sms/rayon_confirmation_test.ts`
- ownership topology analysis over the last 12 months

Key outcome summary:

- `flutter analyze`: passed
- `flutter test`: failed broadly, with governance, widget, copy, and route drift
- `deno check`: passed
- targeted Deno tests for `parse-momo-sms`: passed

## Executive Summary

The app is not release-candidate quality in its current state.

The largest problems are not isolated code defects. They are system-level
contract failures between product policy, mobile behavior, backend security,
release governance, and test coverage.

The current implementation is strongest in these areas:

- repository-oriented app structure remains mostly intact
- Supabase Edge Function TypeScript checks are clean
- MoMo parsing tests are in better shape than the mobile surface around them

The current implementation is weakest in these areas:

- Android SMS processing scope does not match compliance claims
- release governance is materially red because tests and docs have drifted
- operational telemetry used for admin release decisions is client-writable
- deep link production setup is incomplete on both iOS and Android
- auth/OTP controls are functional but not production-grade for abuse and scale

## Severity-Ranked Findings

### 1. Critical: SMS permission scope does not match the declared compliance boundary

The repository repeatedly claims that Android SMS access is limited to approved
M-Money sender IDs:

- [README.md](../README.md#L18)
- [google_play_sms_declaration.md](./google_play_sms_declaration.md#L35)
- [qa_release_readiness.md](./qa_release_readiness.md#L71)

The implementation does something broader:

- [momo_sms_ingestion_repository.dart](../lib/features/momo/repositories/momo_sms_ingestion_repository.dart#L115) accepts a message if the sender is approved **or** the body merely looks like a transaction
- [momo_sms_ingestion_repository.dart](../lib/features/momo/repositories/momo_sms_ingestion_repository.dart#L163) and [momo_sms_ingestion_repository.dart](../lib/features/momo/repositories/momo_sms_ingestion_repository.dart#L185) use broad body heuristics such as `payment`, `received`, `withdraw`, `bundle`, `merchant`, `reference`
- [momo_sms_autoread_service.dart](../lib/features/momo/services/momo_sms_autoread_service.dart#L48) sets inbox recovery lookback to 3650 days
- [momo_sms_autoread_service.dart](../lib/features/momo/services/momo_sms_autoread_service.dart#L50) allows recovery of up to 1000 messages
- [momo_sms_autoread_service.dart](../lib/features/momo/services/momo_sms_autoread_service.dart#L181) runs inbox recovery and [momo_sms_autoread_service.dart](../lib/features/momo/services/momo_sms_autoread_service.dart#L183) uses `_approvedSenderFilter()`, but the later capture step still allows non-approved senders when body heuristics match

Why this matters:

- This is a Google Play restricted-permission risk.
- This is also a privacy boundary failure, because “approved sender only” is a materially narrower claim than “approved sender or body matches heuristics.”
- The implementation currently creates a compliance story the docs cannot truthfully defend.

What it must be like:

- Processing must be strictly bounded to the approved sender set unless policy/legal review explicitly expands the scope and all disclosure, console declarations, privacy text, and reviewer evidence are updated to match.
- Inbox recovery should be narrowly scoped by time and volume, not effectively “scan large historical inbox slices.”

### 2. Critical: Release governance is red and the repo is not in a releasable state

Release policy says no build is release-candidate quality unless `flutter test`
passes with zero failures:

- [qa_release_readiness.md](./qa_release_readiness.md#L8)

That gate is currently red. `flutter test` failed broadly during this audit.
Representative examples of contract drift:

- [intl_locale.dart](../lib/core/utils/intl_locale.dart#L4) hardcodes English-only behavior, while [intl_locale_test.dart](../test/core/utils/intl_locale_test.dart#L6) still expects `fr` to be preserved
- [ROUTE_INVENTORY.md](./ROUTE_INVENTORY.md#L5) says there are 54 routes and 51 screen files, while the generated governance test reports drift and [governance_docs_sync_test.dart](../test/docs/governance_docs_sync_test.dart#L10) enforces exact sync
- [ROUTE_INVENTORY.md](./ROUTE_INVENTORY.md#L93) still says `/admin/rayon/fan-clubs` redirects, while [app_router.dart](../lib/core/router/app_router.dart#L200) defines current admin Rayon routing constants that have changed since the doc snapshot
- [cool_button_test.dart](../test/shared/widgets/cool_button_test.dart#L28) expects `CircularProgressIndicator`, but [cool_button.dart](../lib/shared/widgets/cool_button.dart#L109) renders `CupertinoActivityIndicator`
- [operational_dashboard_screen_test.dart](../test/features/admin/operational_dashboard_screen_test.dart#L8) still encodes previous UI copy expectations for the operations surface
- [profile_data_test.dart](../test/features/profile/profile_data_test.dart#L10) encodes label expectations that no longer match [profile_data.dart](../lib/features/profile/widgets/profile_data.dart#L72)

Why this matters:

- This is not one flaky test.
- Release governance docs, actual routes, UI copy contracts, and widget behavior are drifting independently.
- The repo currently cannot defend “what the app is” because code, docs, and tests disagree.

What it must be like:

- Governance docs must be generated from code in CI and committed in the same change.
- Copy and behavior tests must be updated intentionally, not left to decay after refactors.
- Release blocking checks must be mandatory before any release candidate claim.

### 3. High: Operational health telemetry used by admins is writable from the client by any authenticated user

The admin operations dashboard is documented as the operational truth for release
triage:

- [OPERATIONAL_OBSERVABILITY.md](./OPERATIONAL_OBSERVABILITY.md#L47)

But the underlying event table can be written by any authenticated user:

- [20260313101500_operational_observability.sql](../supabase/migrations/20260313101500_operational_observability.sql#L38) creates an insert policy for all authenticated users
- [operational_health_service.dart](../lib/core/services/operational_health_service.dart#L16) writes directly from the mobile client to `operational_health_events`

Why this matters:

- An ordinary user can generate arbitrary operational events that pollute the
  admin dashboard.
- This breaks the integrity of a release gate that the docs say should be used
  before shipping.
- It is an observability design flaw: dashboards should consume trustworthy
  telemetry, not client-authenticated free-form inserts.

What it must be like:

- Client code should not have direct insert rights to operational release feeds.
- Mobile telemetry should go through a controlled server-side ingest path with
  schema validation, rate limits, enrichment, and trust boundaries that separate
  user events from release-critical signals.

### 4. High: Deep-link production configuration is incomplete on iOS and Android

iOS Universal Links are not production-ready:

- [Runner.entitlements](../ios/Runner/Runner.entitlements#L5) declares associated domains
- [apple-app-site-association](../deeplinks/site/.well-known/apple-app-site-association#L1) has empty `details`

Android App Links are also incomplete:

- [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml#L62) enables auto-verified app links
- [deeplinks assetlinks.json](../deeplinks/site/.well-known/assetlinks.json#L15) still includes `REPLACE_WITH_PLAY_APP_SIGNING_SHA256`
- [hosting assetlinks.json](../hosting/.well-known/assetlinks.json#L15) still includes `REPLACE_WITH_PLAY_APP_SIGNING_SHA256`

Why this matters:

- Production deep-link behavior will be inconsistent or broken.
- Reviewers and users can hit web fallback instead of the app even when platform
  setup claims support.

What it must be like:

- AASA must include real app details.
- Both Android assetlinks files must contain the Play signing certificate
  fingerprint, not placeholders.
- Link verification should be part of release validation, not post-release
  cleanup.

### 5. High: Auth/OTP works functionally but is weak against abuse and does not scale cleanly

`send-otp` currently enforces only per-phone cooldown and per-phone rate
limits:

- [send-otp/index.ts](../supabase/functions/send-otp/index.ts#L20)
- [send-otp/index.ts](../supabase/functions/send-otp/index.ts#L71)
- [send-otp/index.ts](../supabase/functions/send-otp/index.ts#L110)

`verify-otp` currently scans auth users page by page when it needs to repair or
create internal auth state:

- [verify-otp/index.ts](../supabase/functions/verify-otp/index.ts#L86)

Verification attempts are also limited only on the current OTP row:

- [verify-otp/index.ts](../supabase/functions/verify-otp/index.ts#L267)

Why this matters:

- Per-phone limits alone are insufficient against distributed abuse.
- `listUsers()` pagination is an O(n) lookup pattern and will become brittle as
  auth user volume grows.
- Auth flows should not depend on scanning the full auth corpus to recover user
  identity.

What it must be like:

- Add IP/device/network-level throttles and abuse telemetry.
- Replace paginated auth-user discovery with a deterministic indexed mapping.
- Treat review OTP bypasses as tightly controlled release-only behavior with
  monitoring and rotation.

### 6. High: Documentation and compliance evidence are materially out of sync with the codebase

Some repo docs are now false as written:

- [google_play_sms_declaration.md](./google_play_sms_declaration.md#L44) cites files that do not exist
- [google_play_sms_declaration.md](./google_play_sms_declaration.md#L48) claims non-approved senders are ignored, which is no longer true
- [PERMISSIONS.md](./PERMISSIONS.md#L6) documents the permission matrix but omits `READ_SMS` and `RECEIVE_SMS`
- [ROUTE_INVENTORY.md](./ROUTE_INVENTORY.md#L5) is stale relative to code and governance expectations

Why this matters:

- These docs are not harmless notes. They are release evidence, reviewer
  evidence, and governance inputs.
- When compliance docs reference missing files, the repo cannot substantiate its
  own declarations.

What it must be like:

- Compliance and store-review docs must be traceable to existing files.
- Governance docs must be code-generated or CI-validated on every route/screen
  change.

### 7. Medium: Rayon repository refactor has degraded testability and maintainability

The Rayon repository now spreads behavior across `part` extension files that
depend on private repository state:

- [rayon_sports_repository.dart](../lib/features/partners/repositories/rayon_sports_repository.dart#L13)
- [rayon_sports_repository.dart](../lib/features/partners/repositories/rayon_sports_repository.dart#L31)
- [rayon_sports_repository.dart](../lib/features/partners/repositories/rayon_sports_repository.dart#L74)
- [rayon_sports_repository_membership.dart](../lib/features/partners/repositories/rayon_sports_repository_membership.dart#L42)
- [rayon_sports_repository_membership.dart](../lib/features/partners/repositories/rayon_sports_repository_membership.dart#L56)

Why this matters:

- Private-state coupling across `part` files makes mocking and substitution
  brittle.
- This lines up with the broad Rayon-related test failures seen during the audit.
- The repository is becoming a large stateful god-object instead of a cleanly
  testable service boundary.

What it must be like:

- Split partner, membership, tickets, shop, and admin concerns into injectible
  service classes or composable repositories.
- Stop relying on cross-file private member access as the core composition
  mechanism.

### 8. Medium: UI contract drift is visible in widgets, copy, and public identity presentation

Examples:

- [cool_button.dart](../lib/shared/widgets/cool_button.dart#L109) changed the loading indicator type without keeping test contracts in sync
- [profile_data.dart](../lib/features/profile/widgets/profile_data.dart#L107) now resolves labels through localization keys that do not match older test expectations
- [credit_score_detail_widgets.dart](../lib/features/credit/widgets/credit_score_detail_widgets.dart#L575) and [credit_readiness_checklist_widgets.dart](../lib/features/credit/widgets/credit_readiness_checklist_widgets.dart#L18) normalize on `Pending review`
- [public_user_identity.dart](../lib/core/identity/public_user_identity.dart#L15) resolves human names into six-digit public IDs when source names are absent or intentionally masked

Why this matters:

- The UI appears to be evolving without deliberate contract management.
- That makes tests noisy, but it also creates real product confusion around copy,
  identity display, and status labeling.

What it must be like:

- Copy changes should be intentional and centrally managed.
- Identity masking rules should be documented as a product decision, not left to
  emerge from repository-level fallbacks.

### 9. Medium: iOS map configuration is still environment-fragile

iOS expects a Google Maps API key:

- [Info.plist](../ios/Runner/Info.plist#L29)

But both xcconfig files leave it blank by default:

- [Debug.xcconfig](../ios/Flutter/Debug.xcconfig#L1)
- [Release.xcconfig](../ios/Flutter/Release.xcconfig#L1)

Why this matters:

- Local or CI builds can silently miss required config unless `MapsKeys.xcconfig`
  is provided correctly.
- This is survivable in development, but it is still a release-hardening gap.

What it must be like:

- CI/release validation should fail fast when required platform keys are missing.
- The repo should document exactly which non-checked-in config files are
  required for release builds.

### 10. Low to Medium: Database helper hardening is inconsistent

Older admin helper:

- [20260311110000_admin_write_policies.sql](../supabase/migrations/20260311110000_admin_write_policies.sql#L24)

Newer hardened helper:

- [20260311113000_admin_and_groups_contract_alignment.sql](../supabase/migrations/20260311113000_admin_and_groups_contract_alignment.sql#L34)

Why this matters:

- `security definer` functions should consistently pin `search_path`.
- The repo already shows the hardened pattern in a later migration, so the older
  helper stands out as security debt.

What it must be like:

- Standardize helper functions on the hardened pattern and remove older
  inconsistent variants.

### 11. Medium: Ownership concentration is high in auth-sensitive areas

Ownership analysis over the last 12 months found:

- only 2 contributors across 15 observed commits
- a hidden owner controlling 57% of auth code
- bus-factor-1 hotspots in auth-sensitive paths such as
  `lib/core/auth/auth_user_contact.dart`

Source: local ownership analysis summary generated during this audit.

Why this matters:

- The operational risk is not just code quality. It is maintenance fragility.
- Security-sensitive areas should not depend on one effective maintainer.

What it must be like:

- Sensitive paths need shared ownership, documented invariants, and review
  coverage from more than one engineer.

## Current State vs Required State

| Area | Current State | Required State |
|---|---|---|
| SMS compliance boundary | “Approved sender only” is documented, but implementation also accepts broad heuristic matches and deep inbox recovery | Processing rules, disclosure, policy evidence, and code all say the same thing |
| Release readiness | `flutter analyze` is green, but `flutter test` and governance sync are red | All release gates green, including generated governance docs |
| Operational telemetry | Admin release dashboard consumes client-writable events | Release telemetry is server-controlled and trustworthy |
| Auth architecture | Functional, but rate limiting is shallow and user lookup scales poorly | Deterministic user mapping, layered abuse controls, and auditable flows |
| Deep linking | Platform declarations exist, but association files are incomplete | Verified end-to-end deep link readiness for iOS and Android |
| Documentation | Multiple docs are stale, contradictory, or point to missing files | Docs are generated or continuously validated from code |
| Testability | Large partner repositories couple behavior through private state and `part` files | Feature services are modular, injectible, and test-friendly |
| Ownership | Sensitive code has bus-factor-1 hotspots | Critical surfaces have shared ownership and enforced review coverage |

## Recommended Remediation Order

### Immediate release blockers

1. Narrow SMS ingestion to the exact approved-sender boundary or rewrite every
   compliance/reviewer document to match the broader behavior.
2. Fix `flutter test` and re-baseline governance docs from code.
3. Remove direct client insert access to `operational_health_events`.
4. Complete iOS AASA and Android assetlinks production values.

### Next hardening pass

1. Redesign OTP abuse controls and user lookup strategy.
2. Replace stale compliance/release docs with generated or CI-checked versions.
3. Fail CI on missing release configuration such as deep-link and maps setup.

### Structural engineering cleanup

1. Break up the Rayon repository into smaller injected boundaries.
2. Define explicit UI/copy contracts where tests are expected to enforce product
   behavior.
3. Reduce auth ownership concentration through pairing, code reviews, and
   documented invariants.

## Bottom Line

The repo has a viable product foundation, but it is not presently aligned with
its own declared operating model.

The most serious issue is not that a few tests fail. It is that the app,
backend, docs, and compliance story currently describe different systems.

Until the SMS boundary, release governance, telemetry trust model, and deep-link
setup are corrected, the implementation should be treated as pre-release rather
than production-ready.
