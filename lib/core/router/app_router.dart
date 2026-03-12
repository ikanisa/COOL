import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_user_contact.dart';
import '../../features/auth/providers/auth_provider.dart';

import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/otp_verify_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/basket/screens/basket_screen.dart';
import '../../features/credit/screens/credit_score_screen.dart';
import '../../features/credit/screens/credit_readiness_screen.dart';
import '../../features/groups/screens/create_group_screen.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/groups/screens/group_invite_screen.dart';
import '../../features/groups/screens/groups_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/mobility/screens/driver_profile_screen.dart';
import '../../features/mobility/screens/mobility_home_screen.dart';
import '../../features/mobility/screens/schedule_trip_screen.dart';
import '../../features/mobility/screens/trip_board_screen.dart';

import '../../features/momo/screens/momo_screen.dart';
import '../../features/momo/screens/momo_statements_screen.dart';
import '../../features/partners/screens/bank_partner_screen.dart';
import '../../features/partners/screens/fans_screen.dart';
import '../../features/partners/screens/partners_screen.dart';
import '../../features/partners/screens/prisma_partner_screen.dart';
import '../../features/partners/screens/radiant_partner_screen.dart';
import '../../features/partners/screens/rayon/club_shop_screen.dart';
import '../../features/partners/screens/rayon/fan_club_detail_screen.dart';
import '../../features/partners/screens/rayon/fan_clubs_screen.dart';
import '../../features/partners/rayon/screens/fan_profile_screen.dart';
import '../../features/partners/rayon/screens/membership_tiers_screen.dart';
import '../../features/partners/screens/rayon/member_registry_screen.dart';
import '../../features/partners/screens/rayon/my_tickets_screen.dart';
import '../../features/partners/rayon/screens/rayon_home_screen.dart';
import '../../features/partners/screens/rayon/shop_checkout_screen.dart';
import '../../features/partners/screens/rayon/ticket_confirmation_screen.dart';
import '../../features/partners/rayon/screens/support_detail_screen.dart';
import '../../features/partners/rayon/screens/support_screen.dart';
import '../../features/partners/screens/rayon/tickets_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../shared/widgets/qr_scanner_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_dashboard_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_matches_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_tickets_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_shop_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_orders_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_members_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_initiatives_screen.dart';
import '../../features/admin/screens/manage_users_screen.dart';
import '../../features/admin/screens/manage_partners_screen.dart';
import '../../features/admin/screens/manage_services_screen.dart';
import '../../features/admin/screens/manage_quick_actions_screen.dart';
import '../../features/admin/screens/manage_vehicle_types_screen.dart';
import '../../features/admin/screens/manage_countries_screen.dart';
import '../../features/admin/screens/manage_app_config_screen.dart';
import '../status/screens/missions_screen.dart';
import '../../shared/widgets/kill_switch_gate.dart';
import '../../shared/widgets/secure_screen_wrapper.dart';
import '../providers/engagement_providers.dart';
import 'shell_route.dart';

// ────────────────────────────────────────────────────────────────────────
// Route constants
// ────────────────────────────────────────────────────────────────────────

/// Slugs that have a dedicated detail screen (not a generic fans page).
/// As partners become fully data-driven, this set may shrink.
const _partnerDetailSlugs = {'urwego', 'equity', 'radiant', 'prisma'};

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');
final _homeNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'homeNavigator',
);
final _groupsNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'groupsNavigator',
);
final _mobilityNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'mobilityNavigator',
);
final _profileNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'profileNavigator',
);

abstract final class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const language = '/language';
  static const otp = '/otp';
  static const otpVerify = '/otp-verify';
  static const register = '/register';
  static const home = '/home';
  static const groups = '/groups';
  static const groupCreate = '/groups/create';
  static const groupDetail = '/groups/:id';
  static const groupInvite = '/invite/:code';
  static const basket = '/basket';
  static const momo = '/momo';
  static const momoStatements = '/momo/statements';
  static const mobility = '/mobility';
  static const mobilitySchedule = '/mobility/schedule';
  static const mobilityTrips = '/mobility/trips';
  static const mobilityDriver = '/mobility/driver';
  static const partners = '/partners';
  static const partnerFans = '/partners/:id/fans';
  static const rayonHome = '/partners/rayon-sports';
  static const rayonProfile = '/partners/rayon-sports/profile';
  static const rayonRegistry = '/partners/rayon-sports/registry';
  static const rayonClubs = '/partners/rayon-sports/clubs';
  static const rayonClubDetail = '/partners/rayon-sports/clubs/:clubId';
  static const rayonShop = '/partners/rayon-sports/shop';
  static const rayonShopCheckout = '/partners/rayon-sports/shop/checkout';
  static const rayonSupport = '/partners/rayon-sports/support';
  static const rayonSupportDetail =
      '/partners/rayon-sports/support/:initiativeId';
  static const rayonTickets = '/partners/rayon-sports/tickets';
  static const rayonMyTickets = '/partners/rayon-sports/tickets/my-tickets';
  static const rayonTicketConfirm =
      '/partners/rayon-sports/tickets/:ticketId/confirm';
  static const rayonMembership = '/partners/rayon-sports/membership';
  static const credit = '/credit';
  static const creditReadiness = '/credit/readiness';
  static const missions = '/missions';
  static const profile = '/profile';

  static const scanner = '/scanner';

  // Admin routes
  static const admin = '/admin';
  static const adminUsers = '/admin/users';
  static const adminPartners = '/admin/partners';
  static const adminServices = '/admin/services';
  static const adminQuickActions = '/admin/quick-actions';
  static const adminVehicleTypes = '/admin/vehicle-types';
  static const adminCountries = '/admin/countries';
  static const adminAppConfig = '/admin/app-config';

  // RS Admin routes
  static const adminRayon = '/admin/rayon';
  static const adminRayonMatches = '/admin/rayon/matches';
  static const adminRayonTickets = '/admin/rayon/tickets';
  static const adminRayonShop = '/admin/rayon/shop';
  static const adminRayonOrders = '/admin/rayon/orders';
  static const adminRayonMembers = '/admin/rayon/members';
  static const adminRayonFanClubs = '/admin/rayon/fan-clubs';
  static const adminRayonInitiatives = '/admin/rayon/initiatives';

  static String onboardingLocation({String? redirect}) {
    return _location(onboarding, redirect: redirect);
  }

  static String splashLocation({String? redirect}) {
    return _location(splash, redirect: redirect);
  }

  static String otpLocation({String? redirect}) {
    return _location(otp, redirect: redirect);
  }

  static String otpVerifyLocation({required String phone, String? redirect}) {
    return _location(
      otpVerify,
      queryParameters: <String, String>{'phone': phone},
      redirect: redirect,
    );
  }

  static String registerLocation({String? phone, String? redirect}) {
    final queryParameters = <String, String>{};
    if (phone != null && phone.trim().isNotEmpty) {
      queryParameters['phone'] = phone.trim();
    }
    return _location(
      register,
      queryParameters: queryParameters,
      redirect: redirect,
    );
  }

  static String inviteLocation(String code) {
    return '/invite/${code.trim().toUpperCase()}';
  }

  static String rayonClubDetailLocation(String id) {
    return '/partners/rayon-sports/clubs/$id';
  }

  static String rayonSupportDetailLocation(String id) {
    return '/partners/rayon-sports/support/$id';
  }

  static String _location(
    String path, {
    Map<String, String>? queryParameters,
    String? redirect,
  }) {
    final parameters = <String, String>{
      ...?queryParameters,
      if (redirect != null && redirect.trim().isNotEmpty)
        'redirect': redirect.trim(),
    };
    if (parameters.isEmpty) {
      return path;
    }
    return Uri(path: path, queryParameters: parameters).toString();
  }
}

// ────────────────────────────────────────────────────────────────────────
// Router provider
// ────────────────────────────────────────────────────────────────────────

/// Routes that unauthenticated users are allowed to visit.
const _authRoutes = {
  '/',
  AppRoutes.onboarding,
  AppRoutes.language,
  AppRoutes.otp,
  AppRoutes.otpVerify,
  // Note: /register is NOT an auth route — authenticated users can visit
  // it voluntarily from the Profile screen to complete their profile.
};

bool _isAdminRoute(String location) {
  return location == AppRoutes.admin ||
      location.startsWith('${AppRoutes.admin}/');
}

String? _normalizeRedirectTarget(String? target) {
  if (target == null) {
    return null;
  }

  final trimmed = target.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  final path = uri?.path ?? trimmed;
  if (path.isEmpty || path == AppRoutes.splash || _authRoutes.contains(path)) {
    return null;
  }

  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
}

bool _asMetadataBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

bool _hasPartnerScannerAccess(User? user) {
  if (user == null) {
    return false;
  }

  final appMetadata = user.appMetadata;
  if (_asMetadataBool(appMetadata['is_partner_admin'])) {
    return true;
  }

  final partnerAdminIds = appMetadata['partner_admin_ids'];
  if (partnerAdminIds is List) {
    return partnerAdminIds.any((value) => value.toString().trim().isNotEmpty);
  }
  if (partnerAdminIds is Map) {
    return partnerAdminIds.entries.any(
      (entry) =>
          _asMetadataBool(entry.value) &&
          entry.key.toString().trim().isNotEmpty,
    );
  }

  return false;
}

String? resolveAppRedirect({
  required String location,
  String? requestedLocation,
  required bool hasSession,
  required bool hasProfile,
  AuthProfileRestoreState profileRestoreState =
      AuthProfileRestoreState.available,
  bool isAdmin = false,
  String? sessionPhone,
  String? pendingRedirect,
}) {
  final isAuthRoute = _authRoutes.contains(location);
  final isAdminRoute = _isAdminRoute(location);
  final redirectSource =
      pendingRedirect ?? (isAuthRoute ? null : requestedLocation ?? location);
  final redirectTarget = _normalizeRedirectTarget(redirectSource);
  final isProfileRestoreBlocked =
      profileRestoreState == AuthProfileRestoreState.pending ||
      profileRestoreState == AuthProfileRestoreState.failed;

  if (hasSession && isProfileRestoreBlocked) {
    if (location == AppRoutes.splash) {
      return null;
    }
    return AppRoutes.splashLocation(redirect: redirectTarget);
  }

  if (!hasSession) {
    if (location == AppRoutes.splash) {
      return AppRoutes.onboardingLocation(redirect: redirectTarget);
    }
    return isAuthRoute
        ? null
        : AppRoutes.onboardingLocation(
            redirect: _normalizeRedirectTarget(requestedLocation ?? location),
          );
  }

  // Profile completion is optional — users reach /register from Profile screen.
  // No forced redirect for incomplete profiles.

  if (isAdminRoute && !isAdmin) {
    return AppRoutes.home;
  }

  if (location == AppRoutes.splash || isAuthRoute) {
    return redirectTarget ?? AppRoutes.home;
  }

  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authSnapshot = ref.watch(
    authProvider.select(
      (state) => (
        session: state.session,
        hasProfile: state.user?.isProfileComplete ?? false,
        isAdmin: state.user?.isAdmin ?? false,
        profileRestoreState: state.profileRestoreState,
        countryCode: resolveAuthStateCountryCode(state),
      ),
    ),
  );
  final featureFlags = ref.watch(featureFlagsStateProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final location = state.matchedLocation;
      return resolveAppRedirect(
        location: location,
        requestedLocation: state.uri.toString(),
        hasSession: authSnapshot.session != null,
        hasProfile: authSnapshot.hasProfile,
        profileRestoreState: authSnapshot.profileRestoreState,
        isAdmin: authSnapshot.isAdmin,
        sessionPhone: authSessionPhone(authSnapshot.session),
        pendingRedirect: state.uri.queryParameters['redirect'],
      );
    },
    routes: [
      // ── Auth flow ─────────────────────────────────────────────
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => OnboardingScreen(
          redirectPath: state.uri.queryParameters['redirect'],
        ),
      ),
      GoRoute(
        path: AppRoutes.language,
        builder: (context, state) => OnboardingScreen(
          redirectPath: state.uri.queryParameters['redirect'],
        ),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) =>
            OtpScreen(redirectPath: state.uri.queryParameters['redirect']),
      ),
      GoRoute(
        path: AppRoutes.otpVerify,
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          return OtpVerifyScreen(
            phoneNumber: phone,
            redirectPath: state.uri.queryParameters['redirect'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          return RegisterScreen(
            phone: phone,
            redirectPath: state.uri.queryParameters['redirect'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.groupInvite,
        builder: (context, state) {
          final code = state.pathParameters['code'] ?? '';
          return GroupInviteScreen(
            inviteCode: code,
            referralParameters: state.uri.queryParameters,
          );
        },
      ),

      // ── QR Scanner (full-screen, no shell) ─────────────────────
      GoRoute(
        path: AppRoutes.scanner,
        builder: (context, state) {
          final modeStr = state.uri.queryParameters['mode'] ?? 'ticket';
          final mode = modeStr == 'momo' ? QrScanMode.momo : QrScanMode.ticket;
          final ticketScanningEnabled =
              authSnapshot.isAdmin ||
              _hasPartnerScannerAccess(authSnapshot.session?.user);
          return QrScannerScreen(
            mode: mode,
            ticketScanningEnabled: ticketScanningEnabled,
          );
        },
      ),

      // ── Main app (shell with bottom nav) ──────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: HomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _groupsNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.groups,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: GroupsScreen()),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const CreateGroupScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return GroupDetailScreen(groupId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _mobilityNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.mobility,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: KillSwitchGate(
                    enabled: featureFlags.isMobilityEnabled(
                      countryCode: authSnapshot.countryCode,
                      isAdmin: authSnapshot.isAdmin,
                    ),
                    featureName: 'Mobility',
                    child: const MobilityHomeScreen(),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'schedule',
                    builder: (context, state) => const ScheduleTripScreen(),
                  ),
                  GoRoute(
                    path: 'trips',
                    builder: (context, state) => const TripBoardScreen(),
                  ),
                  GoRoute(
                    path: 'driver',
                    builder: (context, state) => const DriverProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ProfileScreen()),
              ),
            ],
          ),
        ],
      ),

      // ── Standalone routes (outside shell) ─────────────────────
      GoRoute(
        path: AppRoutes.basket,
        builder: (context, state) => const BasketScreen(),
      ),
      GoRoute(
        path: AppRoutes.momo,
        builder: (context, state) => KillSwitchGate(
          enabled: featureFlags.isMomoEnabled(
            countryCode: authSnapshot.countryCode,
            isAdmin: authSnapshot.isAdmin,
          ),
          featureName: 'Mobile Money',
          child: const SecureScreenWrapper(child: MomoScreen()),
        ),
      ),
      GoRoute(
        path: AppRoutes.momoStatements,
        builder: (context, state) => const MomoStatementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.partners,
        builder: (context, state) => const PartnersScreen(),
        routes: [
          GoRoute(
            path: 'rayon-sports',
            builder: (context, state) => const RayonHomeScreen(),
            routes: [
              GoRoute(
                path: 'profile',
                builder: (context, state) => const FanProfileScreen(),
              ),
              GoRoute(
                path: 'membership',
                builder: (context, state) => const MembershipTiersScreen(),
              ),
              GoRoute(
                path: 'registry',
                builder: (context, state) => const MemberRegistryScreen(),
              ),
              GoRoute(
                path: 'clubs',
                builder: (context, state) => const FanClubsScreen(),
                routes: [
                  GoRoute(
                    path: ':clubId',
                    builder: (context, state) => FanClubDetailScreen(
                      clubId: state.pathParameters['clubId'] ?? '',
                      referralParameters: state.uri.queryParameters,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'shop',
                builder: (context, state) => const ClubShopScreen(),
                routes: [
                  GoRoute(
                    path: 'checkout',
                    builder: (context, state) => ShopCheckoutScreen(
                      referralParameters: state.uri.queryParameters,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'support',
                builder: (context, state) => const SupportScreen(),
                routes: [
                  GoRoute(
                    path: ':initiativeId',
                    builder: (context, state) => SupportDetailScreen(
                      initiativeId: state.pathParameters['initiativeId'] ?? '',
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'tickets',
                builder: (context, state) => KillSwitchGate(
                  enabled: featureFlags.isTicketPurchaseEnabled(
                    countryCode: authSnapshot.countryCode,
                    isAdmin: authSnapshot.isAdmin,
                  ),
                  featureName: 'Ticket Purchase',
                  child: TicketsScreen(
                    referralParameters: state.uri.queryParameters,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'my-tickets',
                    builder: (context, state) => const MyTicketsScreen(),
                  ),
                  GoRoute(
                    path: ':ticketId/confirm',
                    builder: (context, state) => TicketConfirmationScreen(
                      ticketId: state.pathParameters['ticketId'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: ':id',
            redirect: (context, state) {
              final id = state.pathParameters['id']!;
              if (id == 'rayon-sports') {
                return AppRoutes.rayonHome;
              }
              // Non-football partners get their own detail screen
              if (_partnerDetailSlugs.contains(id)) return null;
              return '/partners/$id/fans';
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return switch (id) {
                'urwego' => BankPartnerScreen(bankId: id),
                'equity' => BankPartnerScreen(bankId: id),
                'radiant' => const RadiantPartnerScreen(),
                'prisma' => const PrismaPartnerScreen(),
                _ => BankPartnerScreen(bankId: id),
              };
            },
            routes: [
              GoRoute(
                path: 'fans',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return FansScreen(partnerId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.credit,
        builder: (context, state) => KillSwitchGate(
          enabled: featureFlags.isCreditEnabled(
            countryCode: authSnapshot.countryCode,
            isAdmin: authSnapshot.isAdmin,
          ),
          featureName: 'Credit Score',
          child: const SecureScreenWrapper(child: CreditScoreScreen()),
        ),
      ),
      GoRoute(
        path: AppRoutes.creditReadiness,
        builder: (context, state) => KillSwitchGate(
          enabled: featureFlags.isCreditEnabled(
            countryCode: authSnapshot.countryCode,
            isAdmin: authSnapshot.isAdmin,
          ),
          featureName: 'Credit Readiness',
          child: const SecureScreenWrapper(child: CreditReadinessScreen()),
        ),
      ),
      GoRoute(
        path: AppRoutes.missions,
        builder: (context, state) => const MissionsScreen(),
      ),

      // ── Admin routes (outside shell, full-screen) ──────────────
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminUsers,
        builder: (context, state) => const ManageUsersScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminPartners,
        builder: (context, state) => const ManagePartnersScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminServices,
        builder: (context, state) => const ManageServicesScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminQuickActions,
        builder: (context, state) => const ManageQuickActionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminVehicleTypes,
        builder: (context, state) => const ManageVehicleTypesScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminCountries,
        builder: (context, state) => const ManageCountriesScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminAppConfig,
        builder: (context, state) => const ManageAppConfigScreen(),
      ),

      // ── RS Admin routes ────────────────────────────────────────
      GoRoute(
        path: AppRoutes.adminRayon,
        builder: (context, state) => const RsAdminDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminRayonMatches,
        builder: (context, state) => const RsAdminMatchesScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminRayonTickets,
        builder: (context, state) => const RsAdminTicketsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminRayonShop,
        builder: (context, state) => const RsAdminShopScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminRayonOrders,
        builder: (context, state) => const RsAdminOrdersScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminRayonMembers,
        builder: (context, state) => const RsAdminMembersScreen(),
      ),
      // TODO(admin): Create dedicated RsAdminFanClubsScreen when fan club
      // management is needed. Using initiatives screen as the closest match.
      GoRoute(
        path: AppRoutes.adminRayonFanClubs,
        builder: (context, state) => const RsAdminInitiativesScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminRayonInitiatives,
        builder: (context, state) => const RsAdminInitiativesScreen(),
      ),
    ],
  );
});
