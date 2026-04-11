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

- `42` screen files measured
- `11` review-range screens
- `3` debt screens
- `0` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`admin_savings_detail_screen.dart`](../lib/features/admin/screens/admin_savings_detail_screen.dart) | `849` | Debt |
| [`admin_savings_screen.dart`](../lib/features/admin/screens/admin_savings_screen.dart) | `807` | Debt |
| [`bank_admin_workspace_screen.dart`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | `780` | Debt |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `608` | Review |
| [`biopay_scan_screen.dart`](../lib/features/biopay/screens/biopay_scan_screen.dart) | `576` | Review |
| [`group_statements_screen.dart`](../lib/features/groups/screens/group_statements_screen.dart) | `518` | Review |
| [`whatsapp_otp_screen.dart`](../lib/features/auth/screens/whatsapp_otp_screen.dart) | `501` | Review |
| [`momo_wallet_screen.dart`](../lib/features/momo/screens/momo_wallet_screen.dart) | `475` | Review |
| [`biopay_nfc_screen.dart`](../lib/features/biopay/screens/biopay_nfc_screen.dart) | `453` | Review |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `451` | Review |
| [`admin_groups_screen.dart`](../lib/features/admin/screens/admin_groups_screen.dart) | `440` | Review |
| [`biopay_register_screen.dart`](../lib/features/biopay/screens/biopay_register_screen.dart) | `435` | Review |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `426` | Review |
| [`biopay_scan_screen_processing.dart`](../lib/features/biopay/screens/biopay_scan_screen_processing.dart) | `417` | Review |
| [`biopay_profile_screen.dart`](../lib/features/biopay/screens/biopay_profile_screen.dart) | `367` | Target |
| [`biopay_qr_screen.dart`](../lib/features/biopay/screens/biopay_qr_screen.dart) | `361` | Target |
| [`system_analytics_screen.dart`](../lib/features/admin/screens/system_analytics_screen.dart) | `357` | Target |
| [`audit_log_screen.dart`](../lib/features/admin/screens/audit_log_screen.dart) | `327` | Target |
| [`operational_dashboard_release_cards.dart`](../lib/features/admin/screens/operational_dashboard_release_cards.dart) | `326` | Target |
| [`admin_workspaces_screen.dart`](../lib/features/admin/screens/admin_workspaces_screen.dart) | `321` | Target |
| [`operational_dashboard_cards.dart`](../lib/features/admin/screens/operational_dashboard_cards.dart) | `296` | Target |
| [`operational_dashboard_manual_review.dart`](../lib/features/admin/screens/operational_dashboard_manual_review.dart) | `296` | Target |
| [`operational_dashboard_utils.dart`](../lib/features/admin/screens/operational_dashboard_utils.dart) | `293` | Target |
| [`group_settings_screen.dart`](../lib/features/groups/screens/group_settings_screen.dart) | `293` | Target |
| [`operational_dashboard_sender_inventory.dart`](../lib/features/admin/screens/operational_dashboard_sender_inventory.dart) | `285` | Target |
| [`group_create_screen.dart`](../lib/features/groups/screens/group_create_screen.dart) | `276` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `252` | Target |
| [`groups_screen_sections.dart`](../lib/features/groups/screens/groups_screen_sections.dart) | `238` | Target |
| [`biopay_nfc_tap_screen.dart`](../lib/features/biopay/screens/biopay_nfc_tap_screen.dart) | `219` | Target |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `201` | Target |
| [`profile_sub_screens.dart`](../lib/features/profile/screens/profile_sub_screens.dart) | `191` | Target |
| [`biopay_home_screen.dart`](../lib/features/biopay/screens/biopay_home_screen.dart) | `179` | Target |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `151` | Target |
| [`profile_sub_screens_account.dart`](../lib/features/profile/screens/profile_sub_screens_account.dart) | `150` | Target |
| [`admin_dashboard_parts.dart`](../lib/features/admin/screens/admin_dashboard_parts.dart) | `125` | Target |
| [`biopay_enrollment_success_screen.dart`](../lib/features/biopay/screens/biopay_enrollment_success_screen.dart) | `119` | Target |
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `119` | Target |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `117` | Target |
| [`manage_admin_roles_screen.dart`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | `117` | Target |
| [`biopay_scan_screen_footer.dart`](../lib/features/biopay/screens/biopay_scan_screen_footer.dart) | `109` | Target |
| [`profile_detail_screens.dart`](../lib/features/profile/screens/profile_detail_screens.dart) | `109` | Target |
| [`profile_sub_screens_support.dart`](../lib/features/profile/screens/profile_sub_screens_support.dart) | `7` | Target |
