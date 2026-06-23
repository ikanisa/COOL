# COOL Repo Restructure and Cleanup Audit - 2026-06-22

## Current State

- Repo root: `/Volumes/PRO-G40/COOL`
- Flutter toolchain: `/Volumes/PRO-G40/flutter_3_44/bin/flutter`
- Current inventory after the cleanup pass: 153 Dart library files, 15 Dart test files, 75 scripts, 77 docs, 16 Supabase function files, 42 migrations, and 126 native/platform files.
- Active app entrypoints: `lib/main.dart`, `lib/main_admin.dart`, and `lib/main_public.dart`.
- Current active Dart reachability: 152 of 153 `lib/**/*.dart` files are reachable from the three app entrypoints. The remaining file, `lib/core/security/play_integrity_service.dart`, is intentionally retained because tests, native Android, Supabase, and Google Play readiness docs lock the Play Integrity implementation surface.
- Local generated-artifact footprint was reduced from about 21 GB to about 205 MB by removing ignored `.cache`, `.dart_tool`, `build`, `output`, Flutter logs, generated Pods, Android Gradle/build/cache output, iOS Flutter ephemeral files, and temporary browser/build evidence. The remaining local footprint is mostly source files, docs, native project files, and `.git`.

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
- Split public website content data from `lib/features/landing/public_content.dart` into focused content parts.
  - Moved route/page catalogue data, `publicWebsitePaths`, `publicPageForPath`, and page summary labels into `lib/features/landing/public_page_content.dart`.
  - Moved infographic workflow titles, body copy, background colors, and step metadata into `lib/features/landing/public_infographic_content.dart`.
  - Kept `public_content.dart` as the public library shell used by `main_public.dart`, admin routing, landing rendering, and public website tests.
- Split public page catalogue content from `lib/features/landing/public_page_content.dart` into focused public-content parts.
  - Moved marketing, product, impact, and partner page data into `lib/features/landing/public_marketing_page_content.dart`.
  - Moved privacy, account deletion, data deletion, and terms page data into `lib/features/landing/public_policy_page_content.dart`.
  - Kept `public_page_content.dart` focused on the route registry, public page models, lookup helper, and summary-label mapping.
- Extracted input/form components from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_inputs.dart`.
  - Moved `OtpCodeField`, `CollectTextInput`, `SearchWithClearField`, and `collectInputDecoration`.
  - `collect_components.dart` re-exports `collect_inputs.dart` to avoid churn across feature imports.
- Extracted shared UI foundation components from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_foundation.dart`.
  - Moved `CollectButton`, `CollectButtonVariant`, `collectionTypeIcon`, `CollectionTypeBadge`, `CollectCard`, and `CollectCardEmphasis`.
  - `collect_components.dart` re-exports `collect_foundation.dart` so existing feature imports remain stable.
- Extracted action/input control components from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_action_controls.dart`.
  - Moved `BottomActionSurface`, `CollectMomoReceiverMode`, `CollectMomoReceiverModeToggle`, and `CollectMobileInputField`.
  - `collect_components.dart` re-exports `collect_action_controls.dart` so route screens keep their existing imports.
- Split shared chrome and scaffold primitives from `lib/shared/widgets/collect_chrome.dart` into focused library parts.
  - Moved `CollectTopChrome`, top-chrome actions, avatar, search, and brand mark controls into `lib/shared/widgets/collect_top_chrome.dart`.
  - Moved `ScreenHeader`, `CollectPlainPageHeader`, route background scope, `PremiumScaffold`, `ScreenScaffoldLayout`, and back-navigation helper into `lib/shared/widgets/collect_scaffold_chrome.dart`.
  - Kept `collect_chrome.dart` as the public library shell exported by `collect_components.dart`.
- Extracted display primitives from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_display_primitives.dart`.
  - Moved `CollectIdDisplay`, `CollectStatusChip`, `CollectAvatar`, and `SectionHeader`.
  - `collect_components.dart` re-exports `collect_display_primitives.dart` so existing feature imports remain stable.
- Extracted tone/icon primitives from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_tone_icon.dart`.
  - Promoted the repeated status icon and tone icon helper into `collectStatusIcon` and `CollectToneIcon`.
  - `collect_components.dart` re-exports `collect_tone_icon.dart` so shared UI modules use one status-icon implementation.
- Extracted state, loading, and safety panels from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_state_panels.dart`.
  - Moved `MinimalStatePanel`, `EmptySearchState`, `CollectWizardProgress`, `FormSectionCard`, `CollectPermissionRecoveryPanel`, `NotificationUpdateRow`, `CollectEmptyState`, `CollectErrorState`, `LoadingSkeleton`, `LoadingStatePanel`, `CollectBottomSheet`, and `InfoSecurityBanner`.
  - `collect_components.dart` re-exports `collect_state_panels.dart` so existing route imports remain stable.
- Split shared state, feedback, loading, and sheet surfaces from `lib/shared/widgets/collect_state_panels.dart` into focused library parts.
  - Moved minimal/empty visual state panels and generated state asset selection into `lib/shared/widgets/collect_state_visuals.dart`.
  - Moved wizard progress, form section cards, permission recovery, notification rows, and safety banners into `lib/shared/widgets/collect_state_feedback.dart`.
  - Moved empty/error full-screen states, loading skeletons, loading panels, and bottom sheets into `lib/shared/widgets/collect_loading_surfaces.dart`.
  - Kept `collect_state_panels.dart` as the public library shell exported by `collect_components.dart`.
- Split the remaining mixed shared component implementations from `lib/shared/widgets/collect_components.dart` into focused library parts.
  - Moved visual feature cards, compact list tiles, compact data-subtitle selection, and empty illustration states into `lib/shared/widgets/collect_feature_surfaces.dart`.
  - Moved bento grids, bento metric cells, quick-action buttons/rails, and insight cards into `lib/shared/widgets/collect_bento_actions.dart`.
  - Moved segmented filters and clipboard snack-bar helper into `lib/shared/widgets/collect_selection_controls.dart`.
  - Kept `collect_components.dart` as the stable public barrel exported and imported by active route, admin, design-system, and test surfaces.
- Extracted financial, payment, and ledger components from `lib/shared/widgets/collect_components.dart` into `lib/shared/widgets/collect_financial_components.dart`.
  - Moved `MoneyCard`, `AmountHero`, `FinancialListRow`, `AmountEntryPanel`, `PaymentReviewSummary`, `PaymentIntentStatusCard`, `PaymentPipelineIndicator`, `PaymentVerifiedRing`, `LedgerRow`, `ReceiverConsentCard`, `MoneyHeroCard`, `ActivityFeedItem`, payment status label/tone helpers, Collect ID label compaction, and MoMo number masking together.
  - `collect_components.dart` re-exports `collect_financial_components.dart` so payment, ledger, design-catalog, and status screens keep their existing imports.
- Split `lib/shared/widgets/collect_financial_components.dart` into focused financial UI parts.
  - Moved money and amount display widgets into `lib/shared/widgets/collect_financial_money.dart`.
  - Moved payment, receiver consent, status label/tone, pipeline, and MoMo masking widgets/helpers into `lib/shared/widgets/collect_financial_payments.dart`.
  - Moved ledger row and activity feed widgets into `lib/shared/widgets/collect_financial_ledger.dart`.
  - Kept `collect_financial_components.dart` as the public library shell so existing imports and exports remain stable.
- Extracted generated group-card media helpers from `lib/shared/widgets/collect_group_cards.dart` into `lib/shared/widgets/collect_group_card_media.dart`.
  - Moved `_GroupCoverMedia`, generated cover rendering, cover image toning, cover scrim/title overlay, public/privacy glyphs, data-image decoding, generated asset selection, and group accent helpers into a Dart `part` file.
  - Updated the app-shell text contract to read the full group-card library, including the part file, instead of asserting all private helpers live in one physical file.
- Extracted create-group presentation helpers from `lib/features/collections/collection_create_screen.dart` into `lib/features/collections/collection_create_widgets.dart`.
  - Moved `_CreateGroupReview`, `_CollectionTypeGrid`, `_CollectionTypeOption`, `_GroupColorPalette`, `_CreateGroupPhotoRow`, `_MobileCreatePanel`, `_ColorSwatchButton`, `_defaultCategorySubtype`, and `_mimeTypeFromName`.
  - Kept `collection_create_screen.dart` focused on step state, validation, image picking, SMS access gating, repository `createCollection`, and navigation.
- Split collection detail presentation helpers from `lib/features/collections/collection_detail_screen.dart` into focused parts.
  - Moved the group hero card, settings entry, stats card, and metric widgets into `lib/features/collections/collection_detail_hero.dart`.
  - Moved the group action strip, share/deep-link action, and circular action buttons into `lib/features/collections/collection_detail_actions.dart`.
  - Moved the contribution timeline and contribution row rendering into `lib/features/collections/collection_detail_timeline.dart`.
  - Kept `collection_detail_screen.dart` focused on repository state selection, missing-group recovery, route-level section order, bottom contribution action, and detail route composition.
- Split group profile presentation helpers from `lib/features/collections/group_profile_screen.dart` into focused parts.
  - Moved group avatar/image preview, image fade-in, mime-type detection, and provider URL filtering into `lib/features/collections/group_profile_media.dart`.
  - Moved edit sections, cadence/type pickers, group color palette, cadence option model, and default category subtype mapping into `lib/features/collections/group_profile_form_controls.dart`.
  - Kept `group_profile_screen.dart` focused on route state, existing collection loading, image picking, save orchestration, and navigation back to manage view.
- Split home route presentation sections from `lib/features/home/home_screen.dart` into focused home parts.
  - Moved the total-collected hero card and angled background panels into `lib/features/home/home_total_collected_card.dart`.
  - Moved the home action strip and action item buttons into `lib/features/home/home_action_strip.dart`.
  - Moved featured/public group layout and contribution action button into `lib/features/home/home_public_groups_section.dart`.
  - Kept `home_screen.dart` focused on Riverpod state selection, route chrome, route-level section ordering, my-groups rendering, and activity rendering.
- Split auth presentation widgets from `lib/features/auth/widgets/auth_screen_widgets.dart` into focused library parts.
  - Moved brand mark and auth headline rendering into `lib/features/auth/widgets/auth_brand_header.dart`.
  - Moved the auth input panel, WhatsApp phone entry, phone anchor, and authentication notice into `lib/features/auth/widgets/auth_input_panel.dart`.
  - Moved the six-digit OTP entry state machine into `lib/features/auth/widgets/auth_otp_entry.dart`.
  - Moved submit, change-number, and resend dock actions into `lib/features/auth/widgets/auth_action_dock.dart`.
  - Kept `auth_screen_widgets.dart` as the stable library shell imported by `auth_screen.dart`.
- Split lower homepage sections from `lib/features/landing/collect_home_sections.dart` into focused landing parts.
  - Moved insurance, CRaaS, stakeholder sections and product/stakeholder card helpers into `lib/features/landing/collect_home_offer_sections.dart`.
  - Moved audience conversion cards, proof metrics, and audience data into `lib/features/landing/collect_home_audience_metrics.dart`.
  - Moved the customer CTA and IKANISA contact card into `lib/features/landing/collect_home_customer_action.dart`.
  - Moved footer navigation and footer link rendering into `lib/features/landing/collect_home_footer.dart`.
  - Moved WhatsApp/email launchers and customer-action scrolling into `lib/features/landing/collect_home_interactions.dart`.
  - Kept `collect_home_sections.dart` as a small compatibility part included by `collect_landing_page.dart`.
- Split public page route rendering from `lib/features/landing/collect_public_page.dart` into focused landing parts.
  - Moved public page hero, media card, and dark metric rendering into `lib/features/landing/collect_public_page_hero.dart`.
  - Moved public page summary and proof tiles into `lib/features/landing/collect_public_page_summary.dart`.
  - Moved public route infographic rendering and animated step cards into `lib/features/landing/collect_public_page_infographic.dart`.
  - Moved public content sections, section numbers, and policy-aware bullet lists into `lib/features/landing/collect_public_page_sections.dart`.
  - Kept `CollectPublicPage` in `collect_public_page.dart` as the route shell used by public routing and tests.
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
- Split payment status routes from `lib/features/status/payment_status_screens.dart` into focused route groups.
  - Moved MoMo return, waiting, and payment state detail routes into `lib/features/status/payment_return_state_screens.dart`.
  - Moved payment support review and fresh-link request routes into `lib/features/status/payment_support_recovery_screens.dart`.
  - Moved shared status hero, collection lookup, tone-icon, and MoMo USSD helpers into `lib/features/status/payment_status_helpers.dart`.
  - Kept `payment_status_screens.dart` as the public library shell re-exported by `production_state_screens.dart`.
- Extracted the remaining large status route groups from `lib/features/status/production_state_screens.dart`.
  - Moved device, notification, privacy, and support routes into `lib/features/status/device_privacy_screens.dart`.
  - Moved legal, account session, and account deletion routes into `lib/features/status/account_legal_screens.dart`.
  - Moved group member roster/search/filter routes into `lib/features/status/group_members_screen.dart`.
  - `production_state_screens.dart` now re-exports each split file and is down to 255 lines.
- Split device, privacy, notification, and support status routes from `lib/features/status/device_privacy_screens.dart` into focused route parts.
  - Moved permission recovery and app-access permission rows into `lib/features/status/device_permission_screens.dart`.
  - Moved privacy/data presentation into `lib/features/status/device_privacy_data_screen.dart`.
  - Moved notification center, preference rows, and notification update feed into `lib/features/status/device_notification_center.dart`.
  - Moved WhatsApp support safety route into `lib/features/status/device_support_screen.dart`.
  - Kept `device_privacy_screens.dart` as the public library shell re-exported by `production_state_screens.dart`, with the shared native notification enable helper.
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
- Split homepage product-media internals from `lib/features/landing/collect_home_product_media.dart` into focused landing parts.
  - Moved the reusable phone mockup, card, readiness, navigation, ledger, discipline, and floating-panel widgets into `lib/features/landing/collect_home_phone_mockup.dart`.
  - Moved product evidence image, evidence stack rows, and evidence item model into `lib/features/landing/collect_home_evidence_media.dart`.
  - Kept `collect_home_product_media.dart` focused on the public-white product media section composition.
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
   - `lib/features/landing/collect_landing_page.dart`, reduced from about 4.3k lines to 162 lines by extracting public route/content data, public detail-page rendering, homepage hero/navigation, access/trust sections, homepage product-media rendering, lower homepage section/CTA/footer rendering, and shared landing primitives.
   - `lib/features/landing/public_content.dart`, reduced from 907 lines to 8 lines by splitting public page catalogue data and public infographic metadata into focused part files.
   - `lib/features/landing/public_page_content.dart`, reduced from 629 lines to 93 lines by splitting marketing/product pages and policy/legal pages into focused public-content part files.
   - `lib/features/landing/collect_home_product_media.dart`, reduced from 615 lines to 37 lines by splitting phone mockup/floating panels and evidence-pack media into focused landing part files.
   - `lib/features/landing/collect_home_sections.dart`, reduced from 713 lines to 1 line by splitting lower homepage offer, audience/proof, CTA/contact, footer, and interaction helpers into focused landing part files.
   - `lib/features/landing/collect_public_page.dart`, reduced from 680 lines to 28 lines by splitting public hero/media, summary/proof, infographic, and public content sections into focused landing part files.
   - `lib/shared/widgets/collect_components.dart`, reduced from about 3.8k lines to 30 lines by extracting input, foundation, action-control, display primitive, tone-icon, state/loading panel, financial/payment/ledger, feature-surface, bento/action, and selection-control components and deleting unused component definitions.
   - `lib/shared/widgets/collect_chrome.dart`, reduced from 715 lines to 11 lines by splitting top chrome controls and scaffold/background primitives into focused part files.
   - `lib/shared/widgets/collect_state_panels.dart`, reduced from 698 lines to 18 lines by splitting visual state panels, feedback surfaces, loading surfaces, and bottom sheets into focused part files.
   - `lib/shared/widgets/collect_financial_components.dart`, reduced from 1,163 lines to 22 lines by splitting money, payment, and ledger/activity widgets into focused part files.
   - `lib/shared/widgets/collect_group_cards.dart`, reduced from 896 lines to 527 lines by extracting generated cover/media/glyph helpers into `collect_group_card_media.dart`.
   - `lib/features/collections/collection_create_screen.dart`, reduced from 812 lines to 394 lines by extracting create-group presentation helpers into `collection_create_widgets.dart`.
   - `lib/features/collections/collection_detail_screen.dart`, reduced from 583 lines to 71 lines by splitting hero/stats, action strip, and contribution timeline rendering into focused part files.
   - `lib/features/collections/group_profile_screen.dart`, reduced from 607 lines to 242 lines by splitting profile media/image helpers and profile form controls into focused part files.
   - `lib/features/home/home_screen.dart`, reduced from 600 lines to 128 lines by splitting the total-collected hero, action strip, and public-group section into focused part files.
   - `lib/features/auth/widgets/auth_screen_widgets.dart`, reduced from 689 lines to 12 lines by splitting brand/headline, phone/input/notice, OTP digit entry, and action dock widgets into focused part files.
   - `lib/features/status/payment_status_screens.dart`, reduced from 735 lines to 17 lines by splitting payment return/state routes, support/recovery routes, and shared helpers into focused part files.
   - `lib/features/status/device_privacy_screens.dart`, reduced from 657 lines to 35 lines by splitting permission recovery/access, privacy/data, notification center, and support routes into focused part files.
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

1. Continue reducing active 500+ line feature screens without changing route contracts: `account_legal_screens.dart`, `group_members_screen.dart`, `group_qr_scanner_screen.dart`, and `ledger_screen.dart`.
2. Split the largest remaining data/presentation modules by stable domain boundaries: `collect_financial_money.dart`, `collect_group_cards.dart`, and the admin login/list/detail runtime parts.
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
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/status/device_privacy_screens.dart lib/features/status/device_permission_screens.dart lib/features/status/device_privacy_data_screen.dart lib/features/status/device_notification_center.dart lib/features/status/device_support_screen.dart test/app_shell_test.dart`: pass after device/privacy route split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for device/privacy route split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after device/privacy route split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/app_shell_test.dart`: pass, 32 tests after device/privacy route split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after device/privacy route split.
- Ruby Dart import/export/part reachability scan: pass, 140 of 141 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/landing/public_content.dart lib/features/landing/public_page_content.dart lib/features/landing/public_marketing_page_content.dart lib/features/landing/public_policy_page_content.dart`: pass after public page content split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for public page content split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after public page content split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after public page content split.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after public page content split.
- Ruby Dart import/export/part reachability scan: pass, 142 of 143 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after public page content split and audit update.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/landing/collect_landing_page.dart lib/features/landing/collect_home_product_media.dart lib/features/landing/collect_home_phone_mockup.dart lib/features/landing/collect_home_evidence_media.dart`: pass after homepage product-media internals split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for homepage product-media internals split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after homepage product-media internals split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after homepage product-media internals split.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after homepage product-media internals split.
- Ruby Dart import/export/part reachability scan: pass, 144 of 145 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after homepage product-media internals split and audit update.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/collections/group_profile_screen.dart lib/features/collections/group_profile_media.dart lib/features/collections/group_profile_form_controls.dart`: pass after group profile presentation split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for group profile presentation split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after group profile presentation split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/features/widgets_test.dart test/visual_evidence_capture_test.dart`: pass, 27 tests with one expected visual-evidence skip after group profile presentation split.
- Ruby Dart import/export/part reachability scan: pass, 146 of 147 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after group profile presentation split and audit update.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/home/home_screen.dart lib/features/home/home_action_strip.dart lib/features/home/home_public_groups_section.dart lib/features/home/home_total_collected_card.dart test/app_shell_test.dart`: pass after home route section split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for home route section split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after home route section split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/app_shell_test.dart`: pass, 32 tests after home route section split.
- Ruby Dart import/export/part reachability scan: pass, 149 of 150 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after home route section split and audit update.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/collections/collection_detail_screen.dart lib/features/collections/collection_detail_hero.dart lib/features/collections/collection_detail_actions.dart lib/features/collections/collection_detail_timeline.dart`: pass after collection detail presentation split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for collection detail presentation split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after collection detail presentation split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/features/widgets_test.dart test/visual_evidence_capture_test.dart test/app_shell_test.dart`: pass, 43 tests with one expected visual-evidence skip after collection detail presentation split.
- Ruby Dart import/export/part reachability scan: pass, 152 of 153 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after collection detail presentation split and audit update.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after final cleanup edits.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart`: pass, 41 tests after tone-icon and state/loading panel extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after tone-icon and state/loading panel extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after tone-icon and state/loading panel extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after tone-icon and state/loading panel extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/shared/widgets/collect_components.dart lib/shared/widgets/collect_feature_surfaces.dart lib/shared/widgets/collect_bento_actions.dart lib/shared/widgets/collect_selection_controls.dart`: pass after remaining shared component split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for remaining shared component split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after remaining shared component split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart test/features/mobile_completion_test.dart test/app_shell_test.dart`: pass, 73 tests after remaining shared component split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after remaining shared component split.
- Ruby Dart import/export/part reachability scan: pass, 123 of 124 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/auth/widgets/auth_screen_widgets.dart lib/features/auth/widgets/auth_brand_header.dart lib/features/auth/widgets/auth_input_panel.dart lib/features/auth/widgets/auth_otp_entry.dart lib/features/auth/widgets/auth_action_dock.dart`: pass after auth widget split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for auth widget split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after auth widget split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/app_shell_test.dart`: pass, 32 tests after auth widget split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after auth widget split.
- Ruby Dart import/export/part reachability scan: pass, 127 of 128 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/landing/collect_landing_page.dart lib/features/landing/collect_home_sections.dart lib/features/landing/collect_home_offer_sections.dart lib/features/landing/collect_home_audience_metrics.dart lib/features/landing/collect_home_customer_action.dart lib/features/landing/collect_home_footer.dart lib/features/landing/collect_home_interactions.dart`: pass after lower homepage section split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for lower homepage section split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after lower homepage section split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after lower homepage section split.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after lower homepage section split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after lower homepage section split.
- Ruby Dart import/export/part reachability scan: pass, 132 of 133 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/landing/collect_landing_page.dart lib/features/landing/collect_public_page.dart lib/features/landing/collect_public_page_hero.dart lib/features/landing/collect_public_page_summary.dart lib/features/landing/collect_public_page_infographic.dart lib/features/landing/collect_public_page_sections.dart`: pass after public page route-rendering split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for public page route-rendering split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after public page route-rendering split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after public page route-rendering split.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after public page route-rendering split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after public page route-rendering split.
- Ruby Dart import/export/part reachability scan: pass, 136 of 137 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/shared/widgets/collect_components.dart lib/shared/widgets/collect_financial_components.dart`: pass after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart`: pass, 41 tests after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 32 tests with one expected visual-evidence skip after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after financial component extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for group-card media extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/shared/widgets/collect_group_cards.dart lib/shared/widgets/collect_group_card_media.dart test/app_shell_test.dart`: pass after group-card media extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after group-card media extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/widgets_test.dart test/app_shell_test.dart`: pass, 27 tests after group-card media extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after group-card media extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after create-group presentation extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/features/widgets_test.dart test/app_shell_test.dart`: pass, 43 tests after create-group presentation extraction.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after create-group presentation extraction.
- Ruby Dart import/export/part reachability scan: pass, 107 of 108 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for financial part split.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/shared/widgets/collect_financial_components.dart lib/shared/widgets/collect_financial_money.dart lib/shared/widgets/collect_financial_payments.dart lib/shared/widgets/collect_financial_ledger.dart`: pass after financial part split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after financial part split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart test/features/mobile_completion_test.dart`: pass, 57 tests after financial part split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after financial part split.
- Ruby Dart import/export/part reachability scan: pass, 110 of 111 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for public content part split.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/landing/public_content.dart lib/features/landing/public_page_content.dart lib/features/landing/public_infographic_content.dart`: pass after public content part split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after public content part split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/landing_page_test.dart`: pass, 7 tests after public content part split.
- `bash scripts/public_landing_prepare_build.sh && ./scripts/public_website_quality_gate.sh --json`: pass, 34/34 static public website checks after public content part split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after public content part split.
- Ruby Dart import/export/part reachability scan: pass, 112 of 113 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/shared/widgets/collect_chrome.dart lib/shared/widgets/collect_top_chrome.dart lib/shared/widgets/collect_scaffold_chrome.dart test/app_shell_test.dart`: pass after shared chrome/scaffold split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for shared chrome/scaffold split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after shared chrome/scaffold split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/design_system_components_test.dart test/features/mobile_completion_test.dart`: pass, 62 tests after shared chrome/scaffold split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after shared chrome/scaffold split.
- Ruby Dart import/export/part reachability scan: pass, 114 of 115 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/features/status/payment_status_screens.dart lib/features/status/payment_return_state_screens.dart lib/features/status/payment_support_recovery_screens.dart lib/features/status/payment_status_helpers.dart`: pass after payment status route split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for payment status route split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after payment status route split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/features/widgets_test.dart test/visual_evidence_capture_test.dart`: pass, 27 tests with one expected visual-evidence skip after payment status route split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after payment status route split.
- Ruby Dart import/export/part reachability scan: pass, 117 of 118 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
- `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/shared/widgets/collect_state_panels.dart lib/shared/widgets/collect_state_visuals.dart lib/shared/widgets/collect_state_feedback.dart lib/shared/widgets/collect_loading_surfaces.dart`: pass after shared state-panel split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`: pass before validation after generated package resolution cleanup for shared state-panel split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass after shared state-panel split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart test/features/mobile_completion_test.dart test/visual_evidence_capture_test.dart`: pass, 57 tests with one expected visual-evidence skip after shared state-panel split.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart`: pass, 59 tests after shared state-panel split.
- Ruby Dart import/export/part reachability scan: pass, 120 of 121 `lib/**/*.dart` files reachable from app entrypoints, with only `lib/core/security/play_integrity_service.dart` intentionally retained outside direct Dart entrypoint reachability.
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
