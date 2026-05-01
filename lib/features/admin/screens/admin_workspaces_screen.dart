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
        message: context.l10n.adminWorkspacesNoAccess,
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
              eyebrow: context.l10n.adminWorkspacesEyebrow,
              title: context.l10n.adminWorkspacesTitle,
              subtitle: context.l10n.adminWorkspacesSubtitle,
              badges: [
                if (access.hasPlatformAccess)
                  AdminStatusChip(
                    label: context.l10n.adminWorkspacesLabelPlatformAdmin,
                    tone: AdminTone.success,
                    icon: CoolIcons.adminPanel,
                  ),
                if (access.hasBankAdminAccess)
                  AdminStatusChip(
                    label: context.l10n.adminWorkspacesLabelBankAdmin,
                    tone: AdminTone.accent,
                    icon: CoolIcons.accountBalanceOutlined,
                  ),
              ],
            ),
            const SizedBox(height: CoolSpace.x4),
            AdminMetricStrip(
              metrics: [
                AdminMetricItem(
                  label: context.l10n.adminWorkspacesLabelVisible,
                  value: access.hasPlatformAccess
                      ? '${2 + access.bankAdminIds.length}'
                      : '${access.bankAdminIds.length}',
                  hint: context.l10n.adminWorkspacesHintEntryPoints,
                  icon: CoolIcons.dashboardCustomize,
                  tone: AdminTone.info,
                ),
                AdminMetricItem(
                  label: context.l10n.adminWorkspacesLabelBankScopes,
                  value: '${access.bankAdminIds.length}',
                  hint: context.l10n.adminWorkspacesHintScopedInstitutions,
                  icon: CoolIcons.accountTree,
                  tone: AdminTone.warning,
                ),
              ],
            ),
            if (access.hasPlatformAccess) ...[
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: context.l10n.platform,
                subtitle: context.l10n.adminWorkspacesPlatformDesc,
                child: Column(
                  children: [
                    _WorkspaceTile(
                      title: context.l10n.adminWorkspacesPlatformTitle,
                      subtitle: context.l10n.adminWorkspacesPlatformSubtitle,
                      icon: CoolIcons.adminPanel,
                      onTap: () => context.push(AppRoutes.adminPlatform),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    _WorkspaceTile(
                      title: context.l10n.adminWorkspacesSavingsTitle,
                      subtitle: context.l10n.adminWorkspacesSavingsSubtitle,
                      icon: CoolIcons.savingsOutlined,
                      onTap: () => context.push(AppRoutes.adminSavings),
                    ),
                  ],
                ),
              ),
            ],
            if (access.hasBankAdminAccess) ...[
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: context.l10n.adminWorkspacesBankTitle,
                subtitle: context.l10n.adminWorkspacesBankSubtitle,
                child: partnersAsync.when(
                  data: (partners) {
                    final workspaces = buildBankAdminDestinations(
                      access: access,
                      partners: partners,
                    );
                    if (workspaces.isEmpty) {
                      return Text(context.l10n.adminWorkspacesEmptyBank);
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
                      Text(context.l10n.adminWorkspacesBankLoadFailed),
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
            CoolIcons.arrowForward,
            size: 18,
            color: colors.tertiaryText,
          ),
        ],
      ),
    );
  }
}
