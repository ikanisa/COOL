# Route Inventory

Generated from [`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart) and related router helpers.

Current router shape:

- `40` `GoRoute` declarations
- `3` shell branches
- `42` screen files under `lib/features/**/screens/*.dart`

Change policy:

- Route changes must regenerate this document from code.
- New user-facing routes must ship with smoke or routing coverage.
- Route changes that grow screen scope must also refresh [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md).

## Auth And Entry

| Path | Target | Shell |
|---|---|---|
| `/` | Redirect | No |
| `/invite/:code` | Redirect | No |
| `/register` | [`WhatsAppOtpScreen`](../lib/features/auth/screens/whatsapp_otp_screen.dart) | No |
| `/scanner` | [`QrScannerScreen`](../lib/shared/widgets/qr_scanner_screen.dart) | No |

## Shell Branches

| Path | Target | Shell |
|---|---|---|
| `/groups` | [`GroupsScreen`](../lib/features/groups/screens/groups_screen.dart) | Home |
| `/groups/:id` | [`GroupDetailScreen`](../lib/features/groups/screens/group_detail_screen.dart) | No |
| `/groups/:id/ledger` | Redirect | No |
| `/groups/:id/settings` | [`GroupSettingsScreen`](../lib/features/groups/screens/group_settings_screen.dart) | No |
| `/groups/:id/statements` | [`GroupStatementsScreen`](../lib/features/groups/screens/group_statements_screen.dart) | No |
| `/groups/create` | [`GroupCreateScreen`](../lib/features/groups/screens/group_create_screen.dart) | No |
| `/home` | [`HomeScreen`](../lib/features/home/screens/home_screen.dart) | Home |
| `/momo/biopay` | [`BiopayHomeScreen`](../lib/features/biopay/screens/biopay_home_screen.dart) | BioPay |
| `/momo/biopay/nfc` | [`BiopayNfcScreen`](../lib/features/biopay/screens/biopay_nfc_screen.dart) | BioPay |
| `/momo/biopay/nfc/tap` | [`BiopayNfcTapScreen`](../lib/features/biopay/screens/biopay_nfc_tap_screen.dart) | BioPay |
| `/momo/biopay/qr` | [`BiopayQrScreen`](../lib/features/biopay/screens/biopay_qr_screen.dart) | BioPay |
| `/momo/biopay/register` | [`BiopayRegisterScreen`](../lib/features/biopay/screens/biopay_register_screen.dart) | BioPay |
| `/momo/biopay/scan` | [`BiopayScanScreen`](../lib/features/biopay/screens/biopay_scan_screen.dart) | BioPay |
| `/momo/biopay/success` | [`BiopayEnrollmentSuccessScreen`](../lib/features/biopay/screens/biopay_enrollment_success_screen.dart) | BioPay |
| `/profile` | [`ProfileScreen`](../lib/features/profile/screens/profile_screen.dart) | Settings |
| `/profile/account` | [`AccountDetailsScreen`](../lib/features/profile/screens/profile_sub_screens_account.dart) | Settings |
| `/profile/wallet` | [`ProfileWalletScreen`](../lib/features/profile/screens/profile_detail_screens.dart) | Settings |

## Standalone Core Routes

| Path | Target | Shell |
|---|---|---|
| `/contribution-circles` | Redirect | No |
| `/contribution-circles/:groupId` | Redirect | No |
| `/contribution-circles/:groupId/settings` | Redirect | No |
| `/contribution-circles/:groupId/statements` | Redirect | No |
| `/momo` | Redirect | No |
| `/momo/wallet` | [`MomoWalletScreen`](../lib/features/momo/screens/momo_wallet_screen.dart) | No |

## Admin Routes

| Path | Target | Shell |
|---|---|---|
| `/admin` | [`AdminWorkspacesScreen`](../lib/features/admin/screens/admin_workspaces_screen.dart) | No |
| `/admin/analytics` | [`SystemAnalyticsScreen`](../lib/features/admin/screens/system_analytics_screen.dart) | No |
| `/admin/app-config` | [`ManageAppConfigScreen`](../lib/features/admin/screens/manage_app_config_screen.dart) | No |
| `/admin/audit-log` | [`AuditLogScreen`](../lib/features/admin/screens/audit_log_screen.dart) | No |
| `/admin/banks/:bankId` | [`BankAdminWorkspaceScreen`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | No |
| `/admin/groups` | [`AdminGroupsScreen`](../lib/features/admin/screens/admin_groups_screen.dart) | No |
| `/admin/operations` | [`OperationalDashboardScreen`](../lib/features/admin/screens/operational_dashboard_screen.dart) | No |
| `/admin/partners` | Redirect | No |
| `/admin/platform` | [`AdminDashboardScreen`](../lib/features/admin/screens/admin_dashboard_screen.dart) | No |
| `/admin/roles` | [`ManageAdminRolesScreen`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | No |
| `/admin/savings` | [`AdminSavingsScreen`](../lib/features/admin/screens/admin_savings_screen.dart) | No |
| `/admin/savings/:groupId` | [`AdminSavingsDetailScreen`](../lib/features/admin/screens/admin_savings_detail_screen.dart) | No |
| `/admin/users` | [`ManageUsersScreen`](../lib/features/admin/screens/manage_users_screen.dart) | No |

