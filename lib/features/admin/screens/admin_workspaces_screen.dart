import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_workspace_kit.dart';
import '../../../shared/widgets/dense_admin_workspace_scaffold.dart';
import '../models/admin_workspace_catalog.dart';
import '../providers/admin_providers.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../widgets/admin_workspace_gate.dart';
import '../../../core/l10n/l10n.dart';

class AdminWorkspacesScreen extends ConsumerWidget {
  const AdminWorkspacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminWorkspaceAccessProvider);
    final partnersAsync = ref.watch(adminPartnersProvider);

    if (!access.hasAnyAdminAccess) {
      return AdminAccessDeniedScaffold(
        title: context.l10n.adminWorkspaces,
        message: 'This account does not have admin workspace access.',
        fallbackLocation: AppRoutes.home,
      );
    }

    return DenseAdminWorkspaceScaffold(
      onBack: () => context.go(AppRoutes.profile),
      backTooltip: context.l10n.back,
      child: SingleChildScrollView(
        padding: CoolSpace.scaffoldPadding,
        child: Column(
          children: [
            AdminPageHeader(
              eyebrow: 'ADMIN ACCESS',
              title: 'Admin Workspaces',
              subtitle:
                  'Open the right control surface for platform or bank operations.',
              badges: [
                if (access.hasPlatformAccess)
                  const AdminStatusChip(
                    label: 'Platform Admin',
                    tone: AdminTone.success,
                    icon: Icons.admin_panel_settings_outlined,
                  ),
                if (access.hasBankAdminAccess)
                  const AdminStatusChip(
                    label: 'Bank Admin',
                    tone: AdminTone.accent,
                    icon: Icons.account_balance_outlined,
                  ),
              ],
            ),
            const SizedBox(height: CoolSpace.x4),
            AdminMetricStrip(
              metrics: [
                AdminMetricItem(
                  label: 'Visible workspaces',
                  value: access.hasPlatformAccess
                      ? '${2 + access.bankAdminIds.length}'
                      : '${access.bankAdminIds.length}',
                  hint: 'Operational entry points',
                  icon: Icons.dashboard_customize_outlined,
                  tone: AdminTone.info,
                ),
                AdminMetricItem(
                  label: 'Bank scopes',
                  value: '${access.bankAdminIds.length}',
                  hint: 'Scoped institutions',
                  icon: Icons.account_tree_outlined,
                  tone: AdminTone.warning,
                ),
              ],
            ),
            if (access.hasPlatformAccess) ...[
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: context.l10n.platform,
                subtitle:
                    'Global app operations, release controls, and oversight.',
                child: Column(
                  children: [
                    _WorkspaceTile(
                      title: 'Platform Admin',
                      subtitle:
                          'Users, services, content, roles, and operations.',
                      icon: Icons.admin_panel_settings_outlined,
                      onTap: () => context.push(AppRoutes.adminPlatform),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    _WorkspaceTile(
                      title: 'Savings & Groups',
                      subtitle:
                          'Centralized savings management, community groups, and allocations.',
                      icon: Icons.savings_outlined,
                      onTap: () => context.push(AppRoutes.adminSavings),
                    ),
                  ],
                ),
              ),
            ],
            if (access.hasBankAdminAccess) ...[
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: 'Bank Workspaces',
                subtitle: 'Allocation review, custody, and ledger exports.',
                child: partnersAsync.when(
                  data: (partners) {
                    final workspaces = buildBankAdminDestinations(
                      access: access,
                      partners: partners,
                    );
                    if (workspaces.isEmpty) {
                      return const Text('No bank workspace is assigned yet.');
                    }

                    return Column(
                      children: [
                        for (
                          var index = 0;
                          index < workspaces.length;
                          index++
                        ) ...[
                          _WorkspaceTile(
                            title: workspaces[index].title,
                            subtitle: workspaces[index].subtitle,
                            icon: workspaces[index].icon,
                            onTap: () => context.push(workspaces[index].route),
                          ),
                          if (index < workspaces.length - 1)
                            const SizedBox(height: CoolSpace.x2),
                        ],
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: CoolSpace.x2),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  error: (error, stackTrace) =>
                      const Text('Bank workspaces failed to load.'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return AdminPanelSurface(
      backgroundColor: colors.inputSurface,
      padding: const EdgeInsets.all(CoolSpace.x4),
      onTap: onTap,
      radius: CoolRadii.md,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primaryText, size: 20),
          ),
          const SizedBox(width: CoolSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: colors.tertiaryText,
          ),
        ],
      ),
    );
  }
}
