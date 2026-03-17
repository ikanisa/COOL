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

- `73` screen files measured
- `31` review-range screens
- `8` debt screens
- `6` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `1310` | Hotspot |
| [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart) | `1216` | Hotspot |
| [`manage_ai_content_screen.dart`](../lib/features/admin/screens/manage_ai_content_screen.dart) | `1114` | Hotspot |
| [`manage_partners_screen.dart`](../lib/features/admin/screens/manage_partners_screen.dart) | `1061` | Hotspot |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `1043` | Hotspot |
| [`shop_checkout_screen.dart`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart) | `1006` | Hotspot |
| [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) | `913` | Debt |
| [`bank_admin_workspace_screen.dart`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | `898` | Debt |
| [`rs_admin_finance_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_finance_screen.dart) | `851` | Debt |
| [`schedule_trip_screen_logic.dart`](../lib/features/mobility/screens/schedule_trip_screen_logic.dart) | `851` | Debt |
| [`driver_detail_screens.dart`](../lib/features/mobility/screens/driver_detail_screens.dart) | `820` | Debt |
| [`member_registry_screen.dart`](../lib/features/partners/screens/rayon/member_registry_screen.dart) | `755` | Debt |
| [`manage_admin_roles_screen.dart`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | `742` | Debt |
| [`tickets_screen.dart`](../lib/features/partners/screens/rayon/tickets_screen.dart) | `728` | Debt |
| [`kyc_id_scan_screen.dart`](../lib/features/profile/screens/kyc_id_scan_screen.dart) | `690` | Review |
| [`rs_admin_initiatives_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | `677` | Review |
| [`group_ledger_screen.dart`](../lib/features/groups/screens/group_ledger_screen.dart) | `675` | Review |
| [`manage_missions_screen.dart`](../lib/features/admin/screens/manage_missions_screen.dart) | `637` | Review |
| [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart) | `635` | Review |
| [`manage_special_products_screen.dart`](../lib/features/admin/screens/manage_special_products_screen.dart) | `613` | Review |
| [`manage_seasons_screen.dart`](../lib/features/admin/screens/manage_seasons_screen.dart) | `584` | Review |
| [`rs_admin_shop_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | `575` | Review |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `573` | Review |
| [`rs_admin_packages_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_packages_screen.dart) | `571` | Review |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `570` | Review |
| [`manage_activities_screen.dart`](../lib/features/admin/screens/manage_activities_screen.dart) | `565` | Review |
| [`credit_score_screen.dart`](../lib/features/credit/screens/credit_score_screen.dart) | `565` | Review |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `562` | Review |
| [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart) | `554` | Review |
| [`rs_admin_members_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | `550` | Review |
| [`rs_admin_tickets_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | `523` | Review |
| [`fan_club_detail_screen.dart`](../lib/features/partners/screens/rayon/fan_club_detail_screen.dart) | `523` | Review |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `510` | Review |
| [`rayon_home_screen.dart`](../lib/features/partners/rayon/screens/rayon_home_screen.dart) | `509` | Review |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `499` | Review |
| [`membership_tiers_screen.dart`](../lib/features/partners/rayon/screens/membership_tiers_screen.dart) | `490` | Review |
| [`trip_board_screen.dart`](../lib/features/mobility/screens/trip_board_screen.dart) | `486` | Review |
| [`driver_profile_screen.dart`](../lib/features/mobility/screens/driver_profile_screen.dart) | `483` | Review |
| [`club_shop_screen.dart`](../lib/features/partners/screens/rayon/club_shop_screen.dart) | `482` | Review |
| [`register_screen.dart`](../lib/features/auth/screens/register_screen.dart) | `474` | Review |
| [`manage_services_screen.dart`](../lib/features/admin/screens/manage_services_screen.dart) | `459` | Review |
| [`rs_admin_orders_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | `451` | Review |
| [`rs_admin_matches_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | `447` | Review |
| [`rs_admin_dashboard_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | `423` | Review |
| [`fan_clubs_screen.dart`](../lib/features/partners/screens/rayon/fan_clubs_screen.dart) | `409` | Review |
| [`schedule_trip_screen.dart`](../lib/features/mobility/screens/schedule_trip_screen.dart) | `395` | Target |
| [`otp_verify_screen.dart`](../lib/features/auth/screens/otp_verify_screen.dart) | `387` | Target |
| [`group_invite_screen.dart`](../lib/features/groups/screens/group_invite_screen.dart) | `386` | Target |
| [`admin_workspaces_screen.dart`](../lib/features/admin/screens/admin_workspaces_screen.dart) | `371` | Target |
| [`manage_quick_actions_screen.dart`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | `358` | Target |
| [`audit_log_screen.dart`](../lib/features/admin/screens/audit_log_screen.dart) | `354` | Target |
| [`radiant_partner_screen.dart`](../lib/features/partners/screens/radiant_partner_screen.dart) | `354` | Target |
| [`bank_onboarding_screen.dart`](../lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart) | `353` | Target |
| [`system_analytics_screen.dart`](../lib/features/admin/screens/system_analytics_screen.dart) | `327` | Target |
| [`manage_vehicle_types_screen.dart`](../lib/features/admin/screens/manage_vehicle_types_screen.dart) | `322` | Target |
| [`support_screen.dart`](../lib/features/partners/rayon/screens/support_screen.dart) | `313` | Target |
| [`my_tickets_screen.dart`](../lib/features/partners/screens/rayon/my_tickets_screen.dart) | `311` | Target |
| [`otp_screen.dart`](../lib/features/auth/screens/otp_screen.dart) | `307` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `305` | Target |
| [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart) | `253` | Target |
| [`rs_admin_analytics_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart) | `223` | Target |
| [`mobility_home_screen.dart`](../lib/features/mobility/screens/mobility_home_screen.dart) | `216` | Target |
| [`ticket_confirmation_screen.dart`](../lib/features/partners/screens/rayon/ticket_confirmation_screen.dart) | `204` | Target |
| [`partner_admin_workspace_screen.dart`](../lib/features/admin/screens/partner_admin_workspace_screen.dart) | `170` | Target |
| [`splash_screen.dart`](../lib/features/auth/screens/splash_screen.dart) | `160` | Target |
| [`prisma_partner_screen.dart`](../lib/features/partners/screens/prisma_partner_screen.dart) | `151` | Target |
| [`partners_screen.dart`](../lib/features/partners/screens/partners_screen.dart) | `138` | Target |
| [`profile_detail_screens.dart`](../lib/features/profile/screens/profile_detail_screens.dart) | `122` | Target |
| [`bank_partner_screen.dart`](../lib/features/partners/screens/bank_partner_screen.dart) | `121` | Target |
| [`credit_readiness_screen.dart`](../lib/features/credit/screens/credit_readiness_screen.dart) | `109` | Target |
| [`onboarding_screen.dart`](../lib/features/auth/screens/onboarding_screen.dart) | `83` | Target |
| [`momo_nfc_screen.dart`](../lib/features/momo/screens/momo_nfc_screen.dart) | `67` | Target |
| [`kyc_selfie_screen.dart`](../lib/features/profile/screens/kyc_selfie_screen.dart) | `12` | Target |
