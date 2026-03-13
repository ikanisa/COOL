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

- `52` screen files measured
- `19` review-range screens
- `6` debt screens
- `2` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart) | `1140` | Hotspot |
| [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) | `1030` | Hotspot |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `908` | Debt |
| [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart) | `854` | Debt |
| [`tickets_screen.dart`](../lib/features/partners/screens/rayon/tickets_screen.dart) | `810` | Debt |
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `804` | Debt |
| [`shop_checkout_screen.dart`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart) | `780` | Debt |
| [`member_registry_screen.dart`](../lib/features/partners/screens/rayon/member_registry_screen.dart) | `718` | Debt |
| [`driver_profile_screen.dart`](../lib/features/mobility/screens/driver_profile_screen.dart) | `695` | Review |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `625` | Review |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `597` | Review |
| [`schedule_trip_screen_logic.dart`](../lib/features/mobility/screens/schedule_trip_screen_logic.dart) | `587` | Review |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `579` | Review |
| [`club_shop_screen.dart`](../lib/features/partners/screens/rayon/club_shop_screen.dart) | `576` | Review |
| [`membership_tiers_screen.dart`](../lib/features/partners/rayon/screens/membership_tiers_screen.dart) | `534` | Review |
| [`rayon_home_screen.dart`](../lib/features/partners/rayon/screens/rayon_home_screen.dart) | `526` | Review |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `515` | Review |
| [`fan_club_detail_screen.dart`](../lib/features/partners/screens/rayon/fan_club_detail_screen.dart) | `507` | Review |
| [`trip_board_screen.dart`](../lib/features/mobility/screens/trip_board_screen.dart) | `480` | Review |
| [`register_screen.dart`](../lib/features/auth/screens/register_screen.dart) | `474` | Review |
| [`manage_services_screen.dart`](../lib/features/admin/screens/manage_services_screen.dart) | `462` | Review |
| [`rs_admin_matches_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | `445` | Review |
| [`support_screen.dart`](../lib/features/partners/rayon/screens/support_screen.dart) | `427` | Review |
| [`fan_clubs_screen.dart`](../lib/features/partners/screens/rayon/fan_clubs_screen.dart) | `426` | Review |
| [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart) | `426` | Review |
| [`rs_admin_shop_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | `425` | Review |
| [`manage_partners_screen.dart`](../lib/features/admin/screens/manage_partners_screen.dart) | `422` | Review |
| [`rs_admin_initiatives_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | `397` | Target |
| [`rs_admin_members_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | `392` | Target |
| [`otp_verify_screen.dart`](../lib/features/auth/screens/otp_verify_screen.dart) | `388` | Target |
| [`group_invite_screen.dart`](../lib/features/groups/screens/group_invite_screen.dart) | `385` | Target |
| [`manage_quick_actions_screen.dart`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | `357` | Target |
| [`my_tickets_screen.dart`](../lib/features/partners/screens/rayon/my_tickets_screen.dart) | `355` | Target |
| [`radiant_partner_screen.dart`](../lib/features/partners/screens/radiant_partner_screen.dart) | `353` | Target |
| [`schedule_trip_screen.dart`](../lib/features/mobility/screens/schedule_trip_screen.dart) | `336` | Target |
| [`mobility_home_screen.dart`](../lib/features/mobility/screens/mobility_home_screen.dart) | `328` | Target |
| [`rs_admin_tickets_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | `327` | Target |
| [`manage_vehicle_types_screen.dart`](../lib/features/admin/screens/manage_vehicle_types_screen.dart) | `303` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `301` | Target |
| [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart) | `281` | Target |
| [`otp_screen.dart`](../lib/features/auth/screens/otp_screen.dart) | `274` | Target |
| [`rs_admin_dashboard_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | `246` | Target |
| [`rs_admin_orders_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | `218` | Target |
| [`ticket_confirmation_screen.dart`](../lib/features/partners/screens/rayon/ticket_confirmation_screen.dart) | `203` | Target |
| [`credit_score_screen.dart`](../lib/features/credit/screens/credit_score_screen.dart) | `185` | Target |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `170` | Target |
| [`splash_screen.dart`](../lib/features/auth/screens/splash_screen.dart) | `159` | Target |
| [`bank_partner_screen.dart`](../lib/features/partners/screens/bank_partner_screen.dart) | `156` | Target |
| [`prisma_partner_screen.dart`](../lib/features/partners/screens/prisma_partner_screen.dart) | `150` | Target |
| [`partners_screen.dart`](../lib/features/partners/screens/partners_screen.dart) | `132` | Target |
| [`onboarding_screen.dart`](../lib/features/auth/screens/onboarding_screen.dart) | `126` | Target |
| [`credit_readiness_screen.dart`](../lib/features/credit/screens/credit_readiness_screen.dart) | `107` | Target |
