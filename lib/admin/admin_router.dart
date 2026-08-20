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
  '/admin/bank-destinations',
  '/admin/bank-destinations/:id',
  '/admin/bank-destination-requests',
  '/admin/bank-destination-requests/:id',
  '/admin/bank-intents',
  '/admin/bank-intents/:id',
  '/admin/bank-transactions',
  '/admin/bank-transactions/:id',
  '/admin/bank-evidence',
  '/admin/bank-evidence/:id',
  '/admin/reconciliation',
  '/admin/reconciliation/:id',
  '/admin/reconciliation-exceptions',
  '/admin/reconciliation-exceptions/:id',
  '/admin/bank-allocation-requests',
  '/admin/bank-allocation-requests/:id',
  '/admin/bank-journal',
  '/admin/bank-journal/:id',
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
          _listRoute(
            '/admin/bank-destinations',
            title: 'Bank details',
            rpcName: 'admin_list_bank_destinations',
            detailPathPrefix: '/admin/bank-destinations',
          ),
          _detailRoute(
            '/admin/bank-destinations/:id',
            title: 'Bank destination detail',
            rpcName: 'admin_get_bank_destination',
            backLabel: 'Bank details',
          ),
          _listRoute(
            '/admin/bank-destination-requests',
            title: 'Bank detail approvals',
            rpcName: 'admin_list_bank_destination_change_requests',
            detailPathPrefix: '/admin/bank-destination-requests',
          ),
          _detailRoute(
            '/admin/bank-destination-requests/:id',
            title: 'Bank detail approval',
            rpcName: 'admin_get_bank_destination_change_request',
            backLabel: 'Bank detail approvals',
          ),
          _listRoute(
            '/admin/bank-intents',
            title: 'Transfer requests',
            rpcName: 'admin_list_bank_transfer_intents',
            detailPathPrefix: '/admin/bank-intents',
          ),
          _detailRoute(
            '/admin/bank-intents/:id',
            title: 'Transfer request detail',
            rpcName: 'admin_get_bank_transfer_intent',
            backLabel: 'Transfer requests',
          ),
          _listRoute(
            '/admin/bank-transactions',
            title: 'Bank transactions',
            rpcName: 'admin_list_bank_transactions',
            detailPathPrefix: '/admin/bank-transactions',
          ),
          _detailRoute(
            '/admin/bank-transactions/:id',
            title: 'Bank transaction detail',
            rpcName: 'admin_get_bank_transaction',
            backLabel: 'Bank transactions',
          ),
          _listRoute(
            '/admin/bank-evidence',
            title: 'Bank evidence',
            rpcName: 'admin_list_bank_evidence',
            detailPathPrefix: '/admin/bank-evidence',
          ),
          _detailRoute(
            '/admin/bank-evidence/:id',
            title: 'Bank evidence detail',
            rpcName: 'admin_get_bank_evidence',
            backLabel: 'Bank evidence',
          ),
          _listRoute(
            '/admin/reconciliation',
            title: 'Daily reconciliation',
            rpcName: 'admin_list_reconciliation_runs',
            detailPathPrefix: '/admin/reconciliation',
          ),
          _detailRoute(
            '/admin/reconciliation/:id',
            title: 'Reconciliation run',
            rpcName: 'admin_get_reconciliation_run',
            backLabel: 'Daily reconciliation',
          ),
          _listRoute(
            '/admin/reconciliation-exceptions',
            title: 'Reconciliation exceptions',
            rpcName: 'admin_list_reconciliation_exceptions',
            detailPathPrefix: '/admin/reconciliation-exceptions',
          ),
          _detailRoute(
            '/admin/reconciliation-exceptions/:id',
            title: 'Reconciliation exception',
            rpcName: 'admin_get_reconciliation_exception',
            backLabel: 'Reconciliation exceptions',
          ),
          _listRoute(
            '/admin/bank-allocation-requests',
            title: 'Allocation approvals',
            rpcName: 'admin_list_bank_allocation_requests',
            detailPathPrefix: '/admin/bank-allocation-requests',
          ),
          _detailRoute(
            '/admin/bank-allocation-requests/:id',
            title: 'Allocation approval',
            rpcName: 'admin_get_bank_allocation_request',
            backLabel: 'Allocation approvals',
          ),
          _listRoute(
            '/admin/bank-journal',
            title: 'Bank journal',
            rpcName: 'admin_list_journal_entries',
            detailPathPrefix: '/admin/bank-journal',
          ),
          _detailRoute(
            '/admin/bank-journal/:id',
            title: 'Journal entry',
            rpcName: 'admin_get_journal_entry',
            backLabel: 'Bank journal',
          ),
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
