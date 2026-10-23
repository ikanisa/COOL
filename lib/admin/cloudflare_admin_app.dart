import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme/app_theme.dart';
import '../app/theme/collect_theme_controller.dart';
import 'core/cloudflare_admin_licenses_page.dart';
import 'core/cloudflare_admin_momo_page.dart';
import 'admin_shell.dart';
import 'shared/admin_theme.dart';
import 'core/admin_account_api.dart';
import 'core/admin_account_pages.dart';
import 'core/admin_auth_guard.dart';
import 'core/cloudflare_admin_location.dart';
import 'core/cloudflare_admin_route_reporting.dart';
import 'core/cloudflare_admin_core_pages.dart';
import 'core/cloudflare_admin_repository.dart';
import 'core/cloudflare_admin_operating_pages.dart';
import 'core/cloudflare_admin_gateway_pages.dart';
import 'core/cloudflare_admin_receiver_pages.dart';
import 'core/cloudflare_admin_email_pages.dart';
import 'core/cloudflare_admin_receipt_pages.dart';
import 'core/cloudflare_admin_reconciliation_pages.dart';
import 'core/cloudflare_admin_sms_pages.dart';
import 'core/cloudflare_admin_notification_operator_page.dart';
import 'core/cloudflare_admin_notification_management_page.dart';
import 'core/cloudflare_admin_session.dart';
import 'core/cloudflare_admin_mfa.dart';
import 'core/cloudflare_admin_email_verification_page.dart';
import 'core/cloudflare_admin_return_location.dart';

export 'core/cloudflare_admin_return_location.dart';
import 'core/cloudflare_admin_privacy_review_host.dart';
import 'core/cloudflare_canonical_reconciliation_pages.dart';
import 'shared/components/admin_page.dart';
import 'shared/components/admin_data_table.dart';
import 'core/admin_models.dart';

/// Cloudflare workspace entrypoint. Operational services are built against the
/// new Cloudflare schema; no legacy data import is required.
class CloudflareAdminApp extends ConsumerWidget {
  const CloudflareAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Collect Admin',
    debugShowCheckedModeBanner: false,
    theme: AdminTheme.adapt(AppTheme.light()),
    darkTheme: AdminTheme.adapt(AppTheme.dark()),
    highContrastTheme: AdminTheme.adapt(AppTheme.highContrastLight()),
    highContrastDarkTheme: AdminTheme.adapt(AppTheme.highContrastDark()),
    themeMode: ref.watch(collectThemeModeProvider),
    routerConfig: ref.watch(cloudflareAdminRouterConfigProvider),
  );
}

final cloudflareAdminRouterConfigProvider = Provider<RouterConfig<Object>>((
  ref,
) {
  final router = ref.watch(cloudflareAdminRouterProvider);
  return RouterConfig(
    routeInformationProvider: CloudflareAdminRouteReporting(
      delegate: router.routeInformationProvider,
    ),
    routeInformationParser: router.routeInformationParser,
    routerDelegate: router.routerDelegate,
    backButtonDispatcher: router.backButtonDispatcher,
  );
});

final cloudflareAdminRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(cloudflareAdminSessionProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    initialLocation: '/admin',
    refreshListenable: refresh,
    redirect: (context, route) {
      final path = route.uri.path;
      if (const {
        '/admin/login',
        '/admin/forgot-password',
        '/admin/setup',
      }.contains(path)) {
        return null;
      }
      final session = ref.read(cloudflareAdminSessionProvider);
      if (session.isLoading || session.hasError) {
        return path == '/admin/session'
            ? null
            : _accountLocation('/admin/session', route.uri.toString());
      }
      final returnTo = cloudflareAdminReturnLocation(
        route.uri.queryParameters['returnTo'],
      );
      if (session.asData?.value == null) {
        return _accountLocation(
          '/admin/login',
          path == '/admin/session' ? returnTo : route.uri.toString(),
        );
      }
      if (path == '/admin/session') return returnTo ?? '/admin';
      if (path == '/admin/security/authenticator' &&
          ref
              .read(cloudflareAdminSessionProvider.notifier)
              .usesEmailVerification) {
        return '/admin/security/verify-email';
      }
      if (path == '/admin/notification-settings' &&
          session.asData!.value!.role != AdminAccountRole.owner) {
        return '/admin';
      }
      if (path == '/admin/admin-users' &&
          !session.asData!.value!.permissions.contains('admin_users.read')) {
        return '/admin';
      }
      for (final area in CloudflareCoreArea.values) {
        if ((path == area.path || path.startsWith('${area.path}/')) &&
            !session.asData!.value!.permissions.contains(area.permission)) {
          return '/admin';
        }
        if ((path == '${area.path}/new' ||
                path.startsWith('${area.path}/') && path.endsWith('/edit')) &&
            !session.asData!.value!.permissions.contains(
              path == '/admin/groups/new'
                  ? 'collections.create'
                  : area.createOperation.permission,
            )) {
          return area.path;
        }
      }
      if (path.startsWith('/admin/ledger-accounts/') &&
          !session.asData!.value!.permissions.contains('ledger.read')) {
        return '/admin';
      }
      if (path.startsWith('/admin/ledger-accounts/') &&
          path.endsWith('/edit') &&
          !session.asData!.value!.permissions.contains('ledger.manage')) {
        return '/admin/ledgers';
      }
      if ((path == '/admin/momo-receipts' ||
              path.startsWith('/admin/momo-receipts/')) &&
          !session.asData!.value!.permissions.any(
            (permission) =>
                permission == 'sms.read' || permission == 'payments.read',
          )) {
        return '/admin';
      }
      for (final entry in const {
        '/admin/reconciliations': 'reconciliations.read',
        '/admin/sms-receipts': 'sms.read',
        '/admin/notification-operator': 'assisted_sms.read',
        '/admin/notification-settings': 'admin_users.manage',
        '/admin/privacy-requests': 'privacy.review',
      }.entries) {
        if ((path == entry.key || path.startsWith('${entry.key}/')) &&
            !session.asData!.value!.permissions.contains(entry.value)) {
          return '/admin';
        }
      }
      if (path == '/') return '/admin';
      if ((path == '/admin/gateway' || path.startsWith('/admin/gateway/')) &&
          !session.asData!.value!.permissions.contains('gateway.read')) {
        return '/admin';
      }
      if (path == '/admin/gateway/new' &&
          !session.asData!.value!.permissions.contains('gateway.manage')) {
        return '/admin/gateway';
      }
      if (path == '/admin/email' &&
          !session.asData!.value!.permissions.contains('email.read')) {
        return '/admin';
      }
      if ((path == '/admin/member-receipts' ||
              path.startsWith('/admin/member-receipts/')) &&
          !session.asData!.value!.permissions.contains('payments.read')) {
        return '/admin';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/admin'),
      GoRoute(
        path: '/admin/session',
        builder: (_, route) => _SessionPage(
          returnLocation: cloudflareAdminReturnLocation(
            route.uri.queryParameters['returnTo'],
          ),
        ),
      ),
      GoRoute(
        path: '/admin/login',
        builder: (context, route) => AdminAccountLoginPage(
          onSignedIn: () => context.go(
            cloudflareAdminReturnLocation(
                  route.uri.queryParameters['returnTo'],
                ) ??
                '/admin',
          ),
          onForgotPassword: () => context.go(
            _accountLocation(
              '/admin/forgot-password',
              route.uri.queryParameters['returnTo'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/admin/forgot-password',
        builder: (context, route) => AdminAccountForgotPasswordPage(
          onBackToLogin: () => context.go(
            _accountLocation(
              '/admin/login',
              route.uri.queryParameters['returnTo'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/admin/setup',
        builder: (context, route) => _SetupPage(
          token: route.uri.queryParameters['token'] ?? '',
          invite: route.uri.queryParameters['invite'] == 'true',
        ),
      ),
      ShellRoute(
        builder: (_, route, child) =>
            _SessionBoundary(location: route.uri.path, child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, _) => const _AccountOverview()),
          GoRoute(
            path: '/admin/momo-receipts',
            builder: (_, _) => const CloudflareAdminMomoPage(),
          ),
          GoRoute(
            path: '/admin/reconciliations',
            builder: (_, _) => Consumer(
              builder: (_, ref, _) =>
                  ref
                          .watch(cloudflareAdminSessionProvider)
                          .asData
                          ?.value
                          ?.usesCanonicalEvidence ==
                      true
                  ? const CanonicalReconciliationQueuePage()
                  : const CloudflareReconciliationQueuePage(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, route) => Consumer(
                  builder: (_, ref, _) =>
                      ref
                              .watch(cloudflareAdminSessionProvider)
                              .asData
                              ?.value
                              ?.usesCanonicalEvidence ==
                          true
                      ? CanonicalReconciliationDetailPage(
                          key: ValueKey('${route.uri.path}:canonical'),
                          transactionId: route.pathParameters['id']!,
                          backPath: reconciliationReturnLocation(
                            route.uri.queryParameters['returnTo'],
                          ),
                        )
                      : CloudflareReconciliationDetailPage(
                          key: ValueKey(route.uri.path),
                          transactionId: route.pathParameters['id']!,
                          backPath: reconciliationReturnLocation(
                            route.uri.queryParameters['returnTo'],
                          ),
                        ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/admin/sms-receipts',
            builder: (_, _) => const CloudflareAdminSmsReceiptsPage(),
            routes: [
              GoRoute(
                path: ':kind/:id',
                builder: (_, route) => CloudflareAdminSmsReceiptDetailPage(
                  key: ValueKey(route.uri.path),
                  sourceKind: route.pathParameters['kind']!,
                  id: route.pathParameters['id']!,
                  returnTo: smsReturnLocation(
                    route.uri.queryParameters['returnTo'],
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/admin/notification-settings',
            builder: (_, _) => const Material(
              type: MaterialType.transparency,
              child: CloudflareAdminNotificationManagementPage(),
            ),
          ),
          GoRoute(
            path: '/admin/notification-operator',
            builder: (_, _) => const Material(
              type: MaterialType.transparency,
              child: CloudflareAdminNotificationOperatorPage(),
            ),
          ),
          GoRoute(
            path: '/admin/email',
            builder: (_, _) => const CloudflareEmailPage(),
          ),
          GoRoute(
            path: '/admin/member-receipts',
            builder: (_, _) => const CloudflareMemberReceiptListPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, route) => CloudflareMemberReceiptDetailPage(
                  key: ValueKey(route.uri.path),
                  id: route.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/admin/gateway',
            builder: (_, _) => const CloudflareGatewayListPage(),
            routes: [
              GoRoute(
                path: 'receiver-grants',
                builder: (_, _) => const CloudflareReceiverGrantListPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, route) => CloudflareReceiverGrantDetailPage(
                      key: ValueKey(route.uri.path),
                      id: route.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'new',
                builder: (_, _) => const CloudflareGatewayEnrollPage(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, route) => CloudflareGatewayDetailPage(
                  key: ValueKey(route.uri.path),
                  id: route.pathParameters['id']!,
                ),
              ),
            ],
          ),
          for (final area in CloudflareCoreArea.values)
            GoRoute(
              path: area.path,
              builder: (_, _) => CloudflareCoreListPage(area: area),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (_, route) => CloudflareOperatingCreatePage(
                    area: area,
                    backPath: cloudflareCoreReturnLocation(
                      area,
                      route.uri.queryParameters['returnTo'],
                    ),
                  ),
                ),
                if (area != CloudflareCoreArea.transactions)
                  GoRoute(
                    path: ':id/edit',
                    builder: (_, route) => CloudflareOperatingEditPage(
                      key: ValueKey(route.uri.path),
                      type: area.nativeResource,
                      id: route.pathParameters['id']!,
                      backPath: '${area.path}/${route.pathParameters['id']}',
                    ),
                  ),
                GoRoute(
                  path: ':id',
                  builder: (_, route) => CloudflareOperatingDetailPage(
                    key: ValueKey(route.uri.path),
                    type: area.detailResource(
                      usesCanonicalEvidence:
                          ref
                              .read(cloudflareAdminSessionProvider)
                              .asData
                              ?.value
                              ?.usesCanonicalEvidence ==
                          true,
                    ),
                    id: route.pathParameters['id']!,
                    backPath: cloudflareCoreReturnLocation(
                      area,
                      route.uri.queryParameters['returnTo'],
                    ),
                  ),
                ),
              ],
            ),
          GoRoute(
            path: '/admin/ledger-accounts/:id',
            builder: (_, route) => CloudflareOperatingDetailPage(
              key: ValueKey(route.uri.path),
              type: 'accounts',
              id: route.pathParameters['id']!,
              backPath: '/admin/ledgers',
            ),
          ),
          GoRoute(
            path: '/admin/ledger-accounts/:id/edit',
            builder: (_, route) => CloudflareOperatingEditPage(
              key: ValueKey(route.uri.path),
              type: 'accounts',
              id: route.pathParameters['id']!,
              backPath: '/admin/ledger-accounts/${route.pathParameters['id']}',
            ),
          ),
          GoRoute(
            path: '/admin/requests',
            builder: (_, route) => CloudflareOperatingRequestPage(
              key: ValueKey(route.uri.toString()),
              requestKey: route.uri.queryParameters['key'] ?? '',
            ),
          ),
          GoRoute(
            path: '/admin/admin-users',
            builder: (_, _) => Consumer(
              builder: (context, ref, _) {
                final user = ref
                    .watch(cloudflareAdminSessionProvider)
                    .asData
                    ?.value;
                final verify =
                    user?.usesEmailVerification == true &&
                    user?.role == AdminAccountRole.owner &&
                    user?.email.toLowerCase() == 'info@ikanisa.com' &&
                    user?.permissions.contains('admin_users.manage') == true &&
                    user?.hasRecentSensitiveVerification() != true;
                return AdminAccountTeamPage(
                  onVerify: verify
                      ? () => context.go(
                          Uri(
                            path: '/admin/security/verify-email',
                            queryParameters: {'returnTo': '/admin/admin-users'},
                          ).toString(),
                        )
                      : null,
                );
              },
            ),
          ),
          GoRoute(
            path: '/admin/privacy-requests',
            builder: (_, _) => const CloudflareAdminPrivacyReviewPageHost(),
          ),
          GoRoute(
            path: '/admin/security',
            builder: (context, _) => CloudflareAdminSecurityPage(
              onSignIn: () {
                ref.read(cloudflareAdminSessionProvider.notifier).clear();
                context.go('/admin/login');
              },
            ),
          ),
          GoRoute(
            path: '/admin/security/verify-email',
            builder: (_, route) => CloudflareAdminEmailVerificationPage(
              returnTo: cloudflareAdminEmailVerificationReturnLocation(
                route.uri.queryParameters['returnTo'],
              ),
            ),
          ),
          GoRoute(
            path: '/admin/security/authenticator',
            builder: (_, _) => const CloudflareAdminMfaPage(),
          ),
          GoRoute(
            path: '/admin/licenses',
            builder: (_, _) => const CloudflareAdminLicensesPage(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, _) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This page is not available in this workspace.'),
            TextButton(
              onPressed: () => context.go('/admin'),
              child: const Text('Go to overview'),
            ),
          ],
        ),
      ),
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

String _accountLocation(String path, String? returnLocation) {
  final destination = cloudflareAdminReturnLocation(returnLocation);
  return Uri(
    path: path,
    queryParameters: destination == null ? null : {'returnTo': destination},
  ).toString();
}

class _SessionBoundary extends ConsumerWidget {
  const _SessionBoundary({required this.location, required this.child});
  final String location;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(adminAuthSessionScopeProvider);
    return KeyedSubtree(
      key: ValueKey(scope),
      child: AdminShell(location: location, child: child),
    );
  }
}

class _SetupPage extends StatefulWidget {
  const _SetupPage({required this.token, required this.invite});
  final String token;
  final bool invite;
  @override
  State<_SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<_SetupPage> {
  late final String _token = widget.token;
  late final bool _invite = widget.invite;
  @override
  void initState() {
    super.initState();
    // The one-use secret stays in this widget only, not browser history.
    removeCloudflareSetupTokenFromLocation();
  }

  @override
  Widget build(BuildContext context) => AdminAccountPasswordSetupPage(
    token: _token,
    invite: _invite,
    onBackToLogin: () => context.go('/admin/login'),
    onRequestReset: () => context.go('/admin/forgot-password'),
  );
}

class _SessionPage extends ConsumerWidget {
  const _SessionPage({this.returnLocation});
  final String? returnLocation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cloudflareAdminSessionProvider);
    final controller = ref.read(cloudflareAdminSessionProvider.notifier);
    return Scaffold(
      body: Center(
        child: session.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.logoutUnconfirmed
                        ? 'Sign-out was not confirmed. Please try again.'
                        : 'Account access could not be checked.',
                  ),
                  FilledButton(
                    onPressed: () async {
                      if (controller.logoutUnconfirmed) {
                        try {
                          await controller.signOut();
                        } catch (_) {
                          // The controller retains the retry state.
                        }
                      } else {
                        await controller.refresh();
                      }
                    },
                    child: Text(
                      controller.logoutUnconfirmed
                          ? 'Retry sign out'
                          : 'Try again',
                    ),
                  ),
                  if (!controller.logoutUnconfirmed)
                    TextButton(
                      onPressed: () => context.go(
                        _accountLocation('/admin/login', returnLocation),
                      ),
                      child: const Text('Go to sign in'),
                    ),
                ],
              )
            : const CircularProgressIndicator(
                semanticsLabel: 'Checking account access',
              ),
      ),
    );
  }
}

class _AccountOverview extends ConsumerWidget {
  const _AccountOverview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    if (user == null) return const SizedBox.shrink();
    return AdminPage(
      title: 'Your workspace',
      subtitle: 'Collect operations, recorded activity and your team.',
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CloudflareCoreOverviewPanel(),
            const SizedBox(height: 24),
            AdminDataTable(
              tableLabel: 'Workspace access',
              rows: [
                AdminTableRowData(
                  id: user.id,
                  title: user.email,
                  subtitle: '',
                  status: user.role.label,
                  amount: '',
                ),
              ],
              columns: [
                AdminTableColumn(label: 'Account', value: (row) => row.title),
                AdminTableColumn(label: 'Access', value: (row) => row.status),
                if (user.role == AdminAccountRole.owner)
                  AdminTableColumn(
                    label: 'Team access',
                    value: (_) => 'Admins and staff',
                    cellBuilder: (_) => TextButton.icon(
                      onPressed: () => context.go('/admin/admin-users'),
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Admins and staff'),
                    ),
                  ),
                AdminTableColumn(
                  label: 'Account security',
                  value: (_) => 'Password and security',
                  cellBuilder: (_) => TextButton.icon(
                    onPressed: () => context.go('/admin/security'),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Password and security'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
