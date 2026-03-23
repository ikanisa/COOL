# Repo Fullstack Audit

_Generated from the local repository on 2026-03-22._

## Scope

This report inventories the implemented application surface directly from the repo: app bootstrap, routes, feature modules, screens, shared UI, assets, backend surfaces, and supporting web/deeplink layers.

Primary source files used for cross-checking: `lib/main.dart`, `lib/app.dart`, `lib/core/router/app_router.dart`, `docs/ROUTE_INVENTORY.md`, `docs/SCREEN_BUDGETS.md`, `pubspec.yaml`, `lib/features/**`, `lib/shared/widgets`, `lib/core/**`, and `supabase/**`.

## Executive Summary

- Router inventory currently exposes `77` GoRoute declarations across `4` shell branches and `79` route-to-screen targets in `docs/ROUTE_INVENTORY.md`.
- Implemented app screen files identified for the runtime surface: `59`. Routed screen files: `57`. Implemented but not GoRouter-addressable feature screens: `2` (`momo_nfc_screen.dart` and `kyc_id_scan_screen.dart`).
- Feature modules under `lib/features/`: `9` major domains with the heaviest surface area in `partners` (`28` screen files) and `admin` (`19` screen files).
- Shared UI layer under `lib/shared/widgets/`: `56` widget files. Core service layer under `lib/core/services/`: `23` service files.
- Backend surface under `supabase/`: `49` function-related files and `115` SQL migrations, plus config/seed files.
- Static support surfaces exist in `hosting/`, `landing/`, and `deeplinks/`, meaning the repo ships both app runtime code and public web/link entrypoints.

## Runtime Stack

- `flutter_riverpod` for state management
- `go_router` for route orchestration
- `supabase_flutter` for backend auth/data/function access
- `firebase_core`, `firebase_messaging`, `firebase_crashlytics`, `firebase_remote_config`, `firebase_performance`, and `firebase_app_check` for observability, messaging, config, and attestation
- `hive_flutter` for local storage and preference persistence
- `dio` for HTTP networking
- `google_maps_flutter`, `geolocator`, and `permission_handler` for mapping and location
- `mobile_scanner`, `qr_flutter`, `camera`, `image_picker`, and `flutter_nfc_kit` for scan/capture/NFC flows
- `pdf`, `syncfusion_flutter_xlsio`, and `file_saver` for statement/export generation
- `google_fonts` and `flutter_svg` for typography and vector asset rendering

## Root Structure

- `lib/`: Flutter application runtime: app bootstrap, router, theme, features, shared widgets, and core services.
- `assets/`: Bundled runtime assets: partner logos, app icons, vehicle icons, and font files declared in `pubspec.yaml`.
- `supabase/`: Backend contract surface: edge functions, SQL migrations, config, and seed scripts.
- `android/` and `ios/`: Native shells and platform integration for the Flutter app.
- `hosting/` and `landing/`: Static web surfaces for legal/account-deletion pages and a separate landing surface.
- `deeplinks/`: Universal link / app link web surface and metadata for install/deeplink flows.
- `test/` and `integration_test/`: Widget, docs-sync, regression, and integration coverage.
- `tool/` and `scripts/`: Repo tooling, generators, and operational helper scripts.

## Feature Module Summary

| Feature | Screens | Widgets | Providers | Repositories | Services | Models | Controllers |
|---|---:|---:|---:|---:|---:|---:|---:|
| `admin` | `19` | `10` | `5` | `4` | `0` | `4` | `1` |
| `auth` | `6` | `0` | `1` | `1` | `0` | `2` | `0` |
| `credit` | `2` | `4` | `2` | `2` | `0` | `4` | `0` |
| `groups` | `5` | `1` | `2` | `1` | `0` | `5` | `0` |
| `home` | `2` | `8` | `3` | `3` | `0` | `3` | `0` |
| `mobility` | `6` | `20` | `7` | `4` | `3` | `8` | `0` |
| `momo` | `3` | `10` | `5` | `4` | `6` | `3` | `1` |
| `partners` | `28` | `22` | `8` | `10` | `1` | `9` | `1` |
| `profile` | `4` | `9` | `1` | `0` | `0` | `0` | `0` |

## App Shell And Cross-Cutting Structure

- Bootstrap entrypoint: `lib/main.dart` initializes Firebase, App Check, Supabase, Hive, portrait lock, Crashlytics, performance tracing, and theme preference hydration before mounting `CoolApp`.
- Root widget: `lib/app.dart` configures `MaterialApp.router`, localization, light/dark themes, and `ThemeSystemChrome` around the GoRouter config.
- Router surface: `lib/core/router/app_redirects.dart`, `lib/core/router/app_router.dart`, `lib/core/router/app_routes.dart`, `lib/core/router/navigation_keys.dart`, `lib/core/router/shell_route.dart`
- Theme surface: `lib/core/theme/app_colors.dart`, `lib/core/theme/app_theme.dart`, `lib/core/theme/app_theme_components.dart`, `lib/core/theme/app_theme_text.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_layout.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`, `lib/core/theme/rs_text_styles.dart`, `lib/core/theme/theme_preference.dart`, `lib/core/theme/theme_preference_provider.dart`, `lib/core/theme/theme_preference_store.dart`, `lib/core/theme/theme_system_chrome.dart`
- Core services: `lib/core/services/app_access_service.dart`, `lib/core/services/app_check_service.dart`, `lib/core/services/app_lifecycle_coordinator.dart`, `lib/core/services/app_review_service.dart`, `lib/core/services/app_session_coordinator.dart`, `lib/core/services/app_update_service.dart`, `lib/core/services/contacts_service.dart`, `lib/core/services/crashlytics_service.dart`, `lib/core/services/deep_link_coordinator.dart`, `lib/core/services/device_settings_service.dart`, `lib/core/services/engagement_tracker.dart`, `lib/core/services/fcm_service.dart`, `lib/core/services/feature_flags_service.dart`, `lib/core/services/firebase_bootstrap_service.dart`, `lib/core/services/hive_runtime.dart`, `lib/core/services/location_service.dart`, `lib/core/services/momo_service.dart`, `lib/core/services/operational_health_service.dart`, `lib/core/services/performance_dio_interceptor.dart`, `lib/core/services/performance_service.dart`, `lib/core/services/screen_security_service.dart`, `lib/core/services/trip_sync_coordinator.dart`, `lib/core/services/whatsapp_contact_service.dart`

## Screen Catalog

The screen catalog below lists every implemented app screen file in the runtime surface, grouped by domain. Routes are taken from `docs/ROUTE_INVENTORY.md`/`app_router.dart`; direct assets are string-literal asset references found in the screen file itself; related files are direct local imports from the screen file.

### Auth And Entry

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/auth/screens/app_access_onboarding_screen.dart` | `AppAccessOnboardingScreen` | `/app-access` (`AppAccessOnboardingScreen`) | Routed | None |
| `lib/features/auth/screens/onboarding_screen.dart` | `OnboardingScreen` | `/onboarding` (`OnboardingScreen`) | Routed | None |
| `lib/features/auth/screens/otp_screen.dart` | `OtpScreen` | `/otp` (`OtpScreen`) | Routed | None |
| `lib/features/auth/screens/otp_verify_screen.dart` | `OtpVerifyScreen` | `/otp-verify` (`OtpVerifyScreen`) | Routed | None |
| `lib/features/auth/screens/register_screen.dart` | `RegisterScreen` | `/register` (`RegisterScreen`) | Routed | None |
| `lib/features/auth/screens/splash_screen.dart` | `SplashScreen` | `/` (`SplashScreen`) | Routed | None |

#### `lib/features/auth/screens/app_access_onboarding_screen.dart`

- Classes: `AppAccessOnboardingScreen`
- Routes: `/app-access` -> `AppAccessOnboardingScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_screen_background.dart`
- Related providers: `lib/core/providers/app_access_provider.dart`
- Related repositories: None
- Related services: `lib/core/services/app_access_service.dart`
- Related models: None
- Shared/core dependencies: `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/auth/screens/onboarding_screen.dart`

- Classes: `OnboardingScreen`
- Routes: `/onboarding` -> `OnboardingScreen`
- Related widgets: `lib/shared/widgets/cool_brand_mark.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_screen_background.dart`
- Related providers: None
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/auth/screens/otp_screen.dart`

- Classes: `OtpScreen`
- Routes: `/otp` -> `OtpScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/core/providers/supported_countries_provider.dart`, `lib/features/auth/providers/auth_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/config/app_market.dart`, `lib/core/config/env_config.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/utils/phone_validator.dart`
- Direct assets: None

#### `lib/features/auth/screens/otp_verify_screen.dart`

- Classes: `OtpVerifyScreen`
- Routes: `/otp-verify` -> `OtpVerifyScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_screen_background.dart`
- Related providers: `lib/core/providers/app_access_provider.dart`, `lib/features/auth/providers/auth_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/config/app_market.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/auth/screens/register_screen.dart`

- Classes: `RegisterScreen`
- Routes: `/register` -> `RegisterScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_text_field.dart`, `lib/shared/widgets/momo_route_type_selector.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/config/app_market.dart`, `lib/core/config/country_catalog.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/utils/phone_validator.dart`
- Direct assets: None

#### `lib/features/auth/screens/splash_screen.dart`

- Classes: `SplashScreen`
- Routes: `/` -> `SplashScreen`
- Related widgets: `lib/shared/widgets/cool_brand_mark.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_screen_background.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### Auth And Entry Module File Inventory

- Screens: `lib/features/auth/screens/app_access_onboarding_screen.dart`, `lib/features/auth/screens/onboarding_screen.dart`, `lib/features/auth/screens/otp_screen.dart`, `lib/features/auth/screens/otp_verify_screen.dart`, `lib/features/auth/screens/register_screen.dart`, `lib/features/auth/screens/splash_screen.dart`
- Providers: `lib/features/auth/providers/auth_provider.dart`
- Repositories: `lib/features/auth/repositories/auth_repository.dart`
- Models: `lib/features/auth/models/face_match_result.dart`, `lib/features/auth/models/user_profile.dart`

### Core Status Screens

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/core/status/screens/cool_tokens_screen.dart` | `CoolTokensScreen` | `/tokens` (`CoolTokensScreen`) | Routed | None |
| `lib/core/status/screens/missions_screen.dart` | `MissionsScreen` | `/missions` (`MissionsScreen`) | Routed | None |
| `lib/core/status/screens/referral_hub_screen.dart` | `ReferralHubScreen` | `/referral` (`ReferralHubScreen`) | Routed | None |

#### `lib/core/status/screens/cool_tokens_screen.dart`

- Classes: `CoolTokensScreen`
- Routes: `/tokens` -> `CoolTokensScreen`
- Related widgets: `lib/core/status/widgets/referral_banner.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_glass_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_status_card.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/mission_progress_card.dart`
- Related providers: `lib/core/status/providers/cool_activities_provider.dart`, `lib/core/status/providers/cool_leaderboard_provider.dart`, `lib/core/status/providers/cool_missions_provider.dart`, `lib/core/status/providers/cool_status_provider.dart`, `lib/features/auth/providers/auth_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/core/status/models/cool_activity.dart`, `lib/core/status/models/cool_leaderboard_entry.dart`, `lib/core/status/models/cool_reward.dart`, `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/core/status/screens/missions_screen.dart`

- Classes: `MissionsScreen`
- Routes: `/missions` -> `MissionsScreen`
- Related widgets: `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_error_view.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/mission_progress_card.dart`
- Related providers: `lib/core/status/providers/cool_missions_provider.dart`, `lib/features/auth/providers/auth_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/core/status/models/cool_mission.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/utils/icon_mapper.dart`
- Direct assets: None

#### `lib/core/status/screens/referral_hub_screen.dart`

- Classes: `ReferralHubScreen`
- Routes: `/referral` -> `ReferralHubScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/qr_share_sheet.dart`
- Related providers: `lib/core/providers/referral_providers.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/core/models/referral_attribution.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### Core Status Screens Module File Inventory

- Screens: `lib/core/status/screens/cool_tokens_screen.dart`, `lib/core/status/screens/missions_screen.dart`, `lib/core/status/screens/referral_hub_screen.dart`

### Credit

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/credit/screens/credit_readiness_screen.dart` | `CreditReadinessScreen` | `/credit/readiness` (`CreditReadinessScreen`) | Routed | None |
| `lib/features/credit/screens/credit_score_screen.dart` | `CreditScoreScreen` | `/credit` (`CreditScoreScreen`) | Routed | None |

#### `lib/features/credit/screens/credit_readiness_screen.dart`

- Classes: `CreditReadinessScreen`
- Routes: `/credit/readiness` -> `CreditReadinessScreen`
- Related widgets: `lib/features/credit/widgets/credit_readiness_checklist_widgets.dart`, `lib/features/credit/widgets/credit_readiness_partner_widgets.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/section_title.dart`, `lib/shared/widgets/secure_screen_mixin.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/credit/providers/credit_provider.dart`, `lib/features/partners/providers/partner_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/auth/models/user_profile.dart`, `lib/features/credit/models/credit_dashboard.dart`, `lib/features/credit/models/credit_readiness.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/credit/screens/credit_score_screen.dart`

- Classes: `CreditScoreScreen`
- Routes: `/credit` -> `CreditScoreScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_glass_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/secure_screen_mixin.dart`
- Related providers: `lib/core/providers/supabase_client_provider.dart`, `lib/features/credit/providers/credit_insights_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/credit/models/credit_insights.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### Credit Module File Inventory

- Screens: `lib/features/credit/screens/credit_readiness_screen.dart`, `lib/features/credit/screens/credit_score_screen.dart`
- Widgets: `lib/features/credit/widgets/credit_readiness_checklist_widgets.dart`, `lib/features/credit/widgets/credit_readiness_partner_widgets.dart`, `lib/features/credit/widgets/credit_score_detail_widgets.dart`, `lib/features/credit/widgets/credit_score_display_widgets.dart`
- Providers: `lib/features/credit/providers/credit_insights_provider.dart`, `lib/features/credit/providers/credit_provider.dart`
- Repositories: `lib/features/credit/repositories/credit_application_repository.dart`, `lib/features/credit/repositories/credit_repository.dart`
- Models: `lib/features/credit/models/credit_dashboard.dart`, `lib/features/credit/models/credit_insights.dart`, `lib/features/credit/models/credit_readiness.dart`, `lib/features/credit/models/partner_credit_application.dart`

### Groups

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/groups/screens/create_group_screen.dart` | `CreateGroupScreen` | `/groups/create` (`CreateGroupScreen`) | Routed | None |
| `lib/features/groups/screens/group_detail_screen.dart` | `GroupDetailScreen` | `/groups/:id` (`GroupDetailScreen`) | Routed | None |
| `lib/features/groups/screens/group_invite_screen.dart` | `GroupInviteScreen` | `/invite/:code` (`GroupInviteScreen`) | Routed | None |
| `lib/features/groups/screens/group_ledger_screen.dart` | `GroupLedgerScreen`, `_ExportFormatSheet` | `/groups/:id/ledger` (`GroupLedgerScreen`) | Routed | None |
| `lib/features/groups/screens/groups_screen.dart` | `GroupsScreen` | `/groups` (`GroupsScreen`) | Routed | None |

#### `lib/features/groups/screens/create_group_screen.dart`

- Classes: `CreateGroupScreen`
- Routes: `/groups/create` -> `CreateGroupScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_text_field.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/groups/providers/groups_provider.dart`, `lib/features/partners/providers/partner_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/models/partner.dart`
- Shared/core dependencies: `lib/core/config/app_market.dart`, `lib/core/config/country_catalog.dart`, `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/groups/screens/group_detail_screen.dart`

- Classes: `GroupDetailScreen`
- Routes: `/groups/:id` -> `GroupDetailScreen`
- Related widgets: `lib/features/groups/widgets/group_detail/group_contribute_sheet.dart`, `lib/features/groups/widgets/group_detail/group_detail_helpers.dart`, `lib/features/groups/widgets/group_detail/group_settings_sheet.dart`, `lib/shared/widgets/contact_picker_sheet.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/member_row.dart`, `lib/shared/widgets/qr_share_sheet.dart`, `lib/shared/widgets/section_title.dart`, `lib/shared/widgets/status_badge.dart`
- Related providers: `lib/core/providers/app_access_provider.dart`, `lib/core/providers/referral_providers.dart`, `lib/features/auth/providers/auth_provider.dart`, `lib/features/groups/providers/groups_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/core/status/models/cool_event.dart`, `lib/features/groups/models/group_detail.dart`
- Shared/core dependencies: `lib/core/config/deep_link_config.dart`, `lib/core/l10n/l10n.dart`, `lib/core/status/cool_status_awarder.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/groups/screens/group_invite_screen.dart`

- Classes: `GroupInviteScreen`
- Routes: `/invite/:code` -> `GroupInviteScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_error_view.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/status_badge.dart`
- Related providers: `lib/core/providers/engagement_providers.dart`, `lib/core/providers/referral_providers.dart`, `lib/features/auth/providers/auth_provider.dart`, `lib/features/groups/providers/groups_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/groups/models/group_detail.dart`
- Shared/core dependencies: `lib/core/auth/auth_user_contact.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/groups/screens/group_ledger_screen.dart`

- Classes: `GroupLedgerScreen`, `_ExportFormatSheet`
- Routes: `/groups/:id/ledger` -> `GroupLedgerScreen`
- Related widgets: `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/groups/providers/group_ledger_provider.dart`, `lib/features/groups/providers/groups_provider.dart`
- Related repositories: None
- Related services: `lib/features/momo/services/momo_statement_export_service.dart`
- Related models: `lib/features/groups/models/group_contribution.dart`, `lib/features/groups/models/group_member.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/groups/screens/groups_screen.dart`

- Classes: `GroupsScreen`
- Routes: `/groups` -> `GroupsScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_glass_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_state_view.dart`, `lib/shared/widgets/status_badge.dart`, `lib/shared/widgets/tab_pill.dart`
- Related providers: `lib/features/groups/providers/groups_provider.dart`, `lib/features/partners/providers/partner_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/groups/models/group.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_layout.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### Groups Module File Inventory

- Screens: `lib/features/groups/screens/create_group_screen.dart`, `lib/features/groups/screens/group_detail_screen.dart`, `lib/features/groups/screens/group_invite_screen.dart`, `lib/features/groups/screens/group_ledger_screen.dart`, `lib/features/groups/screens/groups_screen.dart`
- Widgets: `lib/features/groups/widgets/create_group_parts.dart`
- Providers: `lib/features/groups/providers/group_ledger_provider.dart`, `lib/features/groups/providers/groups_provider.dart`
- Repositories: `lib/features/groups/repositories/group_repository.dart`
- Models: `lib/features/groups/models/group.dart`, `lib/features/groups/models/group_contribution.dart`, `lib/features/groups/models/group_detail.dart`, `lib/features/groups/models/group_join_result.dart`, `lib/features/groups/models/group_member.dart`

### Home

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/home/screens/home_screen.dart` | `HomeScreen` | `/home` (`HomeScreen`) | Routed | None |
| `lib/features/home/screens/seasons_activities_screen.dart` | `SeasonsActivitiesScreen` | `/seasons` (`SeasonsActivitiesScreen`) | Routed | None |

#### `lib/features/home/screens/home_screen.dart`

- Classes: `HomeScreen`
- Routes: `/home` -> `HomeScreen`
- Related widgets: `lib/core/status/widgets/referral_banner.dart`, `lib/features/home/widgets/group_savings_card.dart`, `lib/features/home/widgets/home_header.dart`, `lib/features/home/widgets/home_state_cards.dart`, `lib/features/home/widgets/nexus_recommendations_section.dart`, `lib/features/home/widgets/quick_action_section.dart`, `lib/features/home/widgets/rayon_sport_card.dart`, `lib/features/home/widgets/recent_activity_card.dart`, `lib/features/home/widgets/special_product_card.dart`, `lib/shared/widgets/cool_error_boundary.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/quest_card.dart`, `lib/shared/widgets/season_banner.dart`, `lib/shared/widgets/section_title.dart`
- Related providers: `lib/core/status/providers/home_status_providers.dart`, `lib/features/admin/providers/special_products_provider.dart`, `lib/features/home/providers/home_dashboard_provider.dart`, `lib/features/home/providers/quick_action_provider.dart`, `lib/features/partners/providers/partner_provider.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_layout.dart`
- Direct assets: None

#### `lib/features/home/screens/seasons_activities_screen.dart`

- Classes: `SeasonsActivitiesScreen`
- Routes: `/seasons` -> `SeasonsActivitiesScreen`
- Related widgets: `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`
- Related providers: `lib/features/admin/providers/admin_gamification_providers.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/core/status/models/cool_activity.dart`, `lib/core/status/models/cool_season.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/utils/icon_mapper.dart`
- Direct assets: None

#### Home Module File Inventory

- Screens: `lib/features/home/screens/home_screen.dart`, `lib/features/home/screens/seasons_activities_screen.dart`
- Widgets: `lib/features/home/widgets/group_savings_card.dart`, `lib/features/home/widgets/home_header.dart`, `lib/features/home/widgets/home_state_cards.dart`, `lib/features/home/widgets/nexus_recommendations_section.dart`, `lib/features/home/widgets/quick_action_section.dart`, `lib/features/home/widgets/rayon_sport_card.dart`, `lib/features/home/widgets/recent_activity_card.dart`, `lib/features/home/widgets/special_product_card.dart`
- Providers: `lib/features/home/providers/home_dashboard_provider.dart`, `lib/features/home/providers/nexus_provider.dart`, `lib/features/home/providers/quick_action_provider.dart`
- Repositories: `lib/features/home/repositories/home_dashboard_repository.dart`, `lib/features/home/repositories/nexus_repository.dart`, `lib/features/home/repositories/quick_action_repository.dart`
- Models: `lib/features/home/models/home_dashboard_data.dart`, `lib/features/home/models/nexus_recommendation.dart`, `lib/features/home/models/quick_action.dart`

### Mobility

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/mobility/screens/driver_detail_screens.dart` | `DriverSubscriptionScreen`, `DriverVehicleScreen` | `/mobility/driver/subscription` (`DriverSubscriptionScreen`), `/mobility/driver/vehicle` (`DriverVehicleScreen`) | Routed | None |
| `lib/features/mobility/screens/driver_profile_screen.dart` | `DriverProfileScreen` | `/mobility/driver` (`DriverProfileScreen`) | Routed | None |
| `lib/features/mobility/screens/mobility_home_screen.dart` | `MobilityHomeScreen` | `/mobility` (`MobilityHomeScreen`) | Routed | None |
| `lib/features/mobility/screens/schedule_trip_screen.dart` | `ScheduleTripScreen` | `/mobility/schedule` (`ScheduleTripScreen`) | Routed | None |
| `lib/features/mobility/screens/trip_board_screen.dart` | `TripBoardScreen` | `/mobility/trips` (`TripBoardScreen`) | Routed | None |

#### `lib/features/mobility/screens/driver_detail_screens.dart`

- Classes: `DriverSubscriptionScreen`, `DriverVehicleScreen`
- Routes: `/mobility/driver/subscription` -> `DriverSubscriptionScreen`, `/mobility/driver/vehicle` -> `DriverVehicleScreen`
- Related widgets: `lib/features/mobility/widgets/driver_overview_widgets.dart`, `lib/features/mobility/widgets/driver_profile_models.dart`, `lib/features/mobility/widgets/driver_subscription_widgets.dart`, `lib/features/mobility/widgets/driver_vehicle_trip_widgets.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_scaffold.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/mobility/providers/driver_provider.dart`
- Related repositories: None
- Related services: `lib/core/services/momo_service.dart`
- Related models: None
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/mobility/screens/driver_profile_screen.dart`

- Classes: `DriverProfileScreen`
- Routes: `/mobility/driver` -> `DriverProfileScreen`
- Related widgets: `lib/features/mobility/widgets/driver_overview_widgets.dart`, `lib/features/mobility/widgets/driver_profile_models.dart`, `lib/features/mobility/widgets/driver_subscription_widgets.dart`, `lib/features/mobility/widgets/driver_vehicle_trip_widgets.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_glass_card.dart`, `lib/shared/widgets/cool_screen_scaffold.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/mobility/providers/driver_provider.dart`, `lib/features/mobility/providers/mobility_location_provider.dart`
- Related repositories: None
- Related services: `lib/core/services/momo_service.dart`
- Related models: None
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/mobility/screens/mobility_home_screen.dart`

- Classes: `MobilityHomeScreen`
- Routes: `/mobility` -> `MobilityHomeScreen`
- Related widgets: `lib/features/mobility/widgets/mobility_list_widgets.dart`, `lib/features/mobility/widgets/mobility_listing_sheet.dart`, `lib/shared/widgets/cool_google_map.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/mobility/providers/discovery_provider.dart`, `lib/features/mobility/providers/driver_provider.dart`, `lib/features/mobility/providers/mobility_location_provider.dart`
- Related repositories: None
- Related services: `lib/core/services/whatsapp_contact_service.dart`, `lib/features/mobility/services/mobility_whatsapp_service.dart`
- Related models: `lib/features/mobility/models/driver_info.dart`, `lib/features/mobility/models/trip.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_layout.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/mobility/screens/schedule_trip_screen.dart`

- Classes: `ScheduleTripScreen`
- Routes: `/mobility/schedule` -> `ScheduleTripScreen`
- Related widgets: `lib/features/mobility/widgets/schedule_trip_place_search_sheet.dart`, `lib/features/mobility/widgets/schedule_trip_step_widgets.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/core/providers/engagement_providers.dart`, `lib/core/providers/production_redesign_provider.dart`, `lib/features/auth/providers/auth_provider.dart`, `lib/features/mobility/providers/driver_provider.dart`, `lib/features/mobility/providers/mobility_location_provider.dart`, `lib/features/mobility/providers/mobility_provider.dart`
- Related repositories: None
- Related services: `lib/features/mobility/services/place_search_service.dart`
- Related models: `lib/core/models/geo_point.dart`, `lib/core/status/models/cool_event.dart`, `lib/features/mobility/models/mobility_route_preview.dart`, `lib/features/mobility/models/trip_post_request.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/status/cool_status_awarder.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/utils/intl_locale.dart`
- Direct assets: None

#### `lib/features/mobility/screens/trip_board_screen.dart`

- Classes: `TripBoardScreen`
- Routes: `/mobility/trips` -> `TripBoardScreen`
- Related widgets: `lib/features/mobility/widgets/mobility_listing_sheet.dart`, `lib/features/mobility/widgets/trip_board_content_widgets.dart`, `lib/features/mobility/widgets/trip_board_header_widgets.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/mobility/providers/discovery_provider.dart`, `lib/features/mobility/providers/mobility_location_provider.dart`, `lib/features/mobility/providers/trip_board_provider.dart`
- Related repositories: None
- Related services: `lib/core/services/whatsapp_contact_service.dart`, `lib/features/mobility/services/mobility_whatsapp_service.dart`
- Related models: `lib/features/mobility/models/trip.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### Mobility Module File Inventory

- Screens: `lib/features/mobility/screens/driver_detail_screens.dart`, `lib/features/mobility/screens/driver_profile_screen.dart`, `lib/features/mobility/screens/mobility_home_screen.dart`, `lib/features/mobility/screens/schedule_trip_screen.dart`, `lib/features/mobility/screens/schedule_trip_screen_logic.dart`, `lib/features/mobility/screens/trip_board_screen.dart`
- Widgets: `lib/features/mobility/widgets/driver_detail_parts.dart`, `lib/features/mobility/widgets/driver_overview_widgets.dart`, `lib/features/mobility/widgets/driver_profile_models.dart`, `lib/features/mobility/widgets/driver_subscription_widgets.dart`, `lib/features/mobility/widgets/driver_vehicle_trip_widgets.dart`, `lib/features/mobility/widgets/mobility_driver_widgets.dart`, `lib/features/mobility/widgets/mobility_list_widgets.dart`, `lib/features/mobility/widgets/mobility_listing_sheet.dart`, `lib/features/mobility/widgets/schedule_trip_calendar_suggestions.dart`, `lib/features/mobility/widgets/schedule_trip_place_search_sheet.dart`, `lib/features/mobility/widgets/schedule_trip_review_card.dart`, `lib/features/mobility/widgets/schedule_trip_role_card.dart`, `lib/features/mobility/widgets/schedule_trip_route_preview.dart`, `lib/features/mobility/widgets/schedule_trip_route_widgets.dart`, `lib/features/mobility/widgets/schedule_trip_shared.dart`, `lib/features/mobility/widgets/schedule_trip_step_widgets.dart`, `lib/features/mobility/widgets/trip_board_content_widgets.dart`, `lib/features/mobility/widgets/trip_board_header_widgets.dart`, `lib/features/mobility/widgets/trip_display_strings.dart`, `lib/features/mobility/widgets/widgets.dart`
- Providers: `lib/features/mobility/providers/calendar_suggestions_provider.dart`, `lib/features/mobility/providers/discovery_provider.dart`, `lib/features/mobility/providers/driver_provider.dart`, `lib/features/mobility/providers/mobility_location_provider.dart`, `lib/features/mobility/providers/mobility_provider.dart`, `lib/features/mobility/providers/trip_board_provider.dart`, `lib/features/mobility/providers/vehicle_type_provider.dart`
- Repositories: `lib/features/mobility/repositories/mobility_repository.dart`, `lib/features/mobility/repositories/subscription_repository.dart`, `lib/features/mobility/repositories/trip_repository.dart`, `lib/features/mobility/repositories/vehicle_type_repository.dart`
- Services: `lib/features/mobility/services/mobility_whatsapp_service.dart`, `lib/features/mobility/services/place_search_service.dart`, `lib/features/mobility/services/trip_sync_service.dart`
- Models: `lib/features/mobility/models/driver_info.dart`, `lib/features/mobility/models/driver_profile.dart`, `lib/features/mobility/models/mobility_route_preview.dart`, `lib/features/mobility/models/subscription_status.dart`, `lib/features/mobility/models/trip.dart`, `lib/features/mobility/models/trip_post_request.dart`, `lib/features/mobility/models/trip_type.dart`, `lib/features/mobility/models/vehicle_type.dart`

### MoMo

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/momo/screens/momo_nfc_screen.dart` | `MomoNfcScreen` | Not in GoRouter | Internal / in-flow only | None |
| `lib/features/momo/screens/momo_screen.dart` | `MomoScreen` | `/momo` (`MomoScreen`) | Routed | None |
| `lib/features/momo/screens/momo_statements_screen.dart` | `MomoStatementsScreen` | `/momo/statements` (`MomoStatementsScreen`) | Routed | None |

#### `lib/features/momo/screens/momo_nfc_screen.dart`

- Classes: `MomoNfcScreen`
- Routes: Not registered in GoRouter; screen is launched from in-flow navigation or another screen.
- Related widgets: `lib/features/momo/widgets/momo_qr_nfc_widgets.dart`, `lib/shared/widgets/cool_screen_background.dart`
- Related providers: `lib/core/providers/app_access_provider.dart`, `lib/features/auth/providers/auth_provider.dart`, `lib/features/momo/providers/momo_service_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/config/app_market.dart`, `lib/core/l10n/l10n.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/momo/screens/momo_screen.dart`

- Classes: `MomoScreen`
- Routes: `/momo` -> `MomoScreen`
- Related widgets: `lib/features/momo/widgets/momo_cards_widgets.dart`, `lib/features/momo/widgets/momo_qr_nfc_widgets.dart`, `lib/features/momo/widgets/momo_send_sheet.dart`, `lib/features/momo/widgets/momo_sms_sync_status_card.dart`, `lib/features/profile/widgets/profile_app_access_sheet.dart`, `lib/shared/widgets/balance_card.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/secure_screen_mixin.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/momo/providers/momo_service_provider.dart`, `lib/features/momo/providers/momo_statement_providers.dart`
- Related repositories: None
- Related services: `lib/features/momo/services/nfc_service.dart`
- Related models: `lib/core/models/momo_qr_payload.dart`, `lib/features/momo/models/momo_statement.dart`
- Shared/core dependencies: `lib/core/config/app_market.dart`, `lib/core/config/country_catalog.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`
- Other local dependencies: `lib/features/momo/screens/momo_nfc_screen.dart`
- Direct assets: None

#### `lib/features/momo/screens/momo_statements_screen.dart`

- Classes: `MomoStatementsScreen`
- Routes: `/momo/statements` -> `MomoStatementsScreen`
- Related widgets: `lib/features/momo/widgets/momo_sms_sync_status_card.dart`, `lib/features/profile/widgets/profile_app_access_sheet.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/core/providers/app_lifecycle_providers.dart`, `lib/features/auth/providers/auth_provider.dart`, `lib/features/momo/providers/momo_sms_sync_providers.dart`, `lib/features/momo/providers/momo_statement_providers.dart`
- Related repositories: None
- Related services: `lib/features/momo/services/momo_sms_autoread_service.dart`, `lib/features/momo/services/momo_statement_export_service.dart`
- Related models: `lib/features/momo/models/momo_statement.dart`, `lib/features/momo/models/momo_statement_filters.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/utils/intl_locale.dart`
- Direct assets: None

#### MoMo Module File Inventory

- Screens: `lib/features/momo/screens/momo_nfc_screen.dart`, `lib/features/momo/screens/momo_screen.dart`, `lib/features/momo/screens/momo_statements_screen.dart`
- Widgets: `lib/features/momo/widgets/momo_cards_widgets.dart`, `lib/features/momo/widgets/momo_nfc_widgets.dart`, `lib/features/momo/widgets/momo_qr_nfc_widgets.dart`, `lib/features/momo/widgets/momo_qr_widgets.dart`, `lib/features/momo/widgets/momo_risk_warning_sheet.dart`, `lib/features/momo/widgets/momo_send_sheet.dart`, `lib/features/momo/widgets/momo_sms_rationale_sheet.dart`, `lib/features/momo/widgets/momo_sms_sync_status_card.dart`, `lib/features/momo/widgets/momo_statements_sections.dart`, `lib/features/momo/widgets/widgets.dart`
- Providers: `lib/features/momo/providers/momo_risk_provider.dart`, `lib/features/momo/providers/momo_service_provider.dart`, `lib/features/momo/providers/momo_sms_rationale_provider.dart`, `lib/features/momo/providers/momo_sms_sync_providers.dart`, `lib/features/momo/providers/momo_statement_providers.dart`
- Repositories: `lib/features/momo/repositories/momo_payment_sync_repository.dart`, `lib/features/momo/repositories/momo_sms_ingestion_repository.dart`, `lib/features/momo/repositories/momo_sms_sync_status_repository.dart`, `lib/features/momo/repositories/momo_statement_repository.dart`
- Services: `lib/features/momo/services/momo_service.dart`, `lib/features/momo/services/momo_sms_autoread_service.dart`, `lib/features/momo/services/momo_statement_download_service.dart`, `lib/features/momo/services/momo_statement_export_service.dart`, `lib/features/momo/services/nfc_hce_service.dart`, `lib/features/momo/services/nfc_service.dart`
- Models: `lib/features/momo/models/momo_sms_sync_status.dart`, `lib/features/momo/models/momo_statement.dart`, `lib/features/momo/models/momo_statement_filters.dart`
- Controllers: `lib/features/momo/controllers/momo_statements_controller.dart`

### Partners Core

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart` | `BankOnboardingScreen` | `/partners/:id/onboarding/:type` (`BankOnboardingScreen`) | Routed | None |
| `lib/features/partners/screens/bank_partner_screen.dart` | `BankPartnerScreen` | `/partners/:id` (`BankPartnerScreen`) | Routed | None |
| `lib/features/partners/screens/partners_screen.dart` | `PartnersScreen` | `/partners` (`PartnersScreen`) | Routed | None |
| `lib/features/partners/screens/prisma_partner_screen.dart` | `PrismaPartnerScreen` | `/partners/:id` (`PrismaPartnerScreen`) | Routed | None |
| `lib/features/partners/screens/radiant_partner_screen.dart` | `RadiantPartnerScreen` | `/partners/:id` (`RadiantPartnerScreen`) | Routed | None |

#### `lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart`

- Classes: `BankOnboardingScreen`
- Routes: `/partners/:id/onboarding/:type` -> `BankOnboardingScreen`
- Related widgets: `lib/features/partners/widgets/bank_partner_config.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/auth/models/user_profile.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`
- Direct assets: None

#### `lib/features/partners/screens/bank_partner_screen.dart`

- Classes: `BankPartnerScreen`
- Routes: `/partners/:id` -> `BankPartnerScreen`
- Related widgets: `lib/features/partners/widgets/bank_partner_widgets.dart`, `lib/features/partners/widgets/partner_navigation.dart`, `lib/features/partners/widgets/partner_shared_widgets.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`
- Related providers: `lib/features/partners/providers/partner_provider.dart`, `lib/features/partners/providers/partner_service_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/models/partner.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/partners/screens/partners_screen.dart`

- Classes: `PartnersScreen`
- Routes: `/partners` -> `PartnersScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_membership_card.dart`, `lib/features/partners/widgets/partner_brand_mark.dart`, `lib/features/partners/widgets/partner_navigation.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_state_view.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/section_title.dart`, `lib/shared/widgets/whatsapp_hint_chip.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/partners/providers/partner_provider.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: `lib/core/services/whatsapp_contact_service.dart`
- Related models: `lib/features/partners/models/partner.dart`, `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/utils/icon_mapper.dart`
- Direct assets: None

#### `lib/features/partners/screens/prisma_partner_screen.dart`

- Classes: `PrismaPartnerScreen`
- Routes: `/partners/:id` -> `PrismaPartnerScreen`
- Related widgets: `lib/features/partners/widgets/partner_navigation.dart`, `lib/features/partners/widgets/partner_shared_widgets.dart`, `lib/features/partners/widgets/prisma_partner_config.dart`, `lib/features/partners/widgets/prisma_partner_widgets.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`
- Related providers: `lib/features/partners/providers/partner_provider.dart`, `lib/features/partners/providers/partner_service_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/models/partner.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/partners/screens/radiant_partner_screen.dart`

- Classes: `RadiantPartnerScreen`
- Routes: `/partners/:id` -> `RadiantPartnerScreen`
- Related widgets: `lib/features/partners/widgets/partner_navigation.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/whatsapp_hint_chip.dart`
- Related providers: `lib/features/partners/providers/partner_provider.dart`, `lib/features/partners/providers/partner_service_provider.dart`
- Related repositories: None
- Related services: `lib/core/services/whatsapp_contact_service.dart`
- Related models: `lib/features/partners/models/partner.dart`, `lib/features/partners/models/partner_service.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/utils/icon_mapper.dart`
- Direct assets: None

#### Partners Core Module File Inventory

- Screens: `lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart`, `lib/features/partners/rayon/screens/club_shop_screen.dart`, `lib/features/partners/rayon/screens/fan_club_detail_screen.dart`, `lib/features/partners/rayon/screens/fan_clubs_screen.dart`, `lib/features/partners/rayon/screens/fan_profile_screen.dart`, `lib/features/partners/rayon/screens/member_registry_screen.dart`, `lib/features/partners/rayon/screens/membership_tiers_screen.dart`, `lib/features/partners/rayon/screens/my_tickets_screen.dart`, `lib/features/partners/rayon/screens/rayon_home_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_finance_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_matches_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_members_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_orders_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_packages_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_shop_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart`, `lib/features/partners/rayon/screens/shop_checkout_screen.dart`, `lib/features/partners/rayon/screens/support_detail_screen.dart`, `lib/features/partners/rayon/screens/support_screen.dart`, `lib/features/partners/rayon/screens/ticket_confirmation_screen.dart`, `lib/features/partners/rayon/screens/tickets_screen.dart`, `lib/features/partners/screens/bank_partner_screen.dart`, `lib/features/partners/screens/partners_screen.dart`, `lib/features/partners/screens/prisma_partner_screen.dart`, `lib/features/partners/screens/radiant_partner_screen.dart`
- Widgets: `lib/features/partners/rayon/widgets/fan_profile_parts.dart`, `lib/features/partners/rayon/widgets/member_registry_parts.dart`, `lib/features/partners/rayon/widgets/rs_admin_finance_parts.dart`, `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/features/partners/rayon/widgets/rs_hero_banner.dart`, `lib/features/partners/rayon/widgets/rs_membership_card.dart`, `lib/features/partners/rayon/widgets/rs_service_card.dart`, `lib/features/partners/rayon/widgets/rs_tier_badge.dart`, `lib/features/partners/rayon/widgets/shop_checkout_parts.dart`, `lib/features/partners/rayon/widgets/support_detail_parts.dart`, `lib/features/partners/rayon/widgets/tickets_screen_parts.dart`, `lib/features/partners/widgets/bank_partner_config.dart`, `lib/features/partners/widgets/bank_partner_widgets.dart`, `lib/features/partners/widgets/partner_brand_mark.dart`, `lib/features/partners/widgets/partner_navigation.dart`, `lib/features/partners/widgets/partner_shared_widgets.dart`, `lib/features/partners/widgets/partners_screen_sections.dart`, `lib/features/partners/widgets/prisma_partner_config.dart`, `lib/features/partners/widgets/prisma_partner_widgets.dart`, `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/features/partners/widgets/widgets.dart`
- Providers: `lib/features/partners/providers/member_registry_provider.dart`, `lib/features/partners/providers/partner_provider.dart`, `lib/features/partners/providers/partner_service_provider.dart`, `lib/features/partners/providers/payment_status_provider.dart`, `lib/features/partners/providers/rayon_providers.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/providers/ticket_service_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Repositories: `lib/features/partners/repositories/partner_repository.dart`, `lib/features/partners/repositories/partner_service_repository.dart`, `lib/features/partners/repositories/rayon_sports_checkout.dart`, `lib/features/partners/repositories/rayon_sports_repository.dart`, `lib/features/partners/repositories/rayon_sports_repository_admin.dart`, `lib/features/partners/repositories/rayon_sports_repository_dashboard.dart`, `lib/features/partners/repositories/rayon_sports_repository_initiatives.dart`, `lib/features/partners/repositories/rayon_sports_repository_membership.dart`, `lib/features/partners/repositories/rayon_sports_repository_shop.dart`, `lib/features/partners/repositories/rayon_sports_repository_tickets.dart`
- Services: `lib/features/partners/services/ticket_service.dart`
- Models: `lib/features/partners/models/partner.dart`, `lib/features/partners/models/partner_service.dart`, `lib/features/partners/rayon/models/rs_achievement_models.dart`, `lib/features/partners/rayon/models/rs_data_models.dart`, `lib/features/partners/rayon/models/rs_initiative_models.dart`, `lib/features/partners/rayon/models/rs_membership_models.dart`, `lib/features/partners/rayon/models/rs_models.dart`, `lib/features/partners/rayon/models/rs_shop_models.dart`, `lib/features/partners/rayon/models/rs_ticket_models.dart`
- Controllers: `lib/features/partners/controllers/partners_screen_controller.dart`

### Rayon Consumer

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/partners/rayon/screens/club_shop_screen.dart` | `ClubShopScreen` | `/partners/rayon-sports/shop` (`ClubShopScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/fan_club_detail_screen.dart` | `FanClubDetailScreen` | `/partners/rayon-sports/clubs/:clubId` (`FanClubDetailScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/fan_clubs_screen.dart` | `FanClubsScreen`, `_CreateClubSheet` | `/partners/rayon-sports/clubs` (`FanClubsScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/fan_profile_screen.dart` | `FanProfileScreen` | `/partners/rayon-sports/profile` (`FanProfileScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/member_registry_screen.dart` | `MemberRegistryScreen` | `/partners/rayon-sports/registry` (`MemberRegistryScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/membership_tiers_screen.dart` | `MembershipTiersScreen` | `/partners/rayon-sports/membership` (`MembershipTiersScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/my_tickets_screen.dart` | `MyTicketsScreen` | `/partners/rayon-sports/tickets/my-tickets` (`MyTicketsScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rayon_home_screen.dart` | `RayonHomeScreen` | `/partners/rayon-sports` (`RayonHomeScreen`) | Routed | `assets/images/partners/rs_logo_small.png` |
| `lib/features/partners/rayon/screens/shop_checkout_screen.dart` | `ShopCheckoutScreen` | `/partners/rayon-sports/shop/checkout` (`ShopCheckoutScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/support_detail_screen.dart` | `SupportDetailScreen` | `/partners/rayon-sports/support/:initiativeId` (`SupportDetailScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/support_screen.dart` | `SupportScreen` | `/partners/rayon-sports/support` (`SupportScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/ticket_confirmation_screen.dart` | `TicketConfirmationScreen` | `/partners/rayon-sports/tickets/:ticketId/confirm` (`TicketConfirmationScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/tickets_screen.dart` | `TicketsScreen` | `/partners/rayon-sports/tickets` (`TicketsScreen`) | Routed | None |

#### `lib/features/partners/rayon/screens/club_shop_screen.dart`

- Classes: `ClubShopScreen`
- Routes: `/partners/rayon-sports/shop` -> `ClubShopScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/rs_shop_item.dart`
- Related providers: `lib/core/providers/production_redesign_provider.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/rs_colors.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/fan_club_detail_screen.dart`

- Classes: `FanClubDetailScreen`
- Routes: `/partners/rayon-sports/clubs/:clubId` -> `FanClubDetailScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/rs_achievement_badge.dart`, `lib/shared/widgets/share_card.dart`
- Related providers: `lib/core/providers/production_redesign_provider.dart`, `lib/core/providers/referral_providers.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/config/deep_link_config.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/fan_clubs_screen.dart`

- Classes: `FanClubsScreen`, `_CreateClubSheet`
- Routes: `/partners/rayon-sports/clubs` -> `FanClubsScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_text_field.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/rs_fan_club_card.dart`
- Related providers: `lib/core/providers/production_redesign_provider.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/fan_profile_screen.dart`

- Classes: `FanProfileScreen`
- Routes: `/partners/rayon-sports/profile` -> `FanProfileScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_tier_badge.dart`, `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_glass_card.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/rs_achievement_badge.dart`, `lib/shared/widgets/rs_progress_bar.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/auth/models/user_profile.dart`, `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`, `lib/core/theme/rs_text_styles.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/member_registry_screen.dart`

- Classes: `MemberRegistryScreen`
- Routes: `/partners/rayon-sports/registry` -> `MemberRegistryScreen`
- Related widgets: `lib/features/partners/widgets/partner_navigation.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/rs_tier_badge.dart`
- Related providers: `lib/core/providers/production_redesign_provider.dart`, `lib/features/partners/providers/member_registry_provider.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/membership_tiers_screen.dart`

- Classes: `MembershipTiersScreen`
- Routes: `/partners/rayon-sports/membership` -> `MembershipTiersScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_tier_badge.dart`, `lib/features/partners/widgets/partner_navigation.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/rs_progress_bar.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`, `lib/core/theme/rs_text_styles.dart`
- Other local dependencies: `lib/features/partners/rayon/rs_membership_package.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/my_tickets_screen.dart`

- Classes: `MyTicketsScreen`
- Routes: `/partners/rayon-sports/tickets/my-tickets` -> `MyTicketsScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/rs_digital_ticket.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rayon_home_screen.dart`

- Classes: `RayonHomeScreen`
- Routes: `/partners/rayon-sports` -> `RayonHomeScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_glass_card.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/rs_match_card.dart`
- Related providers: `lib/core/providers/production_redesign_provider.dart`, `lib/features/auth/providers/auth_provider.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/auth/models/user_profile.dart`, `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_layout.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`, `lib/core/theme/rs_text_styles.dart`
- Direct assets: `assets/images/partners/rs_logo_small.png`

#### `lib/features/partners/rayon/screens/shop_checkout_screen.dart`

- Classes: `ShopCheckoutScreen`
- Routes: `/partners/rayon-sports/shop/checkout` -> `ShopCheckoutScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_text_field.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/secure_screen_mixin.dart`
- Related providers: `lib/core/providers/production_redesign_provider.dart`, `lib/core/providers/referral_providers.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/status/cool_status_awarder.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`
- Other local dependencies: `lib/features/partners/rayon/rayon_payment.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/support_detail_screen.dart`

- Classes: `SupportDetailScreen`
- Routes: `/partners/rayon-sports/support/:initiativeId` -> `SupportDetailScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/rs_amount_selector.dart`, `lib/shared/widgets/rs_progress_bar.dart`, `lib/shared/widgets/share_card.dart`
- Related providers: `lib/core/providers/referral_providers.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/config/deep_link_config.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`, `lib/core/theme/rs_text_styles.dart`
- Other local dependencies: `lib/features/partners/rayon/rayon_payment.dart`, `lib/features/partners/rayon/theme/rs_theme.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/support_screen.dart`

- Classes: `SupportScreen`
- Routes: `/partners/rayon-sports/support` -> `SupportScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/rs_initiative_card.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/ticket_confirmation_screen.dart`

- Classes: `TicketConfirmationScreen`
- Routes: `/partners/rayon-sports/tickets/:ticketId/confirm` -> `TicketConfirmationScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/rs_digital_ticket.dart`, `lib/shared/widgets/share_card.dart`
- Related providers: `lib/core/providers/production_redesign_provider.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/config/deep_link_config.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`
- Other local dependencies: `lib/l10n/app_localizations.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/tickets_screen.dart`

- Classes: `TicketsScreen`
- Routes: `/partners/rayon-sports/tickets` -> `TicketsScreen`
- Related widgets: `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/qr_share_sheet.dart`, `lib/shared/widgets/rs_match_card.dart`
- Related providers: `lib/core/providers/production_redesign_provider.dart`, `lib/core/providers/referral_providers.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/config/deep_link_config.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/status/cool_status_awarder.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/rs_colors.dart`, `lib/core/theme/rs_text_styles.dart`
- Other local dependencies: `lib/features/partners/rayon/rayon_payment.dart`
- Direct assets: None

#### Rayon Consumer Module File Inventory

- Screens: `lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart`, `lib/features/partners/rayon/screens/club_shop_screen.dart`, `lib/features/partners/rayon/screens/fan_club_detail_screen.dart`, `lib/features/partners/rayon/screens/fan_clubs_screen.dart`, `lib/features/partners/rayon/screens/fan_profile_screen.dart`, `lib/features/partners/rayon/screens/member_registry_screen.dart`, `lib/features/partners/rayon/screens/membership_tiers_screen.dart`, `lib/features/partners/rayon/screens/my_tickets_screen.dart`, `lib/features/partners/rayon/screens/rayon_home_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_finance_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_matches_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_members_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_orders_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_packages_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_shop_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart`, `lib/features/partners/rayon/screens/shop_checkout_screen.dart`, `lib/features/partners/rayon/screens/support_detail_screen.dart`, `lib/features/partners/rayon/screens/support_screen.dart`, `lib/features/partners/rayon/screens/ticket_confirmation_screen.dart`, `lib/features/partners/rayon/screens/tickets_screen.dart`, `lib/features/partners/screens/bank_partner_screen.dart`, `lib/features/partners/screens/partners_screen.dart`, `lib/features/partners/screens/prisma_partner_screen.dart`, `lib/features/partners/screens/radiant_partner_screen.dart`
- Widgets: `lib/features/partners/rayon/widgets/fan_profile_parts.dart`, `lib/features/partners/rayon/widgets/member_registry_parts.dart`, `lib/features/partners/rayon/widgets/rs_admin_finance_parts.dart`, `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/features/partners/rayon/widgets/rs_hero_banner.dart`, `lib/features/partners/rayon/widgets/rs_membership_card.dart`, `lib/features/partners/rayon/widgets/rs_service_card.dart`, `lib/features/partners/rayon/widgets/rs_tier_badge.dart`, `lib/features/partners/rayon/widgets/shop_checkout_parts.dart`, `lib/features/partners/rayon/widgets/support_detail_parts.dart`, `lib/features/partners/rayon/widgets/tickets_screen_parts.dart`, `lib/features/partners/widgets/bank_partner_config.dart`, `lib/features/partners/widgets/bank_partner_widgets.dart`, `lib/features/partners/widgets/partner_brand_mark.dart`, `lib/features/partners/widgets/partner_navigation.dart`, `lib/features/partners/widgets/partner_shared_widgets.dart`, `lib/features/partners/widgets/partners_screen_sections.dart`, `lib/features/partners/widgets/prisma_partner_config.dart`, `lib/features/partners/widgets/prisma_partner_widgets.dart`, `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/features/partners/widgets/widgets.dart`
- Providers: `lib/features/partners/providers/member_registry_provider.dart`, `lib/features/partners/providers/partner_provider.dart`, `lib/features/partners/providers/partner_service_provider.dart`, `lib/features/partners/providers/payment_status_provider.dart`, `lib/features/partners/providers/rayon_providers.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/providers/ticket_service_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Repositories: `lib/features/partners/repositories/partner_repository.dart`, `lib/features/partners/repositories/partner_service_repository.dart`, `lib/features/partners/repositories/rayon_sports_checkout.dart`, `lib/features/partners/repositories/rayon_sports_repository.dart`, `lib/features/partners/repositories/rayon_sports_repository_admin.dart`, `lib/features/partners/repositories/rayon_sports_repository_dashboard.dart`, `lib/features/partners/repositories/rayon_sports_repository_initiatives.dart`, `lib/features/partners/repositories/rayon_sports_repository_membership.dart`, `lib/features/partners/repositories/rayon_sports_repository_shop.dart`, `lib/features/partners/repositories/rayon_sports_repository_tickets.dart`
- Services: `lib/features/partners/services/ticket_service.dart`
- Models: `lib/features/partners/models/partner.dart`, `lib/features/partners/models/partner_service.dart`, `lib/features/partners/rayon/models/rs_achievement_models.dart`, `lib/features/partners/rayon/models/rs_data_models.dart`, `lib/features/partners/rayon/models/rs_initiative_models.dart`, `lib/features/partners/rayon/models/rs_membership_models.dart`, `lib/features/partners/rayon/models/rs_models.dart`, `lib/features/partners/rayon/models/rs_shop_models.dart`, `lib/features/partners/rayon/models/rs_ticket_models.dart`
- Controllers: `lib/features/partners/controllers/partners_screen_controller.dart`

### Rayon Admin

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart` | `RsAdminAnalyticsScreen` | `/admin/rayon/analytics` (`RsAdminAnalyticsScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart` | `RsAdminDashboardScreen` | `/admin/rayon` (`RsAdminDashboardScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_finance_screen.dart` | `RsAdminFinanceScreen` | `/admin/rayon/finance` (`RsAdminFinanceScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart` | `RsAdminInitiativesScreen`, `_ContributorsSheet` | `/admin/rayon/initiatives` (`RsAdminInitiativesScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_matches_screen.dart` | `RsAdminMatchesScreen` | `/admin/rayon/matches` (`RsAdminMatchesScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_members_screen.dart` | `RsAdminMembersScreen` | `/admin/rayon/members` (`RsAdminMembersScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_orders_screen.dart` | `RsAdminOrdersScreen` | `/admin/rayon/orders` (`RsAdminOrdersScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_packages_screen.dart` | `RsAdminPackagesScreen` | `/admin/rayon/packages` (`RsAdminPackagesScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_shop_screen.dart` | `RsAdminShopScreen` | `/admin/rayon/shop` (`RsAdminShopScreen`) | Routed | None |
| `lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart` | `RsAdminTicketsScreen` | `/admin/rayon/tickets` (`RsAdminTicketsScreen`) | Routed | None |

#### `lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart`

- Classes: `RsAdminAnalyticsScreen`
- Routes: `/admin/rayon/analytics` -> `RsAdminAnalyticsScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_card.dart`
- Related providers: `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart`

- Classes: `RsAdminDashboardScreen`
- Routes: `/admin/rayon` -> `RsAdminDashboardScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_card.dart`
- Related providers: `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_finance_screen.dart`

- Classes: `RsAdminFinanceScreen`
- Routes: `/admin/rayon/finance` -> `RsAdminFinanceScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/momo/providers/momo_statement_providers.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: `lib/features/momo/services/momo_statement_export_service.dart`
- Related models: `lib/features/momo/models/momo_statement.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Other local dependencies: `lib/features/partners/rayon/rayon_payment.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart`

- Classes: `RsAdminInitiativesScreen`, `_ContributorsSheet`
- Routes: `/admin/rayon/initiatives` -> `RsAdminInitiativesScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_skeleton.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_matches_screen.dart`

- Classes: `RsAdminMatchesScreen`
- Routes: `/admin/rayon/matches` -> `RsAdminMatchesScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_skeleton.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_members_screen.dart`

- Classes: `RsAdminMembersScreen`
- Routes: `/admin/rayon/members` -> `RsAdminMembersScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_skeleton.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_orders_screen.dart`

- Classes: `RsAdminOrdersScreen`
- Routes: `/admin/rayon/orders` -> `RsAdminOrdersScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_skeleton.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_packages_screen.dart`

- Classes: `RsAdminPackagesScreen`
- Routes: `/admin/rayon/packages` -> `RsAdminPackagesScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`
- Other local dependencies: `lib/features/partners/rayon/rs_membership_package.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_shop_screen.dart`

- Classes: `RsAdminShopScreen`
- Routes: `/admin/rayon/shop` -> `RsAdminShopScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_skeleton.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

#### `lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart`

- Classes: `RsAdminTicketsScreen`
- Routes: `/admin/rayon/tickets` -> `RsAdminTicketsScreen`
- Related widgets: `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_skeleton.dart`
- Related providers: `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/partners/rayon/models/rs_models.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_foundations.dart`
- Direct assets: None

#### Rayon Admin Module File Inventory

- Screens: `lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart`, `lib/features/partners/rayon/screens/club_shop_screen.dart`, `lib/features/partners/rayon/screens/fan_club_detail_screen.dart`, `lib/features/partners/rayon/screens/fan_clubs_screen.dart`, `lib/features/partners/rayon/screens/fan_profile_screen.dart`, `lib/features/partners/rayon/screens/member_registry_screen.dart`, `lib/features/partners/rayon/screens/membership_tiers_screen.dart`, `lib/features/partners/rayon/screens/my_tickets_screen.dart`, `lib/features/partners/rayon/screens/rayon_home_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_finance_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_matches_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_members_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_orders_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_packages_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_shop_screen.dart`, `lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart`, `lib/features/partners/rayon/screens/shop_checkout_screen.dart`, `lib/features/partners/rayon/screens/support_detail_screen.dart`, `lib/features/partners/rayon/screens/support_screen.dart`, `lib/features/partners/rayon/screens/ticket_confirmation_screen.dart`, `lib/features/partners/rayon/screens/tickets_screen.dart`, `lib/features/partners/screens/bank_partner_screen.dart`, `lib/features/partners/screens/partners_screen.dart`, `lib/features/partners/screens/prisma_partner_screen.dart`, `lib/features/partners/screens/radiant_partner_screen.dart`
- Widgets: `lib/features/partners/rayon/widgets/fan_profile_parts.dart`, `lib/features/partners/rayon/widgets/member_registry_parts.dart`, `lib/features/partners/rayon/widgets/rs_admin_finance_parts.dart`, `lib/features/partners/rayon/widgets/rs_admin_shell.dart`, `lib/features/partners/rayon/widgets/rs_hero_banner.dart`, `lib/features/partners/rayon/widgets/rs_membership_card.dart`, `lib/features/partners/rayon/widgets/rs_service_card.dart`, `lib/features/partners/rayon/widgets/rs_tier_badge.dart`, `lib/features/partners/rayon/widgets/shop_checkout_parts.dart`, `lib/features/partners/rayon/widgets/support_detail_parts.dart`, `lib/features/partners/rayon/widgets/tickets_screen_parts.dart`, `lib/features/partners/widgets/bank_partner_config.dart`, `lib/features/partners/widgets/bank_partner_widgets.dart`, `lib/features/partners/widgets/partner_brand_mark.dart`, `lib/features/partners/widgets/partner_navigation.dart`, `lib/features/partners/widgets/partner_shared_widgets.dart`, `lib/features/partners/widgets/partners_screen_sections.dart`, `lib/features/partners/widgets/prisma_partner_config.dart`, `lib/features/partners/widgets/prisma_partner_widgets.dart`, `lib/features/partners/widgets/rayon_screen_scaffold.dart`, `lib/features/partners/widgets/rayon_state_views.dart`, `lib/features/partners/widgets/widgets.dart`
- Providers: `lib/features/partners/providers/member_registry_provider.dart`, `lib/features/partners/providers/partner_provider.dart`, `lib/features/partners/providers/partner_service_provider.dart`, `lib/features/partners/providers/payment_status_provider.dart`, `lib/features/partners/providers/rayon_providers.dart`, `lib/features/partners/providers/rayon_sports_provider.dart`, `lib/features/partners/providers/ticket_service_provider.dart`, `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- Repositories: `lib/features/partners/repositories/partner_repository.dart`, `lib/features/partners/repositories/partner_service_repository.dart`, `lib/features/partners/repositories/rayon_sports_checkout.dart`, `lib/features/partners/repositories/rayon_sports_repository.dart`, `lib/features/partners/repositories/rayon_sports_repository_admin.dart`, `lib/features/partners/repositories/rayon_sports_repository_dashboard.dart`, `lib/features/partners/repositories/rayon_sports_repository_initiatives.dart`, `lib/features/partners/repositories/rayon_sports_repository_membership.dart`, `lib/features/partners/repositories/rayon_sports_repository_shop.dart`, `lib/features/partners/repositories/rayon_sports_repository_tickets.dart`
- Services: `lib/features/partners/services/ticket_service.dart`
- Models: `lib/features/partners/models/partner.dart`, `lib/features/partners/models/partner_service.dart`, `lib/features/partners/rayon/models/rs_achievement_models.dart`, `lib/features/partners/rayon/models/rs_data_models.dart`, `lib/features/partners/rayon/models/rs_initiative_models.dart`, `lib/features/partners/rayon/models/rs_membership_models.dart`, `lib/features/partners/rayon/models/rs_models.dart`, `lib/features/partners/rayon/models/rs_shop_models.dart`, `lib/features/partners/rayon/models/rs_ticket_models.dart`
- Controllers: `lib/features/partners/controllers/partners_screen_controller.dart`

### Profile

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/features/profile/screens/kyc_id_scan_screen.dart` | `KycIdScanScreen` | Not in GoRouter | Internal / in-flow only | None |
| `lib/features/profile/screens/kyc_selfie_screen.dart` | `KycSelfieScreen` | `/kyc/selfie` (`KycSelfieScreen`) | Routed | None |
| `lib/features/profile/screens/profile_detail_screens.dart` | `ProfileIdentityScreen`, `ProfileTravelRoleScreen`, `ProfileWalletScreen` | `/profile/identity` (`ProfileIdentityScreen`), `/profile/travel-role` (`ProfileTravelRoleScreen`), `/profile/wallet` (`ProfileWalletScreen`) | Routed | None |
| `lib/features/profile/screens/profile_screen.dart` | `ProfileScreen` | `/profile` (`ProfileScreen`) | Routed | None |

#### `lib/features/profile/screens/kyc_id_scan_screen.dart`

- Classes: `KycIdScanScreen`
- Routes: Not registered in GoRouter; screen is launched from in-flow navigation or another screen.
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/kyc_id_scanner_overlay.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`
- Related repositories: None
- Related services: None
- Related models: `lib/features/auth/models/user_profile.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/app_colors.dart`, `lib/core/theme/cool_palette.dart`
- Other local dependencies: `lib/features/profile/screens/kyc_selfie_screen.dart`
- Direct assets: None

#### `lib/features/profile/screens/kyc_selfie_screen.dart`

- Classes: `KycSelfieScreen`
- Routes: `/kyc/selfie` -> `KycSelfieScreen`
- Related widgets: None
- Related providers: None
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: None
- Direct assets: None

#### `lib/features/profile/screens/profile_detail_screens.dart`

- Classes: `ProfileIdentityScreen`, `ProfileTravelRoleScreen`, `ProfileWalletScreen`
- Routes: `/profile/identity` -> `ProfileIdentityScreen`, `/profile/travel-role` -> `ProfileTravelRoleScreen`, `/profile/wallet` -> `ProfileWalletScreen`
- Related widgets: `lib/features/profile/widgets/profile_dialogs.dart`, `lib/features/profile/widgets/profile_momo_edit_sheet.dart`, `lib/features/profile/widgets/profile_travel_role_sheet.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/features/auth/providers/auth_provider.dart`, `lib/features/profile/providers/profile_view_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/config/app_market.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_palette.dart`
- Other local dependencies: `lib/features/profile/screens/kyc_id_scan_screen.dart`
- Direct assets: None

#### `lib/features/profile/screens/profile_screen.dart`

- Classes: `ProfileScreen`
- Routes: `/profile` -> `ProfileScreen`
- Related widgets: `lib/features/profile/widgets/profile_app_access_sheet.dart`, `lib/features/profile/widgets/profile_data.dart`, `lib/features/profile/widgets/profile_dialogs.dart`, `lib/features/profile/widgets/profile_header_widgets.dart`, `lib/features/profile/widgets/profile_settings_widgets.dart`, `lib/features/profile/widgets/profile_theme_sheet.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_screen_scaffold.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/core/status/providers/cool_status_provider.dart`, `lib/features/admin/providers/admin_workspace_access_provider.dart`, `lib/features/auth/providers/auth_provider.dart`, `lib/features/credit/providers/credit_provider.dart`, `lib/features/mobility/providers/driver_provider.dart`, `lib/features/profile/providers/profile_view_provider.dart`
- Related repositories: None
- Related services: None
- Related models: None
- Shared/core dependencies: `lib/core/config/app_config_provider.dart`, `lib/core/l10n/l10n.dart`, `lib/core/router/app_routes.dart`, `lib/core/theme/cool_foundations.dart`, `lib/core/theme/cool_palette.dart`, `lib/core/theme/theme_preference.dart`, `lib/core/theme/theme_preference_provider.dart`
- Direct assets: None

#### Profile Module File Inventory

- Screens: `lib/features/profile/screens/kyc_id_scan_screen.dart`, `lib/features/profile/screens/kyc_selfie_screen.dart`, `lib/features/profile/screens/profile_detail_screens.dart`, `lib/features/profile/screens/profile_screen.dart`
- Widgets: `lib/features/profile/widgets/profile_app_access_sheet.dart`, `lib/features/profile/widgets/profile_data.dart`, `lib/features/profile/widgets/profile_dialogs.dart`, `lib/features/profile/widgets/profile_header_widgets.dart`, `lib/features/profile/widgets/profile_identity_edit_sheet.dart`, `lib/features/profile/widgets/profile_momo_edit_sheet.dart`, `lib/features/profile/widgets/profile_settings_widgets.dart`, `lib/features/profile/widgets/profile_theme_sheet.dart`, `lib/features/profile/widgets/profile_travel_role_sheet.dart`
- Providers: `lib/features/profile/providers/profile_view_provider.dart`

### Shared Routed Utilities

| Screen File | Classes | Routes | Route Status | Direct Assets |
|---|---|---|---|---|
| `lib/shared/widgets/qr_scanner_screen.dart` | `QrScannerScreen`, `_TicketResultSheet` | `/scanner` (`QrScannerScreen`) | Routed | None |

#### `lib/shared/widgets/qr_scanner_screen.dart`

- Classes: `QrScannerScreen`, `_TicketResultSheet`
- Routes: `/scanner` -> `QrScannerScreen`
- Related widgets: `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_toast.dart`
- Related providers: `lib/core/providers/app_access_provider.dart`, `lib/core/providers/supabase_client_provider.dart`, `lib/features/momo/providers/momo_service_provider.dart`
- Related repositories: None
- Related services: `lib/core/services/app_access_service.dart`
- Related models: `lib/core/models/momo_qr_payload.dart`
- Shared/core dependencies: `lib/core/l10n/l10n.dart`, `lib/core/theme/cool_palette.dart`
- Direct assets: None

## Shared UI And Screen Infrastructure

- Shared widget inventory (`lib/shared/widgets/`): `lib/shared/widgets/balance_card.dart`, `lib/shared/widgets/contact_picker_sheet.dart`, `lib/shared/widgets/cool_async_view.dart`, `lib/shared/widgets/cool_bottom_sheet.dart`, `lib/shared/widgets/cool_brand_mark.dart`, `lib/shared/widgets/cool_button.dart`, `lib/shared/widgets/cool_card.dart`, `lib/shared/widgets/cool_empty_view.dart`, `lib/shared/widgets/cool_error_boundary.dart`, `lib/shared/widgets/cool_error_view.dart`, `lib/shared/widgets/cool_glass_card.dart`, `lib/shared/widgets/cool_google_map.dart`, `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_screen_scaffold.dart`, `lib/shared/widgets/cool_skeleton.dart`, `lib/shared/widgets/cool_state_view.dart`, `lib/shared/widgets/cool_status_card.dart`, `lib/shared/widgets/cool_text_field.dart`, `lib/shared/widgets/cool_toast.dart`, `lib/shared/widgets/driver_card.dart`, `lib/shared/widgets/group_card.dart`, `lib/shared/widgets/kill_switch_gate.dart`, `lib/shared/widgets/kyc_id_scanner_overlay.dart`, `lib/shared/widgets/kyc_selfie_screen.dart`, `lib/shared/widgets/member_row.dart`, `lib/shared/widgets/mission_progress_card.dart`, `lib/shared/widgets/momo_route_type_selector.dart`, `lib/shared/widgets/qr_scanner_screen.dart`, `lib/shared/widgets/qr_share_sheet.dart`, `lib/shared/widgets/quest_card.dart`, `lib/shared/widgets/rs_achievement_badge.dart`, `lib/shared/widgets/rs_amount_selector.dart`, `lib/shared/widgets/rs_club_card.dart`, `lib/shared/widgets/rs_digital_ticket.dart`, `lib/shared/widgets/rs_fan_club_card.dart`, `lib/shared/widgets/rs_initiative_card.dart`, `lib/shared/widgets/rs_league_table.dart`, `lib/shared/widgets/rs_match_card.dart`, `lib/shared/widgets/rs_membership_card.dart`, `lib/shared/widgets/rs_progress_bar.dart`, `lib/shared/widgets/rs_service_card.dart`, `lib/shared/widgets/rs_shop_item.dart`, `lib/shared/widgets/rs_ticket_card.dart`, `lib/shared/widgets/rs_tier_badge.dart`, `lib/shared/widgets/season_banner.dart`, `lib/shared/widgets/section_title.dart`, `lib/shared/widgets/secure_screen_mixin.dart`, `lib/shared/widgets/secure_screen_wrapper.dart`, `lib/shared/widgets/share_card.dart`, `lib/shared/widgets/status_badge.dart`, `lib/shared/widgets/tab_pill.dart`, `lib/shared/widgets/trip_card.dart`, `lib/shared/widgets/vehicle_chip.dart`, `lib/shared/widgets/wa_button.dart`, `lib/shared/widgets/whatsapp_hint_chip.dart`, `lib/shared/widgets/widgets.dart`
- Screen infrastructure / wrappers not counted as app screens: `lib/shared/widgets/cool_screen_background.dart`, `lib/shared/widgets/cool_screen_scaffold.dart`, `lib/shared/widgets/secure_screen_mixin.dart`, `lib/shared/widgets/secure_screen_wrapper.dart`, and the delegated implementation `lib/shared/widgets/kyc_selfie_screen.dart`.

## Asset Inventory

### `assets/images`

- `assets/images/.gitkeep`
- `assets/images/cool_logo_mark.png`
- `assets/images/cool_logo_mark_splash.png`
- `assets/images/partners/equity_logo.png`
- `assets/images/partners/rs_logo.png`
- `assets/images/partners/rs_logo_mark.png`
- `assets/images/partners/rs_logo_small.png`
- `assets/images/partners/urwego_logo.png`

### `assets/icons`

- `assets/icons/.gitkeep`
- `assets/icons/cool_app_icon.png`
- `assets/icons/cool_app_icon_foreground.png`
- `assets/icons/vehicle_cab.png`
- `assets/icons/vehicle_moto.png`
- `assets/icons/vehicle_others.png`
- `assets/icons/vehicle_trike.png`
- `assets/icons/vehicle_truck.png`

### `assets/fonts`

- `assets/fonts/Lato-Bold.ttf`
- `assets/fonts/Lato-Regular.ttf`

## Backend, Data, And External Surface Inventory

- Supabase config/seed files: `supabase/config.toml`, `supabase/seed_cool_status.sql`
- Supabase edge function and shared runtime files:
- `supabase/functions/.env.example`
- `supabase/functions/_shared/fcm.ts`
- `supabase/functions/_shared/fcm_test.ts`
- `supabase/functions/_shared/google_workspace.ts`
- `supabase/functions/_shared/http.ts`
- `supabase/functions/_shared/observability.ts`
- `supabase/functions/_shared/otp_abuse.ts`
- `supabase/functions/_shared/otp_abuse_test.ts`
- `supabase/functions/_shared/phone.ts`
- `supabase/functions/_shared/rayon_payments.ts`
- `supabase/functions/_shared/security.ts`
- `supabase/functions/_shared/supabase.ts`
- `supabase/functions/_shared/whatsapp.ts`
- `supabase/functions/allocate-contributions/index.ts`
- `supabase/functions/chat-with-finances/index.ts`
- `supabase/functions/create-financial-memo/index.ts`
- `supabase/functions/delete-account/index.ts`
- `supabase/functions/evaluate-transfer-risk/index.ts`
- `supabase/functions/expire-trips/index.ts`
- `supabase/functions/fetch-workspace-calendar/index.ts`
- `supabase/functions/generate-ai-content/index.ts`
- `supabase/functions/get-financial-insights/index.ts`
- `supabase/functions/get-nexus-recommendations/index.ts`
- `supabase/functions/kyc-ocr/index.ts`
- `supabase/functions/kyc-ocr/rules.ts`
- `supabase/functions/kyc-ocr/rules_test.ts`
- `supabase/functions/maps-gateway/index.ts`
- `supabase/functions/parse-momo-sms/ai_parser.ts`
- `supabase/functions/parse-momo-sms/ai_parser_test.ts`
- `supabase/functions/parse-momo-sms/index.ts`
- `supabase/functions/parse-momo-sms/rayon_confirmation.ts`
- `supabase/functions/parse-momo-sms/rayon_confirmation_test.ts`
- `supabase/functions/parse-momo-sms/reconciliation.ts`
- `supabase/functions/parse-momo-sms/reconciliation_test.ts`
- `supabase/functions/parse-trip-request/index.ts`
- `supabase/functions/record-operational-health/index.ts`
- `supabase/functions/reflect-on-correction/index.ts`
- `supabase/functions/rs-scan-ticket/index.ts`
- `supabase/functions/run-monthly-archive/index.ts`
- `supabase/functions/schedule-financial-future/index.ts`
- `supabase/functions/send-notification/index.ts`
- `supabase/functions/send-otp/index.ts`
- `supabase/functions/sms-ingest/index.ts`
- `supabase/functions/sms-ingest/rules.ts`
- `supabase/functions/sms-ingest/rules_test.ts`
- `supabase/functions/translate-content/index.ts`
- `supabase/functions/verify-face-match/index.ts`
- `supabase/functions/verify-otp/index.ts`
- `supabase/functions/wallet-issuer/index.ts`

- Supabase migration files:
- `supabase/migrations/20260310120000_initial_schema.sql`
- `supabase/migrations/20260310130000_pending_transactions.sql`
- `supabase/migrations/20260310133000_mobile_integration_alignment.sql`
- `supabase/migrations/20260310143000_schedule_trip_expiry.sql`
- `supabase/migrations/20260310153000_ai_momo_sms_pipeline.sql`
- `supabase/migrations/20260310160000_momo_reconciliation_indexes.sql`
- `supabase/migrations/20260310170000_supported_countries_catalog.sql`
- `supabase/migrations/20260310183000_dynamic_momo_ussd_routes.sql`
- `supabase/migrations/20260310190000_trip_board_contact_and_delete.sql`
- `supabase/migrations/20260310200000_rayon_sports_extension.sql`
- `supabase/migrations/20260310213000_rayon_sports_reconciliation.sql`
- `supabase/migrations/20260310220000_rayon_sports_schema_lock.sql`
- `supabase/migrations/20260310224500_mobility_trip_location_alignment.sql`
- `supabase/migrations/20260310230000_mobility_price_note.sql`
- `supabase/migrations/20260310231000_cool_status_foundation.sql`
- `supabase/migrations/20260310232000_cool_missions.sql`
- `supabase/migrations/20260310233000_cool_seasons.sql`
- `supabase/migrations/20260310234000_engagement_foundation.sql`
- `supabase/migrations/20260310235000_referral_activation_reconciliation.sql`
- `supabase/migrations/20260311070000_dynamic_partners.sql`
- `supabase/migrations/20260311080000_dynamic_content.sql`
- `supabase/migrations/20260311110000_admin_write_policies.sql`
- `supabase/migrations/20260311113000_admin_and_groups_contract_alignment.sql`
- `supabase/migrations/20260311113100_group_rpc_create_group_atomic.sql`
- `supabase/migrations/20260311113200_group_rpc_invite_preview.sql`
- `supabase/migrations/20260311113300_group_rpc_join_group_via_invite.sql`
- `supabase/migrations/20260311163000_groups_rls_repair.sql`
- `supabase/migrations/20260311163500_invite_preview_anon_access.sql`
- `supabase/migrations/20260311170000_user_fcm_tokens.sql`
- `supabase/migrations/20260311183000_group_invite_code_runtime_compat.sql`
- `supabase/migrations/20260311190000_trip_status_alignment.sql`
- `supabase/migrations/20260311193000_mobility_trip_client_request_id.sql`
- `supabase/migrations/20260311195000_google_wallet_passes.sql`
- `supabase/migrations/20260311200000_scheduled_trips_geo_rpc.sql`
- `supabase/migrations/20260311203000_partner_mock_seed_batch.sql`
- `supabase/migrations/20260311214500_demo_users_and_comprehensive_mock_seed.sql`
- `supabase/migrations/20260311223000_admin_mock_batch_cleanup.sql`
- `supabase/migrations/20260311230000_supported_countries_validation_metadata.sql`
- `supabase/migrations/20260311230100_urwego_partner_content_refresh.sql`
- `supabase/migrations/20260311232000_prisma_partner_content_refresh.sql`
- `supabase/migrations/20260311233000_momo_validation_triggers.sql`
- `supabase/migrations/20260311234500_momo_validation_reference_views.sql`
- `supabase/migrations/20260311235000_momo_validation_issue_rpc.sql`
- `supabase/migrations/20260311235100_equity_partner_content_refresh.sql`
- `supabase/migrations/20260311235500_credit_scoring_foundation.sql`
- `supabase/migrations/20260311235600_momo_validation_repair_rpc.sql`
- `supabase/migrations/20260311235800_mobility_country_scoping.sql`
- `supabase/migrations/20260312000500_bank_partner_logo_urls.sql`
- `supabase/migrations/20260312001500_rayon_member_registry_rpc.sql`
- `supabase/migrations/20260312004000_statement_rpcs_and_credit_score_cron.sql`
- `supabase/migrations/20260312005500_credit_score_user_refresh_rpc.sql`
- `supabase/migrations/20260312013000_partner_credit_applications.sql`
- `supabase/migrations/20260312160000_uat_backend_compat_hotfix.sql`
- `supabase/migrations/20260312170000_remove_momo_webhook_artifacts.sql`
- `supabase/migrations/20260312173000_public_user_ids.sql`
- `supabase/migrations/20260312191000_user_profile_wallet_routes.sql`
- `supabase/migrations/20260312201500_rayon_kwesa_catalog_contract.sql`
- `supabase/migrations/20260312204500_rayon_kwesa_catalog_cleanup.sql`
- `supabase/migrations/20260312211000_preserve_user_momo_route_preferences.sql`
- `supabase/migrations/20260312223000_repair_momo_sms_pipeline.sql`
- `supabase/migrations/20260313101500_operational_observability.sql`
- `supabase/migrations/20260313114500_partner_payment_routes.sql`
- `supabase/migrations/20260313120500_rwanda_only_cleanup.sql`
- `supabase/migrations/20260313143000_rwanda_only_catalog_cleanup.sql`
- `supabase/migrations/20260313153000_remove_country_scope_from_local_catalog.sql`
- `supabase/migrations/20260313170000_operational_health_ingest_hardening.sql`
- `supabase/migrations/20260313180000_rwanda_only_runtime_content_cleanup.sql`
- `supabase/migrations/20260313183000_otp_abuse_hardening.sql`
- `supabase/migrations/20260313190000_otp_rate_event_phone_limits.sql`
- `supabase/migrations/20260313203000_lock_users_to_rwanda_english.sql`
- `supabase/migrations/20260313223000_rwanda_only_runtime_scope_contract.sql`
- `supabase/migrations/20260313233000_supported_countries_readonly.sql`
- `supabase/migrations/20260313234500_payee_ledgers_and_payee_route_allocations.sql`
- `supabase/migrations/20260314103000_momo_sms_ingest_contract.sql`
- `supabase/migrations/20260314123000_operational_triage_direct_sms.sql`
- `supabase/migrations/20260315110000_kyc_identity_profile_fields.sql`
- `supabase/migrations/20260315113000_bank_admin_group_savings_access.sql`
- `supabase/migrations/20260315120000_lock_operational_health_rls.sql`
- `supabase/migrations/20260315124500_bank_admin_manual_allocation_actions.sql`
- `supabase/migrations/20260315141500_rayon_admin_finance_and_packages.sql`
- `supabase/migrations/20260315153000_group_custodian_partner_link.sql`
- `supabase/migrations/20260315170000_user_theme_preference.sql`
- `supabase/migrations/20260315180000_notify_mission_progress.sql`
- `supabase/migrations/20260316010000_admin_gamification_rls.sql`
- `supabase/migrations/20260316020000_admin_role_assignments.sql`
- `supabase/migrations/20260316030000_admin_audit_log_analytics.sql`
- `supabase/migrations/20260316040000_scoped_rls_audit_triggers.sql`
- `supabase/migrations/20260316080000_admin_audit_log.sql`
- `supabase/migrations/20260316084200_assign_dedicated_admins.sql`
- `supabase/migrations/20260316085000_partners_momo_code.sql`
- `supabase/migrations/20260316090000_platform_analytics_rpc.sql`
- `supabase/migrations/20260316092400_bank_allocation_ai_support.sql`
- `supabase/migrations/20260316100000_seed_admin_role_assignments.sql`
- `supabase/migrations/20260316110000_bank_loans_baskets.sql`
- `supabase/migrations/20260316120000_rs_notifications_batch_analytics.sql`
- `supabase/migrations/20260316120001_update_liffan_to_trike.sql`
- `supabase/migrations/20260316130000_enforce_data_integrity.sql`
- `supabase/migrations/20260316130001_nexus_opportunities.sql`
- `supabase/migrations/20260316131500_mock_tracking_enhancements.sql`
- `supabase/migrations/20260316132000_bank_features_mock_seed.sql`
- `supabase/migrations/20260316132501_fix_audit_trigger.sql`
- `supabase/migrations/20260316133000_app_config_seed.sql`
- `supabase/migrations/20260316140000_gamification_rpcs.sql`
- `supabase/migrations/20260316180000_rayon_sports_audit_fixes.sql`
- `supabase/migrations/20260317080000_momo_delete_rls_and_rate_limit.sql`
- `supabase/migrations/20260317090000_momo_tx_id_dedup.sql`
- `supabase/migrations/20260317100000_secure_operational_health_policy.sql`
- `supabase/migrations/20260317130000_audit_fixes_special_products.sql`
- `supabase/migrations/20260317143000_cool_activities.sql`
- `supabase/migrations/20260317160000_ai_content_generation_config.sql`
- `supabase/migrations/20260317160100_seed_ai_content.sql`
- `supabase/migrations/20260317163000_bank_partner_services_standardize.sql`
- `supabase/migrations/20260317174000_group_enhancements.sql`
- `supabase/migrations/20260318072000_seed_quests_special_products_drop_legacy.sql`
- `supabase/migrations/20260322120000_momo_sms_sync_audit_and_status_alignment.sql`

## Supporting Web, Deep Link, Tooling, And Test Surfaces

### `hosting/`

- `hosting/.well-known/assetlinks.json`
- `hosting/account-deletion/index.html`
- `hosting/index.html`
- `hosting/privacy/index.html`
- `hosting/styles.css`
- `hosting/terms/index.html`

### `landing/`

- `landing/.well-known/assetlinks.json`
- `landing/account-deletion/index.html`
- `landing/assets/apple-touch-icon.png`
- `landing/assets/favicon-16.png`
- `landing/assets/favicon-32.png`
- `landing/assets/icon-192.png`
- `landing/assets/icon-512.png`
- `landing/assets/icon.png`
- `landing/index.html`
- `landing/privacy/index.html`
- `landing/terms/index.html`

### `deeplinks/`

- `deeplinks/release_metadata.json`
- `deeplinks/site/.well-known/apple-app-site-association`
- `deeplinks/site/.well-known/assetlinks.json`
- `deeplinks/site/404.html`
- `deeplinks/site/README.md`
- `deeplinks/site/_redirects`
- `deeplinks/site/assets/deeplink.js`
- `deeplinks/site/assets/store-links.js`
- `deeplinks/site/download-ios/index.html`
- `deeplinks/site/index.html`

### `tool/`

- `tool/deep_link_release_assets.dart`
- `tool/governance_docs.dart`
- `tool/ui_copy_guard.dart`
- `tool/update_governance.dart`

### `scripts/`

- `scripts/_android_release_build.sh`
- `scripts/build_ios_production.sh`
- `scripts/build_ios_staging.sh`
- `scripts/build_play_release.sh`
- `scripts/build_production.sh`
- `scripts/build_qa_apk.sh`
- `scripts/build_staging.sh`
- `scripts/flutterw`
- `scripts/purge_mocks.sh`
- `scripts/release_readiness.sh`
- `scripts/run_device_integration.sh`
- `scripts/supabase_contract_smoke.sh`
- `scripts/verify_android_flavors.sh`
- `scripts/verify_ios_flavors.sh`

### `integration_test/`

- `integration_test/README.md`
- `integration_test/critical_journeys_test.dart`

### `test/`

- `test/accessibility/text_scaling_touch_targets_test.dart`
- `test/core/app_router_feature_gate_test.dart`
- `test/core/app_router_redirect_test.dart`
- `test/core/config/app_market_test.dart`
- `test/core/config/country_catalog_parametric_test.dart`
- `test/core/config/country_catalog_test.dart`
- `test/core/config/env_config_test.dart`
- `test/core/config/rwanda_invariants_test.dart`
- `test/core/config/rwanda_only_invariant_test.dart`
- `test/core/deep_link_config_test.dart`
- `test/core/engagement_event_test.dart`
- `test/core/engagement_feature_flags_test.dart`
- `test/core/fcm_service_test.dart`
- `test/core/identity/user_identity_lookup_test.dart`
- `test/core/l10n/locale_provider_test.dart`
- `test/core/models/engagement_feature_flags_test.dart`
- `test/core/placeholder_route_redirect_test.dart`
- `test/core/providers/app_lifecycle_providers_test.dart`
- `test/core/providers/production_redesign_provider_test.dart`
- `test/core/quick_action_navigation_test.dart`
- `test/core/repository_schema_contract_test.dart`
- `test/core/services/app_access_service_test.dart`
- `test/core/services/app_lifecycle_coordinator_test.dart`
- `test/core/services/feature_flags_service_test.dart`
- `test/core/sync/network_status_test.dart`
- `test/core/sync/sync_engine_test.dart`
- `test/core/theme/app_colors_test.dart`
- `test/core/theme/app_theme_test.dart`
- `test/core/theme/redesign_foundations_test.dart`
- `test/core/theme/theme_preference_test.dart`
- `test/core/theme/theme_system_chrome_test.dart`
- `test/core/utils/app_logger_test.dart`
- `test/core/utils/intl_locale_test.dart`
- `test/core/utils/json_helpers_test.dart`
- `test/core/utils/phone_validator_test.dart`
- `test/docs/deep_link_release_assets_test.dart`
- `test/docs/governance_docs_sync_test.dart`
- `test/docs/hardening_regression_test.dart`
- `test/docs/ui_copy_guard_test.dart`
- `test/features/admin/admin_dashboard_role_filter_test.dart`
- `test/features/admin/admin_rbac_model_test.dart`
- `test/features/admin/admin_repository_fallback_test.dart`
- `test/features/admin/admin_workspaces_screen_test.dart`
- `test/features/admin/bank_admin_workspace_screen_test.dart`
- `test/features/admin/manage_app_config_screen_test.dart`
- `test/features/admin/manage_catalog_market_lock_test.dart`
- `test/features/admin/manage_users_screen_test.dart`
- `test/features/admin/models/admin_feature_rollout_test.dart`
- `test/features/admin/operational_dashboard_screen_test.dart`
- `test/features/admin/partner_admin_workspace_screen_test.dart`
- `test/features/auth/auth_repository_test.dart`
- `test/features/auth/auth_route_flow_test.dart`
- `test/features/auth/delete_account_contract_test.dart`
- `test/features/auth/otp_verify_screen_test.dart`
- `test/features/auth_routing_test.dart`
- `test/features/credit/models/credit_readiness_test.dart`
- `test/features/groups/groups_model_test.dart`
- `test/features/home/home_dashboard_repository_test.dart`
- `test/features/mobility/models/trip_post_request_test.dart`
- `test/features/mobility/providers/driver_provider_test.dart`
- `test/features/mobility/providers/mobility_location_provider_test.dart`
- `test/features/mobility/providers/mobility_provider_test.dart`
- `test/features/mobility/providers/trip_board_provider_test.dart`
- `test/features/mobility/repositories/trip_repository_test.dart`
- `test/features/mobility/schedule_trip_review_card_test.dart`
- `test/features/mobility/services/mobility_whatsapp_service_test.dart`
- `test/features/mobility/services/place_search_service_test.dart`
- `test/features/momo/models/momo_qr_payload_test.dart`
- `test/features/momo/momo_sms_autoread_service_test.dart`
- `test/features/momo/momo_sms_ingestion_repository_test.dart`
- `test/features/momo/momo_statement_filters_test.dart`
- `test/features/momo/momo_statements_route_test.dart`
- `test/features/momo/services/momo_statement_export_service_test.dart`
- `test/features/momo/services/nfc_hce_service_test.dart`
- `test/features/momo/services/nfc_service_test.dart`
- `test/features/momo/widgets/momo_widgets_test.dart`
- `test/features/partners/fan_club_detail_screen_test.dart`
- `test/features/partners/fan_profile_screen_test.dart`
- `test/features/partners/goldens/rayon_club_shop_command_surface.png`
- `test/features/partners/goldens/rayon_fan_club_detail_command_surface.png`
- `test/features/partners/goldens/rayon_fan_clubs_command_surface.png`
- `test/features/partners/goldens/rayon_home_command_surface.png`
- `test/features/partners/goldens/rayon_member_registry_command_surface.png`
- `test/features/partners/member_registry_provider_test.dart`
- `test/features/partners/member_registry_screen_test.dart`
- `test/features/partners/membership_tiers_screen_test.dart`
- `test/features/partners/partner_model_test.dart`
- `test/features/partners/partner_navigation_test.dart`
- `test/features/partners/partners_screen_test.dart`
- `test/features/partners/rayon_home_screen_test.dart`
- `test/features/partners/rayon_lightweight_screens_test.dart`
- `test/features/partners/rayon_profile_lightweight_providers_test.dart`
- `test/features/partners/rayon_redesign_goldens_test.dart`
- `test/features/partners/rayon_shop_catalog_test.dart`
- `test/features/partners/rayon_sports_models_test.dart`
- `test/features/partners/rayon_sports_provider_test.dart`
- `test/features/partners/rs_admin_command_screens_test.dart`
- `test/features/partners/rs_admin_finance_screen_test.dart`
- `test/features/partners/rs_admin_operational_screens_test.dart`
- `test/features/partners/rs_admin_packages_screen_test.dart`
- `test/features/partners/ticket_confirmation_screen_test.dart`
- `test/features/partners/widgets/bank_partner_widgets_test.dart`
- `test/features/partners/widgets/partner_shared_widgets_test.dart`
- `test/features/partners/widgets/prisma_partner_widgets_test.dart`
- `test/features/payment_idempotency_test.dart`
- `test/features/profile/profile_appearance_sheet_test.dart`
- `test/features/profile/profile_data_test.dart`
- `test/features/profile/profile_momo_edit_sheet_test.dart`
- `test/features/profile/widgets/profile_app_access_sheet_test.dart`
- `test/features/rayon_flow_test.dart`
- `test/flutter_test_config.dart`
- `test/groups_provider_test.dart`
- `test/helpers/fake_app_access_service.dart`
- `test/helpers/google_fonts_test_assets.dart`
- `test/helpers/test_bootstrap.dart`
- `test/integration_smoke/admin_route_access_test.dart`
- `test/integration_smoke/app_boot_test.dart`
- `test/integration_smoke/auth_flow_test.dart`
- `test/integration_smoke/credit_readiness_flow_test.dart`
- `test/integration_smoke/credit_score_test.dart`
- `test/integration_smoke/deep_link_test.dart`
- `test/integration_smoke/driver_profile_screen_test.dart`
- `test/integration_smoke/group_detail_screen_test.dart`
- `test/integration_smoke/group_flow_test.dart`
- `test/integration_smoke/groups_screen_test.dart`
- `test/integration_smoke/home_screen_test.dart`
- `test/integration_smoke/momo_flow_test.dart`
- `test/integration_smoke/primary_route_accessibility_test.dart`
- `test/integration_smoke/profile_screen_test.dart`
- `test/integration_smoke/schedule_trip_screen_test.dart`
- `test/integration_smoke/test_harness.dart`
- `test/integration_smoke/ticket_flow_test.dart`
- `test/integration_smoke/trip_board_screen_test.dart`
- `test/integration_smoke/trip_offline_test.dart`
- `test/models/group_test.dart`
- `test/models/trip_test.dart`
- `test/models/user_profile_test.dart`
- `test/providers/auth_notifier_test.dart`
- `test/providers/groups_notifier_test.dart`
- `test/shared/accessibility_smoke_test.dart`
- `test/shared/widgets/contact_picker_sheet_test.dart`
- `test/shared/widgets/cool_async_view_test.dart`
- `test/shared/widgets/cool_button_test.dart`
- `test/shared/widgets/cool_card_test.dart`
- `test/shared/widgets/cool_empty_view_test.dart`
- `test/shared/widgets/cool_error_view_test.dart`
- `test/shared/widgets/cool_screen_scaffold_test.dart`
- `test/shared/widgets/cool_skeleton_test.dart`
- `test/shared/widgets/cool_status_card_test.dart`
- `test/shared/widgets/cool_text_field_test.dart`
- `test/shared/widgets/cool_toast_test.dart`
- `test/shared/widgets/qr_scanner_screen_test.dart`
- `test/shared/widgets/section_title_test.dart`
- `test/shared/widgets/secure_screen_wrapper_test.dart`
- `test/shared/widgets/shared_theme_adaptation_test.dart`
- `test/shared/widgets/status_badge_test.dart`
- `test/shared/widgets/tab_pill_test.dart`
- `test/widget_test.dart`

## Audit Findings

### Strengths

- Feature modules are consistently separated into `screens`, `widgets`, `providers`, `repositories`, and `models`, which makes the runtime surface inspectable by domain.
- Route and screen-budget governance already exist as generated docs, which reduces the risk of hidden route sprawl and oversized screen files.
- The repo contains a real fullstack contract: mobile runtime, shared UI, Supabase backend, Firebase observability, deeplink site, static legal pages, and tests in one workspace.
- Shared UI primitives under `lib/shared/widgets/` and theme layers under `lib/core/theme/` provide a reusable design-system base for ongoing refactors.

### Risks / Follow-Up Areas

- `docs/SCREEN_BUDGETS.md` still reports one hotspot and five debt screens, with the current hotspot on `rayon_home_screen.dart` and debt screens concentrated in Rayon, mobility, and MoMo flows.
- Some implemented screens are not directly registered in GoRouter (`momo_nfc_screen.dart`, `kyc_id_scan_screen.dart`), so navigation coverage depends on in-flow widget navigation rather than the central route table.
- `lib/features/profile/screens/kyc_selfie_screen.dart` is a thin wrapper over `lib/shared/widgets/kyc_selfie_screen.dart`, which is workable but should be documented as intentional delegation to avoid duplicate-screen confusion.
- The backend surface is large (`115` migrations plus extensive function logic), which raises schema/change-management risk and makes migration discipline critical.
- The repo carries multiple public web surfaces (`hosting/`, `landing/`, `deeplinks/`) that can diverge unless ownership and deployment responsibilities stay explicit.

## Bottom Line

This repo is a multi-domain Flutter superapp with consumer, operator, admin, partner, and club/fan surfaces backed by Supabase + Firebase and supplemented by multiple web/deeplink entrypoints. The screen inventory above is the current implemented runtime surface, with related module files and assets enumerated from source so future redesign or audit work can start from an explicit code-backed map instead of informal knowledge.
