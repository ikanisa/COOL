# Full Repo Audit Implementation - 2026-06-15

## Scope

Status: In progress.

This evidence note tracks the long-running full COOL repo audit and
implementation program across Collect mobile, Admin PWA, shared/core code,
Supabase, Android, iOS, web/PWA, tests, scripts, security, privacy,
accessibility, release evidence, and rendered/device validation.

## Baseline

- Branch: `main`
- Head: `6b23339 (HEAD -> main, origin/main, origin/HEAD) Harden Admin PWA production readiness`
- Pinned Flutter: `Flutter 3.44.0`, Dart `3.12.0`
- Initial dirty worktree carried existing Admin OTP/Supabase hardening changes in:
  - `lib/admin/core/admin_runtime.dart`
  - `scripts/supabase_production_readiness.sh`
  - `supabase/functions/auth-send-whatsapp-otp/index.ts`
  - `test/admin_pwa_test.dart`
  - `test/supabase_contract_test.dart`

## Inventory Tooling

Added `scripts/full_repo_audit_inventory.sh` to produce repeatable JSON or
Markdown inventory of the repo audit surface.

The script records:

- git and toolchain baseline
- mobile route contract and GoRouter entries
- admin route contract and GoRouter entries
- Supabase functions and migrations
- scoped file counts across `lib`, `supabase`, `android`, `ios`, `web`,
  `scripts`, `test`, `integration_test`, and `docs`
- risk-marker rows by path, line, and marker only

Sensitive values are not printed by the inventory. Potential secret-like rows
are reported only as marker names with file and line references.

Latest generated local artifacts:

- `output/full_repo_audit_inventory_2026-06-15.json`
- `output/full_repo_audit_inventory_2026-06-15.md`

The `output/` directory is local/ignored evidence storage and is not part of the
tracked release packet.

## Inventory Snapshot

- Scoped files: 500
- Flutter library Dart files: 78
- Dart test/integration files: 14
- Scripts: 50
- Docs: 84
- Native/web platform files: 211
- Supabase functions: 9
- Supabase migrations: 40
- Mobile route contract entries: 52
- Mobile GoRouter entries: 52
- Admin route contract entries: 23
- Literal admin GoRoute entries: 5

The admin router intentionally uses `_listRoute` and `_detailRoute` helpers, so
the `adminRoutePaths` contract remains the authoritative full admin route list.

## Implemented Gap Closure

### Admin OTP Error Hygiene

Finding: the existing dirty worktree already contained Admin OTP/Supabase hook
hardening. The audit retained and validated that behavior rather than widening
the error surface.

Validated:

- Admin UI does not expose raw Supabase hook failure text.
- Supabase OTP hook returns public-safe failure text while logging internal
  delivery details server-side.
- Production readiness script expectation matches the safe hook error.

### Mobile Route Contract Drift

Finding: `collectRoutePaths` was used by tests and route-render coverage, but it
did not include every registered mobile route. In particular, invite, owner
redirects, payment handoff, and share confirmation routes could be missed by
the render-smoke coverage assertion.

Changed:

- `lib/app/router.dart`
  - Added missing contract paths for owner redirects, payment handoff, invite,
    and share confirmation.
- `scripts/mobile_route_render_smoke.sh`
  - Added concrete route specs for the missing redirect/alias paths.
- `test/app_shell_test.dart`
  - Expanded route registration expectations.
- `README.md`
  - Replaced the partial mobile route list with the current route contract.

Result: refreshed inventory reports 52 mobile route contract entries and 52
mobile GoRouter entries.

### Mobile UI, Privacy, and Persona Regression Fixes

The broad widget/persona/mobile-completion test queue surfaced user-visible
regressions after the initial route-contract pass. Fixed issues:

- Group cards no longer inherit a global blur layer from `CollectCard`; this
  restores the expected compact group card surface while preserving explicit
  blur use in shell/bottom-sheet surfaces.
- Payment support review now exposes the expected `Safe note` label.
- Auth OTP state now exposes a clear `Verification code` state and an accessible
  bottom action OTP field after code delivery.
- Help/support copy no longer prints the raw WhatsApp support phone number in
  the app surface.
- Admin record detail panels now include a compact status JSON line so
  system-health checks render `"status": "ok"` visibly.

### Render Evidence Recovery

Finding: local route-render proof was blocked because Chrome DevTools did not
become ready under `--headless=new` in this environment.

Changed:

- `scripts/chrome_cdp_screenshot.mjs`
- `scripts/chrome_cdp_route_matrix.mjs`

Both CDP helpers now default to legacy `--headless`, which is the mode that
exposes DevTools reliably on this Mac. The mode remains overrideable through
`CHROME_CDP_HEADLESS_ARG` for future browser/runtime changes.

Result:

- `scripts/mobile_route_render_smoke.sh` passed and refreshed 54 route
  screenshots at `.cache/mobile_route_render_smoke/20260615T130336Z`.
- `scripts/collect_mobile_design_compliance_audit.sh --json` now passes.
- `scripts/admin_pwa_render_smoke.sh` passed with current Admin PWA runtime and
  desktop/mobile screenshot evidence at
  `.cache/admin_pwa_render_smoke/20260615T131201Z`.

### Release Artifact Refresh

The audit rebuilt release artifacts from the patched source tree:

- `scripts/admin_pwa_release_build.sh`
- `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub`
- `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub`

Result:

- `scripts/release_artifact_manifest.sh --json` passes and wrote
  `output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_2026-06-15.sha256`.
- APK: `build/app/outputs/flutter-apk/app-production-release.apk`
  - SHA-256:
    `fc0bdea987d65a9a2bfa9237918da7223b79d63a9d61fc99b9813960691c0377`
- AAB: `build/app/outputs/bundle/productionRelease/app-production-release.aab`
  - SHA-256:
    `f20bba1d4d647f4961699748579c630f9d178fd6af54c615f82faa112c93db1d`
- `scripts/flutter_mobile_release_gate.sh --json` passes artifact freshness,
  manifest, permission, and signature checks, then blocks only on required
  human approval records for Android signing review and iOS release scope.

Dependency note: both Android release builds emitted Flutter's warning that
`file_saver`, `mobile_scanner`, `share_plus`, and
`shared_preferences_android` still apply Kotlin Gradle Plugin directly. This
is a forward-compatibility risk for future Flutter versions, not a current
build failure.

## Validation Run

Passed:

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/admin_pwa_test.dart test/supabase_contract_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/design_system_components_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/widgets_test.dart test/features/mobile_completion_test.dart test/persona_uat_smoke_test.dart test/admin_pwa_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1
./scripts/release_secret_scan.sh
./scripts/migrations/validate_supabase_migrations.sh
scripts/full_repo_audit_inventory.sh --json
scripts/full_repo_audit_inventory.sh --markdown
./scripts/admin_pwa_release_build.sh
JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub
JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub
./scripts/release_artifact_manifest.sh --json
./scripts/flutter_mobile_release_gate.sh --json
./scripts/mobile_route_render_smoke.sh
./scripts/collect_mobile_design_compliance_audit.sh --json
./scripts/admin_pwa_render_smoke.sh
./scripts/collect_product_boundary_scan.sh --json
./scripts/supabase_production_readiness.sh
```

Validated behavior:

- Admin OTP raw Supabase hook failures are sanitized in the UI.
- Supabase OTP hook contract includes public-safe error handling.
- Admin route contract tests pass.
- Mobile route contract and render-smoke coverage assertions pass.
- Analyzer reports no issues on the patched worktree.
- The targeted broad-failure queue is resolved.
- Full serial Flutter suite passes: `+215: All tests passed!`
- Release documentation gates pass and still fail closed on missing/weak human
  approvals.
- Fallback tracked-file secret scan passes. `gitleaks` is not installed in the
  current shell, so the script used the repo fallback scanner.
- Supabase migration validation passes.
- Current Admin PWA build, metadata, hosting policy, runtime, and rendered
  screenshot smoke pass.
- Current mobile route rendered evidence covers all 54 design-audit routes.
- Current Android APK/AAB and Admin PWA artifacts are fresh relative to source
  mtimes.
- APK signature verifies with `apksigner`; AAB signature verifies with
  `jarsigner`.
- Collect product-boundary scan passes with zero hits.
- Linked Supabase readiness passes code-owned checks, including migration
  history, schema contract, RLS, linked SMS-first rollback UAT, admin/security
  rollback UAT, Edge Function auth contract, deployed endpoint checks, and Edge
  Function secret-name checks.

Current release NO-GO blockers:

```sh
./scripts/release_status.sh --json
```

`release_status.sh --json` remains `NO-GO` / `blocked` with these blocker keys:

- `product_signoff`
- `android_sms_access_uat`
- `android_release_signing_review`
- `ios_release_scope`
- `release_owner_signoff`

These are approval/UAT signoff blockers. The audit did not record or fabricate
human approvals.

Supabase readiness warnings retained for release-owner review:

- Supabase CLI installed locally is `v2.90.0`; newer `v2.106.0` is available.
- Password leaked-credential protection is disabled.
- Auth bot-protection challenge is disabled.
- Supabase organization is on the Free plan.
- Point-in-time restore is disabled.

## Open Work

The full goal is not complete. Remaining phases still require execution:

- subjective/manual mobile screen-by-screen visual review
- subjective/manual Admin PWA screen-by-screen visual review
- Android/iOS/web manifest and permission review
- privacy, retention, SMS, account deletion, and WhatsApp approval review
- accessibility pass across mobile and admin
- physical-device validation where a device is available
- human approval and UAT signoff packet completion for the five release
  blockers above
