# Screen Budgets

Generated from `lib/features/**/screens/*.dart`.

Why this exists:

- Route scope should be visible from code, not remembered in reviews.
- Hotspots and debt screens must be obvious before new UI work lands.
- Regenerating this file keeps the current budget state auditable.

## Budget Rules

### New Screens

| Budget | Threshold | Requirement |
|---|---|---|
| Target | `<= 400` LOC | Normal case for new user-facing routes |
| Review | `401-700` LOC | Allowed only with extracted widgets/services and a justification in PR notes |
| Block | `> 700` LOC | Do not merge as a new route without splitting the flow |

### Existing Screens

| Budget | Threshold | Requirement |
|---|---|---|
| Stable | `<= 700` LOC | Can evolve normally |
| Debt | `701-1000` LOC | New work should reduce or at least not grow route responsibility |
| Hotspot | `> 1000` LOC | Do not grow the file unless the work is explicitly simplifying it |

## Current Snapshot

- `75` screen files measured
- `32` review-range screens
- `5` debt screens
- `1` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`rayon_home_screen.dart`](../lib/features/partners/rayon/screens/rayon_home_screen.dart) | `1410` | Hotspot |
| [`rs_admin_initiatives_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | `820` | Debt |
| [`schedule_trip_screen_logic.dart`](../lib/features/mobility/screens/schedule_trip_screen_logic.dart) | `803` | Debt |
| [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart) | `784` | Debt |
| [`fan_club_detail_screen.dart`](../lib/features/partners/rayon/screens/fan_club_detail_screen.dart) | `762` | Debt |
| [`club_shop_screen.dart`](../lib/features/partners/rayon/screens/club_shop_screen.dart) | `758` | Debt |
| [`kyc_id_scan_screen.dart`](../lib/features/profile/screens/kyc_id_scan_screen.dart) | `698` | Review |
| [`rs_admin_members_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | `692` | Review |
| [`group_ledger_screen.dart`](../lib/features/groups/screens/group_ledger_screen.dart) | `689` | Review |
| [`rs_admin_orders_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | `671` | Review |
| [`schedule_trip_screen.dart`](../lib/features/mobility/screens/schedule_trip_screen.dart) | `669` | Review |
| [`manage_missions_screen.dart`](../lib/features/admin/screens/manage_missions_screen.dart) | `655` | Review |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `632` | Review |
| [`manage_special_products_screen.dart`](../lib/features/admin/screens/manage_special_products_screen.dart) | `628` | Review |
| [`fan_clubs_screen.dart`](../lib/features/partners/rayon/screens/fan_clubs_screen.dart) | `620` | Review |
| [`rs_admin_shop_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | `608` | Review |
| [`manage_seasons_screen.dart`](../lib/features/admin/screens/manage_seasons_screen.dart) | `602` | Review |
| [`rs_admin_packages_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_packages_screen.dart) | `592` | Review |
| [`manage_partners_screen.dart`](../lib/features/admin/screens/manage_partners_screen.dart) | `583` | Review |
| [`manage_activities_screen.dart`](../lib/features/admin/screens/manage_activities_screen.dart) | `580` | Review |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `580` | Review |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `571` | Review |
| [`rs_admin_tickets_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | `568` | Review |
| [`credit_score_screen.dart`](../lib/features/credit/screens/credit_score_screen.dart) | `563` | Review |
| [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart) | `533` | Review |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `516` | Review |
| [`membership_tiers_screen.dart`](../lib/features/partners/rayon/screens/membership_tiers_screen.dart) | `496` | Review |
| [`trip_board_screen.dart`](../lib/features/mobility/screens/trip_board_screen.dart) | `487` | Review |
| [`driver_profile_screen.dart`](../lib/features/mobility/screens/driver_profile_screen.dart) | `483` | Review |
| [`rs_admin_matches_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | `478` | Review |
| [`register_screen.dart`](../lib/features/auth/screens/register_screen.dart) | `476` | Review |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `468` | Review |
| [`tickets_screen.dart`](../lib/features/partners/rayon/screens/tickets_screen.dart) | `445` | Review |
| [`seasons_activities_screen.dart`](../lib/features/home/screens/seasons_activities_screen.dart) | `434` | Review |
| [`rs_admin_analytics_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart) | `428` | Review |
| [`rs_admin_dashboard_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | `427` | Review |
| [`rs_admin_finance_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_finance_screen.dart) | `425` | Review |
| [`otp_verify_screen.dart`](../lib/features/auth/screens/otp_verify_screen.dart) | `403` | Review |
| [`group_invite_screen.dart`](../lib/features/groups/screens/group_invite_screen.dart) | `399` | Target |
| [`manage_ai_content_screen.dart`](../lib/features/admin/screens/manage_ai_content_screen.dart) | `389` | Target |
| [`app_access_onboarding_screen.dart`](../lib/features/auth/screens/app_access_onboarding_screen.dart) | `382` | Target |
| [`admin_workspaces_screen.dart`](../lib/features/admin/screens/admin_workspaces_screen.dart) | `381` | Target |
| [`support_screen.dart`](../lib/features/partners/rayon/screens/support_screen.dart) | `376` | Target |
| [`partner_admin_workspace_screen.dart`](../lib/features/admin/screens/partner_admin_workspace_screen.dart) | `376` | Target |
| [`ticket_confirmation_screen.dart`](../lib/features/partners/rayon/screens/ticket_confirmation_screen.dart) | `376` | Target |
| [`mobility_home_screen.dart`](../lib/features/mobility/screens/mobility_home_screen.dart) | `375` | Target |
| [`manage_quick_actions_screen.dart`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | `372` | Target |
| [`audit_log_screen.dart`](../lib/features/admin/screens/audit_log_screen.dart) | `368` | Target |
| [`radiant_partner_screen.dart`](../lib/features/partners/screens/radiant_partner_screen.dart) | `359` | Target |
| [`bank_onboarding_screen.dart`](../lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart) | `353` | Target |
| [`system_analytics_screen.dart`](../lib/features/admin/screens/system_analytics_screen.dart) | `342` | Target |
| [`manage_vehicle_types_screen.dart`](../lib/features/admin/screens/manage_vehicle_types_screen.dart) | `335` | Target |
| [`otp_screen.dart`](../lib/features/auth/screens/otp_screen.dart) | `318` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `318` | Target |
| [`my_tickets_screen.dart`](../lib/features/partners/rayon/screens/my_tickets_screen.dart) | `314` | Target |
| [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart) | `300` | Target |
| [`member_registry_screen.dart`](../lib/features/partners/rayon/screens/member_registry_screen.dart) | `296` | Target |
| [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart) | `288` | Target |
| [`manage_services_screen.dart`](../lib/features/admin/screens/manage_services_screen.dart) | `276` | Target |
| [`driver_detail_screens.dart`](../lib/features/mobility/screens/driver_detail_screens.dart) | `274` | Target |
| [`bank_admin_workspace_screen.dart`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | `274` | Target |
| [`shop_checkout_screen.dart`](../lib/features/partners/rayon/screens/shop_checkout_screen.dart) | `235` | Target |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `219` | Target |
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `190` | Target |
| [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) | `172` | Target |
| [`splash_screen.dart`](../lib/features/auth/screens/splash_screen.dart) | `171` | Target |
| [`partners_screen.dart`](../lib/features/partners/screens/partners_screen.dart) | `161` | Target |
| [`prisma_partner_screen.dart`](../lib/features/partners/screens/prisma_partner_screen.dart) | `155` | Target |
| [`manage_admin_roles_screen.dart`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | `138` | Target |
| [`bank_partner_screen.dart`](../lib/features/partners/screens/bank_partner_screen.dart) | `125` | Target |
| [`profile_detail_screens.dart`](../lib/features/profile/screens/profile_detail_screens.dart) | `124` | Target |
| [`credit_readiness_screen.dart`](../lib/features/credit/screens/credit_readiness_screen.dart) | `112` | Target |
| [`onboarding_screen.dart`](../lib/features/auth/screens/onboarding_screen.dart) | `91` | Target |
| [`momo_nfc_screen.dart`](../lib/features/momo/screens/momo_nfc_screen.dart) | `67` | Target |
| [`kyc_selfie_screen.dart`](../lib/features/profile/screens/kyc_selfie_screen.dart) | `12` | Target |
