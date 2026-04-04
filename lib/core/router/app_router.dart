import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import 'app_redirects.dart';

import '../../features/home/screens/home_screen.dart';
import '../../features/biopay/models/biopay_enrollment_draft.dart';
import '../../features/biopay/screens/biopay_home_screen.dart';
import '../../features/biopay/screens/biopay_nfc_screen.dart';
import '../../features/biopay/screens/biopay_register_screen.dart';
import '../../features/biopay/screens/biopay_scan_screen.dart';
import '../../features/momo/screens/momo_screen.dart';
import '../../features/momo/screens/momo_statements_screen.dart';
import '../../features/groups/screens/groups_screen.dart';
import '../../features/profile/screens/profile_detail_screens.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/profile_sub_screens.dart';
import '../../shared/widgets/qr_scanner_screen.dart';
import '../../shared/widgets/kill_switch_gate.dart';
import '../../shared/widgets/secure_screen_wrapper.dart';
import '../../features/admin/models/admin_workspace_access.dart';
import '../../features/admin/providers/admin_workspace_access_provider.dart';
import '../providers/engagement_providers.dart';
import 'admin_routes.dart';
import 'navigation_keys.dart';
import 'shell_route.dart';

export 'app_redirects.dart';
export 'app_routes.dart';

final _homeNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'homeNavigator',
);
final _biopayNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'biopayNavigator',
);
final _profileNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'profileNavigator',
);

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
  })
  readAuthSnapshot() {
    final state = ref.read(authProvider);
    final adminAccess = ref.read(adminWorkspaceAccessProvider);
    return (
      session: state.session,
      hasProfile: state.user?.isProfileComplete ?? false,
      isAdmin: state.user?.isAdmin ?? false,
      profileRestoreState: state.profileRestoreState,
      adminAccess: adminAccess,
    );
  }

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refreshListenable,
    observers: [_PageTitleObserver()],
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

        sessionPhone: null,
        pendingRedirect: state.uri.queryParameters['redirect'],
      );
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),

      // ── QR Scanner (full-screen, no shell) ─────────────────────
      GoRoute(
        path: AppRoutes.scanner,
        pageBuilder: (context, state) {
          final authSnapshot = readAuthSnapshot();
          final modeStr = state.uri.queryParameters['mode'] ?? 'ticket';
          final mode = modeStr == 'momo' ? QrScanMode.momo : QrScanMode.ticket;
          final ticketScanningEnabled = authSnapshot.isAdmin;
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
                  child: const HomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _biopayNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.biopayHome,
                pageBuilder: (context, state) {
                  final authSnapshot = readAuthSnapshot();
                  final featureFlags = ref.read(featureFlagsStateProvider);
                  return NoTransitionPage(
                    key: state.pageKey,
                    child: KillSwitchGate(
                      enabled: featureFlags.isBiopayEnabled(
                        isAdmin: authSnapshot.isAdmin,
                      ),
                      featureName: 'BioPay',
                      child: const SecureScreenWrapper(
                        child: BiopayHomeScreen(),
                      ),
                    ),
                  );
                },
                routes: [
                  GoRoute(
                    path: 'register',
                    pageBuilder: (context, state) {
                      final authSnapshot = readAuthSnapshot();
                      final featureFlags = ref.read(featureFlagsStateProvider);
                      return coolPageTransition(
                        context: context,
                        state: state,
                        child: KillSwitchGate(
                          enabled: featureFlags.isBiopayEnabled(
                            isAdmin: authSnapshot.isAdmin,
                          ),
                          featureName: 'BioPay',
                          child: const SecureScreenWrapper(
                            child: BiopayRegisterScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'scan',
                    pageBuilder: (context, state) {
                      final authSnapshot = readAuthSnapshot();
                      final featureFlags = ref.read(featureFlagsStateProvider);
                      final modeParam = state.uri.queryParameters['mode']
                          ?.trim();
                      final mode = modeParam == 'enroll'
                          ? BiopayScanMode.enroll
                          : BiopayScanMode.pay;
                      final draft = state.extra is BiopayEnrollmentDraft
                          ? state.extra! as BiopayEnrollmentDraft
                          : null;
                      return coolPageTransition(
                        context: context,
                        state: state,
                        child: KillSwitchGate(
                          enabled: featureFlags.isBiopayEnabled(
                            isAdmin: authSnapshot.isAdmin,
                          ),
                          featureName: 'BioPay',
                          child: SecureScreenWrapper(
                            child: BiopayScanScreen(
                              mode: mode,
                              enrollmentDraft: draft,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'nfc',
                    pageBuilder: (context, state) {
                      final authSnapshot = readAuthSnapshot();
                      final featureFlags = ref.read(featureFlagsStateProvider);
                      return coolPageTransition(
                        context: context,
                        state: state,
                        child: KillSwitchGate(
                          enabled: featureFlags.isBiopayEnabled(
                            isAdmin: authSnapshot.isAdmin,
                          ),
                          featureName: 'BioPay',
                          child: const SecureScreenWrapper(
                            child: BiopayNfcScreen(),
                          ),
                        ),
                      );
                    },
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
                    builder: (context, state) => ProfileWalletScreen(
                      redirectLocation: state.uri.queryParameters['redirect'],
                    ),
                  ),
                  GoRoute(
                    path: 'account',
                    builder: (context, state) => const AccountDetailsScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (context, state) =>
                        const NotificationsSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'privacy',
                    builder: (context, state) => const PrivacySecurityScreen(),
                  ),
                  GoRoute(
                    path: 'orders',
                    builder: (context, state) => const OrderHistoryScreen(),
                  ),
                  GoRoute(
                    path: 'help',
                    builder: (context, state) => const HelpCenterScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutAppScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // ── MoMo routes ───────────────────────────────────────────
      GoRoute(
        path: AppRoutes.momo,
        redirect: (context, state) {
          if (_hasIncomingMomoLaunch(state.uri)) {
            return null;
          }
          return AppRoutes.biopayHome;
        },
        builder: (context, state) {
          final authSnapshot = readAuthSnapshot();
          final featureFlags = ref.read(featureFlagsStateProvider);
          return KillSwitchGate(
            enabled: featureFlags.isMomoEnabled(isAdmin: authSnapshot.isAdmin),
            featureName: 'Payments',
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
            featureName: 'Payments',
            child: const SecureScreenWrapper(child: MomoStatementsScreen()),
          );
        },
      ),

      // ── Group savings & contribution routes ────────────────────
      GoRoute(
        path: AppRoutes.groupInvite,
        redirect: (context, state) {
          final inviteCode = state.pathParameters['code']?.trim().toUpperCase();
          if (inviteCode == null || inviteCode.isEmpty) {
            return AppRoutes.contributionCircles;
          }
          return Uri(
            path: AppRoutes.contributionCircles,
            queryParameters: <String, String>{'invite_code': inviteCode},
          ).toString();
        },
      ),
      GoRoute(
        path: AppRoutes.contributionCircles,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const GroupsScreen(),
        ),
      ),
      adminRoutes(),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

bool _hasIncomingMomoLaunch(Uri uri) {
  const incomingKeys = <String>{
    'action',
    'recipient',
    'amount',
    'recipient_type',
    'country',
    'reference',
  };
  return uri.queryParameters.keys.any(incomingKeys.contains);
}

class _AppRouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// Sets the browser tab title based on the current route.
///
/// Only active on Flutter Web — native platforms use the OS task switcher
/// which already shows the app name.
class _PageTitleObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateTitle(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _updateTitle(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _updateTitle(previousRoute);
  }

  void _updateTitle(Route<dynamic> route) {
    if (!kIsWeb) return;

    final name = route.settings.name;
    final title = _routeTitleFor(name);
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(label: title, primaryColor: 0xFF0D0A27),
    );
  }
}

/// Maps route paths to human-readable page titles for the browser tab.
String _routeTitleFor(String? path) {
  if (path == null || path.isEmpty || path == '/') return 'COOL';

  final basePath = path.split('?').first;

  // Static routes
  const titles = <String, String>{
    '/home': 'Home — COOL',
    '/groups': 'Groups — COOL',
    '/contribution-circles': 'Contribution Circles — COOL',
    '/momo': 'MoMo — COOL',
    '/momo/statements': 'MoMo Statements — COOL',
    '/momo/biopay': 'BioPay — COOL',
    '/momo/biopay/register': 'BioPay Register — COOL',
    '/momo/biopay/scan': 'BioPay Scan — COOL',
    '/momo/biopay/nfc': 'BioPay NFC — COOL',
    '/profile': 'Profile — COOL',
    '/profile/wallet': 'Wallet — COOL',
    '/profile/account': 'Account — COOL',
    '/profile/notifications': 'Notifications — COOL',
    '/profile/privacy': 'Privacy & Security — COOL',
    '/profile/orders': 'Orders — COOL',
    '/profile/help': 'Help — COOL',
    '/profile/about': 'About — COOL',
    '/admin': 'Admin — COOL',
    '/admin/platform': 'Platform — COOL Admin',
    '/admin/users': 'Users — COOL Admin',
    '/admin/app-config': 'App Config — COOL Admin',
    '/admin/operations': 'Operations — COOL Admin',
    '/admin/roles': 'Roles — COOL Admin',
    '/admin/analytics': 'Analytics — COOL Admin',
    '/admin/audit-log': 'Audit Log — COOL Admin',
    '/scanner': 'Scanner — COOL',
  };

  final exact = titles[basePath];
  if (exact != null) return exact;

  // Dynamic routes (pattern match)
  if (basePath.startsWith('/contribution-circles/')) {
    return 'Group Details — COOL';
  }
  if (basePath.startsWith('/invite/')) {
    return 'Invitation — COOL';
  }
  if (basePath.startsWith('/admin/banks/')) {
    return 'Bank Workspace — COOL Admin';
  }

  return 'COOL';
}
