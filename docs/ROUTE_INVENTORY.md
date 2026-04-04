# Route Inventory

Generated from [`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart).

Current router shape:

- `33` `GoRoute` declarations
- `3` shell branches
- `29` screen files under `lib/features/**/screens/*.dart`

Change policy:

- Route changes must regenerate this document from code.
- New user-facing routes must ship with smoke or routing coverage.
- Route changes that grow screen scope must also refresh [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md).

## Auth And Entry

| Path | Target | Shell |
|---|---|---|
| `/` | [`SplashScreen`](../lib/features/auth/screens/splash_screen.dart) | No |
| `/invite/:code` | Redirect | No |
| `/scanner` | [`QrScannerScreen`](../lib/shared/widgets/qr_scanner_screen.dart) | No |

## Shell Branches

| Path | Target | Shell |
|---|---|---|
| `/home` | [`HomeScreen`](../lib/features/home/screens/home_screen.dart) | Home |
| `/profile` | [`ProfileScreen`](../lib/features/profile/screens/profile_screen.dart) | Settings |
| `/profile/about` | [`AboutAppScreen`](../lib/features/profile/screens/profile_sub_screens_about.dart) | Settings |
| `/profile/account` | [`AccountDetailsScreen`](../lib/features/profile/screens/profile_sub_screens_account.dart) | Settings |
| `/profile/help` | [`HelpCenterScreen`](../lib/features/profile/screens/profile_sub_screens_support.dart) | Settings |
| `/profile/notifications` | [`NotificationsSettingsScreen`](../lib/features/profile/screens/profile_sub_screens_account.dart) | Settings |
| `/profile/orders` | [`OrderHistoryScreen`](../lib/features/profile/screens/profile_sub_screens_support.dart) | Settings |
| `/profile/privacy` | [`PrivacySecurityScreen`](../lib/features/profile/screens/profile_sub_screens_support.dart) | Settings |
| `/profile/wallet` | [`ProfileWalletScreen`](../lib/features/profile/screens/profile_detail_screens.dart) | Settings |

## Standalone Core Routes

| Path | Target | Shell |
|---|---|---|
| `/contribution-circles` | [`GroupsScreen`](../lib/features/groups/screens/groups_screen.dart) | No |
| `/momo` | [`MomoScreen`](../lib/features/momo/screens/momo_screen.dart) | No |
| `/momo/biopay` | [`BiopayHomeScreen`](../lib/features/biopay/screens/biopay_home_screen.dart) | No |
| `/momo/biopay` | [`BiopayHomeScreen`](../lib/features/biopay/screens/biopay_home_screen.dart) | No |
| `/momo/biopay/nfc` | [`BiopayNfcScreen`](../lib/features/biopay/screens/biopay_nfc_screen.dart) | No |
| `/momo/biopay/nfc` | [`BiopayNfcScreen`](../lib/features/biopay/screens/biopay_nfc_screen.dart) | No |
| `/momo/biopay/register` | [`BiopayRegisterScreen`](../lib/features/biopay/screens/biopay_register_screen.dart) | No |
| `/momo/biopay/register` | [`BiopayRegisterScreen`](../lib/features/biopay/screens/biopay_register_screen.dart) | No |
| `/momo/biopay/scan` | [`BiopayScanScreen`](../lib/features/biopay/screens/biopay_scan_screen.dart) | No |
| `/momo/biopay/scan` | [`BiopayScanScreen`](../lib/features/biopay/screens/biopay_scan_screen.dart) | No |
| `/momo/statements` | [`MomoStatementsScreen`](../lib/features/momo/screens/momo_statements_screen.dart) | No |

## Admin Routes

| Path | Target | Shell |
|---|---|---|
| `/admin` | [`AdminWorkspacesScreen`](../lib/features/admin/screens/admin_workspaces_screen.dart) | No |
| `/admin/analytics` | [`SystemAnalyticsScreen`](../lib/features/admin/screens/system_analytics_screen.dart) | No |
| `/admin/app-config` | [`ManageAppConfigScreen`](../lib/features/admin/screens/manage_app_config_screen.dart) | No |
| `/admin/audit-log` | [`AuditLogScreen`](../lib/features/admin/screens/audit_log_screen.dart) | No |
| `/admin/banks/:bankId` | [`BankAdminWorkspaceScreen`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | No |
| `/admin/operations` | [`OperationalDashboardScreen`](../lib/features/admin/screens/operational_dashboard_screen.dart) | No |
| `/admin/partners` | Redirect | No |
| `/admin/platform` | [`AdminDashboardScreen`](../lib/features/admin/screens/admin_dashboard_screen.dart) | No |
| `/admin/roles` | [`ManageAdminRolesScreen`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | No |
| `/admin/users` | [`ManageUsersScreen`](../lib/features/admin/screens/manage_users_screen.dart) | No |

