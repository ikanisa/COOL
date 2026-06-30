import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/collect_shell.dart';
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
import '../features/dev/design_system_catalog_screen.dart';
import '../features/home/home_screen.dart';
import '../features/launch/launch_splash_screen.dart';
import '../features/ledger/ledger_screen.dart';
import '../features/payments/contribution_flow_screen.dart';
import '../features/profile/profile_setup_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/status/production_state_screens.dart';
import '../shared/widgets/collect_components.dart';

final appRouterProvider = Provider<GoRouter>((ref) => createAppRouter());

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
  '/c/:slug',
  '/share/invalid',
  '/share/expired',
  '/share/expired/request',
  '/app',
  '/invite/:publicId',
  '/settings',
  '/settings/profile',
  '/settings/account',
  '/settings/account/delete',
  '/settings/privacy',
  '/settings/help',
  '/settings/legal/terms',
  '/settings/legal/privacy',
  if (kDebugMode) '/dev/design-system',
];

GoRouter createAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => CollectShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => _collectPage(
              state,
              const LaunchSplashScreen(),
              transition: _CollectRouteTransition.fade,
            ),
          ),
          GoRoute(
            path: '/auth',
            pageBuilder: (context, state) => _collectPage(
              state,
              const AuthScreen(),
              transition: _CollectRouteTransition.forward,
            ),
          ),
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _collectPage(
              state,
              const HomeScreen(),
              transition: _CollectRouteTransition.primary,
            ),
          ),
          GoRoute(
            path: '/offline',
            pageBuilder: (context, state) => _collectPage(
              state,
              const OfflineStateScreen(),
              transition: _CollectRouteTransition.utility,
            ),
          ),
          GoRoute(
            path: '/sync',
            pageBuilder: (context, state) => _collectPage(
              state,
              const SyncStatusScreen(),
              transition: _CollectRouteTransition.utility,
            ),
          ),
          GoRoute(
            path: '/groups',
            pageBuilder: (context, state) => _collectPage(
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
                  state,
                  const CollectionCreateScreen(),
                  transition: _CollectRouteTransition.modal,
                ),
              ),
              GoRoute(
                path: ':collectionId',
                pageBuilder: (context, state) => _collectPage(
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
          GoRoute(
            path: '/share/invalid',
            pageBuilder: (context, state) => _collectPage(
              state,
              const SharedLinkProblemScreen(expired: false),
              transition: _CollectRouteTransition.utility,
            ),
          ),
          GoRoute(
            path: '/share/expired',
            pageBuilder: (context, state) => _collectPage(
              state,
              const SharedLinkProblemScreen(expired: true),
              transition: _CollectRouteTransition.utility,
            ),
          ),
          GoRoute(
            path: '/share/expired/request',
            pageBuilder: (context, state) => _collectPage(
              state,
              FreshLinkRequestScreen(
                slug: state.uri.queryParameters['slug'] ?? '',
              ),
              transition: _CollectRouteTransition.modal,
            ),
          ),
          GoRoute(
            path: '/c/:slug',
            pageBuilder: (context, state) => _collectPage(
              state,
              GroupLinkScreen(slug: state.pathParameters['slug']!),
              transition: _CollectRouteTransition.detail,
            ),
          ),
          GoRoute(path: '/app', redirect: (context, state) => '/home'),
          GoRoute(
            path: '/invite/:publicId',
            redirect: (context, state) => '/home',
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _collectPage(
              state,
              const SettingsScreen(),
              transition: _CollectRouteTransition.primary,
            ),
          ),
          GoRoute(
            path: '/settings/profile',
            pageBuilder: (context, state) => _collectPage(
              state,
              const ProfileSetupScreen(),
              transition: _CollectRouteTransition.detail,
            ),
          ),
          GoRoute(
            path: '/settings/account',
            pageBuilder: (context, state) => _collectPage(
              state,
              const AccountSessionScreen(),
              transition: _CollectRouteTransition.detail,
            ),
          ),
          GoRoute(
            path: '/settings/account/delete',
            pageBuilder: (context, state) => _collectPage(
              state,
              const DeleteAccountRequestScreen(),
              transition: _CollectRouteTransition.modal,
            ),
          ),
          GoRoute(
            path: '/settings/privacy',
            pageBuilder: (context, state) => _collectPage(
              state,
              const PrivacyDataScreen(),
              transition: _CollectRouteTransition.detail,
            ),
          ),
          GoRoute(
            path: '/settings/help',
            pageBuilder: (context, state) => _collectPage(
              state,
              const HelpSupportScreen(),
              transition: _CollectRouteTransition.detail,
            ),
          ),
          GoRoute(
            path: '/settings/legal/terms',
            pageBuilder: (context, state) => _collectPage(
              state,
              const LegalScreen(kind: 'terms'),
              transition: _CollectRouteTransition.detail,
            ),
          ),
          GoRoute(
            path: '/settings/legal/privacy',
            pageBuilder: (context, state) => _collectPage(
              state,
              const LegalScreen(kind: 'privacy'),
              transition: _CollectRouteTransition.detail,
            ),
          ),
          if (kDebugMode)
            GoRoute(
              path: '/dev/design-system',
              pageBuilder: (context, state) => _collectPage(
                state,
                const DesignSystemCatalogScreen(),
                transition: _CollectRouteTransition.utility,
              ),
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const _RouteNotFoundScreen(),
  );
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
  GoRouterState state,
  Widget child, {
  _CollectRouteTransition transition = _CollectRouteTransition.detail,
}) {
  final duration = switch (transition) {
    _CollectRouteTransition.utility => CollectMotion.fast,
    _CollectRouteTransition.confirmation => CollectMotion.slow,
    _ => CollectMotion.medium,
  };
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
            begin: const Offset(0.08, 0),
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
              'Return to Groups or Home without exposing receiver information.',
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
