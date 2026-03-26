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
import '../../features/groups/screens/create_group_screen.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/groups/screens/group_ledger_screen.dart';
import '../../features/groups/screens/group_invite_screen.dart';
import '../../features/groups/screens/groups_screen.dart';
import '../../features/home/screens/services_hub_screen.dart';
import '../../features/home/screens/seasons_activities_screen.dart';
import '../../features/partners/rayon/screens/rayon_home_screen.dart';
import '../../features/partners/rayon/screens/club_shop_screen.dart';
import '../../features/momo/screens/momo_screen.dart';
import '../../features/momo/screens/momo_statements_screen.dart';
import '../../features/profile/screens/profile_detail_screens.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../shared/widgets/qr_scanner_screen.dart';
import '../../shared/widgets/kill_switch_gate.dart';
import '../../shared/widgets/secure_screen_wrapper.dart';
import '../status/screens/cool_tokens_screen.dart';
import '../status/screens/referral_hub_screen.dart';
import '../status/screens/missions_screen.dart';
import '../../features/admin/models/admin_workspace_access.dart';
import '../../features/admin/providers/admin_workspace_access_provider.dart';
import '../providers/engagement_providers.dart';
import 'admin_routes.dart';
import 'biopay_routes.dart';
import 'navigation_keys.dart';
import 'partner_routes.dart';
import 'shell_route.dart';

export 'app_redirects.dart';
export 'app_routes.dart';

final _homeNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'homeNavigator',
);
final _shopNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shopNavigator',
);
final _momoNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'momoNavigator',
);
final _servicesNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'servicesNavigator',
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
CustomTransitionPage<T> coolPageTransition<T>({
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
          return coolPageTransition(
            context: context,
            state: state,
            child: QrScannerScreen(
              mode: mode,
              ticketScanningEnabled: ticketScanningEnabled,
            ),
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
                  child: const RayonHomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shopNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.shop,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const ClubShopScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _momoNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.momoTab,
                pageBuilder: (context, state) {
                  final authSnapshot = readAuthSnapshot();
                  final featureFlags = ref.read(featureFlagsStateProvider);
                  return NoTransitionPage(
                    key: state.pageKey,
                    child: KillSwitchGate(
                      enabled: featureFlags.isMomoEnabled(
                        isAdmin: authSnapshot.isAdmin,
                      ),
                      featureName: 'Mobile Money',
                      child: SecureScreenWrapper(
                        child: MomoScreen(launchUri: state.uri),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _servicesNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.services,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const ServicesHubScreen(), // Services Hub
                ),
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
                ],
              ),
            ],
          ),
        ],
      ),

      // ── Groups routes (extracted from shell) ──────────────────
      GoRoute(
        path: AppRoutes.groups,
        builder: (context, state) => const GroupsScreen(),
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

      // ── MoMo routes ───────────────────────────────────────────
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

      // ── BioPay routes (extracted) ─────────────────────────────
      ...biopayRoutes(
        readAuthSnapshot: () {
          final snap = readAuthSnapshot();
          return (isAdmin: snap.isAdmin);
        },
        readFeatureFlags: () => ref.read(featureFlagsStateProvider),
        coolPageTransition: coolPageTransition,
      ),

      // ── Partner + Rayon routes (extracted) ─────────────────────
      partnerRoutes(
        readAuthSnapshot: () {
          final snap = readAuthSnapshot();
          return (isAdmin: snap.isAdmin, hasSession: snap.session != null);
        },
        readFeatureFlags: () => ref.read(featureFlagsStateProvider),
      ),

      // ── Status / engagement routes ────────────────────────────
      GoRoute(
        path: AppRoutes.missions,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const MissionsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.tokens,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const CoolTokensScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.referral,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const ReferralHubScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.seasons,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const SeasonsActivitiesScreen(),
        ),
      ),

      // ── Admin routes (extracted) ──────────────────────────────
      adminRoutes(),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _AppRouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
