import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../widgets/admin_workspace_gate.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_screen_background.dart';

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

    return CoolScreenBackground(
      showGlow: false,
      child: Scaffold(
        backgroundColor: colors.appBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: context.l10n.back,
            onPressed: () => context.go(AppRoutes.profile),
            icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          ),
        ),
        body: ListView(
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
            const SizedBox(height: CoolSpace.x6),
            _IntroCard(
              hasPlatformAccess: access.hasPlatformAccess,
              hasPartnerAccess: access.hasPartnerAdminAccess,
              hasBankAccess: access.hasBankAdminAccess,
            ),
            if (access.hasPlatformAccess) ...[
              const SizedBox(height: CoolSpace.x6),
              _SectionHeader(
                title: context.l10n.platform,
                subtitle: 'Global app operations content',
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
              const _SectionHeader(
                title: 'Partner Workspaces',
                subtitle: 'Partner-scoped admin surfaces for',
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
              const _SectionHeader(
                title: 'Bank Custodian Workspaces',
                subtitle: 'Group savings oversight ledgers',
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
                                    AppRoutes.adminBankWorkspaceLocation(
                                      bank.id,
                                    ),
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
    final roles = <String>[
      if (hasPlatformAccess) 'platform admin (full access to all workspaces)',
      if (!hasPlatformAccess && hasPartnerAccess) 'partner admin',
      if (!hasPlatformAccess && hasBankAccess) 'bank admin',
    ];
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
            'Roles: ${roles.join(', ')}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.inputSurface,
              borderRadius: _adminWorkspaceIconRadius,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primaryText, size: 22),
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
          const SizedBox(width: 12),
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
