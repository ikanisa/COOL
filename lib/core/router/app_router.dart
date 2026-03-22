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
import '../../features/auth/screens/app_access_onboarding_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/credit/screens/credit_score_screen.dart';
import '../../features/credit/screens/credit_readiness_screen.dart';
import '../../features/groups/screens/create_group_screen.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/groups/screens/group_ledger_screen.dart';
import '../../features/groups/screens/group_invite_screen.dart';
import '../../features/groups/screens/groups_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/home/screens/seasons_activities_screen.dart';
import '../../features/mobility/screens/driver_detail_screens.dart';
import '../../features/mobility/screens/driver_profile_screen.dart';
import '../../features/mobility/screens/mobility_home_screen.dart';
import '../../features/mobility/screens/schedule_trip_screen.dart';
import '../../features/mobility/screens/trip_board_screen.dart';
import '../../features/momo/screens/momo_screen.dart';
import '../../features/momo/screens/momo_statements_screen.dart';
import '../../features/partners/bank_onboarding/screens/bank_onboarding_screen.dart';
import '../../features/admin/screens/manage_special_products_screen.dart';
import '../../features/admin/screens/manage_activities_screen.dart';
import '../../features/admin/screens/manage_missions_screen.dart';
import '../../features/admin/screens/manage_seasons_screen.dart';
import '../../features/partners/screens/bank_partner_screen.dart';
import '../../features/partners/screens/partners_screen.dart';
import '../../features/profile/screens/kyc_selfie_screen.dart';
import '../../features/profile/screens/profile_detail_screens.dart';

import '../../features/partners/screens/prisma_partner_screen.dart';
import '../../features/partners/screens/radiant_partner_screen.dart';
import '../../features/partners/rayon/screens/club_shop_screen.dart';
import '../../features/partners/rayon/screens/fan_club_detail_screen.dart';
import '../../features/partners/rayon/screens/fan_clubs_screen.dart';
import '../../features/partners/rayon/screens/fan_profile_screen.dart';
import '../../features/partners/rayon/screens/membership_tiers_screen.dart';
import '../../features/partners/rayon/screens/member_registry_screen.dart';
import '../../features/partners/rayon/screens/my_tickets_screen.dart';
import '../../features/partners/rayon/screens/rayon_home_screen.dart';
import '../../features/partners/rayon/screens/shop_checkout_screen.dart';
import '../../features/partners/rayon/screens/ticket_confirmation_screen.dart';
import '../../features/partners/rayon/screens/support_detail_screen.dart';
import '../../features/partners/rayon/screens/support_screen.dart';
import '../../features/partners/rayon/screens/tickets_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../shared/widgets/qr_scanner_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/admin_workspaces_screen.dart';
import '../../features/admin/screens/bank_admin_workspace_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_dashboard_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_matches_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_tickets_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_shop_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_orders_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_members_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_packages_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_finance_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_analytics_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_initiatives_screen.dart';
import '../../features/admin/screens/partner_admin_workspace_screen.dart';
import '../../features/admin/models/admin_workspace_access.dart';
import '../../features/admin/providers/admin_workspace_access_provider.dart';
import '../../features/admin/screens/manage_users_screen.dart';
import '../../features/admin/screens/manage_partners_screen.dart';
import '../../features/admin/screens/manage_services_screen.dart';
import '../../features/admin/screens/manage_quick_actions_screen.dart';
import '../../features/admin/screens/manage_vehicle_types_screen.dart';
import '../../features/admin/screens/manage_app_config_screen.dart';
import '../../features/admin/screens/operational_dashboard_screen.dart';
import '../../features/admin/screens/manage_admin_roles_screen.dart';
import '../../features/admin/screens/system_analytics_screen.dart';
import '../../features/admin/screens/audit_log_screen.dart';
import '../../features/admin/screens/manage_ai_content_screen.dart';
import '../../features/admin/widgets/admin_workspace_gate.dart';
import '../status/screens/cool_tokens_screen.dart';
import '../status/screens/referral_hub_screen.dart';
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

/// Reusable "Cool" page transition: 300ms Fade + Subtle Scale.
CustomTransitionPage<T> _coolPageTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeOut).animate(animation),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(_appRouterRefreshListenableProvider);

  ({
    Session? session,
    bool hasProfile,
    bool isAdmin,
    AuthProfileRestoreState profileRestoreState,
    AdminWorkspaceAccess adminAccess,
    bool hasRayonAdminAccess,
  })
  readAuthSnapshot() {
    final state = ref.read(authProvider);
    final adminAccess = ref.read(adminWorkspaceAccessProvider);
    final rayonAdminAccessAsync = ref.read(rayonAdminAccessProvider);
    return (
      session: state.session,
      hasProfile: state.user?.isProfileComplete ?? false,
      isAdmin: state.user?.isAdmin ?? false,
      profileRestoreState: state.profileRestoreState,
      adminAccess: adminAccess,
      hasRayonAdminAccess:
          adminAccess.hasPlatformAccess ||
          adminAccess.hasPartnerAdminAccess ||
          rayonAdminAccessAsync.valueOrNull == true,
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
        adminAccess: authSnapshot.adminAccess,
        hasRayonAdminAccess: authSnapshot.hasRayonAdminAccess,
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
        path: AppRoutes.appAccess,
        builder: (context, state) => AppAccessOnboardingScreen(
          redirectPath: state.uri.queryParameters['redirect'],
        ),
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
        pageBuilder: (context, state) {
          final authSnapshot = readAuthSnapshot();
          final modeStr = state.uri.queryParameters['mode'] ?? 'ticket';
          final mode = modeStr == 'momo' ? QrScanMode.momo : QrScanMode.ticket;
          final ticketScanningEnabled =
              authSnapshot.isAdmin ||
              _hasPartnerScannerAccess(authSnapshot.session?.user);
          return _coolPageTransition(
            context: context,
            state: state,
            child: QrScannerScreen(
              mode: mode,
              ticketScanningEnabled: ticketScanningEnabled,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.kycSelfie,
        pageBuilder: (context, state) => _coolPageTransition(
          context: context,
          state: state,
          child: const KycSelfieScreen(),
        ),
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
                    builder: (context, state) {
                      return const CreateGroupScreen();
                    },
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return GroupDetailScreen(groupId: id);
                    },
                    routes: [
                      GoRoute(
                        path: 'ledger',
                        builder: (context, state) {
                          final id = state.pathParameters['id']!;
                          return GroupLedgerScreen(groupId: id);
                        },
                      ),
                    ],
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
                    routes: [
                      GoRoute(
                        path: 'vehicle',
                        builder: (context, state) =>
                            const DriverVehicleScreen(),
                      ),
                      GoRoute(
                        path: 'subscription',
                        builder: (context, state) =>
                            const DriverSubscriptionScreen(),
                      ),
                    ],
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
                routes: [
                  GoRoute(
                    path: 'wallet',
                    builder: (context, state) => const ProfileWalletScreen(),
                  ),
                  GoRoute(
                    path: 'identity',
                    builder: (context, state) => const ProfileIdentityScreen(),
                  ),
                  GoRoute(
                    path: 'travel-role',
                    builder: (context, state) =>
                        const ProfileTravelRoleScreen(),
                  ),
                ],
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
            routes: [
              GoRoute(
                path: 'onboarding/:type',
                builder: (context, state) {
                  final slug = state.pathParameters['id'] ?? '';
                  final typeStr = state.pathParameters['type'] ?? 'loan';
                  final type = typeStr == 'account'
                      ? BankOnboardingType.account
                      : BankOnboardingType.loan;
                  return BankOnboardingScreen(slug: slug, type: type);
                },
              ),
            ],
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
        pageBuilder: (context, state) => _coolPageTransition(
          context: context,
          state: state,
          child: const MissionsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.tokens,
        pageBuilder: (context, state) => _coolPageTransition(
          context: context,
          state: state,
          child: const CoolTokensScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.referral,
        pageBuilder: (context, state) => _coolPageTransition(
          context: context,
          state: state,
          child: const ReferralHubScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.seasons,
        pageBuilder: (context, state) => _coolPageTransition(
          context: context,
          state: state,
          child: const SeasonsActivitiesScreen(),
        ),
      ),

      // ── Admin routes (nested under /admin) ─────────────────────
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminWorkspacesScreen(),
        routes: [
          GoRoute(
            path: 'platform',
            builder: (context, state) =>
                const PlatformAdminGate(child: AdminDashboardScreen()),
          ),
          GoRoute(
            path: 'users',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageUsersScreen()),
          ),
          GoRoute(
            path: 'partners',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManagePartnersScreen()),
          ),
          GoRoute(
            path: 'partners/:partnerId',
            builder: (context, state) => PartnerAdminWorkspaceScreen(
              partnerId: state.pathParameters['partnerId'] ?? '',
            ),
          ),
          GoRoute(
            path: 'services',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageServicesScreen()),
          ),
          GoRoute(
            path: 'quick-actions',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageQuickActionsScreen()),
          ),
          GoRoute(
            path: 'vehicle-types',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageVehicleTypesScreen()),
          ),
          GoRoute(
            path: 'app-config',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageAppConfigScreen()),
          ),
          GoRoute(
            path: 'special-products',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageSpecialProductsScreen()),
          ),
          GoRoute(
            path: 'missions',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageMissionsScreen()),
          ),
          GoRoute(
            path: 'seasons',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageSeasonsScreen()),
          ),
          GoRoute(
            path: 'activities',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageActivitiesScreen()),
          ),
          GoRoute(
            path: 'operations',
            builder: (context, state) =>
                const PlatformAdminGate(child: OperationalDashboardScreen()),
          ),
          GoRoute(
            path: 'roles',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageAdminRolesScreen()),
          ),
          GoRoute(
            path: 'analytics',
            builder: (context, state) =>
                const PlatformAdminGate(child: SystemAnalyticsScreen()),
          ),
          GoRoute(
            path: 'audit-log',
            builder: (context, state) =>
                const PlatformAdminGate(child: AuditLogScreen()),
          ),
          GoRoute(
            path: 'ai-content',
            builder: (context, state) =>
                const PlatformAdminGate(child: ManageAiContentScreen()),
          ),
          GoRoute(
            path: 'banks/:partnerId',
            builder: (context, state) => BankAdminWorkspaceScreen(
              partnerId: state.pathParameters['partnerId'] ?? '',
            ),
          ),
          // ── RS Admin routes (nested under /admin/rayon) ──────────
          GoRoute(
            path: 'rayon',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminDashboardScreen()),
            routes: [
              GoRoute(
                path: 'matches',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminMatchesScreen()),
              ),
              GoRoute(
                path: 'tickets',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminTicketsScreen()),
              ),
              GoRoute(
                path: 'shop',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminShopScreen()),
              ),
              GoRoute(
                path: 'orders',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminOrdersScreen()),
              ),
              GoRoute(
                path: 'members',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminMembersScreen()),
              ),
              GoRoute(
                path: 'packages',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminPackagesScreen()),
              ),
              GoRoute(
                path: 'finance',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminFinanceScreen()),
              ),
              GoRoute(
                path: 'initiatives',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminInitiativesScreen()),
              ),
              GoRoute(
                path: 'analytics',
                builder: (context, state) =>
                    const RayonAdminGate(child: RsAdminAnalyticsScreen()),
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
