# Route Inventory

Generated from [`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart).

Current router shape:

- `91` `GoRoute` declarations
- `3` shell branches
- `68` screen files under `lib/features/**/screens/*.dart`

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
| `/groups` | Redirect | No |
| `/groups/:id` | Redirect | No |
| `/groups/:id/ledger` | Redirect | No |
| `/groups/create` | Redirect | No |
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
| `/contribution-circles` | [`ContributionCirclesScreen`](../lib/features/rayon/screens/contribution_circles_screen.dart) | No |
| `/contribution-circles/:groupId` | [`ContributionCircleDetailScreen`](../lib/features/rayon/screens/contribution_circle_detail_screen.dart) | No |
| `/contributions` | [`SupportScreen`](../lib/features/rayon/screens/support_screen.dart) | No |
| `/contributions/:initiativeId` | [`SupportDetailScreen`](../lib/features/rayon/screens/support_detail_screen.dart) | No |
| `/fan-clubs` | [`FanClubsScreen`](../lib/features/rayon/screens/fan_clubs_screen.dart) | No |
| `/fan-clubs/:clubId` | [`FanClubDetailScreen`](../lib/features/rayon/screens/fan_club_detail_screen.dart) | No |
| `/fan-profile` | [`FanProfileScreen`](../lib/features/rayon/screens/fan_profile_screen.dart) | No |
| `/gamification` | Redirect | No |
| `/leaderboard` | [`FanLeaderboardScreen`](../lib/features/rayon/screens/fan_leaderboard_screen.dart) | No |
| `/match/:matchId/engage` | [`MatchEngagementScreen`](../lib/features/rayon/screens/match_engagement_screen.dart) | No |
| `/membership` | [`MembershipTiersScreen`](../lib/features/rayon/screens/membership_tiers_screen.dart) | No |
| `/missions` | [`MissionsScreen`](../lib/core/status/screens/missions_screen.dart) | No |
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
| `/rayon/registry` | Redirect | No |
| `/referral` | [`ReferralHubScreen`](../lib/core/status/screens/referral_hub_screen.dart) | No |
| `/registry` | [`MemberRegistryScreen`](../lib/features/rayon/screens/member_registry_screen.dart) | No |
| `/seasons` | [`SeasonsActivitiesScreen`](../lib/features/home/screens/seasons_activities_screen.dart) | No |
| `/shop` | [`ClubShopScreen`](../lib/features/rayon/screens/club_shop_screen.dart) | No |
| `/shop/checkout` | [`ShopCheckoutScreen`](../lib/features/rayon/screens/shop_checkout_screen.dart) | No |
| `/shop/product/:productId` | [`ProductDetailScreen`](../lib/features/rayon/screens/product_detail_screen.dart) | No |
| `/tickets` | [`TicketsScreen`](../lib/features/rayon/screens/tickets_screen.dart) | No |
| `/tickets/:ticketId/confirm` | [`TicketConfirmationScreen`](../lib/features/rayon/screens/ticket_confirmation_screen.dart) | No |
| `/tickets/my-tickets` | [`MyTicketsScreen`](../lib/features/rayon/screens/my_tickets_screen.dart) | No |
| `/tokens` | [`CoolTokensScreen`](../lib/core/status/screens/cool_tokens_screen.dart) | No |

## Partner And Rayon Consumer Routes

| Path | Target | Shell |
|---|---|---|
| `/partners` | Redirect | No |
| `/partners/rayon-sports` | Redirect | No |
| `/partners/rayon-sports/clubs` | Redirect | No |
| `/partners/rayon-sports/clubs/:clubId` | Redirect | No |
| `/partners/rayon-sports/membership` | Redirect | No |
| `/partners/rayon-sports/profile` | Redirect | No |
| `/partners/rayon-sports/registry` | Redirect | No |
| `/partners/rayon-sports/shop` | Redirect | No |
| `/partners/rayon-sports/shop/checkout` | Redirect | No |
| `/partners/rayon-sports/shop/product/:productId` | Redirect | No |
| `/partners/rayon-sports/support` | Redirect | No |
| `/partners/rayon-sports/support/:initiativeId` | Redirect | No |
| `/partners/rayon-sports/tickets` | Redirect | No |
| `/partners/rayon-sports/tickets/:ticketId/confirm` | Redirect | No |
| `/partners/rayon-sports/tickets/my-tickets` | Redirect | No |

## Admin Routes

| Path | Target | Shell |
|---|---|---|
| `/admin` | [`AdminWorkspacesScreen`](../lib/features/admin/screens/admin_workspaces_screen.dart) | No |
| `/admin/activities` | [`ManageActivitiesScreen`](../lib/features/admin/screens/manage_activities_screen.dart) | No |
| `/admin/ai-content` | [`ManageAiContentScreen`](../lib/features/admin/screens/manage_ai_content_screen.dart) | No |
| `/admin/analytics` | [`SystemAnalyticsScreen`](../lib/features/admin/screens/system_analytics_screen.dart) | No |
| `/admin/app-config` | [`ManageAppConfigScreen`](../lib/features/admin/screens/manage_app_config_screen.dart) | No |
| `/admin/audit-log` | [`AuditLogScreen`](../lib/features/admin/screens/audit_log_screen.dart) | No |
| `/admin/missions` | [`ManageMissionsScreen`](../lib/features/admin/screens/manage_missions_screen.dart) | No |
| `/admin/operations` | [`OperationalDashboardScreen`](../lib/features/admin/screens/operational_dashboard_screen.dart) | No |
| `/admin/partners` | Redirect | No |
| `/admin/platform` | [`AdminDashboardScreen`](../lib/features/admin/screens/admin_dashboard_screen.dart) | No |
| `/admin/quick-actions` | [`ManageQuickActionsScreen`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | No |
| `/admin/roles` | [`ManageAdminRolesScreen`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | No |
| `/admin/seasons` | [`ManageSeasonsScreen`](../lib/features/admin/screens/manage_seasons_screen.dart) | No |
| `/admin/services` | [`ManageServicesScreen`](../lib/features/admin/screens/manage_services_screen.dart) | No |
| `/admin/special-products` | [`ManageSpecialProductsScreen`](../lib/features/admin/screens/manage_special_products_screen.dart) | No |
| `/admin/users` | [`ManageUsersScreen`](../lib/features/admin/screens/manage_users_screen.dart) | No |

## Rayon Admin Routes

| Path | Target | Shell |
|---|---|---|
| `/admin/rayon` | [`RsAdminDashboardScreen`](../lib/features/rayon/screens/rs_admin_dashboard_screen.dart) | No |
| `/admin/rayon/analytics` | [`RsAdminAnalyticsScreen`](../lib/features/rayon/screens/rs_admin_analytics_screen.dart) | No |
| `/admin/rayon/engagement` | [`RsAdminEngagementScreen`](../lib/features/rayon/screens/rs_admin_engagement_screen.dart) | No |
| `/admin/rayon/finance` | [`RsAdminFinanceScreen`](../lib/features/rayon/screens/rs_admin_finance_screen.dart) | No |
| `/admin/rayon/initiatives` | [`RsAdminInitiativesScreen`](../lib/features/rayon/screens/rs_admin_initiatives_screen.dart) | No |
| `/admin/rayon/matches` | [`RsAdminMatchesScreen`](../lib/features/rayon/screens/rs_admin_matches_screen.dart) | No |
| `/admin/rayon/members` | [`RsAdminMembersScreen`](../lib/features/rayon/screens/rs_admin_members_screen.dart) | No |
| `/admin/rayon/orders` | [`RsAdminOrdersScreen`](../lib/features/rayon/screens/rs_admin_orders_screen.dart) | No |
| `/admin/rayon/packages` | [`RsAdminPackagesScreen`](../lib/features/rayon/screens/rs_admin_packages_screen.dart) | No |
| `/admin/rayon/shop` | [`RsAdminShopScreen`](../lib/features/rayon/screens/rs_admin_shop_screen.dart) | No |
| `/admin/rayon/tickets` | [`RsAdminTicketsScreen`](../lib/features/rayon/screens/rs_admin_tickets_screen.dart) | No |

