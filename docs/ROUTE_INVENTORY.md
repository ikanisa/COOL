# Route Inventory

Generated from [`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart).

Current router shape:

- `71` `GoRoute` declarations
- `4` shell branches
- `70` screen files under `lib/features/**/screens/*.dart`

Change policy:

- Route changes must regenerate this document from code.
- New user-facing routes must ship with smoke or routing coverage.
- Route changes that grow screen scope must also refresh [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md).

## Auth And Entry

| Path | Target | Shell |
|---|---|---|
| `/` | [`SplashScreen`](../lib/features/auth/screens/splash_screen.dart) | No |
| `/invite/:code` | [`GroupInviteScreen`](../lib/features/groups/screens/group_invite_screen.dart) | No |
| `/onboarding` | [`OnboardingScreen`](../lib/features/auth/screens/onboarding_screen.dart) | No |
| `/otp` | [`OtpScreen`](../lib/features/auth/screens/otp_screen.dart) | No |
| `/otp-verify` | [`OtpVerifyScreen`](../lib/features/auth/screens/otp_verify_screen.dart) | No |
| `/register` | [`RegisterScreen`](../lib/features/auth/screens/register_screen.dart) | No |
| `/scanner` | [`QrScannerScreen`](../lib/shared/widgets/qr_scanner_screen.dart) | No |

## Shell Branches

| Path | Target | Shell |
|---|---|---|
| `/groups` | [`GroupsScreen`](../lib/features/groups/screens/groups_screen.dart) | Groups |
| `/groups/:id` | [`GroupDetailScreen`](../lib/features/groups/screens/group_detail_screen.dart) | Groups |
| `/groups/create` | [`CreateGroupScreen`](../lib/features/groups/screens/create_group_screen.dart) | Groups |
| `/home` | [`HomeScreen`](../lib/features/home/screens/home_screen.dart) | Home |
| `/mobility` | [`MobilityHomeScreen`](../lib/features/mobility/screens/mobility_home_screen.dart) | Mobility |
| `/mobility/driver` | [`DriverProfileScreen`](../lib/features/mobility/screens/driver_profile_screen.dart) | Mobility |
| `/mobility/driver/subscription` | [`DriverSubscriptionScreen`](../lib/features/mobility/screens/driver_detail_screens.dart) | Mobility |
| `/mobility/driver/vehicle` | [`DriverVehicleScreen`](../lib/features/mobility/screens/driver_detail_screens.dart) | Mobility |
| `/mobility/schedule` | [`ScheduleTripScreen`](../lib/features/mobility/screens/schedule_trip_screen.dart) | Mobility |
| `/mobility/trips` | [`TripBoardScreen`](../lib/features/mobility/screens/trip_board_screen.dart) | Mobility |
| `/profile` | [`ProfileScreen`](../lib/features/profile/screens/profile_screen.dart) | Profile |
| `/profile/identity` | [`ProfileIdentityScreen`](../lib/features/profile/screens/profile_detail_screens.dart) | Profile |
| `/profile/travel-role` | [`ProfileTravelRoleScreen`](../lib/features/profile/screens/profile_detail_screens.dart) | Profile |
| `/profile/wallet` | [`ProfileWalletScreen`](../lib/features/profile/screens/profile_detail_screens.dart) | Profile |

## Standalone Core Routes

| Path | Target | Shell |
|---|---|---|
| `/credit` | [`CreditScoreScreen`](../lib/features/credit/screens/credit_score_screen.dart) | No |
| `/credit/readiness` | [`CreditReadinessScreen`](../lib/features/credit/screens/credit_readiness_screen.dart) | No |
| `/kyc/selfie` | [`KycSelfieScreen`](../lib/features/profile/screens/kyc_selfie_screen.dart) | No |
| `/missions` | [`MissionsScreen`](../lib/core/status/screens/missions_screen.dart) | No |
| `/momo` | [`MomoScreen`](../lib/features/momo/screens/momo_screen.dart) | No |
| `/momo/statements` | [`MomoStatementsScreen`](../lib/features/momo/screens/momo_statements_screen.dart) | No |
| `/tokens` | [`CoolTokensScreen`](../lib/core/status/screens/cool_tokens_screen.dart) | No |

## Partner And Rayon Consumer Routes

| Path | Target | Shell |
|---|---|---|
| `/partners` | [`PartnersScreen`](../lib/features/partners/screens/partners_screen.dart) | No |
| `/partners/:id` | [`BankPartnerScreen`](../lib/features/partners/screens/bank_partner_screen.dart), [`PrismaPartnerScreen`](../lib/features/partners/screens/prisma_partner_screen.dart), [`RadiantPartnerScreen`](../lib/features/partners/screens/radiant_partner_screen.dart) | No |
| `/partners/:id/onboarding/:type` | [`BankOnboardingScreen`](../lib/features/partners/bank_onboarding/screens/bank_onboarding_screen.dart) | No |
| `/partners/rayon-sports` | [`RayonHomeScreen`](../lib/features/partners/rayon/screens/rayon_home_screen.dart) | No |
| `/partners/rayon-sports/clubs` | [`FanClubsScreen`](../lib/features/partners/screens/rayon/fan_clubs_screen.dart) | No |
| `/partners/rayon-sports/clubs/:clubId` | [`FanClubDetailScreen`](../lib/features/partners/screens/rayon/fan_club_detail_screen.dart) | No |
| `/partners/rayon-sports/membership` | [`MembershipTiersScreen`](../lib/features/partners/rayon/screens/membership_tiers_screen.dart) | No |
| `/partners/rayon-sports/profile` | [`FanProfileScreen`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) | No |
| `/partners/rayon-sports/registry` | [`MemberRegistryScreen`](../lib/features/partners/screens/rayon/member_registry_screen.dart) | No |
| `/partners/rayon-sports/shop` | [`ClubShopScreen`](../lib/features/partners/screens/rayon/club_shop_screen.dart) | No |
| `/partners/rayon-sports/shop/checkout` | [`ShopCheckoutScreen`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart) | No |
| `/partners/rayon-sports/support` | [`SupportScreen`](../lib/features/partners/rayon/screens/support_screen.dart) | No |
| `/partners/rayon-sports/support/:initiativeId` | [`SupportDetailScreen`](../lib/features/partners/rayon/screens/support_detail_screen.dart) | No |
| `/partners/rayon-sports/tickets` | [`TicketsScreen`](../lib/features/partners/screens/rayon/tickets_screen.dart) | No |
| `/partners/rayon-sports/tickets/:ticketId/confirm` | [`TicketConfirmationScreen`](../lib/features/partners/screens/rayon/ticket_confirmation_screen.dart) | No |
| `/partners/rayon-sports/tickets/my-tickets` | [`MyTicketsScreen`](../lib/features/partners/screens/rayon/my_tickets_screen.dart) | No |

## Admin Routes

| Path | Target | Shell |
|---|---|---|
| `/admin` | [`AdminWorkspacesScreen`](../lib/features/admin/screens/admin_workspaces_screen.dart) | No |
| `/admin/analytics` | [`SystemAnalyticsScreen`](../lib/features/admin/screens/system_analytics_screen.dart) | No |
| `/admin/app-config` | [`ManageAppConfigScreen`](../lib/features/admin/screens/manage_app_config_screen.dart) | No |
| `/admin/audit-log` | [`AuditLogScreen`](../lib/features/admin/screens/audit_log_screen.dart) | No |
| `/admin/banks/:partnerId` | [`BankAdminWorkspaceScreen`](../lib/features/admin/screens/bank_admin_workspace_screen.dart) | No |
| `/admin/missions` | [`ManageMissionsScreen`](../lib/features/admin/screens/manage_missions_screen.dart) | No |
| `/admin/operations` | [`OperationalDashboardScreen`](../lib/features/admin/screens/operational_dashboard_screen.dart) | No |
| `/admin/partners` | [`ManagePartnersScreen`](../lib/features/admin/screens/manage_partners_screen.dart) | No |
| `/admin/partners/:partnerId` | [`PartnerAdminWorkspaceScreen`](../lib/features/admin/screens/partner_admin_workspace_screen.dart) | No |
| `/admin/platform` | [`AdminDashboardScreen`](../lib/features/admin/screens/admin_dashboard_screen.dart) | No |
| `/admin/quick-actions` | [`ManageQuickActionsScreen`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | No |
| `/admin/roles` | [`ManageAdminRolesScreen`](../lib/features/admin/screens/manage_admin_roles_screen.dart) | No |
| `/admin/seasons` | [`ManageSeasonsScreen`](../lib/features/admin/screens/manage_seasons_screen.dart) | No |
| `/admin/services` | [`ManageServicesScreen`](../lib/features/admin/screens/manage_services_screen.dart) | No |
| `/admin/special-products` | [`ManageSpecialProductsScreen`](../lib/features/admin/screens/manage_special_products_screen.dart) | No |
| `/admin/users` | [`ManageUsersScreen`](../lib/features/admin/screens/manage_users_screen.dart) | No |
| `/admin/vehicle-types` | [`ManageVehicleTypesScreen`](../lib/features/admin/screens/manage_vehicle_types_screen.dart) | No |

## Rayon Admin Routes

| Path | Target | Shell |
|---|---|---|
| `/admin/rayon` | [`RsAdminDashboardScreen`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | No |
| `/admin/rayon/analytics` | [`RsAdminAnalyticsScreen`](../lib/features/partners/rayon/screens/rs_admin_analytics_screen.dart) | No |
| `/admin/rayon/finance` | [`RsAdminFinanceScreen`](../lib/features/partners/rayon/screens/rs_admin_finance_screen.dart) | No |
| `/admin/rayon/initiatives` | [`RsAdminInitiativesScreen`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | No |
| `/admin/rayon/matches` | [`RsAdminMatchesScreen`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | No |
| `/admin/rayon/members` | [`RsAdminMembersScreen`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | No |
| `/admin/rayon/orders` | [`RsAdminOrdersScreen`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | No |
| `/admin/rayon/packages` | [`RsAdminPackagesScreen`](../lib/features/partners/rayon/screens/rs_admin_packages_screen.dart) | No |
| `/admin/rayon/shop` | [`RsAdminShopScreen`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | No |
| `/admin/rayon/tickets` | [`RsAdminTicketsScreen`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | No |

