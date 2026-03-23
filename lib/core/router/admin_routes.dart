
import 'package:go_router/go_router.dart';


import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/admin_workspaces_screen.dart';
import '../../features/admin/screens/audit_log_screen.dart';
import '../../features/admin/screens/bank_admin_workspace_screen.dart';
import '../../features/admin/screens/manage_activities_screen.dart';
import '../../features/admin/screens/manage_admin_roles_screen.dart';
import '../../features/admin/screens/manage_ai_content_screen.dart';
import '../../features/admin/screens/manage_app_config_screen.dart';
import '../../features/admin/screens/manage_missions_screen.dart';
import '../../features/admin/screens/manage_partners_screen.dart';
import '../../features/admin/screens/manage_quick_actions_screen.dart';
import '../../features/admin/screens/manage_seasons_screen.dart';
import '../../features/admin/screens/manage_services_screen.dart';
import '../../features/admin/screens/manage_special_products_screen.dart';
import '../../features/admin/screens/manage_users_screen.dart';
import '../../features/admin/screens/manage_vehicle_types_screen.dart';
import '../../features/admin/screens/operational_dashboard_screen.dart';
import '../../features/admin/screens/partner_admin_workspace_screen.dart';
import '../../features/admin/screens/system_analytics_screen.dart';
import '../../features/admin/widgets/admin_workspace_gate.dart';
import '../../features/partners/rayon/screens/rs_admin_analytics_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_dashboard_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_finance_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_initiatives_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_matches_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_members_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_orders_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_packages_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_shop_screen.dart';
import '../../features/partners/rayon/screens/rs_admin_tickets_screen.dart';
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
      GoRoute(
        path: 'users',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageUsersScreen()),
      ),
      GoRoute(
        path: 'partners',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManagePartnersScreen()),
      ),
      GoRoute(
        path: 'partners/:partnerId',
        builder: (context, state) => PartnerAdminWorkspaceScreen(
          partnerId: state.pathParameters['partnerId'] ?? '',
        ),
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
        path: 'vehicle-types',
        builder: (context, state) =>
            const PlatformAdminGate(child: ManageVehicleTypesScreen()),
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
      GoRoute(
        path: 'banks/:partnerId',
        builder: (context, state) => BankAdminWorkspaceScreen(
          partnerId: state.pathParameters['partnerId'] ?? '',
        ),
      ),
      // ── RS Admin routes (nested under /admin/rayon) ──────────
      GoRoute(
        path: 'rayon',
        builder: (context, state) =>
            const RayonAdminGate(child: RsAdminDashboardScreen()),
        routes: [
          GoRoute(
            path: 'matches',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminMatchesScreen()),
          ),
          GoRoute(
            path: 'tickets',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminTicketsScreen()),
          ),
          GoRoute(
            path: 'shop',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminShopScreen()),
          ),
          GoRoute(
            path: 'orders',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminOrdersScreen()),
          ),
          GoRoute(
            path: 'members',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminMembersScreen()),
          ),
          GoRoute(
            path: 'packages',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminPackagesScreen()),
          ),
          GoRoute(
            path: 'finance',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminFinanceScreen()),
          ),
          GoRoute(
            path: 'initiatives',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminInitiativesScreen()),
          ),
          GoRoute(
            path: 'analytics',
            builder: (context, state) =>
                const RayonAdminGate(child: RsAdminAnalyticsScreen()),
          ),
        ],
      ),
    ],
  );
}
