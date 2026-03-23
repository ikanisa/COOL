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

- `82` screen files measured
- `36` review-range screens
- `7` debt screens
- `1` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`rayon_home_screen_parts.dart`](../lib/features/partners/rayon/screens/rayon_home_screen_parts.dart) | `1077` | Hotspot |
| [`operational_dashboard_parts.dart`](../lib/features/admin/screens/operational_dashboard_parts.dart) | `914` | Debt |
| [`rs_admin_initiatives_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | `820` | Debt |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `818` | Debt |
| [`club_shop_screen.dart`](../lib/features/partners/rayon/screens/club_shop_screen.dart) | `756` | Debt |
| [`biopay_scan_screen.dart`](../lib/features/biopay/screens/biopay_scan_screen.dart) | `756` | Debt |
| [`schedule_trip_screen_logic.dart`](../lib/features/mobility/screens/schedule_trip_screen_logic.dart) | `731` | Debt |
| [`manage_missions_screen.dart`](../lib/features/admin/screens/manage_missions_screen.dart) | `713` | Debt |
| [`group_ledger_screen.dart`](../lib/features/groups/screens/group_ledger_screen.dart) | `693` | Review |
| [`manage_special_products_screen.dart`](../lib/features/admin/screens/manage_special_products_screen.dart) | `691` | Review |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `690` | Review |
| [`rs_admin_members_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | `690` | Review |
| [`kyc_id_scan_screen.dart`](../lib/features/profile/screens/kyc_id_scan_screen.dart) | `686` | Review |
| [`schedule_trip_screen.dart`](../lib/features/mobility/screens/schedule_trip_screen.dart) | `675` | Review |
| [`rs_admin_orders_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | `670` | Review |
| [`manage_seasons_screen.dart`](../lib/features/admin/screens/manage_seasons_screen.dart) | `658` | Review |
| [`manage_activities_screen.dart`](../lib/features/admin/screens/manage_activities_screen.dart) | `624` | Review |
| [`manage_partners_screen.dart`](../lib/features/admin/screens/manage_partners_screen.dart) | `620` | Review |
| [`rs_admin_shop_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | `610` | Review |
| [`fan_club_detail_screen.dart`](../lib/features/partners/rayon/screens/fan_club_detail_screen.dart) | `601` | Review |
| [`rs_admin_packages_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_packages_screen.dart) | `589` | Review |
| [`credit_score_screen.dart`](../lib/features/credit/screens/credit_score_screen.dart) | `576` | Review |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `573` | Review |
| [`rs_admin_tickets_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | `573` | Review |
| [`fan_clubs_screen.dart`](../lib/features/partners/rayon/screens/fan_clubs_screen.dart) | `561` | Review |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `523` | Review |
| [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart) | `505` | Review |
| [`trip_board_screen.dart`](../lib/features/mobility/screens/trip_board_screen.dart) | `500` | Review |
| [`membership_tiers_screen.dart`](../lib/features/partners/rayon/screens/membership_tiers_screen.dart) | `497` | Review |
| [`rs_admin_matches_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | `480` | Review |
| [`driver_profile_screen.dart`](../lib/features/mobility/screens/driver_profile_screen.dart) | `464` | Review |
| [`register_screen.dart`](../lib/features/auth/screens/register_screen.dart) | `463` | Review |
| [`seasons_activities_screen.dart`](../lib/features/home/screens/seasons_activities_screen.dart) | `457` | Review |
| [`manage_quick_actions_screen.dart`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | `440` | Review |
| [`tickets_screen.dart`](../lib/features/partners/rayon/screens/tickets_screen.dart) | `439` | Review |
| [`rs_admin_dashboard_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | `439` | Review |
| [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart) | `437` | Review |
| [`manage_ai_content_screen.dart`](../lib/features/admin/screens/manage_ai_content_screen.dart) | `426` | Review |
| [`rs_admin_analytics_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart) | `425` | Review |
| [`rs_admin_finance_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_finance_screen.dart) | `420` | Review |
| [`manage_vehicle_types_screen.dart`](../lib/features/admin/screens/manage_vehicle_types_screen.dart) | `406` | Review |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `406` | Review |
| [`group_invite_screen.dart`](../lib/features/groups/screens/group_invite_screen.dart) | `401` | Review |
| [`support_screen.dart`](../lib/features/partners/rayon/screens/support_screen.dart) | `401` | Review |
| [`system_analytics_screen.dart`](../lib/features/admin/screens/system_analytics_screen.dart) | `395` | Target |
| [`partner_admin_workspace_screen.dart`](../lib/features/admin/screens/partner_admin_workspace_screen.dart) | `394` | Target |
| [`otp_verify_screen.dart`](../lib/features/auth/screens/otp_verify_screen.dart) | `393` | Target |
| [`biopay_register_screen.dart`](../lib/features/biopay/screens/biopay_register_screen.dart) | `387` | Target |
| [`mobility_home_screen.dart`](../lib/features/mobility/screens/mobility_home_screen.dart) | `384` | Target |
| [`app_access_onboarding_screen.dart`](../lib/features/auth/screens/app_access_onboarding_screen.dart) | `382` | Target |
| [`admin_workspaces_screen.dart`](../lib/features/admin/screens/admin_workspaces_screen.dart) | `381` | Target |
| [`ticket_confirmation_screen.dart`](../lib/features/partners/rayon/screens/ticket_confirmation_screen.dart) | `376` | Target |
| [`audit_log_screen.dart`](../lib/features/admin/screens/audit_log_screen.dart) | `371` | Target |
| [`radiant_partner_screen.dart`](../lib/features/partners/screens/radiant_partner_screen.dart) | `369` | Target |
| [`bank_onboarding_screen.dart`](../lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart) | `358` | Target |
| [`momo_screen_parts.dart`](../lib/features/momo/screens/momo_screen_parts.dart) | `358` | Target |
| [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart) | `339` | Target |
| [`my_tickets_screen.dart`](../lib/features/partners/rayon/screens/my_tickets_screen.dart) | `337` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `321` | Target |
| [`otp_screen.dart`](../lib/features/auth/screens/otp_screen.dart) | `313` | Target |
| [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart) | `304` | Target |
| [`bank_admin_workspace_screen.dart`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | `298` | Target |
| [`driver_detail_screens.dart`](../lib/features/mobility/screens/driver_detail_screens.dart) | `288` | Target |
| [`manage_services_screen.dart`](../lib/features/admin/screens/manage_services_screen.dart) | `286` | Target |
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `275` | Target |
| [`rayon_home_screen.dart`](../lib/features/partners/rayon/screens/rayon_home_screen.dart) | `262` | Target |
| [`biopay_home_screen.dart`](../lib/features/biopay/screens/biopay_home_screen.dart) | `245` | Target |
| [`biopay_confirm_screen.dart`](../lib/features/biopay/screens/biopay_confirm_screen.dart) | `232` | Target |
| [`shop_checkout_screen.dart`](../lib/features/partners/rayon/screens/shop_checkout_screen.dart) | `232` | Target |
| [`member_registry_screen.dart`](../lib/features/partners/rayon/screens/member_registry_screen.dart) | `229` | Target |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `217` | Target |
| [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) | `167` | Target |
| [`splash_screen.dart`](../lib/features/auth/screens/splash_screen.dart) | `164` | Target |
| [`prisma_partner_screen.dart`](../lib/features/partners/screens/prisma_partner_screen.dart) | `161` | Target |
| [`manage_admin_roles_screen.dart`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | `153` | Target |
| [`partners_screen.dart`](../lib/features/partners/screens/partners_screen.dart) | `131` | Target |
| [`bank_partner_screen.dart`](../lib/features/partners/screens/bank_partner_screen.dart) | `129` | Target |
| [`profile_detail_screens.dart`](../lib/features/profile/screens/profile_detail_screens.dart) | `123` | Target |
| [`credit_readiness_screen.dart`](../lib/features/credit/screens/credit_readiness_screen.dart) | `118` | Target |
| [`onboarding_screen.dart`](../lib/features/auth/screens/onboarding_screen.dart) | `95` | Target |
| [`momo_nfc_screen.dart`](../lib/features/momo/screens/momo_nfc_screen.dart) | `72` | Target |
| [`kyc_selfie_screen.dart`](../lib/features/profile/screens/kyc_selfie_screen.dart) | `12` | Target |
