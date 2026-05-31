import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/collect_shell.dart';
import '../features/admin/admin_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/collections/collection_create_screen.dart';
import '../features/collections/collection_detail_screen.dart';
import '../features/collections/collection_manage_screen.dart';
import '../features/collections/collections_screen.dart';
import '../features/collections/group_link_screen.dart';
import '../features/collections/invite_screen.dart';
import '../features/collections/share_screen.dart';
import '../features/dev/design_system_catalog_screen.dart';
import '../features/home/home_screen.dart';
import '../features/ledger/ledger_screen.dart';
import '../features/payments/contribution_flow_screen.dart';
import '../features/payments/payment_intent_status_screen.dart';
import '../features/profile/profile_setup_screen.dart';
import '../features/settings/settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) => createAppRouter());

const collectRoutePaths = <String>[
  '/auth',
  '/home',
  '/groups',
  '/groups/create',
  '/groups/:collectionId',
  '/groups/:collectionId/manage',
  '/groups/:collectionId/contribute',
  '/groups/:collectionId/pay/:intentId',
  '/groups/:collectionId/share',
  '/groups/:collectionId/invite',
  '/groups/:collectionId/ledger',
  '/c/:slug',
  '/profile/setup',
  '/settings',
  '/admin',
  if (kDebugMode) '/dev/design-system',
];

GoRouter createAppRouter({String initialLocation = '/home'}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      if (state.uri.path == '/') {
        return '/home';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => CollectShell(child: child),
        routes: [
          GoRoute(
            path: '/auth',
            builder: (context, state) => const AuthScreen(),
          ),
          GoRoute(
            path: '/profile/setup',
            builder: (context, state) => const ProfileSetupScreen(),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/groups',
            builder: (context, state) => const CollectionsScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (context, state) => const CollectionCreateScreen(),
              ),
              GoRoute(
                path: ':collectionId',
                builder: (context, state) => CollectionDetailScreen(
                  collectionId: state.pathParameters['collectionId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'manage',
                    builder: (context, state) => CollectionManageScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'contribute',
                    builder: (context, state) => ContributionFlowScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'pay/:intentId',
                    builder: (context, state) => PaymentIntentStatusScreen(
                      collectionId: state.pathParameters['collectionId']!,
                      intentId: state.pathParameters['intentId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'share',
                    builder: (context, state) => ShareScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'invite',
                    builder: (context, state) => InviteScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'ledger',
                    builder: (context, state) => LedgerScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/c/:slug',
            builder: (context, state) =>
                GroupLinkScreen(slug: state.pathParameters['slug']!),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminScreen(),
          ),
          if (kDebugMode)
            GoRoute(
              path: '/dev/design-system',
              builder: (context, state) => const DesignSystemCatalogScreen(),
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const _RouteNotFoundScreen(),
  );
}

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Route not found')));
  }
}
