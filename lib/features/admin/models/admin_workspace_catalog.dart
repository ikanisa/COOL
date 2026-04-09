import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import 'admin_workspace_access.dart';

enum AdminWorkspaceKind { platform, bank }

class AdminWorkspaceDestination {
  const AdminWorkspaceDestination({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    this.scopeId,
  });

  final AdminWorkspaceKind kind;
  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  final String? scopeId;
}

List<AdminWorkspaceDestination> buildPlatformAdminDestinations(
  BuildContext context,
) {
  final l10n = context.l10n;
  return <AdminWorkspaceDestination>[
    AdminWorkspaceDestination(
      kind: AdminWorkspaceKind.platform,
      title: l10n.adminUsers,
      subtitle: l10n.adminUsersDesc,
      route: AppRoutes.adminUsers,
      icon: Icons.person_rounded,
    ),
    AdminWorkspaceDestination(
      kind: AdminWorkspaceKind.platform,
      title: l10n.adminAppConfig,
      subtitle: l10n.adminAppConfigDesc,
      route: AppRoutes.adminAppConfig,
      icon: Icons.settings_rounded,
    ),
    AdminWorkspaceDestination(
      kind: AdminWorkspaceKind.platform,
      title: l10n.adminOperations,
      subtitle: l10n.adminReleaseDesc,
      route: AppRoutes.adminOperations,
      icon: Icons.monitor_heart_rounded,
    ),
    AdminWorkspaceDestination(
      kind: AdminWorkspaceKind.platform,
      title: l10n.adminAdminRoles,
      subtitle: l10n.adminAdminRolesDesc,
      route: AppRoutes.adminRoles,
      icon: Icons.admin_panel_settings_rounded,
    ),
    AdminWorkspaceDestination(
      kind: AdminWorkspaceKind.platform,
      title: l10n.adminSystemAnalytics,
      subtitle: l10n.adminSystemAnalyticsDesc,
      route: AppRoutes.adminAnalytics,
      icon: Icons.analytics_rounded,
    ),
    AdminWorkspaceDestination(
      kind: AdminWorkspaceKind.platform,
      title: l10n.adminAuditLog,
      subtitle: l10n.adminAuditLogDesc,
      route: AppRoutes.adminAuditLog,
      icon: Icons.history_rounded,
    ),
    const AdminWorkspaceDestination(
      kind: AdminWorkspaceKind.platform,
      title: 'Groups',
      subtitle: 'View contribution groups, members, and wallet routing.',
      route: AppRoutes.adminGroups,
      icon: Icons.groups_rounded,
    ),
  ];
}

List<AdminWorkspaceDestination> buildBankAdminDestinations({
  required AdminWorkspaceAccess access,
  required List<Map<String, dynamic>> partners,
}) {
  final visibleBankPartners = partners
      .where((partner) {
        final id = partner['id']?.toString().trim() ?? '';
        final category =
            partner['category']?.toString().trim().toLowerCase() ?? '';
        if (id.isEmpty || category != 'bank') {
          return false;
        }
        return access.hasPlatformAccess || access.bankAdminIds.contains(id);
      })
      .toList(growable: false);

  final destinations = visibleBankPartners
      .map(
        (partner) => AdminWorkspaceDestination(
          kind: AdminWorkspaceKind.bank,
          title: partner['name']?.toString().trim().isNotEmpty == true
              ? partner['name'].toString().trim()
              : 'Bank workspace',
          subtitle: 'Manual review, ledgers, and custody operations.',
          route: AppRoutes.adminBankWorkspaceLocation(
            partner['id']!.toString(),
          ),
          icon: Icons.account_balance_rounded,
          scopeId: partner['id']?.toString(),
        ),
      )
      .toList(growable: true);

  if (!access.hasPlatformAccess) {
    final knownIds = visibleBankPartners
        .map((partner) => partner['id']?.toString())
        .whereType<String>()
        .toSet();
    for (final bankId in access.bankAdminIds) {
      if (knownIds.contains(bankId)) {
        continue;
      }
      destinations.add(
        AdminWorkspaceDestination(
          kind: AdminWorkspaceKind.bank,
          title: 'Bank $bankId',
          subtitle: 'Manual review, ledgers, and custody operations.',
          route: AppRoutes.adminBankWorkspaceLocation(bankId),
          icon: Icons.account_balance_rounded,
          scopeId: bankId,
        ),
      );
    }
  }

  destinations.sort(
    (left, right) =>
        left.title.toLowerCase().compareTo(right.title.toLowerCase()),
  );
  return destinations;
}
