part of '../screens/partners_screen.dart';

class _FootballTab extends ConsumerWidget {
  const _FootballTab({required this.onOpenRayonSports});

  final VoidCallback onOpenRayonSports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final partnersAsync = ref.watch(footballPartnersProvider);

    return partnersAsync.when(
      loading: () =>
          _LoadingState(title: l10n.loading, message: 'Loading partners…'),
      error: (error, _) => _ErrorState(
        error: error.toString(),
        onRetry: () => ref.invalidate(footballPartnersProvider),
      ),
      data: (partners) {
        if (partners.isEmpty) {
          return const _EmptyState(label: 'No football partners yet');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < partners.length; index++) ...[
              if (index > 0) const SizedBox(height: 18),
              _FootballHeroCard(
                partner: partners[index],
                onTap: partners[index].slug == 'rayon-sports'
                    ? onOpenRayonSports
                    : () {
                        CoolToast.info(
                          context,
                          '${partners[index].name} will be available soon.',
                        );
                      },
              ),
              if (index == 0) ...[
                const SizedBox(height: 18),
                const SectionTitle(title: 'Featured experiences'),
                const SizedBox(height: 10),
                _ResponsiveFeatureGrid(
                  items: [
                    _FeatureTileData(
                      key: const ValueKey('partner_feature_fan_registry'),
                      icon: Icons.people_rounded,
                      title: l10n.fanRegistry,
                      subtitle: l10n.fansCount(partners[index].fanCount),
                      onTap: () => context.push(AppRoutes.rayonRegistry),
                    ),
                    _FeatureTileData(
                      key: const ValueKey('partner_feature_fan_clubs'),
                      icon: Icons.groups_rounded,
                      title: l10n.fanClubs,
                      subtitle: l10n.clubsCount(partners[index].clubCount),
                      onTap: () => context.push(AppRoutes.rayonClubs),
                    ),
                    _FeatureTileData(
                      key: const ValueKey('partner_feature_ticketing'),
                      icon: Icons.confirmation_number_rounded,
                      title: l10n.ticketing,
                      subtitle: l10n.gamesCount(partners[index].gameCount),
                      onTap: () => context.push(AppRoutes.rayonTickets),
                    ),
                    _FeatureTileData(
                      key: const ValueKey('partner_feature_club_shop'),
                      icon: Icons.shopping_bag_rounded,
                      title: l10n.clubShop,
                      subtitle: 'Jerseys fan gear and',
                      onTap: () => context.push(AppRoutes.rayonShop),
                    ),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _FootballHeroCard extends StatelessWidget {
  const _FootballHeroCard({required this.partner, required this.onTap});

  final Partner partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final isRayon = partner.slug == 'rayon-sports';
    return Semantics(
      button: true,
      label: 'Open ${partner.name}',
      child: CoolCard(
        onTap: onTap,
        semanticsLabel: 'Open ${partner.name}',
        gradient: isRayon
            ? RsColors.rsHeroGradient
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  colors.analyticsSurface,
                  colors.cardSurfaceStrong,
                ],
              ),
        borderColor: isRayon ? RsColors.rsBlueBorder : colors.borderStrong,
        child: Stack(
          children: [
            Positioned(
              right: -5,
              top: 8,
              child: Icon(
                IconMapper.from(partner.emoji),
                size: 60,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isRayon
                          ? RsColors.rsGold.withValues(alpha: 0.18)
                          : colors.info.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isRayon
                            ? RsColors.rsGold.withValues(alpha: 0.4)
                            : colors.info.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          IconMapper.from(partner.emoji),
                          size: 13,
                          color: isRayon ? RsColors.rsGoldLight : colors.info,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isRayon ? 'Rayon hub' : context.l10n.officialPartner,
                          style: text.rayon(
                            theme.textTheme.labelMedium,
                            fontWeight: FontWeight.w700,
                            color: isRayon ? RsColors.rsGoldLight : colors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x3),
                  Text(
                    partner.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x1),
                  Text(
                    partner.subtitle ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _stat(
                        context: context,
                        value: _formatCompactCount(partner.fanCount),
                        label: context.l10n.fansTitle,
                        valueColor: isRayon
                            ? RsColors.rsGoldLight
                            : colors.info,
                        labelColor: colors.tertiaryText,
                      ),
                      _divider(colors.borderStrong),
                      _stat(
                        context: context,
                        value: partner.clubCount.toString(),
                        label: context.l10n.fanClubs,
                        valueColor: isRayon
                            ? RsColors.rsGoldLight
                            : colors.info,
                        labelColor: colors.tertiaryText,
                      ),
                      _divider(colors.borderStrong),
                      _stat(
                        context: context,
                        value: partner.gameCount.toString(),
                        label: 'Games',
                        valueColor: isRayon
                            ? RsColors.rsGoldLight
                            : colors.info,
                        labelColor: colors.tertiaryText,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat({
    required BuildContext context,
    required String value,
    required String label,
    required Color valueColor,
    required Color labelColor,
  }) {
    final text = context.coolText;
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: text.mono(
              theme.textTheme.titleLarge,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          Text(
            label,
            style: text.rayon(
              theme.textTheme.labelMedium,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(Color color) {
    return Container(width: 1, height: 28, color: color);
  }

  static String _formatCompactCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      onTap: onTap,
      semanticsLabel: title,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
              alignment: Alignment.center,
              child: Icon(icon, size: 26, color: colors.primaryText),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: CoolSpace.x1),
            Expanded(
              child: Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFeatureGrid extends StatelessWidget {
  const _ResponsiveFeatureGrid({required this.items});

  final List<_FeatureTileData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 860 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: constraints.maxWidth >= 860 ? 1.1 : 0.92,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _FeatureTile(
              key: item.key,
              icon: item.icon,
              title: item.title,
              subtitle: item.subtitle,
              onTap: item.onTap,
            );
          },
        );
      },
    );
  }
}

class _FeatureTileData {
  const _FeatureTileData({
    this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final Key? key;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}

class _BanksTab extends ConsumerWidget {
  const _BanksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final partnersAsync = ref.watch(bankPartnersProvider);

    return partnersAsync.when(
      loading: () =>
          _LoadingState(title: l10n.loading, message: 'Loading partners…'),
      error: (error, _) => _ErrorState(
        error: error.toString(),
        onRetry: () => ref.invalidate(bankPartnersProvider),
      ),
      data: (partners) {
        if (partners.isEmpty) {
          return const _EmptyState(label: 'No finance partners yet');
        }

        return Column(
          children: [
            CoolCard(
              backgroundColor: colors.financialSurface,
              borderColor: colors.info.withValues(alpha: 0.24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bank custody for group savings',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  CoolButton(
                    label: 'Create group savings',
                    icon: Icons.savings_rounded,
                    onTap: () => context.push(AppRoutes.groupCreate),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
            for (var index = 0; index < partners.length; index++) ...[
              if (index > 0) const SizedBox(height: CoolSpace.x3),
              _BankPartnerCard(partner: partners[index]),
            ],
          ],
        );
      },
    );
  }
}

class _BankPartnerCard extends StatelessWidget {
  const _BankPartnerCard({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Open ${partner.name}',
      child: CoolCard(
        onTap: () => context.push('/partners/${partner.slug}'),
        semanticsLabel: 'Open ${partner.name}',
        gradient: colors.accentGradient,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colors.accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        context.l10n.bankingPartner,
                        style: text.rayon(
                          theme.textTheme.labelMedium,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  PartnerBrandMark(
                    partner: partner,
                    width: 122,
                    height: 58,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x3),
              Text(
                partner.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                partner.subtitle ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _bankStat(
                    context: context,
                    value: partner.fanCount > 0
                        ? partner.fanCount.toString()
                        : '—',
                    label: context.l10n.activeGroups,
                    valueColor: colors.accent,
                    labelColor: colors.tertiaryText,
                  ),
                  const SizedBox(width: 20),
                  _bankStat(
                    context: context,
                    value: partner.clubCount > 0
                        ? _formatRwf(partner.clubCount)
                        : '—',
                    label: context.l10n.rwfHeld,
                    valueColor: colors.accent,
                    labelColor: colors.tertiaryText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bankStat({
    required BuildContext context,
    required String value,
    required String label,
    required Color valueColor,
    required Color labelColor,
  }) {
    final text = context.coolText;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: text.mono(
            theme.textTheme.titleLarge,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: text.rayon(
            theme.textTheme.labelMedium,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
      ],
    );
  }

  static String _formatRwf(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return amount.toString();
  }
}

class _OrgsTab extends ConsumerWidget {
  const _OrgsTab();

  Future<void> _openPartnerChat(
    BuildContext context, {
    required Partner partner,
  }) {
    final phone = partner.whatsappNumber ?? '';
    return WhatsAppContactService.openChat(
      context,
      phoneNumber: phone,
      message: 'Hello ${partner.name} I would',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final partnersAsync = ref.watch(orgPartnersProvider);

    return partnersAsync.when(
      loading: () =>
          _LoadingState(title: l10n.loading, message: 'Loading partners…'),
      error: (error, _) => _ErrorState(
        error: error.toString(),
        onRetry: () => ref.invalidate(orgPartnersProvider),
      ),
      data: (partners) {
        if (partners.isEmpty) {
          return const _EmptyState(label: 'No service partners yet');
        }

        return Column(
          children: [
            for (var index = 0; index < partners.length; index++) ...[
              if (index > 0) const SizedBox(height: CoolSpace.x3),
              _OrgPartnerCard(
                partner: partners[index],
                onTap: () =>
                    _openPartnerChat(context, partner: partners[index]),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _OrgPartnerCard extends StatelessWidget {
  const _OrgPartnerCard({required this.partner, required this.onTap});

  final Partner partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final isInsurance = partner.slug == 'radiant';
    return CoolCard(
      gradient: isInsurance
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colors.analyticsSurface,
                colors.cardSurfaceStrong,
              ],
            )
          : colors.accentGradient,
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(
            right: -5,
            bottom: 5,
            child: Icon(
              IconMapper.from(partner.emoji),
              size: 50,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isInsurance
                        ? colors.info.withValues(alpha: 0.16)
                        : colors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isInsurance
                          ? colors.info.withValues(alpha: 0.3)
                          : colors.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        IconMapper.from(partner.emoji),
                        size: 13,
                        color: isInsurance ? colors.info : colors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _categoryLabel(context, partner),
                        style: text.rayon(
                          theme.textTheme.labelMedium,
                          fontWeight: FontWeight.w700,
                          color: isInsurance ? colors.info : colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  partner.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  partner.subtitle ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                const WhatsAppHintChip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _categoryLabel(BuildContext context, Partner partner) {
    final l10n = context.l10n;
    if (partner.category == PartnerCategory.bank) {
      return l10n.bankingPartner;
    }
    if (partner.slug == 'radiant') {
      return 'Insurance partner';
    }
    if (partner.slug == 'prisma') {
      return 'Professional services';
    }
    return 'Service partner';
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: CoolStateView.loading(
        title: title,
        message: message,
        compact: true,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: CoolStateView.error(
        title: 'load partners failed',
        message: error,
        actionLabel: context.l10n.retryAction,
        action: onRetry,
        compact: true,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: CoolStateView.empty(
        title: label,
        message: 'Check back later for',
        icon: Icons.handshake_outlined,
        compact: true,
      ),
    );
  }
}
