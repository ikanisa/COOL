# COOL Mobile Production Readiness Audit

Date: 2026-04-11
Scope: full Flutter mobile app review across `lib/`, `test/`, `integration_test/`, `android/`, `ios/`, `supabase/functions/`, release scripts, and GitHub Actions.

## Executive Verdict

Status: not yet ready for a broad world-class production launch.

Current state: the app is materially stronger than a typical pre-launch Flutter codebase. It has a feature-based structure, meaningful automated coverage, real release-gate scripts, App Check-aware OTP flows, Android signing discipline, and better-than-average observability hooks. It is not yet at world-class launch discipline because the final release path is still only partially proven, store-grade automation is incomplete, and a few high-churn orchestration layers remain too large and too central to the app's reliability.

Post-audit remediation update:

- Android tagged-release automation now produces both a signed APK and a signed AAB.
- The repo now has an explicit release-candidate wrapper that enforces the
  minify canary, remote smoke, rollout verification, release metadata checks,
  and Firebase App Check provider verification.
- iOS store release automation is now explicitly de-scoped instead of being
  implied by partial validation scripts.

Recommended release posture today:

- internal dogfood / staging: yes
- controlled beta with explicit rollback plan: yes, after release blockers below are closed
- broad public launch: not yet

## What I Changed In This Pass

Implemented:

- `lib/bootstrap/app_bootstrap.dart`
  - reused the same initialized `CrashlyticsService` and `PerformanceService` from cold-start bootstrap inside the Riverpod graph
  - removed a bootstrap/provider seam where startup telemetry instances were created once for initial auth prep and then replaced by new instances after `ProviderScope`
  - outcome: cleaner startup architecture, better observability continuity, less duplicate service construction

- `lib/features/home/widgets/home_operations_section.dart`
- `lib/features/admin/widgets/manage_admin_roles_parts.dart`
- `lib/shared/widgets/cool_search_field.dart`
  - fixed strict `const` hygiene so `flutter analyze --fatal-infos` stays clean

- `docs/qa_release_readiness.md`
  - updated the release-readiness doc to match the real `scripts/release_readiness.sh` gate, including integration smoke, migration validation, full Deno coverage, and optional canary/remote smoke gates

- `.github/workflows/release.yml`
- `scripts/run_release_candidate.sh`
- `scripts/verify_release_metadata.sh`
- `scripts/verify_firebase_app_check.ts`
- `docs/RELEASE_PROCESS.md`
  - converted the tagged release lane into a stricter release-candidate gate
  - added signed Android AAB generation and artifact upload
  - made iOS store release scope explicit instead of ambiguous

Validated already present in current `HEAD`:

- OTP send/verify functions enforce abuse controls and support App Check enforcement
- Android release builds refuse silent debug signing unless explicitly opted into for non-distribution verification
- iOS permissions were pruned to match current app scope and unnecessary file-sharing flags were removed
- CI now uploads integration smoke JSON correctly and points Deno at real test files

## Validation Performed

Executed during this audit:

- `flutter analyze --fatal-infos`
- `flutter test --concurrency=1 test/providers/auth_notifier_test.dart test/core/providers/app_lifecycle_providers_test.dart`
- `flutter test --concurrency=1 test/core/services/whatsapp_otp_service_test.dart`
- `deno test supabase/functions/_shared/app_check_test.ts supabase/functions/send-otp/index_test.ts supabase/functions/verify-otp/index_test.ts`
- `flutter pub outdated`

Results:

- analyzer: clean
- targeted auth/lifecycle/mobile OTP tests: passing
- targeted Deno security/OTP tests: passing
- dependency health: acceptable but behind on a few important majors

## Live Verification Update

Production-backed checks executed after the initial audit:

- `bash scripts/release_readiness.sh` with
  `RUN_ANDROID_MINIFY_CANARY=1`,
  `RUN_REMOTE_SMOKE=1`,
  `RUN_MOMO_SMS_ROLLOUT_VERIFY=1`
- `bash scripts/supabase_contract_smoke.sh`
- `bash scripts/verify_momo_sms_supabase_rollout.sh`
- `bash scripts/build_production_minified_canary.sh`
- `bash scripts/build_play_release.sh`

Observed results against the linked project:

- the original release-readiness failure on staging/production parity was a
  release-script policy issue, not a backend defect; the repo now supports
  production-only release mode and can now skip staging explicitly with
  `COOL_SKIP_STAGING_BACKEND_VALIDATION=1` even when repo-local env files still
  define `SUPABASE_STAGING_*`
- the linked production project was behind local schema state by two migrations;
  both were applied successfully:
  - `20260411150000_admin_pwa_sessions_and_browser_events.sql`
  - `20260411170000_admin_pwa_rbac_and_audit_contracts.sql`
- M-Money rollout verification now passes after triggering the built-in
  migration safety check, which recorded a trusted
  `momo_sms_migration_safety` operational event and moved the release SMS
  health to `healthy`
- the missing frontend-used `parse-member-list` Edge Function was deployed to
  the linked production project during this audit session
- Supabase contract smoke is now blocked only by one missing hosted secret:
  `FIREBASE_SERVICE_ACCOUNT_JSON`. That same missing credential also blocks
  Firebase App Check provider verification for production
- the production minified APK artifact was produced at
  `build/app/outputs/flutter-apk/app-production-release.apk`
- the Android AAB build did not finish cleanly during this session, and no
  `app-production-release.aab` was present on disk when the build was stopped
- Firebase App Check provider verification still could not be executed because a
  Firebase service account credential was not supplied for this session

## Strong Areas

- Project structure is feature-oriented and navigable: `core/`, `features/*`, `shared/`, `bootstrap/`
- Automated coverage is broad: 229 test files across unit, widget, accessibility, smoke, golden, and edge-function tests
- Release governance exists in code, not only in tribal knowledge: `scripts/release_readiness.sh`, `docs/qa_release_readiness.md`, route/screen governance docs, and CI gates
- OTP flows are materially hardened with rate limiting, cooldowns, structured error handling, and App Check-aware request headers
- Android release discipline is better than average due to explicit keystore enforcement and minify commentary/gating
- iOS permission posture is intentionally narrowed rather than over-declared

## Severity-Ranked Findings

## Critical

### 1. Full production release path is still not proven end-to-end on store-grade artifacts and real devices

Evidence:

- `scripts/release_readiness.sh`
- `docs/qa_release_readiness.md`
- `android/app/build.gradle.kts`

Why this matters:

- source-level hardening is not enough for launch quality
- the remaining risk is in minified release behavior, signing, environment injection, deep-link associations, remote hosted-function behavior, and real-device regressions
- the Android build file itself still documents that production minify verification on real hardware is required before shipping

Best practical fix:

- make one signed release-candidate pass mandatory before broad launch
- run `bash scripts/release_readiness.sh` with `RUN_ANDROID_MINIFY_CANARY=1`, `RUN_REMOTE_SMOKE=1`, and `RUN_MOMO_SMS_ROLLOUT_VERIFY=1`
- build the real production artifact, validate on a device matrix, and record results in a release log

### 2. iOS store release automation is explicitly de-scoped and therefore still blocks a broad iOS launch

Evidence:

- `.github/workflows/release.yml`
- `docs/RELEASE_PROCESS.md`
- `scripts/build_ios_production.sh`

Why this matters:

- Android store-grade artifact automation is now present in the tagged release workflow
- iOS remains intentionally outside the automated tagged release scope
- for a "world-class production launch" that includes iOS, the current repo still lacks a signed TestFlight / App Store lane

Best practical fix:

- keep Android tagged releases producing both signed APK and signed AAB artifacts
- treat iOS as out of scope until a signed TestFlight / App Store lane exists
- if iOS becomes launch scope, fail release tags unless that lane is implemented and verified on macOS CI

### 3. App Check, signing, and hosted-secret correctness still depend on manual external configuration

Evidence:

- `docs/app_check_enforcement.md`
- `.github/workflows/release.yml`
- `scripts/sync_supabase_function_secrets.sh`

Why this matters:

- the code paths are present, but launch can still fail if Firebase App Check providers, debug-token cleanup, Supabase hosted secrets, or keystore metadata are misconfigured outside the repo
- this is an operational blocker, not a source-code blocker

Best practical fix:

- run a production-environment checklist that verifies:
  - App Check providers are registered for Android and iOS
  - hosted Supabase function secrets match production values
  - Android signing keys and iOS release metadata are correct
  - negative tests fail correctly when App Check headers are absent

## High

### 4. Auth/session lifecycle is too concentrated in one notifier

Evidence:

- `lib/features/auth/providers/auth_provider.dart` at 641 lines

Why this matters:

- this notifier owns anonymous auth, session restore, OTP session upgrade, profile creation, profile update, error mapping, and some domain normalization
- the result is harder-to-test lifecycle behavior and a higher chance of regressions whenever auth changes

Best practical fix:

- split into three narrow responsibilities:
  - session bootstrap / restore
  - OTP upgrade flow
  - profile mutation coordinator
- keep `AuthState` as the single UI-facing state object and avoid adding more provider layers than necessary

### 5. App bootstrap is still too dense and too central

Evidence:

- `lib/bootstrap/app_bootstrap.dart` at 429 lines

Why this matters:

- it coordinates Firebase, App Check, Supabase, Hive, runtime config logging, theme hydration, auth bootstrap, startup splash handling, and error presentation in one widget/state class
- this pass removed one duplication seam by reusing bootstrap telemetry instances, but the overall boot pipeline is still hard to reason about and hard to test in isolation

Best practical fix:

- extract a `BootstrapPipeline` or equivalent service with small step objects
- keep the UI widget focused on rendering progress, retry, and terminal errors
- preserve the current order of operations; do not rebuild bootstrap semantics unnecessarily

### 6. Several large UI modules remain expensive to maintain

Evidence:

- `lib/shared/widgets/admin_workspace_kit.dart` at 852 lines
- `lib/features/admin/screens/admin_savings_detail_screen.dart` at 815 lines
- `lib/features/admin/screens/admin_savings_screen.dart` at 791 lines
- `lib/features/admin/screens/bank_admin_workspace_screen.dart` at 779 lines
- multiple other screens/widgets in the 430-575 line range

Why this matters:

- these files are harder to review, harder to test surgically, and more likely to accumulate implicit coupling between layout, state wiring, and business rules

Best practical fix:

- split by screen section, not by arbitrary helper count
- keep orchestration in the screen and move reusable content sections into narrowly named widgets
- avoid abstraction churn unless two or more surfaces truly share behavior

### 7. Dependency health is acceptable but lagging on important majors

Evidence from `flutter pub outdated`:

- `flutter_riverpod` `2.6.1 -> 3.3.1`
- `go_router` `16.3.0 -> 17.2.0`
- minor lag on `share_plus`, `syncfusion_flutter_xlsio`, `mocktail`

Why this matters:

- major framework lag increases future upgrade cost and leaves the app off the mainline bugfix path

Best practical fix:

- schedule a controlled dependency pass after launch blockers are closed
- upgrade Riverpod and GoRouter in isolation with router/auth smoke coverage expanded first

### 8. A local forked dependency needs explicit ownership and maintenance policy

Evidence:

- `pubspec.yaml` overrides `flutter_contacts` to `third_party/flutter_contacts`

Why this matters:

- a vendored fork can silently drift from upstream security fixes and platform compatibility updates
- without a patch ledger, the team can forget why the fork exists

Best practical fix:

- document the exact delta from upstream
- add an owner and review cadence
- upstream or retire the fork when possible

## Medium

### 9. Release documentation had drifted from the real gate

Evidence:

- `docs/qa_release_readiness.md`
- `scripts/release_readiness.sh`

Why this matters:

- stale release docs create false confidence and inconsistent launch behavior across engineers

Best practical fix:

- completed in this pass for the current checklist
- keep docs sync covered by CI and treat release-doc drift as a governance defect

### 10. Provider graph scale is large enough to require stricter conventions

Evidence:

- 121 provider declarations found under `lib/`

Why this matters:

- Riverpod is being used effectively, but at this size the codebase needs stronger rules around ownership, naming, and layering to avoid hidden coupling

Best practical fix:

- document simple conventions:
  - repositories depend on `supabaseClientProvider`
  - feature providers do not reach across unrelated feature boundaries
  - cross-cutting services live under `core/`
  - tests must override providers rather than reaching global singletons

## Low

### 11. Strict analyzer hygiene had small but real noise

Evidence:

- three `const` cleanups were needed in widget files

Why this matters:

- low severity, but keeping `--fatal-infos` green is part of launch discipline

Best practical fix:

- completed in this pass
- keep `flutter analyze --fatal-infos` non-negotiable in CI and local release scripts

## Prioritized Refactor Plan

### Phase 0: Must complete before broad production launch

- run full release-candidate validation with the optional canary and remote smoke gates enabled
- build store-grade artifacts for the intended launch platforms
- verify Firebase App Check provider registration and hosted-secret correctness in production
- execute the manual critical-journey device matrix from `docs/qa_release_readiness.md`

### Phase 1: Safe architecture hardening immediately after blockers close

- split `AuthNotifier` by responsibility while preserving the external state contract
- extract boot-step orchestration out of `AppBootstrap`
- break up the largest admin/shared UI files by section boundaries

### Phase 2: Release engineering and dependency health

- add Android AAB and iOS/TestFlight automation
- upgrade `flutter_riverpod` and `go_router` with focused regression coverage
- document ownership for the `flutter_contacts` fork

### Phase 3: Ongoing maintainability

- enforce file-size budgets more broadly
- formalize provider-layer conventions
- keep release, governance, and environment docs synced through CI

## Production Hardening Checklist

- `flutter analyze --fatal-infos` is green
- targeted auth/lifecycle/mobile OTP tests are green
- Deno OTP/App Check tests are green
- release readiness script is green with optional canary/remote smoke gates enabled
- Android production artifact is signed, minified, and tested on real hardware
- iOS production artifact is archived/signed/tested, or iOS is explicitly de-scoped
- Firebase App Check production providers are registered and verified
- Supabase hosted function secrets are synced and validated
- deep-link association metadata is current for the release
- manual critical journeys have been executed and recorded
- rollback owner, rollback artifact, and rollback procedure are assigned before go-live

## Release Blockers

- no recorded end-to-end signed release-candidate run on real devices
- no recorded execution of the new full release-candidate pass against production-backed secrets and systems
- iOS store release remains explicitly out of scope for the current automated launch path
- external production prerequisites for App Check/signing/secrets still need explicit verification

## Final Go-Live Assessment

Production-readiness grade: B- for code quality, C+ for release discipline, not launch-approved yet for a broad public rollout.

The codebase is no longer in "fragile prototype" territory. It has real shape, real tests, and real hardening. The remaining gap is not a wholesale rewrite; it is disciplined completion of the release path and targeted simplification of the two most critical orchestration layers. Close the release blockers, keep the current business logic stable, and this can move to a credible production launch without unnecessary architectural churn.
