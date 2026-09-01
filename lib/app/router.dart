import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/collect_shell.dart';
import '../features/activity/activity_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/collections/collection_create_screen.dart';
import '../features/collections/collection_detail_screen.dart';
import '../features/collections/collection_manage_screen.dart';
import '../features/collections/collections_screen.dart';
import '../features/collections/group_creation_platform.dart';
import '../features/collections/group_profile_screen.dart';
import '../features/collections/group_link_screen.dart';
import '../features/collections/group_qr_scanner_screen.dart';
import '../features/collections/share_screen.dart';
import '../features/home/home_screen.dart';
import '../features/launch/launch_splash_screen.dart';
import '../features/ledger/ledger_screen.dart';
import '../features/payments/contribution_flow_screen.dart';
import '../features/payments/contribute_entry_screen.dart';
import '../features/profile/profile_edit_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/app_permissions_screen.dart';
import '../features/settings/bank_transfer_settings_screen.dart';
import '../features/settings/settings_subscreens.dart';
import '../features/status/production_state_screens.dart';
import '../shared/repositories/collect_repository.dart';
import '../shared/widgets/collect_components.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _CollectRouterRefresh();
  ref.onDispose(refresh.dispose);
  ref.listen(
    collectRepositoryProvider.select(
      (state) => (state.currentProfile != null, state.isLoading),
    ),
    (_, _) => refresh.notify(),
  );

  return createAppRouter(
    refreshListenable: refresh,
    routeRedirect: (state) {
      final collectState = ref.read(collectRepositoryProvider);
      return collectAuthenticationRedirect(
        uri: state.uri,
        hasProfile: collectState.currentProfile != null,
        isLoading: collectState.isLoading,
      );
    },
  );
});

const collectRoutePaths = <String>[
  '/',
  '/auth',
  '/home',
  '/offline',
  '/sync',
  '/groups',
  '/groups/scan',
  '/groups/create',
  '/groups/:collectionId',
  '/groups/:collectionId/members',
  '/groups/:collectionId/manage',
  '/groups/:collectionId/profile',
  '/groups/:collectionId/contribute',
  '/groups/:collectionId/share',
  '/groups/:collectionId/invite',
  '/groups/:collectionId/ledger',
  '/contribute',
  '/activity',
  '/c/:slug',
  '/share/invalid',
  '/share/expired',
  '/share/expired/request',
  '/app',
  '/invite/:publicId',
  '/settings',
  '/settings/profile',
  '/settings/notifications',
  '/settings/bank-transfer',
  '/settings/permissions',
  '/settings/appearance',
  '/settings/security',
  '/settings/account',
  '/settings/account/delete',
  '/settings/privacy',
  '/settings/help',
  '/settings/legal/terms',
  '/settings/legal/privacy',
];

GoRouter createAppRouter({
  String initialLocation = '/',
  Listenable? refreshListenable,
  String? Function(GoRouterState state)? routeRedirect,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: routeRedirect == null
        ? null
        : (context, state) => routeRedirect(state),
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _collectPage(
          context,
          state,
          const LaunchSplashScreen(),
          transition: _CollectRouteTransition.fade,
        ),
      ),
      GoRoute(
        path: '/auth',
        pageBuilder: (context, state) => _collectPage(
          context,
          state,
          const AuthScreen(),
          // Authentication is an entry surface, not a pushed detail page.
          // A fade also keeps direct /auth launches visibly painted on iOS;
          // Cupertino's initial push transition can otherwise retain an
          // empty first frame in native screenshot and cold-start evidence.
          transition: _CollectRouteTransition.fade,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            CollectShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            initialLocation: '/home',
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) => _collectPage(
                  context,
                  state,
                  const HomeScreen(),
                  transition: _CollectRouteTransition.primary,
                ),
              ),
              GoRoute(
                path: '/offline',
                pageBuilder: (context, state) => _collectPage(
                  context,
                  state,
                  const OfflineRecoveryScreen(),
                  transition: _CollectRouteTransition.utility,
                ),
              ),
              GoRoute(
                path: '/sync',
                pageBuilder: (context, state) => _collectPage(
                  context,
                  state,
                  const SyncRecoveryScreen(),
                  transition: _CollectRouteTransition.utility,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            initialLocation: '/groups',
            routes: [
              GoRoute(
                path: '/groups',
                pageBuilder: (context, state) => _collectPage(
                  context,
                  state,
                  const CollectionsScreen(),
                  transition: _CollectRouteTransition.primary,
                ),
                routes: [
                  GoRoute(
                    path: 'join',
                    redirect: (context, state) => '/groups/scan',
                  ),
                  GoRoute(
                    path: 'scan',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const GroupQrScannerScreen(),
                      transition: _CollectRouteTransition.modal,
                    ),
                  ),
                  GoRoute(
                    path: 'create',
                    redirect: (context, state) =>
                        canCreateGroupsOnThisPlatform() ? null : '/groups',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const CollectionCreateScreen(),
                      transition: _CollectRouteTransition.modal,
                    ),
                  ),
                  GoRoute(
                    path: ':collectionId',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      CollectionDetailScreen(
                        collectionId: state.pathParameters['collectionId']!,
                      ),
                      transition: _CollectRouteTransition.detail,
                    ),
                    routes: [
                      GoRoute(
                        path: 'members',
                        pageBuilder: (context, state) => _collectPage(
                          context,
                          state,
                          GroupMembersScreen(
                            collectionId: state.pathParameters['collectionId']!,
                          ),
                          transition: _CollectRouteTransition.detail,
                        ),
                      ),
                      GoRoute(
                        path: 'manage',
                        pageBuilder: (context, state) => _collectPage(
                          context,
                          state,
                          CollectionManageScreen(
                            collectionId: state.pathParameters['collectionId']!,
                          ),
                          transition: _CollectRouteTransition.detail,
                        ),
                      ),
                      GoRoute(
                        path: 'profile',
                        pageBuilder: (context, state) => _collectPage(
                          context,
                          state,
                          GroupProfileScreen(
                            collectionId: state.pathParameters['collectionId']!,
                          ),
                          transition: _CollectRouteTransition.detail,
                        ),
                      ),
                      GoRoute(
                        path: 'contribute',
                        pageBuilder: (context, state) => _collectPage(
                          context,
                          state,
                          ContributionFlowScreen(
                            collectionId: state.pathParameters['collectionId']!,
                          ),
                          transition: _CollectRouteTransition.modal,
                        ),
                      ),
                      GoRoute(
                        path: 'share',
                        pageBuilder: (context, state) => _collectPage(
                          context,
                          state,
                          ShareScreen(
                            collectionId: state.pathParameters['collectionId']!,
                          ),
                          transition: _CollectRouteTransition.modal,
                        ),
                      ),
                      GoRoute(
                        path: 'invite',
                        redirect: (context, state) =>
                            '/groups/${state.pathParameters['collectionId']}/share',
                      ),
                      GoRoute(
                        path: 'ledger',
                        pageBuilder: (context, state) => _collectPage(
                          context,
                          state,
                          LedgerScreen(
                            collectionId: state.pathParameters['collectionId']!,
                          ),
                          transition: _CollectRouteTransition.detail,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            initialLocation: '/contribute',
            routes: [
              GoRoute(
                path: '/contribute',
                pageBuilder: (context, state) => _collectPage(
                  context,
                  state,
                  const ContributeEntryScreen(),
                  transition: _CollectRouteTransition.primary,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            initialLocation: '/activity',
            routes: [
              GoRoute(
                path: '/activity',
                pageBuilder: (context, state) => _collectPage(
                  context,
                  state,
                  const ActivityScreen(),
                  transition: _CollectRouteTransition.primary,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            initialLocation: '/settings',
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => _collectPage(
                  context,
                  state,
                  const SettingsScreen(),
                  transition: _CollectRouteTransition.primary,
                ),
                routes: [
                  GoRoute(
                    path: 'profile',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const ProfileEditScreen(),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'account',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const AccountSessionScreen(),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'notifications',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const NotificationSettingsScreen(),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'bank-transfer',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const BankTransferSettingsScreen(),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'permissions',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const AppPermissionsScreen(),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'appearance',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const AppearanceSettingsScreen(),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'security',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const SecuritySettingsScreen(),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'account/delete',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const DeleteAccountRequestScreen(),
                      transition: _CollectRouteTransition.modal,
                    ),
                  ),
                  GoRoute(
                    path: 'privacy',
                    redirect: (context, state) => '/settings/legal/privacy',
                  ),
                  GoRoute(
                    path: 'help',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const HelpSettingsScreen(),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'legal/terms',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const LegalScreen(kind: 'terms'),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                  GoRoute(
                    path: 'legal/privacy',
                    pageBuilder: (context, state) => _collectPage(
                      context,
                      state,
                      const LegalScreen(kind: 'privacy'),
                      transition: _CollectRouteTransition.detail,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/app', redirect: (context, state) => '/home'),
      GoRoute(path: '/invite/:publicId', redirect: (context, state) => '/home'),
      GoRoute(path: '/share/invalid', redirect: (context, state) => '/groups'),
      GoRoute(path: '/share/expired', redirect: (context, state) => '/groups'),
      GoRoute(
        path: '/share/expired/request',
        redirect: (context, state) => '/groups',
      ),
      GoRoute(
        path: '/c/:slug',
        pageBuilder: (context, state) => _collectPage(
          context,
          state,
          GroupLinkScreen(slug: state.pathParameters['slug']!),
          transition: _CollectRouteTransition.detail,
        ),
      ),
    ],
    errorBuilder: (context, state) => const _RouteNotFoundScreen(),
  );
}

String? collectAuthenticationRedirect({
  required Uri uri,
  required bool hasProfile,
  required bool isLoading,
}) {
  final isHeldSplash =
      uri.path == '/' && uri.queryParameters['holdSplash'] == '1';

  if (isLoading) {
    if (isHeldSplash) return null;
    return Uri(
      path: '/',
      queryParameters: {'holdSplash': '1', 'next': uri.toString()},
    ).toString();
  }

  if (isHeldSplash) {
    final next = _safeInternalRoute(uri.queryParameters['next']);
    if (hasProfile) return next?.toString() ?? '/home';
    if (next != null && _isPublicUnauthenticatedPath(next.path)) {
      return next.toString();
    }
    return '/auth';
  }

  if (hasProfile) {
    if (uri.path == '/' || uri.path == '/auth') return '/home';
    return null;
  }

  if (uri.path == '/') return '/auth';
  if (!_isPublicUnauthenticatedPath(uri.path)) return '/auth';
  return null;
}

bool _isPublicUnauthenticatedPath(String path) {
  return path == '/' || path == '/auth' || path.startsWith('/c/');
}

Uri? _safeInternalRoute(String? rawRoute) {
  if (rawRoute == null || rawRoute.isEmpty) return null;
  final route = Uri.tryParse(rawRoute);
  if (route == null ||
      route.hasScheme ||
      route.hasAuthority ||
      !route.path.startsWith('/') ||
      route.path.startsWith('//') ||
      route.path == '/') {
    return null;
  }
  return route;
}

class _CollectRouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

enum _CollectRouteTransition {
  fade,
  primary,
  forward,
  detail,
  modal,
  utility,
  confirmation,
}

Page<void> _collectPage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  _CollectRouteTransition transition = _CollectRouteTransition.detail,
}) {
  final duration = CollectMotion.duration(context, switch (transition) {
    _CollectRouteTransition.utility => CollectMotion.fast,
    _CollectRouteTransition.confirmation => CollectMotion.slow,
    _ => CollectMotion.medium,
  });
  final platform = Theme.of(context).platform;
  final usesNativeIosNavigation =
      platform == TargetPlatform.iOS &&
      transition != _CollectRouteTransition.fade &&
      transition != _CollectRouteTransition.primary;
  if (usesNativeIosNavigation) {
    return CupertinoPage<void>(
      key: state.pageKey,
      name: state.name,
      arguments: state.extra,
      fullscreenDialog: transition == _CollectRouteTransition.modal,
      child: child,
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.name,
    arguments: state.extra,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
        return child;
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: CollectMotion.standard,
        reverseCurve: Curves.easeInCubic,
      );
      return switch (transition) {
        _CollectRouteTransition.fade => FadeTransition(
          opacity: curved,
          child: child,
        ),
        _CollectRouteTransition.primary => FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        ),
        _CollectRouteTransition.forward ||
        _CollectRouteTransition.detail => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.035, 0.012),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        ),
        _CollectRouteTransition.modal => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        ),
        _CollectRouteTransition.utility => FadeTransition(
          opacity: curved,
          child: child,
        ),
        _CollectRouteTransition.confirmation => ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        ),
      };
    },
  );
}

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return ScreenScaffoldLayout(
      title: 'Screen not found',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.warning,
          title: 'This screen is unavailable.',
          message:
              'Return to Groups or Home without exposing bank information.',
          tone: CollectStatusTone.warning,
        ),
        CollectButton(
          label: 'Home',
          icon: CollectIcons.home,
          onPressed: () => context.go('/home'),
          expand: true,
        ),
        CollectButton(
          label: 'Groups',
          icon: CollectIcons.collections,
          variant: CollectButtonVariant.secondary,
          onPressed: () => context.go('/groups'),
          expand: true,
        ),
      ],
    );
  }
}
