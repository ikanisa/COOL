import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/dense_admin_workspace_scaffold.dart';
import '../../../shared/widgets/admin_section_header.dart';
import '../../partners/models/partner.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../widgets/admin_workspace_gate.dart';
import '../../../core/l10n/l10n.dart';

EdgeInsets _adminWorkspacesListPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: CoolSpace.x7);

const BorderRadius _adminWorkspaceIconRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

class AdminWorkspacesScreen extends ConsumerWidget {
  const AdminWorkspacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final access = ref.watch(adminWorkspaceAccessProvider);
    final partnerWorkspaces = ref.watch(adminPartnerWorkspacesProvider);
    final bankWorkspaces = ref.watch(adminBankWorkspacesProvider);
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
      child: ListView(
        padding: _adminWorkspacesListPadding(),
        children: [
          Text(
            'Admin Workspaces',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
              height: 1.1,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Open the right control surface for platform, partner, or bank operations.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          _IntroCard(hasPlatformAccess: access.hasPlatformAccess),
          if (access.hasPartnerAdminAccess) ...[
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Partner Workspaces',
              message: 'Scoped partner operations assigned to this account.',
            ),
            const SizedBox(height: CoolSpace.x3),
            _WorkspaceCollection(
              asyncPartners: partnerWorkspaces,
              emptyLabel: 'No partner workspaces assigned.',
              onTap: (partner) => context.push(
                AppRoutes.adminPartnerWorkspaceLocation(partner.id),
              ),
            ),
          ],
          if (access.hasBankAdminAccess) ...[
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Bank Custodian Workspaces',
              message: 'Scoped bank operations assigned to this account.',
            ),
            const SizedBox(height: CoolSpace.x3),
            _WorkspaceCollection(
              asyncPartners: bankWorkspaces,
              emptyLabel: 'No bank workspaces assigned.',
              onTap: (partner) => context.push(
                AppRoutes.adminBankWorkspaceLocation(partner.id),
              ),
            ),
          ],
          if (access.hasPlatformAccess) ...[
            const SizedBox(height: CoolSpace.x6),
            AdminSectionHeader(
              title: context.l10n.platform,
              message: 'Global app operations and release controls.',
            ),
            const SizedBox(height: CoolSpace.x3),
            _WorkspaceCard(
              title: 'Platform Admin',
              subtitle: 'Users, services, content, roles, and operations.',
              icon: Icons.admin_panel_settings_outlined,
              onTap: () => context.push(AppRoutes.adminPlatform),
            ),
            const SizedBox(height: CoolSpace.x3),
            _WorkspaceCard(
              title: 'Rayon Sports',
              subtitle: 'Matches, tickets, shop, membership, and engagement.',
              icon: Icons.sports_soccer_rounded,
              onTap: () => context.push(AppRoutes.adminRayon),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.hasPlatformAccess});

  final bool hasPlatformAccess;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Open the right workspace',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Verified access is active for this account.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Wrap(
            spacing: CoolSpace.x2,
            runSpacing: CoolSpace.x2,
            children: [
              if (hasPlatformAccess)
                const _RoleChip(
                  label: 'Platform Admin',
                  color: Color(0xFF2ECC71),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: context.coolText.mono(
          Theme.of(context).textTheme.labelSmall,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _WorkspaceCollection extends StatelessWidget {
  const _WorkspaceCollection({
    required this.asyncPartners,
    required this.emptyLabel,
    required this.onTap,
  });

  final AsyncValue<List<Partner>> asyncPartners;
  final String emptyLabel;
  final void Function(Partner partner) onTap;

  @override
  Widget build(BuildContext context) {
    return asyncPartners.when(
      data: (partners) {
        if (partners.isEmpty) {
          return Text(emptyLabel);
        }

        return Column(
          children: [
            for (var index = 0; index < partners.length; index++) ...[
              _WorkspaceCard(
                title: partners[index].name,
                subtitle:
                    partners[index].subtitle ??
                    '${partners[index].country} · ${partners[index].category.dbValue}',
                icon: partners[index].isBank
                    ? Icons.account_balance_rounded
                    : Icons.sports_soccer_rounded,
                onTap: () => onTap(partners[index]),
              ),
              if (index != partners.length - 1)
                const SizedBox(height: CoolSpace.x3),
            ],
          ],
        );
      },
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, _) => Text(emptyLabel),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
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
    return CoolCard(
      onTap: onTap,
      semanticsLabel: '$title workspace. $subtitle',
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.highlightColor.withValues(alpha: 0.04),
              borderRadius: _adminWorkspaceIconRadius,
              border: Border.all(color: colors.border),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primaryText, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.secondaryText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.highlightColor.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(CoolRadii.sm),
              border: Border.all(color: colors.border),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }
}
