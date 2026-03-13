import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_user_contact.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'app_redirects.dart';

import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/otp_verify_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
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
import '../../features/admin/screens/manage_app_config_screen.dart';
import '../../features/admin/screens/operational_dashboard_screen.dart';
import '../status/screens/missions_screen.dart';
import '../../shared/widgets/kill_switch_gate.dart';
import '../../shared/widgets/secure_screen_wrapper.dart';
import '../providers/engagement_providers.dart';
import 'navigation_keys.dart';
import 'shell_route.dart';

export 'app_redirects.dart';
export 'app_routes.dart';

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

final _appRouterRefreshListenableProvider = Provider<ChangeNotifier>((ref) {
  final notifier = _AppRouterRefreshNotifier();
  ref.listen(authProvider, (previous, next) => notifier.refresh());
  ref.listen(featureFlagsStateProvider, (previous, next) => notifier.refresh());
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(_appRouterRefreshListenableProvider);

  ({
    Session? session,
    bool hasProfile,
    bool isAdmin,
    AuthProfileRestoreState profileRestoreState,
  })
  readAuthSnapshot() {
    final state = ref.read(authProvider);
    return (
      session: state.session,
      hasProfile: state.user?.isProfileComplete ?? false,
      isAdmin: state.user?.isAdmin ?? false,
      profileRestoreState: state.profileRestoreState,
    );
  }

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authSnapshot = readAuthSnapshot();
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
          final authSnapshot = readAuthSnapshot();
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
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
          showNavigationChrome: appShellRootLocations.contains(state.uri.path),
        ),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const HomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _groupsNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.groups,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const GroupsScreen(),
                ),
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
                pageBuilder: (context, state) {
                  final authSnapshot = readAuthSnapshot();
                  final featureFlags = ref.read(featureFlagsStateProvider);
                  return NoTransitionPage(
                    key: state.pageKey,
                    child: KillSwitchGate(
                      enabled: featureFlags.isMobilityEnabled(
                        isAdmin: authSnapshot.isAdmin,
                      ),
                      featureName: 'Mobility',
                      child: const MobilityHomeScreen(),
                    ),
                  );
                },
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
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const ProfileScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      // ── Standalone routes (outside shell) ─────────────────────
      GoRoute(
        path: AppRoutes.momo,
        builder: (context, state) {
          final authSnapshot = readAuthSnapshot();
          final featureFlags = ref.read(featureFlagsStateProvider);
          return KillSwitchGate(
            enabled: featureFlags.isMomoEnabled(isAdmin: authSnapshot.isAdmin),
            featureName: 'Mobile Money',
            child: SecureScreenWrapper(child: MomoScreen(launchUri: state.uri)),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.momoStatements,
        builder: (context, state) {
          final authSnapshot = readAuthSnapshot();
          final featureFlags = ref.read(featureFlagsStateProvider);
          return KillSwitchGate(
            enabled: featureFlags.isMomoEnabled(isAdmin: authSnapshot.isAdmin),
            featureName: 'Mobile Money',
            child: const SecureScreenWrapper(child: MomoStatementsScreen()),
          );
        },
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
                builder: (context, state) {
                  final authSnapshot = readAuthSnapshot();
                  final featureFlags = ref.read(featureFlagsStateProvider);
                  return KillSwitchGate(
                    enabled: featureFlags.isTicketPurchaseEnabled(
                      isAdmin: authSnapshot.isAdmin,
                    ),
                    featureName: 'Ticket Purchase',
                    child: TicketsScreen(
                      referralParameters: state.uri.queryParameters,
                    ),
                  );
                },
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
            redirect: (context, state) =>
                resolvePartnerDetailRedirect(state.pathParameters['id']!),
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
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.credit,
        builder: (context, state) {
          final authSnapshot = readAuthSnapshot();
          final featureFlags = ref.read(featureFlagsStateProvider);
          return KillSwitchGate(
            enabled: featureFlags.isCreditEnabled(
              isAdmin: authSnapshot.isAdmin,
            ),
            featureName: 'Credit Score',
            child: const SecureScreenWrapper(child: CreditScoreScreen()),
          );
        },
        routes: [
          GoRoute(
            path: 'readiness',
            builder: (context, state) {
              final authSnapshot = readAuthSnapshot();
              final featureFlags = ref.read(featureFlagsStateProvider);
              return KillSwitchGate(
                enabled: featureFlags.isCreditEnabled(
                  isAdmin: authSnapshot.isAdmin,
                ),
                featureName: 'Credit Readiness',
                child: const SecureScreenWrapper(
                  child: CreditReadinessScreen(),
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.missions,
        builder: (context, state) => const MissionsScreen(),
      ),

      // ── Admin routes (nested under /admin) ─────────────────────
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminDashboardScreen(),
        routes: [
          GoRoute(
            path: 'users',
            builder: (context, state) => const ManageUsersScreen(),
          ),
          GoRoute(
            path: 'partners',
            builder: (context, state) => const ManagePartnersScreen(),
          ),
          GoRoute(
            path: 'services',
            builder: (context, state) => const ManageServicesScreen(),
          ),
          GoRoute(
            path: 'quick-actions',
            builder: (context, state) => const ManageQuickActionsScreen(),
          ),
          GoRoute(
            path: 'vehicle-types',
            builder: (context, state) => const ManageVehicleTypesScreen(),
          ),
          GoRoute(
            path: 'app-config',
            builder: (context, state) => const ManageAppConfigScreen(),
          ),
          GoRoute(
            path: 'operations',
            builder: (context, state) => const OperationalDashboardScreen(),
          ),
          // ── RS Admin routes (nested under /admin/rayon) ──────────
          GoRoute(
            path: 'rayon',
            builder: (context, state) => const RsAdminDashboardScreen(),
            routes: [
              GoRoute(
                path: 'matches',
                builder: (context, state) => const RsAdminMatchesScreen(),
              ),
              GoRoute(
                path: 'tickets',
                builder: (context, state) => const RsAdminTicketsScreen(),
              ),
              GoRoute(
                path: 'shop',
                builder: (context, state) => const RsAdminShopScreen(),
              ),
              GoRoute(
                path: 'orders',
                builder: (context, state) => const RsAdminOrdersScreen(),
              ),
              GoRoute(
                path: 'members',
                builder: (context, state) => const RsAdminMembersScreen(),
              ),
              GoRoute(
                path: 'initiatives',
                builder: (context, state) => const RsAdminInitiativesScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _AppRouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
