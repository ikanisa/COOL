part of 'admin_dashboard_screen.dart';

EdgeInsets _adminRoleBadgePadding() => CoolSpace.denseSectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _supportSheetHorizontalPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _supportSheetListPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: CoolSpace.x7);

EdgeInsets _supportSheetTilePadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x4,
  right: CoolSpace.x4,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

Widget _supportSheetHandle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Container(
    width: 44,
    height: 4,
    decoration: BoxDecoration(
      color: colors.tertiaryText.withValues(alpha: 0.28),
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// Role badge row — shows which roles the user has
// ═══════════════════════════════════════════════════════════════

class _RoleBadgeRow extends StatelessWidget {
  const _RoleBadgeRow({required this.access});
  final AdminWorkspaceAccess access;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final badges = <_RoleBadge>[
      if (access.hasPlatformAccess)
        _RoleBadge(context.l10n.platformAdmin, colors.success),
      if (access.hasBankAdminAccess)
        _RoleBadge(context.l10n.bankAdmin, colors.info),
      if (access.hasPartnerAdminAccess)
        _RoleBadge(context.l10n.rayonSports, colors.accent),
    ];

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: CoolSpace.x3,
      runSpacing: CoolSpace.x2,
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
    final theme = Theme.of(context);
    return Container(
      padding: _adminRoleBadgePadding(),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      padding: CoolSpace.sectionPadding,
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
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.md),
              ),
              border: Border.all(color: colors.border),
            ),
            child: Icon(section.icon, size: 22, color: colors.primaryText),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            section.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CoolSpace.x2),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    return SizedBox(
      width: double.infinity,
      child: CoolCard(
        onTap: () {
          HapticFeedback.selectionClick();
          _showSupportSheet(context, ref);
        },
        semanticsLabel:
            '${context.l10n.adminSupportMode}. ${context.l10n.adminSupportModeDesc}',
        padding: CoolSpace.denseSectionPadding,
        useGradient: true,
        gradient: LinearGradient(
          colors: [colors.analyticsSurface, colors.teamSurface],
        ),
        borderRadius: CoolRadii.lg,
        borderColor: colors.info.withValues(alpha: 0.32),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.info.withValues(alpha: 0.16),
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.md),
                ),
                border: Border.all(color: colors.info.withValues(alpha: 0.22)),
              ),
              child: Icon(
                Icons.support_agent_rounded,
                size: 24,
                color: colors.info,
              ),
            ),
            SizedBox(width: space.x4),
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
                  const SizedBox(height: CoolSpace.x1),
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
            Icon(
              Icons.chevron_right_rounded,
              color: colors.tertiaryText,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _showSupportSheet(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.read(adminPartnersProvider);

    showCoolBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final colors = sheetCtx.coolSemanticColors;
        final theme = Theme.of(sheetCtx);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.overlaySurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CoolRadii.xl),
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: CoolSpace.x4),
                _supportSheetHandle(sheetCtx),
                const SizedBox(height: CoolSpace.x6),
                Padding(
                  padding: _supportSheetHorizontalPadding(),
                  child: Row(
                    children: [
                      Icon(
                        Icons.support_agent_rounded,
                        color: colors.info,
                        size: 22,
                      ),
                      const SizedBox(width: CoolSpace.x3),
                      Text(
                        context.l10n.adminSupportMode,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CoolSpace.x2),
                Padding(
                  padding: _supportSheetHorizontalPadding(),
                  child: Text(
                    context.l10n.adminSupportModeHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
                Flexible(
                  child: partnersAsync.when(
                    loading: () => Padding(
                      padding: CoolSpace.sectionPadding.copyWith(
                        top: CoolSpace.x7,
                        bottom: CoolSpace.x7,
                      ),
                      child: CircularProgressIndicator(color: colors.accent),
                    ),
                    error: (e, _) => Padding(
                      padding: CoolSpace.sectionPadding,
                      child: Text(
                        context.l10n.adminFailedToLoadPartners(e.toString()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                    data: (partners) {
                      if (partners.isEmpty) {
                        return Padding(
                          padding: CoolSpace.sectionPadding,
                          child: Text(
                            context.l10n.adminNoPartnersFound,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        padding: _supportSheetListPadding(),
                        itemCount: partners.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: CoolSpace.x3),
                        itemBuilder: (ctx, index) {
                          final p = partners[index];
                          final name =
                              p['name']?.toString() ?? context.l10n.unknown;
                          final id = p['id']?.toString() ?? '';
                          final type =
                              p['partner_type']?.toString() ?? 'partner';
                          final isBank = type.toLowerCase().contains('bank');
                          final iconTone = isBank
                              ? colors.info
                              : colors.primaryText;
                          final iconSurface = isBank
                              ? colors.info.withValues(alpha: 0.14)
                              : colors.teamSurface;

                          return ListTile(
                            contentPadding: _supportSheetTilePadding(),
                            tileColor: colors.operationalSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(CoolRadii.sm),
                              ),
                              side: BorderSide(
                                color: colors.border,
                                width: 1.3,
                              ),
                            ),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: iconSurface,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(CoolRadii.xs),
                                ),
                              ),
                              child: Icon(
                                isBank
                                    ? Icons.account_balance_rounded
                                    : Icons.sports_soccer_rounded,
                                size: 20,
                                color: iconTone,
                              ),
                            ),
                            title: Text(
                              name,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              type.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.tertiaryText,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              size: 24,
                              color: colors.tertiaryText,
                            ),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(sheetCtx).pop();
                              final route = isBank
                                  ? AppRoutes.adminBankWorkspaceLocation(id)
                                  : AppRoutes.adminPartnerWorkspaceLocation(id);
                              context.push(route);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
