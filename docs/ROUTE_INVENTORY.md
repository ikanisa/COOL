# Route Inventory

Last updated: March 12, 2026

This is the source-of-truth inventory for Flutter routes declared in
[`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart).

Current router shape:

- `55` `GoRoute` declarations
- `4` shell branches (`home`, `groups`, `mobility`, `profile`)
- `53` screen files under `lib/features/**/screens`

Change policy:

- Any PR that adds, removes, renames, or re-guards a route must update this file.
- Any new user-facing route must ship with at least one smoke or routing test.
- Route changes that increase screen scope should also update
  [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md).

## Auth And Entry

| Path | Screen | Shell | Notes |
|---|---|---|---|
| `/` | [`SplashScreen`](../lib/features/auth/screens/splash_screen.dart) | No | Boot and profile-restore holding route |
| `/onboarding` | [`OnboardingScreen`](../lib/features/auth/screens/onboarding_screen.dart) | No | Signed-out landing route |
| `/language` | [`OnboardingScreen`](../lib/features/auth/screens/onboarding_screen.dart) | No | Alias route for onboarding language entry |
| `/otp` | [`OtpScreen`](../lib/features/auth/screens/otp_screen.dart) | No | WhatsApp OTP request |
| `/otp-verify?phone=` | [`OtpVerifyScreen`](../lib/features/auth/screens/otp_verify_screen.dart) | No | OTP verification |
| `/register?phone=` | [`RegisterScreen`](../lib/features/auth/screens/register_screen.dart) | No | Voluntary profile completion |
| `/invite/:code` | [`GroupInviteScreen`](../lib/features/groups/screens/group_invite_screen.dart) | No | Invite deep link, supports referral params |
| `/scanner?mode=ticket|momo` | [`QrScannerScreen`](../lib/shared/widgets/qr_scanner_screen.dart) | No | Ticket scanning is role-gated |

## Shell Branches

| Path | Screen | Shell Branch | Notes |
|---|---|---|---|
| `/home` | [`HomeScreen`](../lib/features/home/screens/home_screen.dart) | Home | Default authenticated landing route |
| `/groups` | [`GroupsScreen`](../lib/features/groups/screens/groups_screen.dart) | Groups | Group browse and launch route |
| `/groups/create` | [`CreateGroupScreen`](../lib/features/groups/screens/create_group_screen.dart) | Groups | Group creation |
| `/groups/:id` | [`GroupDetailScreen`](../lib/features/groups/screens/group_detail_screen.dart) | Groups | Group detail and contribution surface |
| `/mobility` | [`MobilityHomeScreen`](../lib/features/mobility/screens/mobility_home_screen.dart) | Mobility | Governed by mobility rollout flag |
| `/mobility/schedule` | [`ScheduleTripScreen`](../lib/features/mobility/screens/schedule_trip_screen.dart) | Mobility | Trip scheduling flow |
| `/mobility/trips` | [`TripBoardScreen`](../lib/features/mobility/screens/trip_board_screen.dart) | Mobility | Trip discovery and owned trips |
| `/mobility/driver` | [`DriverProfileScreen`](../lib/features/mobility/screens/driver_profile_screen.dart) | Mobility | Driver profile and operations |
| `/profile` | [`ProfileScreen`](../lib/features/profile/screens/profile_screen.dart) | Profile | Account, settings, and launchpad route |

## Standalone Core Routes

| Path | Screen | Shell | Notes |
|---|---|---|---|
| `/basket` | [`BasketScreen`](../lib/features/basket/screens/basket_screen.dart) | No | Compatibility placeholder route |
| `/momo` | [`MomoScreen`](../lib/features/momo/screens/momo_screen.dart) | No | Governed by MoMo rollout flag |
| `/momo/statements` | [`MomoStatementsScreen`](../lib/features/momo/screens/momo_statements_screen.dart) | No | Statements and export flow |
| `/credit` | [`CreditScoreScreen`](../lib/features/credit/screens/credit_score_screen.dart) | No | Governed by credit rollout flag |
| `/credit/readiness` | [`CreditReadinessScreen`](../lib/features/credit/screens/credit_readiness_screen.dart) | No | Governed by credit rollout flag |
| `/missions` | [`MissionsScreen`](../lib/core/status/screens/missions_screen.dart) | No | Engagement missions |

## Partner And Rayon Consumer Routes

| Path | Screen | Shell | Notes |
|---|---|---|---|
| `/partners` | [`PartnersScreen`](../lib/features/partners/screens/partners_screen.dart) | No | Partner discovery hub |
| `/partners/rayon-sports` | [`RayonHomeScreen`](../lib/features/partners/rayon/screens/rayon_home_screen.dart) | No | Rayon home surface |
| `/partners/rayon-sports/profile` | [`FanProfileScreen`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) | No | Member profile |
| `/partners/rayon-sports/membership` | [`MembershipTiersScreen`](../lib/features/partners/rayon/screens/membership_tiers_screen.dart) | No | Membership tiers |
| `/partners/rayon-sports/registry` | [`MemberRegistryScreen`](../lib/features/partners/screens/rayon/member_registry_screen.dart) | No | Member registry |
| `/partners/rayon-sports/clubs` | [`FanClubsScreen`](../lib/features/partners/screens/rayon/fan_clubs_screen.dart) | No | Fan-club index |
| `/partners/rayon-sports/clubs/:clubId` | [`FanClubDetailScreen`](../lib/features/partners/screens/rayon/fan_club_detail_screen.dart) | No | Fan-club detail |
| `/partners/rayon-sports/shop` | [`ClubShopScreen`](../lib/features/partners/screens/rayon/club_shop_screen.dart) | No | Club shop |
| `/partners/rayon-sports/shop/checkout` | [`ShopCheckoutScreen`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart) | No | Shop checkout |
| `/partners/rayon-sports/support` | [`SupportScreen`](../lib/features/partners/rayon/screens/support_screen.dart) | No | Support initiatives index |
| `/partners/rayon-sports/support/:initiativeId` | [`SupportDetailScreen`](../lib/features/partners/rayon/screens/support_detail_screen.dart) | No | Support initiative detail |
| `/partners/rayon-sports/tickets` | [`TicketsScreen`](../lib/features/partners/screens/rayon/tickets_screen.dart) | No | Governed by ticket rollout flag |
| `/partners/rayon-sports/tickets/my-tickets` | [`MyTicketsScreen`](../lib/features/partners/screens/rayon/my_tickets_screen.dart) | No | Owned tickets |
| `/partners/rayon-sports/tickets/:ticketId/confirm` | [`TicketConfirmationScreen`](../lib/features/partners/screens/rayon/ticket_confirmation_screen.dart) | No | Ticket confirmation end state |
| `/partners/:id` | [`BankPartnerScreen`](../lib/features/partners/screens/bank_partner_screen.dart), [`RadiantPartnerScreen`](../lib/features/partners/screens/radiant_partner_screen.dart), [`PrismaPartnerScreen`](../lib/features/partners/screens/prisma_partner_screen.dart) | No | Dynamic partner detail route; non-dedicated partners redirect to `/partners/:id/fans` |
| `/partners/:id/fans` | [`FansScreen`](../lib/features/partners/screens/fans_screen.dart) | No | Generic partner fan surface |

## Admin Routes

| Path | Screen | Notes |
|---|---|---|
| `/admin` | [`AdminDashboardScreen`](../lib/features/admin/screens/admin_dashboard_screen.dart) | Admin landing route |
| `/admin/users` | [`ManageUsersScreen`](../lib/features/admin/screens/manage_users_screen.dart) | User management |
| `/admin/partners` | [`ManagePartnersScreen`](../lib/features/admin/screens/manage_partners_screen.dart) | Partner management |
| `/admin/services` | [`ManageServicesScreen`](../lib/features/admin/screens/manage_services_screen.dart) | Service catalog management |
| `/admin/quick-actions` | [`ManageQuickActionsScreen`](../lib/features/admin/screens/manage_quick_actions_screen.dart) | Home quick actions |
| `/admin/vehicle-types` | [`ManageVehicleTypesScreen`](../lib/features/admin/screens/manage_vehicle_types_screen.dart) | Mobility vehicle types |
| `/admin/countries` | [`ManageCountriesScreen`](../lib/features/admin/screens/manage_countries_screen.dart) | Supported-country and routing config |
| `/admin/app-config` | [`ManageAppConfigScreen`](../lib/features/admin/screens/manage_app_config_screen.dart) | App configuration |

## Rayon Admin Routes

| Path | Screen | Notes |
|---|---|---|
| `/admin/rayon` | [`RsAdminDashboardScreen`](../lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart) | Rayon admin landing route |
| `/admin/rayon/matches` | [`RsAdminMatchesScreen`](../lib/features/partners/rayon/screens/rs_admin_matches_screen.dart) | Match operations |
| `/admin/rayon/tickets` | [`RsAdminTicketsScreen`](../lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart) | Ticket operations |
| `/admin/rayon/shop` | [`RsAdminShopScreen`](../lib/features/partners/rayon/screens/rs_admin_shop_screen.dart) | Shop operations |
| `/admin/rayon/orders` | [`RsAdminOrdersScreen`](../lib/features/partners/rayon/screens/rs_admin_orders_screen.dart) | Order operations |
| `/admin/rayon/members` | [`RsAdminMembersScreen`](../lib/features/partners/rayon/screens/rs_admin_members_screen.dart) | Member operations |
| `/admin/rayon/fan-clubs` | [`RsAdminInitiativesScreen`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | Temporary reuse until fan-club admin route exists |
| `/admin/rayon/initiatives` | [`RsAdminInitiativesScreen`](../lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart) | Initiative operations |
