import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../models/admin_workspace_access.dart';
import '../providers/admin_providers.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

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
        l.adminVehicleTypes,
        Icons.directions_car_filled_rounded,
        '/admin/vehicle-types',
        l.adminVehicleTypesDesc,
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
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
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

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Semantics(
            button: true,
            label: context.l10n.backToProfile,
            child: IconButton(
              tooltip: context.l10n.back,
              icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
              onPressed: () => context.pop(),
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CoolLayout.horizontalPagePadding,
              0,
              CoolLayout.horizontalPagePadding,
              CoolLayout.gutter,
            ),
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
              const SizedBox(height: 8),
              Text(
                'Platform controls, partner workspaces, and operational oversight in one command surface.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
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
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 14),
                    _RoleBadgeRow(access: access),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
              // ── Support Mode card (platform admin only) ──────────
              if (access.hasPlatformAccess) ...[
                const SizedBox(height: 20),
                _SupportModeCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Role badge row — shows which roles the user has
// ═══════════════════════════════════════════════════════════════

class _RoleBadgeRow extends StatelessWidget {
  const _RoleBadgeRow({required this.access});
  final AdminWorkspaceAccess access;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final badges = <_RoleBadge>[
      if (access.hasPlatformAccess)
        _RoleBadge(context.l10n.platformAdmin, Colors.green),
      if (access.hasBankAdminAccess)
        _RoleBadge(context.l10n.bankAdmin, palette.blue),
      if (access.hasPartnerAdminAccess)
        _RoleBadge(context.l10n.rayonSports, Colors.purple),
    ];

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 10, runSpacing: 8, children: badges);
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Models & cards
// ═══════════════════════════════════════════════════════════════

class _AdminSection {
  const _AdminSection(
    this.title,
    this.icon,
    this.route,
    this.subtitle, {
    this.visibleTo,
  });
  final String title;
  final IconData icon;
  final String route;
  final String subtitle;

  /// Which roles can see this section.
  /// `null` means platform admin only (strictest default).
  final Set<AdminRole>? visibleTo;
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.section});
  final _AdminSection section;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      padding: const EdgeInsets.all(18),
      backgroundColor: colors.cardSurfaceStrong,
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(section.route);
      },
      semanticsLabel: '${section.title}. ${section.subtitle}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.operationalSurface,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: colors.border),
            ),
            child: Icon(section.icon, size: 22, color: colors.primaryText),
          ),
          const SizedBox(height: 14),
          Text(
            section.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              section.subtitle,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Support Mode — workspace impersonation
// ═══════════════════════════════════════════════════════════════

class _SupportModeCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _showSupportSheet(context, ref);
      },
      child: SizedBox(
        width: double.infinity,
        child: CoolCard(
          padding: const EdgeInsets.all(20),
          useGradient: true,
          gradient: LinearGradient(
            colors: [colors.analyticsSurface, colors.teamSurface],
          ),
          borderRadius: 28,
          borderColor: palette.blue.withValues(alpha: 0.3),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: palette.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  border: Border.all(
                    color: palette.blue.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  Icons.support_agent_rounded,
                  size: 24,
                  color: palette.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.adminSupportMode,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.adminSupportModeDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.text3, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showSupportSheet(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final partnersAsync = ref.read(adminPartnersProvider);

    showCoolBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final palette = sheetCtx.coolPalette;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.text3.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Icon(
                      Icons.support_agent_rounded,
                      color: palette.blue,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      context.l10n.adminSupportMode,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  context.l10n.adminSupportModeHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 24),
              Flexible(
                child: partnersAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      context.l10n.adminFailedToLoadPartners(e.toString()),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  data: (partners) {
                    if (partners.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(
                          context.l10n.adminNoPartnersFound,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
                      itemCount: partners.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (ctx, index) {
                        final p = partners[index];
                        final name =
                            p['name']?.toString() ?? context.l10n.unknown;
                        final id = p['id']?.toString() ?? '';
                        final type = p['partner_type']?.toString() ?? 'partner';
                        final isBank = type.toLowerCase().contains('bank');

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            tileColor: palette.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                color: palette.border,
                                width: 1.5,
                              ),
                            ),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: (isBank ? palette.blue : Colors.purple)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isBank
                                    ? Icons.account_balance_rounded
                                    : Icons.sports_soccer_rounded,
                                size: 20,
                                color: isBank ? palette.blue : Colors.purple,
                              ),
                            ),
                            title: Text(
                              name,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              type.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: palette.text3,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              size: 24,
                              color: palette.text3,
                            ),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(sheetCtx).pop();
                              final route = isBank
                                  ? AppRoutes.adminBankWorkspaceLocation(id)
                                  : AppRoutes.adminPartnerWorkspaceLocation(id);
                              context.push(route);
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
