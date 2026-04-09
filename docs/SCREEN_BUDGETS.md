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

- `31` screen files measured
- `4` review-range screens
- `4` debt screens
- `0` hotspot screens

## Measured Screens

| Screen | LOC | Status |
|---|---|---|
| [`operational_dashboard_parts.dart`](../lib/features/admin/screens/operational_dashboard_parts.dart) | `914` | Debt |
| [`biopay_scan_screen.dart`](../lib/features/biopay/screens/biopay_scan_screen.dart) | `879` | Debt |
| [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) | `819` | Debt |
| [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart) | `772` | Debt |
| [`biopay_register_screen.dart`](../lib/features/biopay/screens/biopay_register_screen.dart) | `451` | Review |
| [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) | `436` | Review |
| [`bank_admin_workspace_screen.dart`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | `419` | Review |
| [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart) | `418` | Review |
| [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart) | `399` | Target |
| [`manage_quick_actions_screen.dart`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | `393` | Target |
| [`profile_sub_screens_about.dart`](../lib/features/profile/screens/profile_sub_screens_about.dart) | `383` | Target |
| [`system_analytics_screen.dart`](../lib/features/admin/screens/system_analytics_screen.dart) | `378` | Target |
| [`audit_log_screen.dart`](../lib/features/admin/screens/audit_log_screen.dart) | `371` | Target |
| [`group_create_screen.dart`](../lib/features/groups/screens/group_create_screen.dart) | `341` | Target |
| [`admin_workspaces_screen.dart`](../lib/features/admin/screens/admin_workspaces_screen.dart) | `313` | Target |
| [`biopay_nfc_screen.dart`](../lib/features/biopay/screens/biopay_nfc_screen.dart) | `305` | Target |
| [`splash_screen.dart`](../lib/features/auth/screens/splash_screen.dart) | `262` | Target |
| [`biopay_home_screen.dart`](../lib/features/biopay/screens/biopay_home_screen.dart) | `259` | Target |
| [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart) | `255` | Target |
| [`profile_sub_screens.dart`](../lib/features/profile/screens/profile_sub_screens.dart) | `255` | Target |
| [`home_screen.dart`](../lib/features/home/screens/home_screen.dart) | `245` | Target |
| [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart) | `244` | Target |
| [`momo_screen_parts.dart`](../lib/features/momo/screens/momo_screen_parts.dart) | `237` | Target |
| [`profile_sub_screens_support.dart`](../lib/features/profile/screens/profile_sub_screens_support.dart) | `237` | Target |
| [`profile_sub_screens_account.dart`](../lib/features/profile/screens/profile_sub_screens_account.dart) | `228` | Target |
| [`manage_users_screen.dart`](../lib/features/admin/screens/manage_users_screen.dart) | `171` | Target |
| [`manage_admin_roles_screen.dart`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | `149` | Target |
| [`admin_dashboard_parts.dart`](../lib/features/admin/screens/admin_dashboard_parts.dart) | `123` | Target |
| [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart) | `115` | Target |
| [`profile_detail_screens.dart`](../lib/features/profile/screens/profile_detail_screens.dart) | `87` | Target |
| [`momo_nfc_screen.dart`](../lib/features/momo/screens/momo_nfc_screen.dart) | `72` | Target |
