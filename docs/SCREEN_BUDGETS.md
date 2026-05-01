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
- `12` review-range screens
- `0` debt screens
- `0` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`biopay_scan_screen.dart`](../lib/features/biopay/screens/biopay_scan_screen.dart) | `472` | Review |
| [`biopay_nfc_screen.dart`](../lib/features/biopay/screens/biopay_nfc_screen.dart) | `467` | Review |
| [`biopay_register_screen.dart`](../lib/features/biopay/screens/biopay_register_screen.dart) | `446` | Review |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `445` | Review |
| [`admin_groups_screen.dart`](../lib/features/admin/screens/admin_groups_screen.dart) | `440` | Review |
| [`admin_savings_screen.dart`](../lib/features/admin/screens/admin_savings_screen.dart) | `430` | Review |
| [`bank_admin_workspace_parts.dart`](../lib/features/admin/screens/bank_admin_workspace_parts.dart) | `430` | Review |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `421` | Review |
| [`whatsapp_otp_parts.dart`](../lib/features/auth/screens/whatsapp_otp_parts.dart) | `417` | Review |
| [`biopay_scan_screen_processing.dart`](../lib/features/biopay/screens/biopay_scan_screen_processing.dart) | `415` | Review |
| [`group_settings_screen.dart`](../lib/features/groups/screens/group_settings_screen.dart) | `412` | Review |
| [`admin_savings_widgets.dart`](../lib/features/admin/screens/admin_savings_widgets.dart) | `402` | Review |
| [`manage_admin_roles_screen.dart`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | `399` | Target |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `389` | Target |
| [`group_create_screen.dart`](../lib/features/groups/screens/group_create_screen.dart) | `385` | Target |
| [`biopay_qr_screen.dart`](../lib/features/biopay/screens/biopay_qr_screen.dart) | `375` | Target |
| [`admin_savings_detail_screen_parts.dart`](../lib/features/admin/screens/admin_savings_detail_screen_parts.dart) | `355` | Target |
| [`bank_admin_workspace_screen.dart`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | `354` | Target |
| [`momo_wallet_parts.dart`](../lib/features/momo/screens/momo_wallet_parts.dart) | `350` | Target |
| [`group_detail_screen_parts.dart`](../lib/features/groups/screens/group_detail_screen_parts.dart) | `337` | Target |
| [`admin_savings_detail_widgets.dart`](../lib/features/admin/screens/admin_savings_detail_widgets.dart) | `333` | Target |
| [`audit_log_screen.dart`](../lib/features/admin/screens/audit_log_screen.dart) | `328` | Target |
| [`group_statements_screen.dart`](../lib/features/groups/screens/group_statements_screen.dart) | `321` | Target |
| [`momo_wallet_screen.dart`](../lib/features/momo/screens/momo_wallet_screen.dart) | `308` | Target |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `306` | Target |
| [`operational_dashboard_cards.dart`](../lib/features/admin/screens/operational_dashboard_cards.dart) | `296` | Target |
| [`operational_dashboard_manual_review.dart`](../lib/features/admin/screens/operational_dashboard_manual_review.dart) | `296` | Target |
| [`operational_dashboard_sender_inventory.dart`](../lib/features/admin/screens/operational_dashboard_sender_inventory.dart) | `285` | Target |
| [`admin_savings_detail_screen.dart`](../lib/features/admin/screens/admin_savings_detail_screen.dart) | `282` | Target |
| [`operational_dashboard_utils.dart`](../lib/features/admin/screens/operational_dashboard_utils.dart) | `282` | Target |
| [`whatsapp_otp_screen.dart`](../lib/features/auth/screens/whatsapp_otp_screen.dart) | `268` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `252` | Target |
| [`system_analytics_screen.dart`](../lib/features/admin/screens/system_analytics_screen.dart) | `246` | Target |
| [`admin_workspaces_screen.dart`](../lib/features/admin/screens/admin_workspaces_screen.dart) | `221` | Target |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `220` | Target |
| [`biopay_nfc_tap_screen.dart`](../lib/features/biopay/screens/biopay_nfc_tap_screen.dart) | `219` | Target |
| [`groups_screen_sections.dart`](../lib/features/groups/screens/groups_screen_sections.dart) | `214` | Target |
| [`group_statements_screen_parts.dart`](../lib/features/groups/screens/group_statements_screen_parts.dart) | `193` | Target |
| [`group_detail_widgets.dart`](../lib/features/groups/screens/group_detail_widgets.dart) | `192` | Target |
| [`profile_sub_screens.dart`](../lib/features/profile/screens/profile_sub_screens.dart) | `191` | Target |
| [`biopay_scan_screen_view.dart`](../lib/features/biopay/screens/biopay_scan_screen_view.dart) | `168` | Target |
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `158` | Target |
| [`admin_dashboard_parts.dart`](../lib/features/admin/screens/admin_dashboard_parts.dart) | `156` | Target |
| [`profile_sub_screens_account.dart`](../lib/features/profile/screens/profile_sub_screens_account.dart) | `150` | Target |
| [`biopay_scan_screen_footer.dart`](../lib/features/biopay/screens/biopay_scan_screen_footer.dart) | `126` | Target |
| [`biopay_enrollment_success_screen.dart`](../lib/features/biopay/screens/biopay_enrollment_success_screen.dart) | `116` | Target |
| [`profile_detail_screens.dart`](../lib/features/profile/screens/profile_detail_screens.dart) | `109` | Target |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `102` | Target |
| [`operational_dashboard_release_cards.dart`](../lib/features/admin/screens/operational_dashboard_release_cards.dart) | `91` | Target |
| [`biopay_home_screen.dart`](../lib/features/biopay/screens/biopay_home_screen.dart) | `91` | Target |
| [`biopay_scan_screen_lifecycle.dart`](../lib/features/biopay/screens/biopay_scan_screen_lifecycle.dart) | `71` | Target |
| [`profile_sub_screens_support.dart`](../lib/features/profile/screens/profile_sub_screens_support.dart) | `7` | Target |
