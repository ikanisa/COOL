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
          return const _EmptyState(
            label: 'No football partners yet',
          );
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
    final isRayon = partner.slug == 'rayon-sports';
    return Semantics(
      button: true,
      label: 'Open ${partner.name}',
      child: GestureDetector(
        onTap: onTap,
        child: CoolCard(
          gradient: isRayon ? AppColors.rsHeroGradient : AppColors.blueGradient,
          borderColor: isRayon ? AppColors.rsBlueBorder : AppColors.border,
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
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isRayon
                            ? AppColors.rsGold.withValues(alpha: 0.18)
                            : AppColors.blue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isRayon
                              ? AppColors.rsGold.withValues(alpha: 0.4)
                              : AppColors.blue.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            IconMapper.from(partner.emoji),
                            size: 13,
                            color: isRayon
                                ? AppColors.rsGoldLight
                                : AppColors.blue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isRayon
                                ? 'Rayon hub'
                                : context.l10n.officialPartner,
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isRayon
                                  ? AppColors.rsGoldLight
                                  : AppColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      partner.name,
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      partner.subtitle ?? '',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _stat(
                          _formatCompactCount(partner.fanCount),
                          context.l10n.fansTitle,
                          isRayon,
                        ),
                        _divider(),
                        _stat(
                          partner.clubCount.toString(),
                          context.l10n.fanClubs,
                          isRayon,
                        ),
                        _divider(),
                        _stat(partner.gameCount.toString(), 'Games', isRayon),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label, bool isRayon) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isRayon ? AppColors.rsGoldLight : AppColors.blue,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 28, color: AppColors.border2);
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
    return CoolCard(
      onTap: onTap,
      semanticsLabel: title,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: AppColors.text),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
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
            childAspectRatio: constraints.maxWidth >= 860 ? 1.15 : 1.5,
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
              borderColor: AppColors.blue.withValues(alpha: 0.24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Credit readiness comes first',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Check your savings and',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  CoolButton(
                    label: 'Open readiness checklist',
                    icon: Icons.assignment_turned_in_outlined,
                    onTap: () => context.push(AppRoutes.creditReadiness),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < partners.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
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
    return Semantics(
      button: true,
      label: 'Open ${partner.name}',
      child: GestureDetector(
        onTap: () => context.push('/partners/${partner.slug}'),
        child: CoolCard(
          gradient: AppColors.accentGradient,
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
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          context.l10n.bankingPartner,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
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
                const SizedBox(height: 12),
                Text(
                  partner.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  partner.subtitle ?? '',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _bankStat(
                      partner.fanCount > 0 ? partner.fanCount.toString() : '—',
                      context.l10n.activeGroups,
                      AppColors.accent,
                    ),
                    const SizedBox(width: 20),
                    _bankStat(
                      partner.clubCount > 0
                          ? _formatRwf(partner.clubCount)
                          : '—',
                      context.l10n.rwfHeld,
                      AppColors.accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bankStat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.text3,
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
      message:
          'Hello ${partner.name} I would',
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
              if (index > 0) const SizedBox(height: 12),
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
    final isInsurance = partner.slug == 'radiant';
    return CoolCard(
      gradient: isInsurance ? AppColors.blueGradient : AppColors.accentGradient,
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
                        ? AppColors.blue.withValues(alpha: 0.15)
                        : AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isInsurance
                          ? AppColors.blue.withValues(alpha: 0.3)
                          : AppColors.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        IconMapper.from(partner.emoji),
                        size: 13,
                        color: isInsurance ? AppColors.blue : AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _categoryLabel(context, partner),
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isInsurance
                              ? AppColors.blue
                              : AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  partner.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  partner.subtitle ?? '',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
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
