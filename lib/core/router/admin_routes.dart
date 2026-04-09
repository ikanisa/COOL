import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/admin_groups_screen.dart';
import '../../features/admin/screens/admin_workspaces_screen.dart';
import '../../features/admin/screens/audit_log_screen.dart';
import '../../features/admin/screens/bank_admin_workspace_screen.dart';
import '../../features/admin/screens/manage_admin_roles_screen.dart';
import '../../features/admin/screens/manage_app_config_screen.dart';
import '../../features/admin/screens/manage_users_screen.dart';
import '../../features/admin/screens/operational_dashboard_screen.dart';
import '../../features/admin/screens/system_analytics_screen.dart';
import '../../features/admin/widgets/admin_workspace_gate.dart';
import 'app_routes.dart';

/// Admin route tree nested under [AppRoutes.admin].
GoRoute adminRoutes() {
  return GoRoute(
    path: AppRoutes.admin,
    builder: (context, state) => const AdminWorkspacesScreen(),
    routes: [
      GoRoute(
        path: 'platform',
        builder: (context, state) =>
            const PlatformAdminGate(child: AdminDashboardScreen()),
      ),
      GoRoute(path: 'partners', redirect: (context, state) => AppRoutes.admin),
      GoRoute(
        path: 'banks/:bankId',
        builder: (context, state) {
          final bankId = state.pathParameters['bankId']?.trim() ?? '';
          return BankAdminWorkspaceGate(
            bankId: bankId,
            child: BankAdminWorkspaceScreen(bankId: bankId),
          );
        },
      ),
      GoRoute(
        path: 'users',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageUsersScreen()),
      ),
      GoRoute(
        path: 'app-config',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageAppConfigScreen()),
      ),
      GoRoute(
        path: 'operations',
        builder: (context, state) =>
            const PlatformAdminGate(child: OperationalDashboardScreen()),
      ),
      GoRoute(
        path: 'roles',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageAdminRolesScreen()),
      ),
      GoRoute(
        path: 'analytics',
        builder: (context, state) =>
            const PlatformAdminGate(child: SystemAnalyticsScreen()),
      ),
      GoRoute(
        path: 'audit-log',
        builder: (context, state) =>
            const PlatformAdminGate(child: AuditLogScreen()),
      ),
      GoRoute(
        path: 'groups',
        builder: (context, state) =>
            const PlatformAdminGate(child: AdminGroupsScreen()),
      ),
    ],
  );
}
