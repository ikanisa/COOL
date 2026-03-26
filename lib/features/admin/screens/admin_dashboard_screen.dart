import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/admin_workspace_access.dart';
import '../providers/admin_providers.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

part 'admin_dashboard_parts.dart';

EdgeInsets _adminDashboardListPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: CoolLayout.gutter);

/// Admin Dashboard — role-filtered card grid for admin management screens.
///
/// Platform admins see every card. Bank admins see only bank-related cards.
/// Rayon Sport admins see only Rayon-related cards.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  static List<_AdminSection> _buildSections(BuildContext context) {
    final l = context.l10n;
    return [
      _AdminSection(
        l.adminUsers,
        Icons.person_rounded,
        '/admin/users',
        l.adminUsersDesc,
      ),
      _AdminSection(
        l.adminPartners,
        Icons.handshake_rounded,
        '/admin/partners',
        l.adminPartnersDesc,
      ),
      _AdminSection(
        l.adminServices,
        Icons.assignment_rounded,
        '/admin/services',
        l.adminServicesDesc,
      ),
      _AdminSection(
        l.adminQuickActions,
        Icons.bolt_rounded,
        '/admin/quick-actions',
        l.adminSpecialProductsDesc,
      ),
      _AdminSection(
        l.adminAppConfig,
        Icons.settings_rounded,
        '/admin/app-config',
        l.adminAppConfigDesc,
      ),
      _AdminSection(
        l.adminOperations,
        Icons.monitor_heart_rounded,
        '/admin/operations',
        l.adminReleaseDesc,
      ),
      _AdminSection(
        l.rayonSports,
        Icons.sports_soccer_rounded,
        '/admin/rayon',
        'Matches, tickets, shop, members',
        visibleTo: {AdminRole.admin, AdminRole.rayonSport},
      ),
      _AdminSection(
        l.adminSpecialProducts,
        Icons.star_rounded,
        '/admin/special-products',
        'Buri Munsi and savings cards',
        visibleTo: {AdminRole.admin, AdminRole.bank},
      ),
      _AdminSection(
        l.adminMissions,
        Icons.flag_rounded,
        '/admin/missions',
        l.adminMissionsDesc,
        visibleTo: {AdminRole.admin, AdminRole.rayonSport, AdminRole.bank},
      ),
      _AdminSection(
        l.adminSeasons,
        Icons.emoji_events_rounded,
        '/admin/seasons',
        l.adminLiveOpsDesc,
        visibleTo: {AdminRole.admin, AdminRole.rayonSport, AdminRole.bank},
      ),
      _AdminSection(
        l.adminActivities,
        Icons.local_fire_department_rounded,
        '/admin/activities',
        l.adminSeasonsDesc,
        visibleTo: {AdminRole.admin, AdminRole.rayonSport, AdminRole.bank},
      ),
      _AdminSection(
        l.adminAdminRoles,
        Icons.admin_panel_settings_rounded,
        '/admin/roles',
        l.adminAdminRolesDesc,
      ),
      _AdminSection(
        l.adminSystemAnalytics,
        Icons.analytics_rounded,
        '/admin/analytics',
        l.adminSystemAnalyticsDesc,
      ),
      _AdminSection(
        l.adminAiContent,
        Icons.auto_awesome_rounded,
        '/admin/ai-content',
        l.adminAiContentDesc,
      ),
      _AdminSection(
        l.adminAuditLog,
        Icons.history_rounded,
        '/admin/audit-log',
        l.adminAuditLogDesc,
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    final access = ref.watch(adminWorkspaceAccessProvider);

    // Filter sections based on user's role
    final sections = _buildSections(context)
        .where((section) {
          // If visibleTo is null, only platform admins can see it
          if (section.visibleTo == null) {
            return access.hasPlatformAccess;
          }
          // Platform admins always see everything
          if (access.hasPlatformAccess) return true;
          // Check specific role visibility
          if (section.visibleTo!.contains(AdminRole.bank) &&
              access.hasBankAdminAccess) {
            return true;
          }
          if (section.visibleTo!.contains(AdminRole.rayonSport) &&
              access.hasPartnerAdminAccess) {
            return true;
          }
          return false;
        })
        .toList(growable: false);

    return AdminDetailScaffold(
      backTooltip: context.l10n.back,
      onBack: () => context.pop(),
      child: SafeArea(
        child: ListView(
          padding: _adminDashboardListPadding(),
          children: [
            Semantics(
              header: true,
              label: context.l10n.adminPanelTitle,
              child: Text(
                context.l10n.adminPanelTitle,
                style: theme.textTheme.displayLarge?.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              'Platform controls, partner workspaces, and operational oversight in one command surface.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: space.x6),
            CoolCard(
              backgroundColor: colors.operationalSurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin command',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x2),
                  Text(
                    access.hasPlatformAccess
                        ? 'Full platform visibility with audit, content, and workspace management.'
                        : 'Role-scoped access with only the surfaces assigned to your institution or partner.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x3),
                  _RoleBadgeRow(access: access),
                ],
              ),
            ),
            SizedBox(height: space.x6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.02,
              ),
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                return _AdminCard(section: section);
              },
            ),
            if (access.hasPlatformAccess) ...[
              SizedBox(height: space.x5),
              _SupportModeCard(),
            ],
          ],
        ),
      ),
    );
  }
}
