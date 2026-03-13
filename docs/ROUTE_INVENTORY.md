# Route Inventory

Generated from code in 
[`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart).

Current router shape:

- `36` `GoRoute` declarations
- `4` shell branches
- `54` screen files under `lib/features/**/screens/*.dart`

Change policy:

- Route changes must regenerate this document from code.
- New user-facing routes must ship with smoke or routing coverage.
- Route changes that grow screen scope must also refresh 
[`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md).

## Auth And Entry

| Path | Target | Shell |
|---|---|---|
| `/` | [`SplashScreen`](../lib/features/auth/screens/splash_screen.dart) | No |
| `/invite/:code` | [`GroupInviteScreen`](../lib/features/groups/screens/group_invite_screen.dart) | No |
| `/language` | [`OnboardingScreen`](../lib/features/auth/screens/onboarding_screen.dart) | No |
| `/onboarding` | [`OnboardingScreen`](../lib/features/auth/screens/onboarding_screen.dart) | No |
| `/otp` | [`OtpScreen`](../lib/features/auth/screens/otp_screen.dart) | No |
| `/otp-verify` | [`OtpVerifyScreen`](../lib/features/auth/screens/otp_verify_screen.dart) | No |
| `/register` | [`RegisterScreen`](../lib/features/auth/screens/register_screen.dart) | No |
| `/scanner` | [`QrScannerScreen`](../lib/shared/widgets/qr_scanner_screen.dart) | No |

## Shell Branches

| Path | Target | Shell |
|---|---|---|
| `/groups` | [`CreateGroupScreen`](../lib/features/groups/screens/create_group_screen.dart), [`GroupDetailScreen`](../lib/features/groups/screens/group_detail_screen.dart), [`GroupsScreen`](../lib/features/groups/screens/groups_screen.dart) | Groups |
| `/home` | [`HomeScreen`](../lib/features/home/screens/home_screen.dart) | Home |
| `/mobility` | [`DriverProfileScreen`](../lib/features/mobility/screens/driver_profile_screen.dart), [`MobilityHomeScreen`](../lib/features/mobility/screens/mobility_home_screen.dart), [`ScheduleTripScreen`](../lib/features/mobility/screens/schedule_trip_screen.dart), [`TripBoardScreen`](../lib/features/mobility/screens/trip_board_screen.dart) | Mobility |
| `/profile` | [`ProfileScreen`](../lib/features/profile/screens/profile_screen.dart) | Profile |

## Standalone Core Routes

| Path | Target | Shell |
|---|---|---|
| `/basket` | Redirect | No |
| `/credit` | [`CreditScoreScreen`](../lib/features/credit/screens/credit_score_screen.dart) | No |
| `/credit/readiness` | [`CreditReadinessScreen`](../lib/features/credit/screens/credit_readiness_screen.dart) | No |
| `/missions` | [`MissionsScreen`](../lib/core/status/screens/missions_screen.dart) | No |
| `/momo` | [`MomoScreen`](../lib/features/momo/screens/momo_screen.dart) | No |
| `/momo/statements` | [`MomoStatementsScreen`](../lib/features/momo/screens/momo_statements_screen.dart) | No |

## Partner And Rayon Consumer Routes

| Path | Target | Shell |
|---|---|---|
| `/partners` | Redirect | No |

## Admin Routes

| Path | Target | Shell |
|---|---|---|
| `/admin` | [`AdminDashboardScreen`](../lib/features/admin/screens/admin_dashboard_screen.dart) | No |
| `/admin/app-config` | [`ManageAppConfigScreen`](../lib/features/admin/screens/manage_app_config_screen.dart) | No |
| `/admin/countries` | [`ManageCountriesScreen`](../lib/features/admin/screens/manage_countries_screen.dart) | No |
| `/admin/operations` | [`OperationalDashboardScreen`](../lib/features/admin/screens/operational_dashboard_screen.dart) | No |
| `/admin/partners` | [`ManagePartnersScreen`](../lib/features/admin/screens/manage_partners_screen.dart) | No |
| `/admin/quick-actions` | [`ManageQuickActionsScreen`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | No |
| `/admin/services` | [`ManageServicesScreen`](../lib/features/admin/screens/manage_services_screen.dart) | No |
| `/admin/users` | [`ManageUsersScreen`](../lib/features/admin/screens/manage_users_screen.dart) | No |
| `/admin/vehicle-types` | [`ManageVehicleTypesScreen`](../lib/features/admin/screens/manage_vehicle_types_screen.dart) | No |

## Rayon Admin Routes

| Path | Target | Shell |
|---|---|---|
| `/admin/rayon` | [`RsAdminDashboardScreen`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | No |
| `/admin/rayon/fan-clubs` | [`RsAdminInitiativesScreen`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | No |
| `/admin/rayon/initiatives` | [`RsAdminInitiativesScreen`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | No |
| `/admin/rayon/matches` | [`RsAdminMatchesScreen`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | No |
| `/admin/rayon/members` | [`RsAdminMembersScreen`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | No |
| `/admin/rayon/orders` | [`RsAdminOrdersScreen`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | No |
| `/admin/rayon/shop` | [`RsAdminShopScreen`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | No |
| `/admin/rayon/tickets` | [`RsAdminTicketsScreen`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | No |

