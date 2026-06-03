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
import '../features/status/production_state_screens.dart';
import '../shared/providers/collect_app_state.dart';
import '../shared/widgets/collect_components.dart';

final appRouterProvider = Provider<GoRouter>((ref) => createAppRouter());

const collectRoutePaths = <String>[
  '/auth',
  '/auth/success',
  '/auth/failure',
  '/onboarding',
  '/home',
  '/offline',
  '/sync',
  '/notifications',
  '/permissions/sms',
  '/permissions/sms-denied',
  '/permissions/device',
  '/platform/iphone-create-unavailable',
  '/groups',
  '/groups/join',
  '/groups/create',
  '/groups/:collectionId',
  '/groups/:collectionId/created',
  '/groups/:collectionId/joined',
  '/groups/:collectionId/members',
  '/groups/:collectionId/owner',
  '/groups/:collectionId/owner/sms-health',
  '/groups/:collectionId/owner/receiver',
  '/groups/:collectionId/manage',
  '/groups/:collectionId/contribute',
  '/groups/:collectionId/pay/:intentId/waiting',
  '/groups/:collectionId/pay/:intentId/state/:state',
  '/groups/:collectionId/pay/:intentId',
  '/groups/:collectionId/share',
  '/groups/:collectionId/invite',
  '/groups/:collectionId/ledger',
  '/c/:slug',
  '/share/invalid',
  '/share/expired',
  '/settings',
  '/settings/profile',
  '/settings/readiness',
  '/settings/account',
  '/settings/account/delete',
  '/settings/privacy',
  '/settings/help',
  '/settings/legal/terms',
  '/settings/legal/privacy',
  '/share/confirmed',
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
            path: '/onboarding',
            builder: (context, state) => const OnboardingScreen(),
          ),
          GoRoute(
            path: '/auth',
            builder: (context, state) => const AuthScreen(),
          ),
          GoRoute(
            path: '/auth/success',
            builder: (context, state) => const AuthResultScreen(success: true),
          ),
          GoRoute(
            path: '/auth/failure',
            builder: (context, state) => const AuthResultScreen(success: false),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/offline',
            builder: (context, state) => const OfflineStateScreen(),
          ),
          GoRoute(
            path: '/sync',
            builder: (context, state) => const SyncStatusScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationCenterScreen(),
          ),
          GoRoute(
            path: '/permissions/sms',
            builder: (context, state) => const SmsPermissionEducationScreen(),
          ),
          GoRoute(
            path: '/permissions/sms-denied',
            builder: (context, state) => const SmsPermissionDeniedScreen(),
          ),
          GoRoute(
            path: '/permissions/device',
            builder: (context, state) => const NotificationPermissionScreen(),
          ),
          GoRoute(
            path: '/platform/iphone-create-unavailable',
            builder: (context, state) => const IphoneCreateUnavailableScreen(),
          ),
          GoRoute(
            path: '/groups',
            builder: (context, state) => const CollectionsScreen(),
            routes: [
              GoRoute(
                path: 'join',
                builder: (context, state) => const JoinGroupPortalScreen(),
              ),
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
                    path: 'created',
                    builder: (context, state) => GroupCreatedSuccessScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'joined',
                    builder: (context, state) => JoinGroupConfirmationScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'members',
                    builder: (context, state) => GroupMembersScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'owner',
                    builder: (context, state) => GroupOwnerDashboardScreen(
                      collectionId: state.pathParameters['collectionId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'sms-health',
                        builder: (context, state) => OwnerSmsHealthScreen(
                          collectionId: state.pathParameters['collectionId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'receiver',
                        builder: (context, state) =>
                            OwnerReceiverManagementScreen(
                              collectionId:
                                  state.pathParameters['collectionId']!,
                            ),
                      ),
                    ],
                  ),
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
                    path: 'pay/:intentId/handoff',
                    redirect: (context, state) =>
                        '/groups/${state.pathParameters['collectionId']}/pay/${state.pathParameters['intentId']}/waiting',
                  ),
                  GoRoute(
                    path: 'pay/:intentId/waiting',
                    builder: (context, state) => ReturnFromMomoWaitingScreen(
                      collectionId: state.pathParameters['collectionId']!,
                      intentId: state.pathParameters['intentId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'pay/:intentId/state/:state',
                    builder: (context, state) => PaymentStateDetailScreen(
                      collectionId: state.pathParameters['collectionId']!,
                      intentId: state.pathParameters['intentId']!,
                      state: _paymentStateFromPath(
                        state.pathParameters['state'],
                      ),
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
            path: '/share/invalid',
            builder: (context, state) =>
                const SharedLinkProblemScreen(expired: false),
          ),
          GoRoute(
            path: '/share/expired',
            builder: (context, state) =>
                const SharedLinkProblemScreen(expired: true),
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
            path: '/settings/profile',
            builder: (context, state) => const ProfileSetupScreen(),
          ),
          GoRoute(
            path: '/settings/readiness',
            builder: (context, state) => const ProfileReadinessScreen(),
          ),
          GoRoute(
            path: '/settings/account',
            builder: (context, state) => const AccountSessionScreen(),
          ),
          GoRoute(
            path: '/settings/account/delete',
            builder: (context, state) => const DeleteAccountRequestScreen(),
          ),
          GoRoute(
            path: '/settings/privacy',
            builder: (context, state) => const PrivacyDataScreen(),
          ),
          GoRoute(
            path: '/settings/help',
            builder: (context, state) => const HelpSupportScreen(),
          ),
          GoRoute(
            path: '/settings/legal/terms',
            builder: (context, state) => const LegalScreen(kind: 'terms'),
          ),
          GoRoute(
            path: '/settings/legal/privacy',
            builder: (context, state) => const LegalScreen(kind: 'privacy'),
          ),
          GoRoute(
            path: '/share/confirmed',
            builder: (context, state) => ShareConfirmationScreen(
              message: state.uri.queryParameters['message'] ?? 'Link copied.',
            ),
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

PaymentUiStatus _paymentStateFromPath(String? value) {
  return switch (value) {
    'confirmed' => PaymentUiStatus.confirmed,
    'expired' => PaymentUiStatus.expired,
    'needs-review' => PaymentUiStatus.needsReview,
    _ => PaymentUiStatus.pending,
  };
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
              'Return to verified groups or the home overview without exposing receiver MoMo details.',
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
