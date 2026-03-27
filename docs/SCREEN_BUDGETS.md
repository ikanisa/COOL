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

- `67` screen files measured
- `25` review-range screens
- `6` debt screens
- `2` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`club_shop_screen.dart`](../lib/features/partners/rayon/screens/club_shop_screen.dart) | `1418` | Hotspot |
| [`profile_sub_screens.dart`](../lib/features/profile/screens/profile_sub_screens.dart) | `1150` | Hotspot |
| [`operational_dashboard_parts.dart`](../lib/features/admin/screens/operational_dashboard_parts.dart) | `914` | Debt |
| [`rs_admin_initiatives_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | `821` | Debt |
| [`biopay_scan_screen.dart`](../lib/features/biopay/screens/biopay_scan_screen.dart) | `807` | Debt |
| [`product_detail_screen.dart`](../lib/features/partners/rayon/screens/product_detail_screen.dart) | `775` | Debt |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `772` | Debt |
| [`manage_missions_screen.dart`](../lib/features/admin/screens/manage_missions_screen.dart) | `713` | Debt |
| [`group_ledger_screen.dart`](../lib/features/groups/screens/group_ledger_screen.dart) | `694` | Review |
| [`manage_special_products_screen.dart`](../lib/features/admin/screens/manage_special_products_screen.dart) | `691` | Review |
| [`rs_admin_members_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | `691` | Review |
| [`rs_admin_orders_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | `670` | Review |
| [`manage_seasons_screen.dart`](../lib/features/admin/screens/manage_seasons_screen.dart) | `659` | Review |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `626` | Review |
| [`manage_activities_screen.dart`](../lib/features/admin/screens/manage_activities_screen.dart) | `624` | Review |
| [`manage_partners_screen.dart`](../lib/features/admin/screens/manage_partners_screen.dart) | `620` | Review |
| [`rs_admin_shop_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | `610` | Review |
| [`rs_admin_packages_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_packages_screen.dart) | `590` | Review |
| [`rs_admin_tickets_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | `574` | Review |
| [`fan_clubs_screen.dart`](../lib/features/partners/rayon/screens/fan_clubs_screen.dart) | `561` | Review |
| [`fan_club_detail_screen.dart`](../lib/features/partners/rayon/screens/fan_club_detail_screen.dart) | `527` | Review |
| [`seasons_activities_screen.dart`](../lib/features/home/screens/seasons_activities_screen.dart) | `519` | Review |
| [`membership_tiers_screen.dart`](../lib/features/partners/rayon/screens/membership_tiers_screen.dart) | `498` | Review |
| [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart) | `495` | Review |
| [`rs_admin_matches_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | `480` | Review |
| [`support_screen.dart`](../lib/features/partners/rayon/screens/support_screen.dart) | `448` | Review |
| [`groups_screen_parts.dart`](../lib/features/groups/screens/groups_screen_parts.dart) | `442` | Review |
| [`rs_admin_dashboard_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | `439` | Review |
| [`admin_dashboard_parts.dart`](../lib/features/admin/screens/admin_dashboard_parts.dart) | `433` | Review |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `432` | Review |
| [`rs_admin_analytics_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart) | `425` | Review |
| [`rs_admin_finance_screen.dart`](../lib/features/partners/rayon/screens/rs_admin_finance_screen.dart) | `420` | Review |
| [`manage_ai_content_screen.dart`](../lib/features/admin/screens/manage_ai_content_screen.dart) | `405` | Review |
| [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart) | `400` | Target |
| [`tickets_screen.dart`](../lib/features/partners/rayon/screens/tickets_screen.dart) | `399` | Target |
| [`admin_workspaces_screen.dart`](../lib/features/admin/screens/admin_workspaces_screen.dart) | `396` | Target |
| [`partner_admin_workspace_screen.dart`](../lib/features/admin/screens/partner_admin_workspace_screen.dart) | `394` | Target |
| [`manage_quick_actions_screen.dart`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | `393` | Target |
| [`group_invite_screen.dart`](../lib/features/groups/screens/group_invite_screen.dart) | `388` | Target |
| [`biopay_register_screen.dart`](../lib/features/biopay/screens/biopay_register_screen.dart) | `387` | Target |
| [`system_analytics_screen.dart`](../lib/features/admin/screens/system_analytics_screen.dart) | `378` | Target |
| [`ticket_confirmation_screen.dart`](../lib/features/partners/rayon/screens/ticket_confirmation_screen.dart) | `376` | Target |
| [`biopay_nfc_screen.dart`](../lib/features/biopay/screens/biopay_nfc_screen.dart) | `375` | Target |
| [`audit_log_screen.dart`](../lib/features/admin/screens/audit_log_screen.dart) | `371` | Target |
| [`radiant_partner_screen.dart`](../lib/features/partners/screens/radiant_partner_screen.dart) | `369` | Target |
| [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart) | `340` | Target |
| [`my_tickets_screen.dart`](../lib/features/partners/rayon/screens/my_tickets_screen.dart) | `337` | Target |
| [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart) | `304` | Target |
| [`manage_services_screen.dart`](../lib/features/admin/screens/manage_services_screen.dart) | `286` | Target |
| [`member_registry_screen.dart`](../lib/features/partners/rayon/screens/member_registry_screen.dart) | `285` | Target |
| [`bank_admin_workspace_screen.dart`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | `281` | Target |
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `280` | Target |
| [`biopay_home_screen.dart`](../lib/features/biopay/screens/biopay_home_screen.dart) | `277` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `255` | Target |
| [`momo_screen_parts.dart`](../lib/features/momo/screens/momo_screen_parts.dart) | `241` | Target |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `240` | Target |
| [`shop_checkout_screen.dart`](../lib/features/partners/rayon/screens/shop_checkout_screen.dart) | `221` | Target |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `203` | Target |
| [`splash_screen.dart`](../lib/features/auth/screens/splash_screen.dart) | `202` | Target |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `171` | Target |
| [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) | `166` | Target |
| [`partners_screen.dart`](../lib/features/partners/screens/partners_screen.dart) | `165` | Target |
| [`prisma_partner_screen.dart`](../lib/features/partners/screens/prisma_partner_screen.dart) | `161` | Target |
| [`manage_admin_roles_screen.dart`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | `153` | Target |
| [`bank_partner_screen.dart`](../lib/features/partners/screens/bank_partner_screen.dart) | `129` | Target |
| [`profile_detail_screens.dart`](../lib/features/profile/screens/profile_detail_screens.dart) | `82` | Target |
| [`momo_nfc_screen.dart`](../lib/features/momo/screens/momo_nfc_screen.dart) | `72` | Target |
