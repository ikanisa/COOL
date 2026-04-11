import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/providers/auth_provider.dart';
import 'app_redirects.dart';

import '../../features/groups/screens/group_create_screen.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/groups/screens/group_settings_screen.dart';
import '../../features/groups/screens/group_statements_screen.dart';
import '../../features/groups/screens/groups_screen.dart';
import '../../features/momo/screens/momo_wallet_screen.dart';
import '../../shared/widgets/qr_scanner_screen.dart';

import '../../shared/widgets/secure_screen_wrapper.dart';
import '../../features/admin/models/admin_workspace_access.dart';
import '../../features/admin/providers/admin_workspace_access_provider.dart';
import '../providers/engagement_providers.dart';
import 'admin_routes.dart';
import 'app_router_refresh_notifier.dart';
import 'app_shell_branches.dart';
import 'cool_page_transition.dart';
import 'navigation_keys.dart';
import 'page_title_observer.dart';
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
  final notifier = AppRouterRefreshNotifier();
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
    initialLocation: AppRoutes.home,
    refreshListenable: refreshListenable,
    observers: [PageTitleObserver()],
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
      GoRoute(path: '/', redirect: (context, state) => AppRoutes.home),

      // ── QR Scanner (full-screen, no shell) ─────────────────────
      GoRoute(
        path: AppRoutes.scanner,
        pageBuilder: (context, state) {
          return coolPageTransition(
            context: context,
            state: state,
            child: const QrScannerScreen(mode: QrScanMode.momo),
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
          buildHomeShellBranch(navigatorKey: _homeNavigatorKey),
          buildBiopayShellBranch(
            navigatorKey: _biopayNavigatorKey,
            coolPageTransition: coolPageTransition,
            readIsBiopayEnabled: () {
              final authSnapshot = readAuthSnapshot();
              final featureFlags = ref.read(featureFlagsStateProvider);
              return featureFlags.isBiopayEnabled(
                isAdmin: authSnapshot.isAdmin,
              );
            },
          ),
          buildProfileShellBranch(navigatorKey: _profileNavigatorKey),
        ],
      ),

      // ── MoMo legacy redirect ─────────────────────────────────────
      GoRoute(
        path: AppRoutes.momo,
        redirect: (context, state) => AppRoutes.biopayHome,
      ),
      GoRoute(
        path: AppRoutes.momoWallet,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const SecureScreenWrapper(child: MomoWalletScreen()),
        ),
      ),

      // ── Group savings & contribution routes ────────────────────
      GoRoute(
        path: AppRoutes.groups,
        redirect: (context, state) {
          return Uri(
            path: AppRoutes.contributionCircles,
            queryParameters: state.uri.queryParameters.isEmpty
                ? null
                : state.uri.queryParameters,
          ).toString();
        },
      ),
      GoRoute(
        path: AppRoutes.groupCreate,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const SecureScreenWrapper(child: GroupCreateScreen()),
        ),
      ),
      GoRoute(
        path: AppRoutes.groupDetail,
        redirect: (context, state) {
          final groupId = state.pathParameters['id']?.trim();
          if (groupId == null || groupId.isEmpty) {
            return AppRoutes.contributionCircles;
          }
          return AppRoutes.contributionCircleDetailLocation(groupId);
        },
      ),
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
          child: SecureScreenWrapper(
            child: GroupsScreen(
              inviteCode: state.uri.queryParameters['invite_code'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.contributionCircleDetail,
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId']?.trim() ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: SecureScreenWrapper(
              child: GroupDetailScreen(groupId: groupId),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.contributionCircleSettings,
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId']?.trim() ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: SecureScreenWrapper(
              child: GroupSettingsScreen(groupId: groupId),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.contributionCircleStatements,
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId']?.trim() ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: SecureScreenWrapper(
              child: GroupStatementsScreen(groupId: groupId),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.groupLedger,
        redirect: (context, state) {
          final groupId = state.pathParameters['id']?.trim();
          if (groupId == null || groupId.isEmpty) {
            return AppRoutes.contributionCircles;
          }
          return AppRoutes.contributionCircleDetailLocation(groupId);
        },
      ),

      adminRoutes(),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
