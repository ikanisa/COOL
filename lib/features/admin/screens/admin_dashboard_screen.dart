import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/cool_layout.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../models/admin_workspace_access.dart';
import '../providers/admin_providers.dart';
import '../providers/admin_workspace_access_provider.dart';

/// Admin Dashboard — role-filtered card grid for admin management screens.
///
/// Platform admins see every card. Bank admins see only bank-related cards.
/// Rayon Sport admins see only Rayon-related cards.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  /// All available admin sections with role visibility tags.
  /// `null` roles means platform-admin-only (default).
  static const _allSections = [
    _AdminSection(
      'Users',
      Icons.person_rounded,
      '/admin/users',
      'Inspect profiles and demo batches',
    ),
    _AdminSection(
      'Partners',
      Icons.handshake_rounded,
      '/admin/partners',
      'Manage partner profiles',
    ),
    _AdminSection(
      'Services',
      Icons.assignment_rounded,
      '/admin/services',
      'Partner service offerings',
    ),
    _AdminSection(
      'Quick Actions',
      Icons.bolt_rounded,
      '/admin/quick-actions',
      'Home screen cards',
    ),
    _AdminSection(
      'Vehicle Types',
      Icons.directions_car_filled_rounded,
      '/admin/vehicle-types',
      'Mobility filter chips',
    ),
    _AdminSection(
      'App Config',
      Icons.settings_rounded,
      '/admin/app-config',
      'Key-value settings',
    ),
    _AdminSection(
      'Operations',
      Icons.monitor_heart_rounded,
      '/admin/operations',
      'Release health and triage',
    ),
    _AdminSection(
      'Rayon Sports',
      Icons.sports_soccer_rounded,
      '/admin/rayon',
      'Matches, tickets, shop, members',
      visibleTo: {AdminRole.admin, AdminRole.rayonSport},
    ),
    _AdminSection(
      'Special Products',
      Icons.star_rounded,
      '/admin/special-products',
      'Buri Munsi and savings cards',
      visibleTo: {AdminRole.admin, AdminRole.bank},
    ),
    _AdminSection(
      'Missions',
      Icons.flag_rounded,
      '/admin/missions',
      'Create & manage cooperative missions',
    ),
    _AdminSection(
      'Seasons',
      Icons.emoji_events_rounded,
      '/admin/seasons',
      'Live-ops campaigns & rewards',
    ),
    _AdminSection(
      'Activities',
      Icons.local_fire_department_rounded,
      '/admin/activities',
      'Token-earning gamification activities',
    ),
    _AdminSection(
      'Admin Roles',
      Icons.admin_panel_settings_rounded,
      '/admin/roles',
      'Assign & manage admin access',
    ),
    _AdminSection(
      'System Analytics',
      Icons.analytics_rounded,
      '/admin/analytics',
      'Platform-wide metrics & trends',
    ),
    _AdminSection(
      'AI Content',
      Icons.auto_awesome_rounded,
      '/admin/ai-content',
      'AI-generated UI with approval gate',
    ),
    _AdminSection(
      'Audit Log',
      Icons.history_rounded,
      '/admin/audit-log',
      'Who did what, when',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final access = ref.watch(adminWorkspaceAccessProvider);

    // Filter sections based on user's role
    final sections = _allSections.where((section) {
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
    }).toList(growable: false);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Back to profile',
          child: IconButton(
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_rounded, color: palette.text),
            onPressed: () => context.pop(),
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CoolLayout.horizontalPagePadding,
              0,
              CoolLayout.horizontalPagePadding,
              CoolLayout.gutter,
            ),
            children: [
              Text(
                'Admin Panel',
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 12),
              _RoleBadgeRow(access: access),
              const SizedBox(height: 24),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
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
        const _RoleBadge('Platform Admin', Colors.green),
      if (access.hasBankAdminAccess)
        _RoleBadge('Bank Admin', palette.blue),
      if (access.hasPartnerAdminAccess)
        const _RoleBadge('Rayon Sport', Colors.purple),
    ];

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: badges,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    return CoolCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(section.route);
      },
      semanticsLabel: '${section.title}. ${section.subtitle}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(section.icon, size: 20, color: palette.text2),
          ),
          const SizedBox(height: 10),
          Text(
            section.title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Text(
              section.subtitle,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.text3,
                  ),
              maxLines: 2,
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _showSupportSheet(context, ref);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.blue.withValues(alpha: 0.12),
              Colors.purple.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border:
              Border.all(color: palette.blue.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: palette.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
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
                    'Support Mode',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Open a bank or rayon workspace as support',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.text3, size: 24),
          ],
        ),
      ),
    );
  }

  void _showSupportSheet(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.read(adminPartnersProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final palette = sheetCtx.coolPalette;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
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
                    Icon(Icons.support_agent_rounded,
                        color: palette.blue, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Support Mode',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'Navigate into a partner workspace to view and manage it as support.',
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
                      'Failed to load partners: $e',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  data: (partners) {
                    if (partners.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(
                          'No partners found',
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
                        final name = p['name']?.toString() ?? 'Unknown';
                        final id = p['id']?.toString() ?? '';
                        final type = p['partner_type']?.toString() ?? 'partner';
                        final isBank = type.toLowerCase().contains('bank');

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 8),
                            tileColor: palette.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side:
                                  BorderSide(color: palette.border, width: 1.5),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            subtitle: Text(
                              type.toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
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

