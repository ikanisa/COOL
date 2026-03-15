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

- `59` screen files measured
- `19` review-range screens
- `7` debt screens
- `5` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`bank_admin_workspace_screen.dart`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | `1746` | Hotspot |
| [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart) | `1216` | Hotspot |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `1079` | Hotspot |
| [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart) | `1052` | Hotspot |
| [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) | `1029` | Hotspot |
| [`shop_checkout_screen.dart`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart) | `980` | Debt |
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `930` | Debt |
| [`tickets_screen.dart`](../lib/features/partners/screens/rayon/tickets_screen.dart) | `859` | Debt |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `848` | Debt |
| [`rs_admin_finance_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_finance_screen.dart) | `826` | Debt |
| [`driver_detail_screens.dart`](../lib/features/mobility/screens/driver_detail_screens.dart) | `820` | Debt |
| [`member_registry_screen.dart`](../lib/features/partners/screens/rayon/member_registry_screen.dart) | `755` | Debt |
| [`rayon_home_screen.dart`](../lib/features/partners/rayon/screens/rayon_home_screen.dart) | `650` | Review |
| [`club_shop_screen.dart`](../lib/features/partners/screens/rayon/club_shop_screen.dart) | `621` | Review |
| [`schedule_trip_screen_logic.dart`](../lib/features/mobility/screens/schedule_trip_screen_logic.dart) | `619` | Review |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `603` | Review |
| [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart) | `603` | Review |
| [`rs_admin_packages_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_packages_screen.dart) | `570` | Review |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `563` | Review |
| [`trip_board_screen.dart`](../lib/features/mobility/screens/trip_board_screen.dart) | `544` | Review |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `526` | Review |
| [`fan_club_detail_screen.dart`](../lib/features/partners/screens/rayon/fan_club_detail_screen.dart) | `523` | Review |
| [`fan_clubs_screen.dart`](../lib/features/partners/screens/rayon/fan_clubs_screen.dart) | `516` | Review |
| [`membership_tiers_screen.dart`](../lib/features/partners/rayon/screens/membership_tiers_screen.dart) | `488` | Review |
| [`driver_profile_screen.dart`](../lib/features/mobility/screens/driver_profile_screen.dart) | `483` | Review |
| [`register_screen.dart`](../lib/features/auth/screens/register_screen.dart) | `465` | Review |
| [`manage_services_screen.dart`](../lib/features/admin/screens/manage_services_screen.dart) | `459` | Review |
| [`schedule_trip_screen.dart`](../lib/features/mobility/screens/schedule_trip_screen.dart) | `459` | Review |
| [`rs_admin_matches_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | `446` | Review |
| [`manage_partners_screen.dart`](../lib/features/admin/screens/manage_partners_screen.dart) | `434` | Review |
| [`rs_admin_shop_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | `428` | Review |
| [`rs_admin_initiatives_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | `397` | Target |
| [`otp_verify_screen.dart`](../lib/features/auth/screens/otp_verify_screen.dart) | `389` | Target |
| [`group_invite_screen.dart`](../lib/features/groups/screens/group_invite_screen.dart) | `386` | Target |
| [`admin_workspaces_screen.dart`](../lib/features/admin/screens/admin_workspaces_screen.dart) | `371` | Target |
| [`rs_admin_members_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | `365` | Target |
| [`support_screen.dart`](../lib/features/partners/rayon/screens/support_screen.dart) | `362` | Target |
| [`manage_quick_actions_screen.dart`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | `358` | Target |
| [`radiant_partner_screen.dart`](../lib/features/partners/screens/radiant_partner_screen.dart) | `354` | Target |
| [`rs_admin_tickets_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | `316` | Target |
| [`manage_vehicle_types_screen.dart`](../lib/features/admin/screens/manage_vehicle_types_screen.dart) | `315` | Target |
| [`my_tickets_screen.dart`](../lib/features/partners/screens/rayon/my_tickets_screen.dart) | `311` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `304` | Target |
| [`otp_screen.dart`](../lib/features/auth/screens/otp_screen.dart) | `303` | Target |
| [`mobility_home_screen.dart`](../lib/features/mobility/screens/mobility_home_screen.dart) | `300` | Target |
| [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart) | `263` | Target |
| [`rs_admin_orders_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | `219` | Target |
| [`partner_admin_workspace_screen.dart`](../lib/features/admin/screens/partner_admin_workspace_screen.dart) | `214` | Target |
| [`ticket_confirmation_screen.dart`](../lib/features/partners/screens/rayon/ticket_confirmation_screen.dart) | `204` | Target |
| [`credit_score_screen.dart`](../lib/features/credit/screens/credit_score_screen.dart) | `201` | Target |
| [`rs_admin_dashboard_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | `189` | Target |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `173` | Target |
| [`profile_detail_screens.dart`](../lib/features/profile/screens/profile_detail_screens.dart) | `163` | Target |
| [`splash_screen.dart`](../lib/features/auth/screens/splash_screen.dart) | `160` | Target |
| [`bank_partner_screen.dart`](../lib/features/partners/screens/bank_partner_screen.dart) | `157` | Target |
| [`prisma_partner_screen.dart`](../lib/features/partners/screens/prisma_partner_screen.dart) | `151` | Target |
| [`partners_screen.dart`](../lib/features/partners/screens/partners_screen.dart) | `138` | Target |
| [`credit_readiness_screen.dart`](../lib/features/credit/screens/credit_readiness_screen.dart) | `108` | Target |
| [`onboarding_screen.dart`](../lib/features/auth/screens/onboarding_screen.dart) | `83` | Target |
