import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin_shell.dart';
import 'core/admin_auth_guard.dart';
import 'core/admin_repository_base.dart';
import '../features/landing/collect_landing_page.dart';
import 'shared/components/admin_empty_state.dart';
import 'shared/components/admin_page.dart';

const publicLandingHome = bool.fromEnvironment('COLLECT_PUBLIC_LANDING_HOME');
const _adminDomain = 'admin.collect.ikanisa.com';

const adminRoutePaths = <String>[
  '/admin/login',
  '/admin/denied',
  '/admin',
  '/admin/groups',
  '/admin/groups/:id',
  '/admin/members',
  '/admin/members/:id',
  '/admin/payees',
  '/admin/transactions',
  '/admin/transactions/:id',
  '/admin/reconciliations',
  '/admin/ledgers',
  '/admin/notifications',
  '/admin/notifications/:id',
  '/admin/audit-logs',
  '/admin/settings',
  '/admin/feature-flags',
  '/admin/system-health',
  '/admin/admin-users',
  '/admin/admin-users/:id',
];

final adminRouterProvider = Provider<GoRouter>((ref) {
  final guard = ref.watch(adminAuthGuardProvider);
  final showPublicHome = _shouldShowPublicLandingHome();
  return GoRouter(
    initialLocation: showPublicHome ? _publicInitialLocation() : '/admin',
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == '/') return showPublicHome ? null : '/admin';
      if (showPublicHome && path.length > 1 && path.endsWith('/')) {
        final normalized = path.substring(0, path.length - 1);
        if (publicWebsitePaths.contains(normalized)) return normalized;
      }
      if (!showPublicHome && publicWebsitePaths.contains(path)) {
        return '/admin';
      }
      if (path == '/admin/login') return null;
      if (path.startsWith('/admin') && !guard.isAuthorized) {
        return '/admin/login';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const CollectLandingPage(),
      ),
      for (final page in _publicPagesForRouter)
        GoRoute(
          path: page.path,
          builder: (context, state) => CollectPublicPage(data: page),
        ),
      GoRoute(
        path: '/admin/login',
        builder: (context, state) => const AdminLoginPage(),
      ),
      GoRoute(
        path: '/admin/denied',
        builder: (context, state) => const AdminDeniedPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminOverviewContent(),
          ),
          _listRoute(
            '/admin/groups',
            title: 'Groups',
            rpcName: 'admin_list_collections',
            detailPathPrefix: '/admin/groups',
          ),
          _detailRoute(
            '/admin/groups/:id',
            title: 'Group detail',
            rpcName: 'admin_get_collection',
            backLabel: 'Groups',
          ),
          _listRoute(
            '/admin/members',
            title: 'Members',
            rpcName: 'admin_list_users',
            detailPathPrefix: '/admin/members',
          ),
          _detailRoute(
            '/admin/members/:id',
            title: 'Member detail',
            rpcName: 'admin_get_user',
            backLabel: 'Members',
          ),
          ..._financialAdminRoutes,
          _listRoute(
            '/admin/notifications',
            title: 'Notifications',
            rpcName: 'admin_list_notifications',
            detailPathPrefix: '/admin/notifications',
          ),
          _detailRoute(
            '/admin/notifications/:id',
            title: 'Notification detail',
            rpcName: 'admin_get_notification',
            backLabel: 'Notifications',
          ),
          _listRoute(
            '/admin/audit-logs',
            title: 'Audit logs',
            rpcName: 'admin_list_audit_logs',
          ),
          _listRoute(
            '/admin/settings',
            title: 'Settings',
            rpcName: 'admin_list_settings',
          ),
          _listRoute(
            '/admin/feature-flags',
            title: 'Feature flags',
            rpcName: 'admin_list_feature_flags',
            actionKind: 'feature_flag_toggle',
          ),
          GoRoute(
            path: '/admin/system-health',
            builder: (context, state) => const AdminDetailPage(
              title: 'System health',
              rpcName: 'admin_system_health',
              id: 'system',
            ),
          ),
          _listRoute(
            '/admin/admin-users',
            title: 'Admin users',
            rpcName: 'admin_list_admin_users',
            detailPathPrefix: '/admin/admin-users',
          ),
          _detailRoute(
            '/admin/admin-users/:id',
            title: 'Admin user detail',
            rpcName: 'admin_get_admin_user',
            backLabel: 'Admin users',
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        AdminUnknownRoutePage(location: state.uri.path),
  );
});

List<RouteBase> get _financialAdminRoutes => [
  GoRoute(
    path: '/admin/payees',
    builder: (context, state) => const AdminCollectOperationsPage(
      operation: CollectAdminOperation.payees,
    ),
  ),
  GoRoute(
    path: '/admin/transactions',
    builder: (context, state) => const AdminCollectOperationsPage(
      operation: CollectAdminOperation.transactions,
    ),
  ),
  GoRoute(
    path: '/admin/transactions/:id',
    builder: (context, state) =>
        AdminCollectTransactionDetailPage(id: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/admin/reconciliations',
    builder: (context, state) => const AdminCollectOperationsPage(
      operation: CollectAdminOperation.reconciliations,
    ),
  ),
  GoRoute(
    path: '/admin/ledgers',
    builder: (context, state) => const AdminCollectOperationsPage(
      operation: CollectAdminOperation.ledgers,
    ),
  ),
];

bool _shouldShowPublicLandingHome() {
  if (!publicLandingHome) return false;
  return Uri.base.host.toLowerCase() != _adminDomain;
}

String _publicInitialLocation() {
  final path = Uri.base.path;
  if (path.length > 1 && path.endsWith('/')) {
    final normalized = path.substring(0, path.length - 1);
    if (publicWebsitePaths.contains(normalized)) return normalized;
  }
  if (publicWebsitePaths.contains(path)) return path;
  return '/';
}

final _publicPagesForRouter = publicWebsitePaths
    .where((path) => path != '/')
    .map(publicPageForPath)
    .toList(growable: false);

GoRoute _listRoute(
  String path, {
  required String title,
  required String rpcName,
  String? detailPathPrefix,
  String? actionKind,
}) {
  return GoRoute(
    path: path,
    builder: (context, state) => AdminRpcListPage(
      title: title,
      rpcName: rpcName,
      detailPathPrefix: detailPathPrefix,
      actionKind: actionKind,
    ),
  );
}

class AdminUnknownRoutePage extends StatelessWidget {
  const AdminUnknownRoutePage({required this.location, super.key});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AdminPage(
        title: 'Admin route not found',
        subtitle: location.isEmpty
            ? 'The requested admin screen is not registered.'
            : '$location is not a registered admin screen.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminEmptyState(
              title: 'This admin screen is unavailable',
              message: 'Return to overview.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/admin'),
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('Operations overview'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/admin/login'),
                  icon: const Icon(Icons.login_outlined),
                  label: const Text('Admin login'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

GoRoute _detailRoute(
  String path, {
  required String title,
  required String rpcName,
  required String backLabel,
}) {
  final backPath = path.replaceFirst('/:id', '');
  return GoRoute(
    path: path,
    builder: (context, state) => AdminDetailPage(
      title: title,
      rpcName: rpcName,
      id: state.pathParameters['id']!,
      backPath: backPath,
      backLabel: backLabel,
    ),
  );
}
