import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/dense_admin_workspace_scaffold.dart';
import '../../../shared/widgets/admin_section_header.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../widgets/admin_workspace_gate.dart';
import '../../../core/l10n/l10n.dart';

EdgeInsets _adminWorkspacesListPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: CoolSpace.x7);

EdgeInsets _adminWorkspaceCardSpacing() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

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
    final partnerWorkspacesAsync = ref.watch(adminPartnerWorkspacesProvider);
    final bankWorkspacesAsync = ref.watch(adminBankWorkspacesProvider);

    if (!access.hasAnyAdminAccess) {
      return AdminAccessDeniedScaffold(
        title: context.l10n.adminWorkspaces,
        message: 'This account does not',
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
          _IntroCard(
            hasPlatformAccess: access.hasPlatformAccess,
            hasPartnerAccess: access.hasPartnerAdminAccess,
            hasBankAccess: access.hasBankAdminAccess,
          ),
          if (access.hasPlatformAccess) ...[
            const SizedBox(height: CoolSpace.x6),
            AdminSectionHeader(
              title: context.l10n.platform,
              message: 'Global app operations content',
            ),
            const SizedBox(height: CoolSpace.x3),
            _WorkspaceCard(
              title: 'Platform Admin',
              subtitle: 'Users partners services app',
              icon: Icons.admin_panel_settings_outlined,
              onTap: () => context.push(AppRoutes.adminPlatform),
            ),
          ],
          if (access.hasPartnerAdminAccess) ...[
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Partner Workspaces',
              message: 'Partner-scoped admin surfaces for',
            ),
            const SizedBox(height: CoolSpace.x3),
            partnerWorkspacesAsync.when(
              data: (partners) => partners.isEmpty
                  ? const _EmptyWorkspaceCard(
                      message: 'No explicit partner workspace',
                    )
                  : Column(
                      children: partners
                          .map(
                            (partner) => Padding(
                              padding: _adminWorkspaceCardSpacing(),
                              child: _WorkspaceCard(
                                title: partner.name,
                                subtitle: partner.slug == 'rayon-sports'
                                    ? 'Open the current Rayon Sports admin workspace.'
                                    : 'Open the partner workspace foundation.',
                                icon: Icons.storefront_rounded,
                                onTap: () => context.push(
                                  partner.slug == 'rayon-sports'
                                      ? AppRoutes.adminRayon
                                      : AppRoutes.adminPartnerWorkspaceLocation(
                                          partner.id,
                                        ),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
              loading: () => const _InlineLoadingCard(
                message: 'Loading partner workspaces...',
              ),
              error: (error, _) => const _EmptyWorkspaceCard(
                message: 'Load partner workspaces failed',
              ),
            ),
          ],
          if (access.hasBankAdminAccess) ...[
            const SizedBox(height: CoolSpace.x6),
            const AdminSectionHeader(
              title: 'Bank Custodian Workspaces',
              message: 'Group savings oversight ledgers',
            ),
            const SizedBox(height: CoolSpace.x3),
            bankWorkspacesAsync.when(
              data: (banks) => banks.isEmpty
                  ? const _EmptyWorkspaceCard(
                      message: 'No explicit bank workspace',
                    )
                  : Column(
                      children: banks
                          .map(
                            (bank) => Padding(
                              padding: _adminWorkspaceCardSpacing(),
                              child: _WorkspaceCard(
                                title: bank.name,
                                subtitle: 'Open the bank custodian',
                                icon: Icons.account_balance_rounded,
                                onTap: () => context.push(
                                  AppRoutes.adminBankWorkspaceLocation(bank.id),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
              loading: () => const _InlineLoadingCard(
                message: 'Loading bank workspaces...',
              ),
              error: (error, _) => const _EmptyWorkspaceCard(
                message: 'Load bank workspaces failed',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.hasPlatformAccess,
    required this.hasPartnerAccess,
    required this.hasBankAccess,
  });

  final bool hasPlatformAccess;
  final bool hasPartnerAccess;
  final bool hasBankAccess;

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
              if (hasPartnerAccess)
                const _RoleChip(
                  label: 'Partner Admin',
                  color: Color(0xFF4AA4FF),
                ),
              if (hasBankAccess)
                const _RoleChip(label: 'Bank Admin', color: Color(0xFFC9A84C)),
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

class _InlineLoadingCard extends StatelessWidget {
  const _InlineLoadingCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyWorkspaceCard extends StatelessWidget {
  const _EmptyWorkspaceCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w500,
          color: colors.secondaryText,
          height: 1.4,
        ),
      ),
    );
  }
}
