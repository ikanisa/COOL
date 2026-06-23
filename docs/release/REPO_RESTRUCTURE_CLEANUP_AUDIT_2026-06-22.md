# COOL Repo Restructure and Cleanup Audit - 2026-06-22

## Current State

- Repo root: `/Volumes/PRO-G40/COOL`
- Flutter toolchain: `/Volumes/PRO-G40/flutter_3_44/bin/flutter`
- Current inventory after the cleanup pass: 106 Dart library files, 15 Dart test files, 75 scripts, 77 docs, 15 Supabase function files, 42 migrations, and 120 native/platform files.
- Active app entrypoints: `lib/main.dart`, `lib/main_admin.dart`, and `lib/main_public.dart`.
- Current active Dart reachability: 105 of 106 `lib/**/*.dart` files are reachable from the three app entrypoints. The remaining file, `lib/core/security/play_integrity_service.dart`, is intentionally retained because tests, native Android, Supabase, and Google Play readiness docs lock the Play Integrity implementation surface.
- Local generated-artifact footprint was reduced from about 21 GB to about 237 MB by removing ignored `.cache`, `.dart_tool`, `build`, `output`, Flutter logs, generated Pods, Android Gradle/build/cache output, iOS Flutter ephemeral files, and temporary browser/build evidence. The remaining local footprint is mostly source files, docs, native project files, and `.git`.

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
- Extracted shared UI foundation components from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_foundation.dart`.
  - Moved `CollectButton`, `CollectButtonVariant`, `collectionTypeIcon`, `CollectionTypeBadge`, `CollectCard`, and `CollectCardEmphasis`.
  - `collect_components.dart` re-exports `collect_foundation.dart` so existing feature imports remain stable.
- Extracted action/input control components from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_action_controls.dart`.
  - Moved `BottomActionSurface`, `CollectMomoReceiverMode`, `CollectMomoReceiverModeToggle`, and `CollectMobileInputField`.
  - `collect_components.dart` re-exports `collect_action_controls.dart` so route screens keep their existing imports.
- Extracted display primitives from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_display_primitives.dart`.
  - Moved `CollectIdDisplay`, `CollectStatusChip`, `CollectAvatar`, and `SectionHeader`.
  - `collect_components.dart` re-exports `collect_display_primitives.dart` so existing feature imports remain stable.
- Extracted tone/icon primitives from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_tone_icon.dart`.
  - Promoted the repeated status icon and tone icon helper into `collectStatusIcon` and `CollectToneIcon`.
  - `collect_components.dart` re-exports `collect_tone_icon.dart` so shared UI modules use one status-icon implementation.
- Extracted state, loading, and safety panels from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_state_panels.dart`.
  - Moved `MinimalStatePanel`, `EmptySearchState`, `CollectWizardProgress`, `FormSectionCard`, `CollectPermissionRecoveryPanel`, `NotificationUpdateRow`, `CollectEmptyState`, `CollectErrorState`, `LoadingSkeleton`, `LoadingStatePanel`, `CollectBottomSheet`, and `InfoSecurityBanner`.
  - `collect_components.dart` re-exports `collect_state_panels.dart` so existing route imports remain stable.
- Extracted financial, payment, and ledger components from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_financial_components.dart`.
  - Moved `MoneyCard`, `AmountHero`, `FinancialListRow`, `AmountEntryPanel`, `PaymentReviewSummary`, `PaymentIntentStatusCard`, `PaymentPipelineIndicator`, `PaymentVerifiedRing`, `LedgerRow`, `ReceiverConsentCard`, `MoneyHeroCard`, `ActivityFeedItem`, payment status label/tone helpers, Collect ID label compaction, and MoMo number masking together.
  - `collect_components.dart` re-exports `collect_financial_components.dart` so payment, ledger, design-catalog, and status screens keep their existing imports.
- Extracted onboarding/legal/auth-result status screens from `lib/features/status/production_state_screens.dart` into `lib/features/status/onboarding_status_screens.dart`.
  - Moved `OnboardingScreen`, `LegalConsentScreen`, `AuthResultScreen`, and their onboarding step-list helper together.
  - `production_state_screens.dart` re-exports `onboarding_status_screens.dart` to keep router imports stable.
- Removed dead shared component definitions from `lib/shared/widgets/collect_components.dart`.
  - Removed `CollectConfirmationDialog`, `CollectProgressBar`, `CollectAvatarStack`, `ActivityRow`, `CollectSearchField`, `CollectDynamicIsland`, `AdminReviewCard`, and `SecurityNotice`.
  - These widgets had no app or test references; stale design docs were updated so the catalog reflects the active component API.
  - This reduced `collect_components.dart` by 444 lines without changing route behavior.
- Extracted access-state screens from `lib/features/status/production_state_screens.dart` into `lib/features/status/access_state_screens.dart`.
  - Moved `SmsPermissionDeniedScreen`, `IphoneCreateUnavailableScreen`, `OfflineStateScreen`, and `SyncStatusScreen`.
  - Replaced private helper coupling with public shared components so the extracted file is self-contained.
  - `production_state_screens.dart` re-exports `access_state_screens.dart` to keep router imports stable.
- Extracted payment and MoMo status screens from `lib/features/status/production_state_screens.dart` into `lib/features/status/payment_status_screens.dart`.
  - Moved `ReturnFromMomoWaitingScreen`, `PaymentStateDetailScreen`, `PaymentSupportReviewScreen`, `FreshLinkRequestScreen`, and their payment-only helpers.
  - `production_state_screens.dart` re-exports `payment_status_screens.dart` so existing route imports remain stable.
  - This reduced `production_state_screens.dart` to about 1.9k lines.
- Extracted the remaining large status route groups from `lib/features/status/production_state_screens.dart`.
  - Moved device, notification, privacy, and support routes into `lib/features/status/device_privacy_screens.dart`.
  - Moved legal, account session, and account deletion routes into `lib/features/status/account_legal_screens.dart`.
  - Moved group member roster/search/filter routes into `lib/features/status/group_members_screen.dart`.
  - `production_state_screens.dart` now re-exports each split file and is down to 255 lines.
- Split `lib/admin/core/admin_runtime.dart` into focused admin runtime parts.
  - Moved the admin login page and login-only input/status/error widgets into `lib/admin/core/admin_login_runtime.dart`.
  - Moved admin list paging, queue summaries, list specs, and row actions into `lib/admin/core/admin_list_runtime.dart`.
  - Moved admin detail pages, SMS reveal panel, detail field specs, safe detail formatting, and reparse detail action into `lib/admin/core/admin_detail_runtime.dart`.
  - Kept providers, realtime invalidation subscription, Supabase-backed `AdminRepository`, denied page, and overview composition in `admin_runtime.dart`.
  - Used Dart `part` files to preserve the current library-private helper boundary without route/import churn.
- Split `lib/shared/repositories/collect_repository.dart` into focused repository library parts.
  - Moved Riverpod repository providers, derived collection summary providers, and contribution/profile ownership matching into `lib/shared/repositories/collect_repository_providers.dart`.
  - Moved `CollectState` into `lib/shared/repositories/collect_repository_state.dart`.
  - Moved seeded local fixture data and empty-state construction into `lib/shared/repositories/collect_repository_fixture.dart`.
  - Moved live Supabase read-side hydration into `lib/shared/repositories/collect_repository_live_reader.dart`.
  - Kept `CollectRepository` as the public write/workflow API for auth, profile updates, group creation, payments, SMS access, realtime sync, member lookup, and owner health.
  - Updated repository text-contract tests to read the full repository library instead of one physical file.
- Split public website page rendering from `lib/features/landing/collect_landing_page.dart`.
  - Moved `CollectPublicPage`, public page hero/media/summary/infographic/content sections, proof tiles, and bullet helpers into `lib/features/landing/collect_public_page.dart`.
  - Kept `collect_landing_page.dart` as the landing-library entrypoint and main homepage renderer.
  - Used a Dart `part` file so private shared landing components such as navigation, buttons, section bands, CTA, and footer remain reusable without import churn.
  - Restored public privacy email contact and source-backed impact/partner metrics required by the public website content tests.
- Split homepage hero and navigation rendering from `lib/features/landing/collect_landing_page.dart`.
  - Moved `_LandingHero`, navigation links, compact public links, CTA button primitive, hero copy/flow, and hero product visual into `lib/features/landing/collect_home_hero.dart`.
  - Kept the private `_LandingButton` API available to public pages and lower CTA sections through the landing library part boundary.
  - Used a Dart `part` file to preserve private helper access without route/import churn.
- Split homepage product-media rendering from `lib/features/landing/collect_landing_page.dart`.
  - Moved `_ProductMediaSection`, phone mockup widgets, floating ledger/discipline panels, media proof visual, evidence stack rows, and the private evidence item model into `lib/features/landing/collect_home_product_media.dart`.
  - Kept shared landing primitives such as `_SectionBand`, `_SectionIntro`, navigation, and route assembly in `collect_landing_page.dart` because multiple remaining homepage and public sections still use them.
  - Used a Dart `part` file to preserve private helper access without route/import churn.
- Split lower homepage sections and public CTA/footer rendering from `lib/features/landing/collect_landing_page.dart`.
  - Moved `_InsuranceSection`, `_CraasSection`, `_StakeholderSection`, `_CustomerActionSection`, `_LandingFooter`, audience/proof/product/contact cards, and their private data models into `lib/features/landing/collect_home_sections.dart`.
  - Kept `collect_landing_page.dart` focused on top-level route assembly, app-access, trust-proof, and shared section primitives.
  - Used a Dart `part` file to preserve private helper access without route/import churn.
- Split homepage access, USSD, and trust-proof rendering from `lib/features/landing/collect_landing_page.dart`.
  - Moved `_AudienceConversionSection`, `_AppAccessSection`, `_UssdCommandVisual`, `_PhoneKey`, and `_TrustProofSection` into `lib/features/landing/collect_home_access_trust.dart`.
  - Kept public WhatsApp/USSD behavior unchanged through existing private constants and helper functions.
  - Used a Dart `part` file to preserve private helper access without route/import churn.
- Split shared landing section primitives from `lib/features/landing/collect_landing_page.dart`.
  - Moved `_SectionBand`, `_SplitSection`, `_SectionIntro`, `_StepRail`, and `_StepTile` into `lib/features/landing/collect_landing_primitives.dart`.
  - `collect_landing_page.dart` is now the landing-library shell: imports, part declarations, constants, and top-level `CollectLandingPage` route assembly.
- Narrowed the repository text secret scan in `test/security_hygiene_test.dart` so ignored generated folders are skipped.
  - Skips `.cache`, `output`, `release-evidence`, and `evidence-packs` in addition to existing generated roots.
- Removed stale generated output from the working tree:
  - `.cache/`
  - `build/`
  - `output/`
  - `.dart_tool/` before validation, then removed again after validation
  - Flutter log files and `.DS_Store` files
  - generated Android Gradle/build/cache output, generated iOS Pods, and ephemeral Flutter files
  - untracked stale build checksum and public website screenshot evidence from `docs/release`

## Findings

1. The repo does not have a large active-code dead-file problem after the latest baseline cleanup. The remaining issue is structural concentration: several files are too large and mix routing, presentation composition, state rendering, and reusable components.
2. The largest Dart files are the main restructuring targets:
   - `lib/features/landing/collect_landing_page.dart`, reduced from about 4.3k lines to 153 lines by extracting public route/content data, public detail-page rendering, homepage hero/navigation, access/trust sections, homepage product-media rendering, lower homepage section/CTA/footer rendering, and shared landing primitives.
   - `lib/shared/widgets/collect_components.dart`, reduced from about 3.8k lines to 667 lines by extracting input, foundation, action-control, display primitive, tone-icon, state/loading panel, and financial/payment/ledger components and deleting unused component definitions.
   - `lib/features/status/production_state_screens.dart`, reduced from about 3.0k lines to 255 lines by extracting onboarding/legal/auth-result, access-state, payment-status, device/privacy, account/legal, and member roster screens.
   - `lib/admin/core/admin_runtime.dart`, reduced from about 1.8k lines to 276 lines by extracting login, list-runtime, and detail-runtime parts.
   - `lib/shared/repositories/collect_repository.dart`, reduced from about 1.2k lines to 792 lines by extracting providers, state, fixture data, and live Supabase read-side hydration.
3. Documentation and evidence are heavy: `docs/design` and `docs/release` contain 61 files combined. They are useful for audit history, but the active repo should keep only current product, architecture, operation, and release decision docs in the main docs tree. Historical evidence should move to an archive/export outside the production source repo once approved.
4. Script count is high at 75. Many are active release gates, but scripts should be grouped by purpose and retired when superseded:
   - `scripts/release/*`
   - `scripts/supabase/*`
   - `scripts/android/*`
   - `scripts/admin/*`
   - `scripts/public/*`
   - `scripts/design/*`
5. Ignored local output, not tracked code, was the disk-growth problem: prior `.cache` and `build` output accounted for most of the footprint. These folders should stay ignored and out of tests; local cleanup should remove them whenever fresh evidence is not needed.
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

1. Continue splitting `collect_components.dart` by component family without changing public widget APIs.
2. Continue reducing `lib/features/landing/collect_landing_page.dart` by extracting homepage section widgets and presentation-only public website components.
3. Add or extend a route/user-journey manifest test that fails when mobile/admin/public route contracts drift.
4. Re-run:
   - `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`
   - `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub`
   - `./scripts/repo_wide_qa_uat.sh --json` before release/go-live claims.

## Validation In This Pass

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format ...`: pass.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/landing_page_test.dart test/features/widgets_test.dart test/features/design_system_components_test.dart test/security_hygiene_test.dart`: pass, 73 tests.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart`: pass, 41 tests after dead component removal.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after access-state extraction.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after regenerating `build/public_web`.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after release/evidence cleanup.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after final cleanup edits.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart`: pass, 41 tests after tone-icon and state/loading panel extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after tone-icon and state/loading panel extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after tone-icon and state/loading panel extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after tone-icon and state/loading panel extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/shared/widgets/collect_components.dart lib/shared/widgets/collect_financial_components.dart`: pass after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart`: pass, 41 tests after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after admin runtime part-file extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/admin_pwa_test.dart`: pass, 22 tests after admin runtime part-file extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/supabase_contract_test.dart`: pass, 38 tests after admin runtime part-file extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after admin runtime part-file extraction and generated native-artifact cleanup.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after repository provider/state/fixture/live-reader extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/shared/collect_repository_test.dart test/supabase_contract_test.dart`: pass, 53 tests after repository provider/state/fixture/live-reader extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/features/widgets_test.dart`: pass, 27 tests after repository provider/state/fixture/live-reader extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after repository provider/state/fixture/live-reader extraction and security contract update.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after public detail-page renderer extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after public detail-page renderer extraction and public content restoration.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after public detail-page renderer extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after public detail-page renderer extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after homepage product-media part extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after homepage product-media part extraction.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after homepage product-media part extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after homepage product-media part extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/landing/collect_landing_page.dart lib/features/landing/collect_home_sections.dart lib/features/landing/collect_home_product_media.dart lib/features/landing/collect_public_page.dart`: pass after lower homepage section extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after lower homepage section extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after lower homepage section extraction.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after lower homepage section extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after lower homepage section extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for the hero/navigation extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/landing/collect_landing_page.dart lib/features/landing/collect_home_hero.dart lib/features/landing/collect_home_sections.dart lib/features/landing/collect_home_product_media.dart lib/features/landing/collect_public_page.dart`: pass after homepage hero/navigation extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after homepage hero/navigation extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after homepage hero/navigation extraction.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after homepage hero/navigation extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after homepage hero/navigation extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for access/trust and primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/landing/collect_landing_page.dart lib/features/landing/collect_home_access_trust.dart lib/features/landing/collect_landing_primitives.dart lib/features/landing/collect_home_hero.dart lib/features/landing/collect_home_sections.dart lib/features/landing/collect_home_product_media.dart lib/features/landing/collect_public_page.dart`: pass after access/trust and primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after access/trust and primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after access/trust and primitive extraction.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after access/trust and primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after access/trust and primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after payment-status extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after payment-status extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after full status-module extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after shared foundation/action-control extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart`: pass, 41 tests after shared foundation/action-control extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after shared foundation/action-control extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after shared foundation/action-control extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after shared display primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart`: pass, 41 tests after shared display primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after shared display primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after shared display primitive extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after tone-icon and state/loading panel extraction.
