import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../partners/models/partner.dart';
import '../../partners/providers/partner_provider.dart';
import '../widgets/admin_workspace_gate.dart';

class PartnerAdminWorkspaceScreen extends ConsumerWidget {
  const PartnerAdminWorkspaceScreen({required this.partnerId, super.key});

  final String partnerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PartnerAdminGate(
      partnerId: partnerId,
      child: ref
          .watch(partnerByIdProvider(partnerId))
          .when(
            data: (partner) {
              if (partner?.slug == 'rayon-sports') {
                return const RayonAdminGate(child: _RayonForwardingView());
              }

              return _PartnerWorkspacePlaceholder(partner: partner);
            },
            loading: () =>
                AdminLoadingScaffold(title: context.l10n.partnerAdmin),
            error: (_, _) => AdminAccessDeniedScaffold(
              title: context.l10n.partnerAdmin,
              message:
                  'The partner workspace could not be loaded. Please try again.',
            ),
          ),
    );
  }
}

class _PartnerWorkspacePlaceholder extends StatelessWidget {
  const _PartnerWorkspacePlaceholder({required this.partner});

  final Partner? partner;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final resolvedPartner = partner;
    final title = resolvedPartner?.name ?? 'Partner Admin';
    final description =
        resolvedPartner?.description ??
        resolvedPartner?.subtitle ??
        'Partner-specific controls are being standardized onto the new executive admin system.';

    return _PartnerWorkspaceShell(
      appBarTitle: resolvedPartner == null ? context.l10n.partnerAdmin : title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.displaySmall?.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Workspace launch sequence',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.accent,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          CoolCard(
            backgroundColor: colors.cardSurfaceStrong,
            borderColor: colors.borderStrong,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _partnerSurfaceFor(
                          colors,
                          resolvedPartner?.category,
                        ),
                        borderRadius: BorderRadius.circular(CoolRadii.lg),
                        border: Border.all(color: colors.borderStrong),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        resolvedPartner?.emoji ?? '🤝',
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                    const SizedBox(width: CoolSpace.x4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dedicated partner command center',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: colors.primaryText,
                            ),
                          ),
                          const SizedBox(height: CoolSpace.x2),
                          Text(
                            description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x6),
                Wrap(
                  spacing: CoolSpace.x3,
                  runSpacing: CoolSpace.x3,
                  children: [
                    _WorkspaceSignal(
                      label: 'Category',
                      value: _categoryLabelFor(resolvedPartner?.category),
                    ),
                    _WorkspaceSignal(
                      label: 'Country',
                      value: resolvedPartner?.country ?? 'RW',
                    ),
                    _WorkspaceSignal(
                      label: 'Status',
                      value: resolvedPartner?.isActive ?? true
                          ? 'Active partner'
                          : 'Inactive partner',
                    ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(CoolSpace.x5),
                  decoration: BoxDecoration(
                    color: colors.operationalSurface,
                    borderRadius: BorderRadius.circular(CoolRadii.md),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'This workspace will inherit the shared admin shell, role-aware navigation, analytics panels, and action modules instead of introducing a one-off partner interface.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
                CoolButton(
                  label: 'Back to workspaces',
                  variant: CoolButtonVariant.secondary,
                  onTap: () => context.go(AppRoutes.admin),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RayonForwardingView extends StatelessWidget {
  const _RayonForwardingView();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return _PartnerWorkspaceShell(
      appBarTitle: 'Partner Admin',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rayon Sports Admin',
            style: theme.textTheme.displaySmall?.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Dedicated command routing',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.accent,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          CoolCard(
            backgroundColor: colors.cardSurfaceStrong,
            borderColor: colors.borderStrong,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: colors.accentGradient,
                    borderRadius: BorderRadius.circular(CoolRadii.lg),
                    border: Border.all(
                      color: colors.highlightColor.withValues(alpha: 0.16),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: CoolSpace.x5),
                Text(
                  'Rayon Sports uses its own executive control surface for tickets, finance, shop, members, and club operations.',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x3),
                Text(
                  'Open the dedicated Rayon workspace to manage fixtures, payment routing, supporters, and commercial operations with the new shared admin language.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
                const Wrap(
                  spacing: CoolSpace.x3,
                  runSpacing: CoolSpace.x3,
                  children: [
                    _WorkspaceSignal(label: 'Scope', value: 'Matches'),
                    _WorkspaceSignal(label: 'Scope', value: 'Members'),
                    _WorkspaceSignal(label: 'Scope', value: 'Finance'),
                  ],
                ),
                const SizedBox(height: CoolSpace.x6),
                CoolButton(
                  label: context.l10n.openRayonSportsAdmin,
                  onTap: () => context.go(AppRoutes.adminRayon),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSignal extends StatelessWidget {
  const _WorkspaceSignal({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x4,
        vertical: CoolSpace.x3,
      ),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        border: Border.all(color: colors.border),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label · ',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.secondaryText,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerWorkspaceShell extends StatelessWidget {
  const _PartnerWorkspaceShell({required this.appBarTitle, required this.body});

  final String appBarTitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolScreenBackground(
      showGlow: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: colors.primaryText),
          title: Text(
            appBarTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: CoolSpace.pagePadding,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _categoryLabelFor(PartnerCategory? category) {
  return switch (category) {
    PartnerCategory.bank => 'Banking',
    PartnerCategory.football => 'Club',
    PartnerCategory.organization => 'Organization',
    null => 'Partner',
  };
}

Color _partnerSurfaceFor(CoolSemanticColors colors, PartnerCategory? category) {
  return switch (category) {
    PartnerCategory.bank => colors.financialSurface,
    PartnerCategory.football => colors.teamSurface,
    PartnerCategory.organization => colors.operationalSurface,
    null => colors.cardSurface,
  };
}
