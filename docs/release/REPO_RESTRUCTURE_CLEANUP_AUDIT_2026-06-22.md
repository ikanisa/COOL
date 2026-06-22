# COOL Repo Restructure and Cleanup Audit - 2026-06-22

## Current State

- Repo root: `/Volumes/PRO-G40/COOL`
- Flutter toolchain: `/Volumes/PRO-G40/flutter_3_44/bin/flutter`
- Current inventory: 79 Dart library files, 17 Dart test files, 67 scripts, 100 docs, 14 Supabase functions, 42 migrations, and 210 native/platform files.
- Active app entrypoints: `lib/main.dart`, `lib/main_admin.dart`, and `lib/main_public.dart`.
- Current active Dart reachability: 78 of 79 `lib/**/*.dart` files are reachable from app entrypoints. The remaining file, `lib/core/security/play_integrity_service.dart`, is intentionally retained because tests, native Android, Supabase, and Google Play readiness docs lock the Play Integrity implementation surface.
- Local generated-artifact footprint was reduced from about 21 GB to about 312 MB by removing ignored `.cache`, `build`, `output`, `.dart_tool`, Flutter logs, generated Pods, and temporary browser/build evidence. Package resolution was restored with `flutter pub get` before validation.

## Guidance Used

- Flutter architecture guidance favors separation of UI and data layers, MVVM-style views/view models, repositories, services, and adapting the guidance to the application instead of forcing a generic pattern.
- Flutter data-layer guidance treats repositories as the source of truth and services as stateless wrappers around external APIs or platform plugins.
- Flutter accessibility guidance makes accessibility a release criterion, not a late polish step.
- Flutter performance guidance prioritizes controlling build cost, minimizing opacity/clipping and intrinsic layout passes, efficient lists, and measuring frame work before claiming performance readiness.
- Material 3 remains the design-system reference, but Collect-specific semantic tokens and components should remain the source of truth in code.

## Cleanup Already Landed In Baseline

- Removed unused admin/core placeholders:
  - `lib/admin/core/admin_filters.dart`
  - `lib/admin/core/admin_permissions.dart`
  - `lib/admin/core/admin_table_state.dart`
- Removed unused admin shared widgets:
  - `lib/admin/shared/components/admin_action_menu.dart`
  - `lib/admin/shared/components/admin_detail_drawer.dart`
  - `lib/admin/shared/components/admin_timeline.dart`
- Removed unused generic placeholders:
  - `lib/core/constants/app_constants.dart`
  - `lib/core/errors/app_exception.dart`
  - `lib/core/security/security_policy.dart`
  - `lib/core/utils/string_utils.dart`

## Cleanup Executed In This Pass

- Extracted public website route/content data from `lib/features/landing/collect_landing_page.dart` into `lib/features/landing/public_content.dart`.
  - `collect_landing_page.dart` is now focused on rendering and page composition.
  - `public_content.dart` owns `publicWebsitePaths`, `publicPageForPath`, public page data, and public infographic step metadata.
  - `collect_landing_page.dart` re-exports `public_content.dart` to keep existing imports stable.
- Extracted input/form components from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_inputs.dart`.
  - Moved `OtpCodeField`, `CollectTextInput`, `SearchWithClearField`, and `collectInputDecoration`.
  - `collect_components.dart` re-exports `collect_inputs.dart` to avoid churn across feature imports.
- Extracted onboarding/legal/auth-result status screens from `lib/features/status/production_state_screens.dart` into `lib/features/status/onboarding_status_screens.dart`.
  - Moved `OnboardingScreen`, `LegalConsentScreen`, `AuthResultScreen`, and their onboarding step-list helper together.
  - `production_state_screens.dart` re-exports `onboarding_status_screens.dart` to keep router imports stable.
- Narrowed the repository text secret scan in `test/security_hygiene_test.dart` so ignored generated folders are skipped.
  - Skips `.cache`, `output`, `release-evidence`, and `evidence-packs` in addition to existing generated roots.
- Removed stale generated output from the working tree:
  - `.cache/`
  - `build/`
  - `output/`
  - `.dart_tool/` before validation, then regenerated only package resolution state through `flutter pub get`
  - Flutter log files and `.DS_Store` files
  - generated iOS Pods and ephemeral Flutter files
  - untracked stale build checksum and public website screenshot evidence from `docs/release`

## Findings

1. The repo does not have a large active-code dead-file problem after the latest baseline cleanup. The remaining issue is structural concentration: several files are too large and mix routing, presentation composition, state rendering, and reusable components.
2. The largest Dart files are the main restructuring targets:
   - `lib/features/landing/collect_landing_page.dart`, reduced from about 4.3k lines to about 3.3k lines by extracting public route/content data.
   - `lib/shared/widgets/collect_components.dart`, reduced from about 3.8k lines to about 3.7k lines by extracting input components.
   - `lib/features/status/production_state_screens.dart`, reduced from about 3.0k lines to about 2.9k lines by extracting onboarding/legal/auth-result screens.
   - `lib/admin/core/admin_runtime.dart` at about 1.8k lines.
   - `lib/shared/repositories/collect_repository.dart` at about 1.2k lines.
3. Documentation and evidence are heavy: `docs/design` and `docs/release` contain about 84 files combined. They are useful for audit history, but the active repo should keep only current product, architecture, operation, and release decision docs in the main docs tree. Historical evidence should move to an archive/export outside the production source repo once approved.
4. Script count is high at 67. Many are active release gates, but scripts should be grouped by purpose and retired when superseded:
   - `scripts/release/*`
   - `scripts/supabase/*`
   - `scripts/android/*`
   - `scripts/admin/*`
   - `scripts/public/*`
   - `scripts/design/*`
5. Ignored local output dominates disk usage, not tracked code: `.cache` is about 14 GB and `build` is about 5.5 GB. These should stay ignored and out of tests. Local cleanup can remove them when fresh evidence is not needed.
6. The security hygiene test scanned ignored output folders; this has been narrowed so source validation remains fast and relevant.

## Target Structure

```text
lib/
  app/
    app.dart
    router.dart
    env/
    theme/
  core/
    notifications/
    security/
    supabase/
    utils/
    widgets/
  features/
    auth/
      presentation/
    collections/
      application/
      presentation/
    home/
      presentation/
    landing/
      data/
      presentation/
    ledger/
      presentation/
    payments/
      application/
      presentation/
    profile/
      presentation/
    settings/
      presentation/
    status/
      presentation/
  shared/
    models/
    repositories/
    widgets/
admin/
  keep under lib/admin until a package split is justified.
```

This is a staged migration target, not a one-shot move. The repo should keep current imports working after each step.

## Refactoring Plan

1. Stabilize source gates.
   - Keep `flutter analyze --no-pub`, focused security tests, route contract tests, and render smoke scripts as the minimum proof layer.
   - Keep ignored output out of source scanners.

2. Split oversized presentation files.
   - Break `collect_landing_page.dart` into route/page data, section widgets, shared public website components, and page shell.
   - Break `collect_components.dart` by component family: buttons/actions, cards, visual assets, empty/error states, and forms.
   - Break `production_state_screens.dart` by route group: permissions, offline/sync, share recovery, payment support, readiness.

3. Introduce feature-local presentation/application boundaries.
   - Move business decisions out of widget `build()` methods into small view-model/state helpers where there is real branching.
   - Preserve Riverpod as the DI/state pattern; do not add another state framework.
   - Keep `CollectRepository` as the existing data source first, then split only by proven domain seams such as collections, payments, profile, notifications, and admin.

4. Consolidate design-system ownership.
   - Treat `lib/app/theme/*` plus `lib/shared/widgets/*` as the source of truth.
   - Replace one-off repeated styling inside feature screens with named tokens/components.
   - Keep dark mode, large text, reduced motion, and minimum target size checks in widget tests or render smoke where practical.

5. Restructure scripts after code modules stabilize.
   - Move scripts into purpose folders and update Makefile/docs references in the same commit.
   - Remove scripts only after a reference scan and a replacement gate prove they are obsolete.

6. Reduce tracked documentation noise.
   - Keep current docs: README, architecture, environment, database, Supabase operations, privacy/compliance, current release decision, current Play/public website goals.
   - Move historical evidence reports and dated design audits out of the production repo or into a separately approved archive folder.

7. Performance and UI/UX proof.
   - Add route-level journey matrices for mobile, admin, and public website.
   - Use profile/release builds for performance claims.
   - Validate large text, accessible labels, and no clipped/overlapping text on representative mobile and web surfaces.

## Do Not Remove Without Explicit Product Approval

- Supabase migrations: even old migrations are part of forward-only database history.
- Release approval/signoff docs: these are governance artifacts.
- Play Integrity surfaces: implementation exists but live activation is config/deploy gated.
- Native Android/iOS resource density variants: duplicates by hash can still be platform-required.
- Current public website docs/scripts added in the latest baseline.

## Immediate Next Implementation Batch

1. Continue splitting `production_state_screens.dart` by route group: permissions, offline/sync, share recovery, payment support, readiness.
2. Add a route/user-journey manifest test that fails when mobile/admin/public route contracts drift.
3. Continue splitting `collect_components.dart` by component family without changing public widget APIs.
4. Re-run:
   - `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`
   - `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub`
   - `./scripts/repo_wide_qa_uat.sh --json` before release/go-live claims.

## Validation In This Pass

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format ...`: pass.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/landing_page_test.dart test/features/widgets_test.dart test/features/design_system_components_test.dart test/security_hygiene_test.dart`: pass, 73 tests.
