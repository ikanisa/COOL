# Collect Flutter Product, iOS, Architecture, and Release Readiness Goal - 2026-06-26

## Objective

Convert the broad Codex goal skill stack into a concrete COOL/Collect workstream:
verify the current Flutter product surface, architecture boundaries, design
system, accessibility, adaptive UI, backend/API contracts, payment expansion
posture, iOS/App Store readiness, and release-governance gates from current
repo evidence.

Codex owns repo-internal preparation, build hardening, evidence generation,
metadata drafting, release-readiness cleanup, and release-owner execution for
this workstream. App Store Connect/App Privacy publication, TestFlight or Play
Console uploads, App Review submission, and release-owner actions are delegated
to Codex and do not require a separate owner signoff gate. Codex should still
stop when a required credential, signing asset, billing detail, legal identity
detail, or irreversible production-service mutation cannot be completed safely
from the available workspace and account context.

## Current Product Shape

- App: `Collect`, a Flutter/Supabase platform for SMS-first MoMo group
  contributions.
- Package: `collect_app`, version `1.2.2+9`, Dart SDK `^3.12.0`.
- Mobile entrypoint: `lib/main.dart`.
- Admin PWA entrypoint: `lib/main_admin.dart`.
- Public web entrypoint: `lib/main_public.dart`.
- Mobile routing: `lib/app/router.dart` with Home, Groups, Settings, auth,
  permissions, payment, ledger, share, profile, support, and legal routes.
- State and DI: Riverpod providers with `CollectRepository` as the primary
  app data boundary.
- Backend: Supabase Auth, Postgres/RLS/RPCs, Realtime invalidation, and Edge
  Functions.
- Payments: MoMo SMS-first payment intents are active; Stripe diaspora
  foundation code exists in Supabase functions and migrations, but production
  payment-provider changes still need a concrete credentialed execution path and
  post-change evidence.
- iOS bundle: `app.cool.mobile`, production scheme present under
  `ios/Runner.xcodeproj`.

## Architecture And Module Map

- `lib/app/`: app shell, router, environment, and Collect theme.
- `lib/app/theme/`: source-controlled design tokens for color, spacing,
  typography, radius, shadows, icons, motion, and component tokens.
- `lib/core/`: security, Supabase, notifications, logging, and utility
  primitives.
- `lib/shared/`: models, repository, providers, and reusable Collect widgets.
- `lib/features/`: user-facing mobile features split by auth, launch, home,
  collections, payments, ledger, profile, settings, landing, status, and dev
  design-system catalog.
- `lib/admin/`: separate admin app shell, router, runtime, guards, repository
  abstractions, and shared admin components.
- `supabase/functions/`: Edge Function layer for OTP, SMS ingestion/parsing,
  allocation, notifications, Play Integrity, and Stripe support.
- `supabase/migrations/`: forward-only database contract history.

The current shape is a modular Flutter app with shared repository/data
boundaries rather than strict per-feature clean-architecture packages. Future
large feature work should keep presentation/domain/data seams explicit and avoid
feature-to-feature internal imports.

## Design, Accessibility, And Adaptive UI Requirements

- Keep tokens source-controlled in `lib/app/theme/`.
- Keep feature screens on shared Collect components rather than raw colors or
  one-off controls.
- Preserve minimum tap-target sizing through theme/component defaults.
- Maintain large-text and compact-viewport widget coverage for critical flows.
- Keep semantic labels on non-text controls and avoid color-only status
  communication.
- Keep reduced-motion expectations in shared motion/component primitives.
- Treat the development design-system catalog route as a validation aid only:
  production route contracts must not depend on debug-only screens.

Current source evidence supports this posture:

- `collect_mobile_design_compliance_audit` passes in the current gate surface.
- `flutter test --no-pub` passes with design-system, mobile-completion,
  app-shell, landing, security, release-docs, repository, and persona tests.

## Backend, Privacy, And Payment Boundaries

- Flutter must not store service-role, OpenAI, WhatsApp Cloud API, SMS gateway,
  Apple, Google, or signing secrets.
- Raw SMS is protected data and must remain outside member-facing surfaces.
- Supabase RLS/RPCs and Edge Functions are the production authorization and
  workflow boundary; client-side admin guards are not sufficient alone.
- Payment-intent writes, SMS ingestion, parser output, allocation, and ledger
  changes must remain auditable and idempotent where the backend contract allows.
- Stripe-related diaspora contribution functions should follow Checkout
  Sessions/Setup Intents guidance and remain gated until payment, compliance,
  and release approvals are explicit.

## Emerging Technology And Platform Scope

- Large screens, foldables, iPad, and future spatial/AI features should be
  adopted only when they improve a real Collect job and have fallback UI.
- iOS currently supports contributor-oriented scope; Android remains the
  platform for group creation/SMS ingestion.
- iPhone group creation must stay unavailable unless the product/backend SMS
  ingestion model changes and is reapproved.

## Current Validation Evidence

Commands run on 2026-06-26 from `/Volumes/PRO-G40/COOL`:

- `flutter --version`: Flutter `3.44.3`, Dart `3.12.2`.
- `dart --version`: Dart `3.12.2`.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass, no
  issues found.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub`: pass, `261`
  tests passed, `1` visual evidence test intentionally skipped because
  `COLLECT_VISUAL_EVIDENCE_DIR` was not set.
- `./scripts/migrations/validate_supabase_migrations.sh`: pass.
- `./scripts/release_secret_scan.sh`: pass with tracked-file fallback scanner.
- `./scripts/collect_product_boundary_scan.sh --json`: pass, `153` source
  files scanned, `0` hits.
- `./scripts/release_status.sh --json`: `NO-GO`, blocker key
  `android_release_artifacts`.
- `./scripts/flutter_mobile_release_gate.sh --json`: blocked on missing
  production Android APK/AAB artifacts and missing artifact signature
  verification.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --flavor production
  --release`: started, resolved dependencies, then the Flutter wrapper was
  interrupted after it stayed open without a visible Gradle child.
- `cd android && ./gradlew :app:assembleProductionRelease --stacktrace`:
  blocked by the intended production signing guard. The configured Android
  signing certificate SHA-256 was
  `9EE12172C78A8A487906D9159BFDD17B4D78ABA3541F17B410659E6D60DDCC10`, but the
  expected Play app-signing SHA-256 is
  `451738E69ADF1B4D3FAA7A659020282E027B47862671C9FC3245AF822B4D2A92`.
- Android UAT emulator `Pixel_5_API_34_Lite` booted as `emulator-5554`
  with Android SDK `34`, `720x1280`, density `320`. Earlier UAT attempts exposed
  stale design-token references; `lib/shared/widgets/collect_state_feedback.dart`
  now uses `CollectRadius.mdBorder`, and
  `lib/shared/widgets/collect_group_card_media.dart` now uses
  `colors.orangePaint`.
- `scripts/android_device_uat.sh` now launches the Flutter UAT command through
  a Ruby supervisor with a dedicated process group, timeout summary output, and
  TERM/KILL fallback cleanup. A fake-ADB/fake-Flutter timeout simulation
  returned exit `124`, wrote `status: timeout`, set `timed_out: true`, and
  stopped the spawned child process. This hardens future UAT evidence capture
  but does not count as real device UAT.
- Direct Gradle isolation for
  `:app:assembleProductionDebug` passed and wrote
  `.cache/android_gradle_direct_uat/result.json` with `status: pass`,
  `exit_code: 0`, and `elapsed_seconds: 90` on the warm rerun.
- A real emulator rerun on `emulator-5554` with
  `ANDROID_UAT_TIMEOUT_SECONDS=900` passed:
  `.cache/android_device_uat_premium_frontend/summary.json` records
  `status: pass`, `exit_code: 0`, `timed_out: false`, target
  `integration_test/mobile_route_matrix_device_uat_test.dart`, and log SHA-256
  `079ca95a033f3e3718ee1de2228564a0e11f35717310ef01ca11004266163d2f`. The log
  includes `58` `collect_route_uat:pass:` markers through `/sync`.
- `android/gradle.properties`: removed unsupported
  `kotlin.incremental.useClasspathSnapshot=false`. A follow-up
  `./gradlew :app:assembleProductionRelease --stacktrace` did not repeat that
  deprecated-property warning; it still failed at the same signing fingerprint
  guard. Flutter still warns that `file_saver`, `mobile_scanner`, `share_plus`,
  and `shared_preferences_android` apply Kotlin Gradle Plugin directly, which
  remains a dependency/tooling upgrade item.
- `android/app/build.gradle.kts`: added
  `printReleaseSigningCertificateStatus`, a redacted JSON preflight task that
  reports signing certificate fingerprint state without printing keystore
  passwords or key aliases.
- `scripts/android_release_signing_preflight.sh`: added a wrapper for the
  Gradle preflight task.
- `./scripts/android_release_signing_preflight.sh --json`: the preflight now
  distinguishes Google Play upload signing from the Play app-signing
  certificate. The configured local certificate SHA-256 is
  `9EE12172C78A8A487906D9159BFDD17B4D78ABA3541F17B410659E6D60DDCC10`; it differs
  from the Play app-signing SHA-256
  `451738E69ADF1B4D3FAA7A659020282E027B47862671C9FC3245AF822B4D2A92`, which is
  expected when Play App Signing uses a separate upload key.
- `./scripts/admin_pwa_release_build.sh`: pass; built `build/web` from
  `lib/main_admin.dart`, then passed the Admin PWA manifest and hosting gates.
- `./scripts/release_artifact_manifest.sh --json`: blocked only on missing
  Android release artifacts after the Admin PWA build:
  `build/app/outputs/flutter-apk/app-production-release.apk` and
  `build/app/outputs/bundle/productionRelease/app-production-release.aab`.
- `scripts/release_artifact_manifest.sh` and
  `scripts/flutter_mobile_release_gate.sh`: Android artifact freshness now
  includes `android/gradle.properties`, so signing/build property changes are
  considered when validating APK/AAB freshness.
- `test/release_docs_test.dart`: added
  `Android artifact freshness includes Gradle property changes` to lock the
  `android/gradle.properties` freshness input into both release gates.
- `scripts/android_kotlin_plugin_compat_gate.sh`: added a warning-level Android
  plugin compatibility gate that scans `.flutter-plugins-dependencies` and
  reports plugins whose Android Gradle files still apply Kotlin Gradle Plugin
  directly.
- `Makefile`: added `android-kotlin-plugin-compat` and
  `android-kotlin-plugin-compat-json` command surfaces for the warning-level
  gate.
- `Makefile`: added `android-release-signing-preflight` and
  `android-release-signing-preflight-json` command surfaces for fast redacted
  signing diagnosis.
- `scripts/repo_wide_qa_uat.sh`: now captures
  `android_release_signing_preflight.json` in real and fixture QA bundles and
  reports the surface as `blocked` when the configured signing certificate does
  not match Play signing.
- `scripts/repo_wide_qa_uat.sh`: now captures
  `android_kotlin_plugin_compat.json` in real and fixture QA bundles and
  reports the surface as `warning` instead of failing the release by itself.
- `scripts/release_evidence_index.sh`: now requires the
  `android_release_signing_preflight` command in indexed QA evidence and
  includes `android_release_signing_preflight.json` in bundle file inventory.
- `scripts/release_evidence_index.sh`: now requires the
  `android_kotlin_plugin_compat` command in indexed QA evidence and includes
  `android_kotlin_plugin_compat.json` in bundle file inventory.
- `./scripts/android_kotlin_plugin_compat_gate.sh --json`: `warning`; current
  plugin markers are reported for `file_saver`, `image_picker_android`,
  `mobile_scanner`, `share_plus`, and `shared_preferences_android`. This is a
  future Flutter/AGP compatibility risk, not the current release-stopping
  blocker.
- `QA_UAT_FIXTURE=1 QA_UAT_ADMIN_LIVE_FIXTURE_PASS=1
  QA_UAT_BUNDLE_DIR=/tmp/cool_repo_wide_fixture_signing_preflight
  ./scripts/repo_wide_qa_uat.sh --json`: expected fixture `FAIL` because the
  fixture intentionally keeps Admin live deployment, worktree review, UAT,
  artifacts, Supabase, and release evidence blocked/non-production; the
  `android_release_signing_preflight` surface reported `blocked`, and the
  nested evidence index recorded that command as `blocked` with exit `1`.
- `QA_UAT_FIXTURE=1 QA_UAT_ADMIN_LIVE_FIXTURE_PASS=1
  QA_UAT_BUNDLE_DIR=/tmp/cool_repo_wide_fixture_android_kotlin
  ./scripts/repo_wide_qa_uat.sh --json`: expected fixture `FAIL` because the
  fixture intentionally keeps Admin live deployment, worktree review, UAT,
  artifacts, Supabase, and release evidence blocked/non-production; the new
  `android_kotlin_plugin_compat` command was present with exit `0`, JSON
  evidence was written, and the repo-wide surface reported `warning`.
- `docs/release/product_design_mobile_audit_2026-06-26/`: existing mobile
  product-design audit evidence contains a manifest for `48` routes at
  `390x844` with no console errors recorded in the route capture entries.
  Screenshot files were converted from mislabeled JPEG data to real PNG files
  while preserving the manifest paths.
- `scripts/product_design_mobile_audit_artifact_gate.sh`: added a product-design
  route screenshot artifact gate that validates manifest shape, route count,
  viewport, file containment, PNG headers, dimensions, byte counts, and
  console-error counts.
- `Makefile`, `scripts/repo_wide_qa_uat.sh`, and
  `scripts/release_evidence_index.sh`: now expose, capture, and index
  `product_design_mobile_audit_artifact_gate` so screenshot artifact integrity
  is part of normal release evidence.
- `./scripts/product_design_mobile_audit_artifact_gate.sh --json`: pass,
  `48` routes at `390x844`.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
  test/release_docs_test.dart`: pass, `54` tests passed.
- `bash -n scripts/repo_wide_qa_uat.sh scripts/release_evidence_index.sh
  scripts/release_artifact_manifest.sh scripts/flutter_mobile_release_gate.sh
  scripts/android_kotlin_plugin_compat_gate.sh
  scripts/android_release_signing_preflight.sh
  scripts/product_design_mobile_audit_artifact_gate.sh`: pass.
- `git status --short`: contains this goal's modified files and new report /
  script; generated folders remain ignored.
- Generated folders `build/`, `.dart_tool/`, `.cache/`, and `output/` are
  ignored and not tracked by `git ls-files`.

Current inventory snapshot:

- `lib` Dart files: `153`.
- Dart tests: `17`.
- Scripts: `76`.
- Docs: `81`.
- Supabase function files: `16`.
- Supabase migrations: `42`.
- iOS files: `136`.
- Android files: `62`.
- Web files: `8`.

## iOS And App Store Evidence

XcodeBuildMCP session state on 2026-06-26:

- Session defaults were empty for project/workspace, scheme, and simulator.
- Project discovery found:
  - `/Volumes/PRO-G40/COOL/ios/Runner.xcodeproj`
  - `/Volumes/PRO-G40/COOL/ios/Runner.xcworkspace`
- The MCP response recommended `session_set_defaults()`, but that tool is not
  exposed in this session, so no simulator build/run was attempted through
  XcodeBuildMCP.

Existing repo evidence remains the current iOS baseline:

- `docs/release/IOS_APP_STORE_READINESS_2026-06-24.md`
- `docs/release/IOS_APP_STORE_COMPLETION_ALTERNATIVES_2026-06-25.md`
- `fastlane/Fastfile`
- `fastlane/app_privacy_details.json`
- `fastlane/screenshots/en-GB/`
- `ios/ExportOptionsAppStore.plist`

Known iOS blockers remain external/local-environment and signing/account
blockers until reverified:

- Local Xcode/CoreSimulator trust/session health must be repaired before
  simulator proof or local archive validation.
- Apple Distribution signing and App Store provisioning must be configured
  before local IPA upload.
- App Privacy and App Store Connect publishing are delegated Codex-owned release
  actions when the required account access and source-of-truth metadata are
  available.
- Build upload, TestFlight selection, App Review submission, and Play Console
  submission are delegated Codex-owned release actions; blockers should be
  treated as credential, signing, account, or evidence gaps rather than human
  approval gaps.

## Aggregate Gate Note

`./scripts/repo_wide_qa_uat.sh --json` was started during this pass but was
interrupted after the nested serial Flutter test driver stopped emitting final
JSON. Cache directories written under `.cache/repo_wide_qa_uat/20260626T*`
include release-doc fixture bundles whose `worktree_review.json` reports
`branch: fixture`; those fixture bundles are not production evidence. Use the
standalone command results above as the current authoritative evidence for this
pass.

## Current Verdict

Code-owned Flutter source health is green for this pass. Fresh Flutter-test
visual evidence now covers all `56` mobile route-smoke routes at `390x844` in
`.cache/flutter_visual_evidence_premium_frontend/mobile/summary.json`, and
`scripts/collect_mobile_design_compliance_audit.sh --json` passes when paired
with the real Android UAT pass summary. Release remains `NO-GO` because
production Android APK/AAB artifacts cannot be produced with the currently
configured local signing key and because iOS/App Store upload still
requires external signing/account/tooling remediation before Codex can execute
the delegated upload/submission path.

Code-owned cleanup in this pass was limited to release/build hardening:
removing an unsupported Kotlin incremental property, adding a redacted Android
signing preflight, teaching both Android artifact freshness gates to include
`android/gradle.properties`, and adding a warning-level gate for Flutter's
future Kotlin Gradle Plugin compatibility warning. Product-design evidence
cleanup converted the route screenshots to valid PNGs and added an artifact
gate. A Chrome CDP hard-timeout guard was added after local Chrome/Chromium
headless capture hung before DevTools readiness. Android UAT cleanup fixed the
stale `CollectRadii.medium` reference and relaxed the emulator lockscreen guard
to check actual keyguard/focused-lockscreen state. The UAT wrapper now records
timeout evidence and cleans up the supervised process group instead of leaving
silent Gradle/Flutter runs without a summary. The remaining release blockers
are Android signing material and Apple signing/account tooling, not application
feature code.

## Next Implementation Steps

1. Keep `android/key.properties` or `COOL_ANDROID_*` environment variables
   pointed at the registered Google Play upload key, optionally set
   `COOL_EXPECTED_UPLOAD_SIGNING_SHA256` when the Play Console upload
   certificate fingerprint is available, then rebuild production Android APK/AAB
   and rerun `./scripts/flutter_mobile_release_gate.sh --json`.
2. Rerun `./scripts/repo_wide_qa_uat.sh --json` after Android artifacts exist;
   if it hangs again, isolate the serial nested Flutter test step before
   treating aggregate evidence as current.
3. Repair local Xcode/CoreSimulator or use the documented GitHub Actions /
   second-Mac / Xcode Cloud path for iOS archive proof.
4. Configure App Store Connect API credentials when needed for the selected
   upload path.
5. Treat release-owner, external publication/submission, and repo-readiness work
   as Codex-owned under the delegated release authority recorded in this goal;
   pause only for missing credentials, signing assets, account access, or
   production mutations that cannot be executed safely from the available
   workspace and account context.
