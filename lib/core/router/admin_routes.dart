import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/admin_workspaces_screen.dart';
import '../../features/admin/screens/audit_log_screen.dart';
import '../../features/admin/screens/manage_activities_screen.dart';
import '../../features/admin/screens/manage_admin_roles_screen.dart';
import '../../features/admin/screens/manage_ai_content_screen.dart';
import '../../features/admin/screens/manage_app_config_screen.dart';
import '../../features/admin/screens/manage_missions_screen.dart';
import '../../features/admin/screens/manage_quick_actions_screen.dart';
import '../../features/admin/screens/manage_seasons_screen.dart';
import '../../features/admin/screens/manage_services_screen.dart';
import '../../features/admin/screens/manage_special_products_screen.dart';
import '../../features/admin/screens/manage_users_screen.dart';
import '../../features/admin/screens/operational_dashboard_screen.dart';
import '../../features/admin/screens/system_analytics_screen.dart';
import '../../features/admin/widgets/admin_workspace_gate.dart';
import '../../features/rayon/screens/rs_admin_analytics_screen.dart';
import '../../features/rayon/screens/rs_admin_dashboard_screen.dart';
import '../../features/rayon/screens/rs_admin_finance_screen.dart';
import '../../features/rayon/screens/rs_admin_initiatives_screen.dart';
import '../../features/rayon/screens/rs_admin_matches_screen.dart';
import '../../features/rayon/screens/rs_admin_members_screen.dart';
import '../../features/rayon/screens/rs_admin_orders_screen.dart';
import '../../features/rayon/screens/rs_admin_packages_screen.dart';
import '../../features/rayon/screens/rs_admin_shop_screen.dart';
import '../../features/rayon/screens/rs_admin_tickets_screen.dart';
import '../../features/rayon/screens/rs_admin_engagement_screen.dart';
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
        path: 'users',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageUsersScreen()),
      ),
      GoRoute(
        path: 'services',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageServicesScreen()),
      ),
      GoRoute(
        path: 'quick-actions',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageQuickActionsScreen()),
      ),
      GoRoute(
        path: 'app-config',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageAppConfigScreen()),
      ),
      GoRoute(
        path: 'special-products',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageSpecialProductsScreen()),
      ),
      GoRoute(
        path: 'missions',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageMissionsScreen()),
      ),
      GoRoute(
        path: 'seasons',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageSeasonsScreen()),
      ),
      GoRoute(
        path: 'activities',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageActivitiesScreen()),
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
        path: 'ai-content',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageAiContentScreen()),
      ),
      // ── RS Admin routes (nested under /admin/rayon) ──────────
      GoRoute(
        path: 'rayon',
        builder: (context, state) =>
            const PlatformAdminGate(child: RsAdminDashboardScreen()),
        routes: [
          GoRoute(
            path: 'matches',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminMatchesScreen()),
          ),
          GoRoute(
            path: 'tickets',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminTicketsScreen()),
          ),
          GoRoute(
            path: 'shop',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminShopScreen()),
          ),
          GoRoute(
            path: 'orders',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminOrdersScreen()),
          ),
          GoRoute(
            path: 'members',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminMembersScreen()),
          ),
          GoRoute(
            path: 'packages',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminPackagesScreen()),
          ),
          GoRoute(
            path: 'finance',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminFinanceScreen()),
          ),
          GoRoute(
            path: 'initiatives',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminInitiativesScreen()),
          ),
          GoRoute(
            path: 'analytics',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminAnalyticsScreen()),
          ),
          GoRoute(
            path: 'engagement',
            builder: (context, state) =>
                const PlatformAdminGate(child: RsAdminEngagementScreen()),
          ),
        ],
      ),
    ],
  );
}
