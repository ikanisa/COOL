# Fullstack Remediation Implementation Plan

Date: 2026-03-13

Based on:

- [fullstack_audit_report_2026-03-13.md](/Volumes/PRO-G40/COOL/docs/fullstack_audit_report_2026-03-13.md)
- [qa_release_readiness.md](/Volumes/PRO-G40/COOL/docs/qa_release_readiness.md)
- [RELEASE_PROCESS.md](/Volumes/PRO-G40/COOL/docs/RELEASE_PROCESS.md)

## Objective

Bring the COOL app from its current pre-release, contract-drifted state to a
production-ready state where:

- code, tests, docs, and store/compliance claims describe the same system
- release gates are trustworthy and green
- security-sensitive surfaces have clear trust boundaries
- mobile platform configuration is production-complete
- partner and feature modules are testable and maintainable

## Planning Principles

1. Fix truth gaps before feature polish.
2. Narrow risky behavior before documenting exceptions.
3. Restore release confidence before shipping more product scope.
4. Move trust-critical logic off the client where integrity matters.
5. Prefer CI-enforced governance over manual discipline.

## Recommended Delivery Shape

This should run as a six-phase program over roughly 4 to 6 weeks, with Phase 0
and Phase 1 treated as release blockers.

Suggested execution model:

- one engineering lead for cross-phase sequencing
- one mobile lead for Flutter and platform work
- one backend lead for Supabase, Edge Functions, and DB policy hardening
- one product/release owner for compliance language and release sign-off

## Critical Path

This is the required order:

1. Freeze release claims and decide the true SMS boundary.
2. Restore green release gates and governance docs.
3. Remove client write access from release-critical telemetry.
4. Complete deep-link and platform release configuration.
5. Harden OTP/auth abuse controls and lookup architecture.
6. Refactor high-friction repositories and formalize ownership.

## Phase 0: Program Control And Truth Freeze

### Goal

Stop drift while remediation is underway.

### Duration

1 to 2 working days

### Tasks

1. Declare a temporary release freeze for production tags.
2. Create a remediation branch or epic with all audit findings mapped to owners.
3. Mark [fullstack_audit_report_2026-03-13.md](/Volumes/PRO-G40/COOL/docs/fullstack_audit_report_2026-03-13.md) as the active source of truth for this effort.
4. Require any concurrent product changes to update tests and governance docs in the same PR.
5. Decide the shipping SMS policy.

### Recommendation

Take the narrow path:

- keep SMS autoread only for approved M-Money senders
- remove heuristic acceptance of non-approved senders
- reduce inbox recovery scope sharply

Do not widen the compliance story unless legal/policy review explicitly approves
it.

### Deliverables

- remediation tracker with owners and due dates
- written SMS boundary decision
- temporary release freeze notice in team workflow

### Exit Criteria

- no one is still treating the repo as release-ready
- one approved payment-confirmation truth statement exists

## Phase 1: Release Truth Restoration

### Goal

Make the implementation, tests, and docs agree again.

### Duration

5 to 7 working days

### Workstream 1A: SMS Boundary Correction

Tasks:

1. Change SMS capture logic so non-approved senders are rejected.
2. Remove or sharply narrow body-only heuristic acceptance.
3. Reduce inbox recovery lookback from years to a small operational window.
4. Reduce recovery volume limits to the smallest practical bound.
5. Add tests for approved sender acceptance and non-approved sender rejection.

Likely files:

- `lib/features/momo/repositories/momo_sms_ingestion_repository.dart`
- `lib/features/momo/services/momo_sms_autoread_service.dart`
- `test/features/momo/`

Exit Criteria:

- code enforces the same sender boundary the repo declares
- tests prove that broad inbox scanning is no longer possible

### Workstream 1B: Governance And Test Baseline Recovery

Tasks:

1. Fix the failing `flutter test` suite in severity order.
2. Regenerate route and screen governance docs from code.
3. Remove or update stale tests that encode old behavior.
4. Reconcile UI copy tests with intentional current product wording.
5. Add a CI check that fails when route docs drift.

Likely files:

- `docs/ROUTE_INVENTORY.md`
- `docs/SCREEN_BUDGETS.md`
- `tool/governance_docs.dart`
- `test/docs/governance_docs_sync_test.dart`
- `test/shared/widgets/cool_button_test.dart`
- `test/core/utils/intl_locale_test.dart`
- `test/features/admin/operational_dashboard_screen_test.dart`
- `test/features/profile/profile_data_test.dart`

Exit Criteria:

- `flutter analyze` passes
- `flutter test` passes
- governance docs match generated output exactly

### Workstream 1C: Documentation Truth Cleanup

Tasks:

1. Rewrite the Google Play SMS declaration around the actual implementation.
2. Remove references to missing files from compliance docs.
3. Update permissions docs to include SMS if SMS remains in scope.
4. Update README payment language where it overstates current guarantees.
5. Cross-check release docs against the implemented route and feature surface.

Likely files:

- `README.md`
- `docs/google_play_sms_declaration.md`
- `docs/PERMISSIONS.md`
- `docs/qa_release_readiness.md`

Exit Criteria:

- no compliance or release doc points to missing code
- store-facing language matches the implementation exactly

## Phase 2: Security And Trust Boundary Hardening

### Goal

Make release-critical and auth-critical systems trustworthy by design.

### Duration

5 to 7 working days

### Workstream 2A: Operational Telemetry Integrity

Tasks:

1. Remove direct client insert rights to `operational_health_events`.
2. Introduce a server-side telemetry ingest path for mobile health events.
3. Separate untrusted client telemetry from release-gating telemetry.
4. Rate-limit telemetry ingestion and validate payload shape.
5. Update the operations dashboard docs and queries to use trusted signals only.

Recommended implementation shape:

- mobile client calls an Edge Function or authenticated RPC
- server stamps trusted metadata
- release dashboard consumes only server-classified events

Likely files:

- `supabase/migrations/20260313101500_operational_observability.sql`
- `lib/core/services/operational_health_service.dart`
- `supabase/functions/_shared/observability.ts`
- `docs/OPERATIONAL_OBSERVABILITY.md`

Exit Criteria:

- authenticated clients cannot directly poison release telemetry
- admin operations surfaces read only from trusted event paths

### Workstream 2B: OTP And Auth Hardening

Tasks:

1. Add IP-based and device-based throttling around OTP send and verify.
2. Add abuse telemetry and lockout analytics.
3. Replace `listUsers()` pagination with a deterministic phone-to-auth-user mapping strategy.
4. Review review-account OTP bypasses and isolate them behind explicit environment controls.
5. Add tests for rate limiting and user-lookup repair behavior.

Recommended implementation shape:

- create a dedicated table or mapping strategy keyed by normalized phone
- enforce per-phone, per-IP, and sliding-window controls
- keep repair logic constant-time against indexed records

Likely files:

- `supabase/functions/send-otp/index.ts`
- `supabase/functions/verify-otp/index.ts`
- `supabase/functions/_shared/security.ts`
- `supabase/migrations/`

Exit Criteria:

- no auth flow depends on scanning the full auth user list
- OTP controls are layered, measurable, and test-covered

### Workstream 2C: Database Helper Hardening

Tasks:

1. replace older `security definer` helper patterns with `set search_path`
2. remove duplicate admin helper ambiguity where practical
3. add SQL regression checks for admin policy helpers

Likely files:

- `supabase/migrations/20260311110000_admin_write_policies.sql`
- follow-up hardening migration under `supabase/migrations/`

Exit Criteria:

- privileged helper functions follow one hardened pattern

## Phase 3: Platform Production Completion

### Goal

Close native and hosted configuration gaps that would break production behavior.

### Duration

3 to 5 working days

### Workstream 3A: Deep Links

Tasks:

1. populate the iOS `apple-app-site-association` file with the real app details
2. add the Google Play signing SHA-256 fingerprint to both Android assetlinks files
3. validate supported route coverage for app links and universal links
4. add a release checklist item for link verification on signed builds

Likely files:

- `deeplinks/site/.well-known/apple-app-site-association`
- `deeplinks/site/.well-known/assetlinks.json`
- `hosting/.well-known/assetlinks.json`
- `ios/Runner/Runner.entitlements`
- `android/app/src/main/AndroidManifest.xml`

Exit Criteria:

- signed iOS build opens supported `https://cool.app/...` routes in-app
- signed Android build verifies app links with final Play fingerprint

### Workstream 3B: iOS Runtime Config Completeness

Tasks:

1. define a secure path for `GOOGLE_MAPS_IOS_API_KEY` if embedded `google_maps_flutter` rendering is intended to ship on iOS
2. keep release validation aligned with the current fallback contract so missing client keys warn instead of blocking builds when map widgets are intentionally hidden
3. document the required local and CI config files
4. verify iOS behavior through the standard build path, including the non-map fallback state when the key is absent

Likely files:

- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`
- `ios/Runner/Info.plist`
- release build scripts or CI workflow

Exit Criteria:

- iOS builds fail fast when required platform config is missing
- maps render through the normal release path

### Workstream 3C: Native Release Validation

Tasks:

1. run signed Android and iOS smoke builds
2. verify deep links, maps, notifications bootstrap, and payment entry surfaces
3. record release evidence for future store and QA reviews

Exit Criteria:

- platform-level smoke sheet is complete and reproducible

## Phase 4: Architecture And Testability Refactor

### Goal

Reduce repository coupling and make failing feature surfaces easier to maintain.

### Duration

5 to 8 working days

### Workstream 4A: Rayon Module Decomposition

Tasks:

1. split the Rayon repository into smaller injected services:
   - membership
   - tickets
   - shop
   - initiatives
   - admin
2. stop using `part`-based private-state coupling for core behavior composition
3. make provider tests depend on explicit interfaces rather than one large repository object
4. restore full Rayon-related test coverage after refactor

Likely files:

- `lib/features/partners/repositories/rayon_sports_repository.dart`
- `lib/features/partners/repositories/rayon_sports_repository_membership.dart`
- `lib/features/partners/repositories/rayon_sports_repository_tickets.dart`
- `lib/features/partners/repositories/rayon_sports_repository_shop.dart`
- `lib/features/partners/repositories/rayon_sports_repository_admin.dart`
- `lib/features/partners/providers/`
- `test/features/partners/`

Exit Criteria:

- Rayon providers and screens can be tested without private member leakage
- repository boundaries are narrow and injectable

### Workstream 4B: UI Contract Stabilization

Tasks:

1. decide which UI copy and label surfaces are product contracts
2. centralize repeated status labels and wording
3. align loading-indicator tests with the chosen widget behavior
4. document public-user-identity display rules so tests encode the intended privacy posture

Likely files:

- `lib/shared/widgets/cool_button.dart`
- `lib/features/profile/widgets/profile_data.dart`
- `lib/features/credit/widgets/`
- `lib/core/identity/public_user_identity.dart`
- related tests

Exit Criteria:

- tests fail on intentional product regressions, not on unmanaged copy drift

## Phase 5: Release Governance And Operationalization

### Goal

Prevent the same class of drift from reappearing.

### Duration

3 to 5 working days

### Workstream 5A: CI Enforcement

Tasks:

1. make governance doc sync a required CI gate
2. fail CI on release config placeholders such as unresolved assetlink fingerprints
3. fail CI if store/compliance docs reference missing files
4. require `flutter test`, Deno checks, and release-readiness scripts on protected branches

Likely touchpoints:

- `.github/workflows/`
- `scripts/release_readiness.sh`
- lightweight doc-lint scripts under `scripts/` or `tool/`

Exit Criteria:

- the repo cannot silently drift back into a contradictory state

### Workstream 5B: Ownership And Review Controls

Tasks:

1. identify auth, payment, and admin-observability paths as sensitive ownership areas
2. require two-person review on those paths
3. create short design invariants for:
   - payment confirmation scope
   - OTP/auth identity mapping
   - operational telemetry trust model
4. spread ownership through pairing or planned follow-on changes

Recommended sensitive paths:

- `lib/features/auth/`
- `lib/features/momo/`
- `lib/core/services/operational_health_service.dart`
- `supabase/functions/send-otp/`
- `supabase/functions/verify-otp/`
- `supabase/migrations/` affecting auth/admin policy

Exit Criteria:

- sensitive surfaces no longer have effective single-owner risk

## Phase 6: Release Candidate Certification

### Goal

Prove the app is truly releasable after remediation.

### Duration

2 to 3 working days

### Certification Checklist

1. `flutter analyze` passes.
2. `flutter test` passes.
3. `deno check` passes.
4. targeted Edge Function tests pass.
5. governance docs are regenerated and committed.
6. compliance docs are accurate and traceable.
7. operations dashboard is fed only by trusted telemetry.
8. Android and iOS deep links are verified on signed builds.
9. OTP abuse controls are exercised in QA.
10. release owner signs off that repo truth and shipping truth match.

### Output

- one signed release candidate build
- one release evidence bundle
- one post-remediation summary documenting what changed and what remains deferred

## Dependency Map

| Phase | Depends On | Blocks |
|---|---|---|
| Phase 0 | none | all later phases |
| Phase 1 | Phase 0 SMS decision | release candidate work |
| Phase 2 | Phase 0 and Phase 1 truth restoration | trusted ops and auth sign-off |
| Phase 3 | Phase 1 doc cleanup | native production readiness |
| Phase 4 | Phase 1 green baseline | maintainability and partner reliability |
| Phase 5 | Phases 1 to 4 | durable prevention controls |
| Phase 6 | Phases 1 to 5 | shipping |

## Suggested Ticket Breakdown

### P0 Release blockers

- narrow SMS ingestion scope to approved senders only
- reduce inbox recovery scope and add tests
- fix failing Flutter tests and regenerate governance docs
- rewrite stale compliance docs
- remove direct client insert into operational health feed
- complete deep-link production files

### P1 Security and platform hardening

- auth lookup redesign and abuse throttling
- release config validation for iOS maps and hosted artifacts
- DB helper hardening migration

### P2 Structural cleanup

- Rayon repository decomposition
- UI contract centralization
- ownership and review policy rollout

## Definition Of Done

This remediation program is done only when all of the following are true:

- the repo can pass all declared release gates
- the compliance story is defensible from code and docs alone
- release-critical telemetry is trustworthy
- platform setup is complete on both Android and iOS
- the highest-risk modules are testable and have shared ownership

## Bottom Line

The right strategy is not to patch isolated failures in arbitrary order.

The right strategy is:

1. restore truth
2. restore trust
3. restore release readiness
4. then refactor for durability

If Phase 1 and Phase 2 are not completed first, later cleanup work will sit on
top of the same broken release foundation.
