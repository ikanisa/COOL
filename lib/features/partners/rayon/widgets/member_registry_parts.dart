part of '../screens/member_registry_screen.dart';

class _RegistryCommandCard extends StatelessWidget {
  const _RegistryCommandCard({
    required this.visibleCount,
    required this.activeFilter,
    required this.topFan,
    required this.query,
    required this.hasMore,
    required this.onFilterSelected,
  });

  final int visibleCount;
  final MemberRegistryFilter activeFilter;
  final RsRegistryMember? topFan;
  final String query;
  final bool hasMore;
  final ValueChanged<MemberRegistryFilter> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF071224), Color(0xFF0D2758), Color(0xFF163C70)],
      ),
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supporter Registry Command',
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          SizedBox(height: space.x1 + 2),
          Text(
            'Search, filter, and review supporter records.',
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.76),
              height: 1.4,
            ),
          ),
          SizedBox(height: space.x4),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: MemberRegistryFilter.values
                .map(
                  (filter) => VehicleChip(
                    label: filter.label,
                    isSelected: filter == activeFilter,
                    onTap: () => onFilterSelected(filter),
                  ),
                )
                .toList(),
          ),
          SizedBox(height: space.x4),
          Row(
            children: [
              Expanded(
                child: _RegistryMetricTile(
                  label: 'Visible',
                  value: '$visibleCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RegistryMetricTile(
                  label: 'View',
                  value: activeFilter.label.replaceAll(' Members', ''),
                  highlight: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RegistryMetricTile(
                  label: 'Top Fan',
                  value: topFan == null
                      ? 'Pending'
                      : _formatPoints(topFan!.points),
                ),
              ),
            ],
          ),
          SizedBox(height: space.x3 + 2),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: [
              _RegistrySignalPill(
                icon: Icons.verified_user_outlined,
                label: topFan == null
                    ? 'Registry verification live'
                    : '${topFan!.displayName} leading',
              ),
              _RegistrySignalPill(
                icon: Icons.search_rounded,
                label: query.trim().isEmpty
                    ? 'Search command ready'
                    : 'Query: ${query.trim()}',
              ),
              _RegistrySignalPill(
                icon: Icons.fact_check_outlined,
                label: hasMore
                    ? 'Additional records available'
                    : 'Current segment loaded',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RegistryMetricTile extends StatelessWidget {
  const _RegistryMetricTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x3),
      decoration: BoxDecoration(
        color: highlight
            ? RsColors.rsGold.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(
          color: highlight
              ? RsColors.rsGold.withValues(alpha: 0.34)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: highlight ? RsColors.rsGoldLight : Colors.white,
            ),
          ),
          SizedBox(height: space.x1 / 2),
          Text(
            label,
            style: text.rayon(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.inputSurface,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.borderStrong),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: text.rayon(
          theme.textTheme.bodyMedium,
          fontWeight: FontWeight.w700,
          color: colors.primaryText,
        ),
        cursorColor: colors.accent,
        decoration: InputDecoration(
          hintText: context.l10n.searchNameOrId,
          hintStyle: text.rayon(
            theme.textTheme.bodyMedium,
            fontWeight: FontWeight.w600,
            color: colors.tertiaryText,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: colors.secondaryText),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}

class _RegistrySignalPill extends StatelessWidget {
  const _RegistrySignalPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: RsColors.rsBluePale),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.rayon(
                  theme.textTheme.labelMedium,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopFanSpotlight extends StatelessWidget {
  const _TopFanSpotlight({required this.member});

  final RsRegistryMember member;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: RsColors.rsGold.withValues(alpha: 0.4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Fan This Month',
                  style: text.rayon(
                    theme.textTheme.labelLarge,
                    fontWeight: FontWeight.w800,
                    color: RsColors.rsGoldLight,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: CoolSpace.x2),
                Text(
                  member.displayName,
                  style: text.rayonCondensed(
                    theme.textTheme.headlineMedium,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryText,
                    height: 0.98,
                  ),
                ),
                const SizedBox(height: CoolSpace.x2),
                Text(
                  '#${member.membershipNumber} · ${_formatPoints(member.points)} Tokens',
                  style: text.mono(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          RsTierBadge(tier: member.tier),
        ],
      ),
    );
  }
}

class _MemberListTile extends StatelessWidget {
  const _MemberListTile({required this.member});

  final RsRegistryMember member;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final avatarTextColor = member.tier == FanTier.silver
        ? colors.appBackground
        : colors.accentForeground;

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _avatarGradient(member.tier),
              ),
              border: Border.all(
                color: member.tier.color.withValues(alpha: 0.32),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initialsFor(member.displayName),
              style: text.rayonCondensed(
                theme.textTheme.titleLarge,
                fontWeight: FontWeight.w800,
                color: avatarTextColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  style: text.rayon(
                    theme.textTheme.titleSmall,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  '#${member.membershipNumber} · ${member.chapter} · ${_formatPoints(member.points)} Tokens',
                  style: text.mono(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          RsTierBadge(tier: member.tier),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.visibleCount, required this.onTap});

  final int visibleCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CoolButton(
      label: 'Load more · $visibleCount loaded',
      onTap: onTap,
      variant: CoolButtonVariant.secondary,
    );
  }
}

class _TierLegendCard extends StatelessWidget {
  const _TierLegendCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Membership tiers',
            style: text.rayon(
              theme.textTheme.labelLarge,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          for (final tier in FanTier.values) ...[
            _TierLegendRow(tier: tier, range: _tierRangeFor(tier)),
            if (tier != FanTier.values.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TierLegendRow extends StatelessWidget {
  const _TierLegendRow({required this.tier, required this.range});

  final FanTier tier;
  final String range;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            tier.label,
            style: text.rayonCondensed(
              theme.textTheme.titleMedium,
              fontWeight: FontWeight.w800,
              color: tier == FanTier.silver ? colors.primaryText : tier.color,
            ),
          ),
        ),
        Text(
          range,
          style: text.mono(
            theme.textTheme.bodySmall,
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

class _EmptyRegistryState extends StatelessWidget {
  const _EmptyRegistryState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final message = query.trim().isEmpty
        ? 'No members match the selected filter.'
        : 'No members matched "$query".';

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Text(
        message,
        style: text.rayon(
          theme.textTheme.bodyMedium,
          fontWeight: FontWeight.w600,
          color: colors.secondaryText,
          height: 1.4,
        ),
      ),
    );
  }
}

List<Color> _avatarGradient(FanTier tier) {
  return switch (tier) {
    FanTier.blue => [RsColors.rsBlueLight, RsColors.rsBlue],
    FanTier.silver => [const Color(0xFFE4E8F1), const Color(0xFF8C94A9)],
    FanTier.gold => [RsColors.rsGoldLight, RsColors.rsGold],
    FanTier.platinum => [const Color(0xFFC8DCFF), const Color(0xFF7D6A8E)],
  };
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList(growable: false);

  if (parts.isEmpty) {
    return 'RS';
  }

  return parts.map((part) => part.characters.first.toUpperCase()).join();
}

String _formatPoints(int points) {
  final raw = points.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < raw.length; i++) {
    final indexFromEnd = raw.length - i;
    buffer.write(raw[i]);
    if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
      buffer.write(',');
    }
  }

  return buffer.toString();
}

String _tierRangeFor(FanTier tier) {
  return switch (tier) {
    FanTier.blue => '0-999 Tokens',
    FanTier.silver => '1,000-1,999 Tokens',
    FanTier.gold => '2,000-4,999 Tokens',
    FanTier.platinum => '5,000+ Tokens',
  };
}
