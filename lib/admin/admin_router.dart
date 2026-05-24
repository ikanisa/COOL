import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin_shell.dart';
import 'core/admin_auth_guard.dart';
import 'core/admin_repository_base.dart';

const adminRoutePaths = <String>[
  '/admin/login',
  '/admin/denied',
  '/admin',
  '/admin/collections',
  '/admin/collections/:id',
  '/admin/public-requests',
  '/admin/users',
  '/admin/users/:id',
  '/admin/payments',
  '/admin/payments/:id',
  '/admin/payment-events',
  '/admin/payment-events/:id',
  '/admin/unallocated',
  '/admin/ledger',
  '/admin/receivers',
  '/admin/receivers/:id',
  '/admin/sms',
  '/admin/sms/:id',
  '/admin/audit-logs',
  '/admin/settings',
  '/admin/feature-flags',
  '/admin/system-health',
  '/admin/admin-users',
];

final adminRouterProvider = Provider<GoRouter>((ref) {
  final guard = ref.watch(adminAuthGuardProvider);
  return GoRouter(
    initialLocation: '/admin',
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == '/') return '/admin';
      if (path == '/admin/login') return null;
      if (path.startsWith('/admin') && !guard.isAuthorized) {
        return '/admin/login';
      }
      return null;
    },
    routes: [
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
            '/admin/collections',
            title: 'Collections',
            rpcName: 'admin_list_collections',
            detailPathPrefix: '/admin/collections',
          ),
          _detailRoute(
            '/admin/collections/:id',
            title: 'Collection detail',
            rpcName: 'admin_get_collection',
          ),
          _listRoute(
            '/admin/public-requests',
            title: 'Public requests',
            rpcName: 'admin_list_public_requests',
            actionKind: 'public_request_review',
          ),
          _listRoute(
            '/admin/users',
            title: 'Users',
            rpcName: 'admin_list_users',
            detailPathPrefix: '/admin/users',
          ),
          _detailRoute(
            '/admin/users/:id',
            title: 'User detail',
            rpcName: 'admin_get_user',
          ),
          _listRoute(
            '/admin/payments',
            title: 'Payments',
            rpcName: 'admin_list_payments',
            detailPathPrefix: '/admin/payments',
          ),
          _detailRoute(
            '/admin/payments/:id',
            title: 'Payment detail',
            rpcName: 'admin_get_payment',
          ),
          _listRoute(
            '/admin/payment-events',
            title: 'Payment events',
            rpcName: 'admin_list_payment_events',
            detailPathPrefix: '/admin/payment-events',
            actionKind: 'payment_event_reparse',
          ),
          _detailRoute(
            '/admin/payment-events/:id',
            title: 'Payment event detail',
            rpcName: 'admin_get_payment_event',
          ),
          _listRoute(
            '/admin/unallocated',
            title: 'Unallocated payments',
            rpcName: 'admin_list_unallocated',
            detailPathPrefix: '/admin/payment-events',
            actionKind: 'payment_event_reparse',
          ),
          _listRoute(
            '/admin/ledger',
            title: 'Ledger',
            rpcName: 'admin_list_ledger',
          ),
          _listRoute(
            '/admin/receivers',
            title: 'Receivers',
            rpcName: 'admin_list_receivers',
            detailPathPrefix: '/admin/receivers',
          ),
          _detailRoute(
            '/admin/receivers/:id',
            title: 'Receiver detail',
            rpcName: 'admin_get_receiver',
          ),
          _listRoute(
            '/admin/sms',
            title: 'SMS metadata',
            rpcName: 'admin_list_sms_metadata',
            detailPathPrefix: '/admin/sms',
          ),
          GoRoute(
            path: '/admin/sms/:id',
            builder: (context, state) =>
                AdminSmsDetailPage(id: state.pathParameters['id']!),
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
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        const Scaffold(body: Center(child: Text('Admin route not found'))),
  );
});

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

GoRoute _detailRoute(
  String path, {
  required String title,
  required String rpcName,
}) {
  return GoRoute(
    path: path,
    builder: (context, state) => AdminDetailPage(
      title: title,
      rpcName: rpcName,
      id: state.pathParameters['id']!,
    ),
  );
}
