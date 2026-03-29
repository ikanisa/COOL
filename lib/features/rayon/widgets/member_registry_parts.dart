part of '../screens/member_registry_screen.dart';

// ─── Tier chip (blue fill for selected, dark outline for others) ──────────

class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? RsColors.rsRed : Colors.transparent,
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          border: Border.all(
            color: isSelected ? RsColors.rsRed : colors.borderStrong,
          ),
        ),
        child: Text(
          label,
          style: text.rayonCondensed(
            Theme.of(context).textTheme.labelLarge,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : colors.secondaryText,
          ),
        ),
      ),
    );
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────

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
        color: colors.cardSurface,
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
          hintText: 'Search by ID or Name...',
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

// ─── Top Fan Spotlight section ────────────────────────────────────────────

class _TopFanSpotlightSection extends StatelessWidget {
  const _TopFanSpotlightSection({required this.member});

  final RsRegistryMember member;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: CoolSpace.x6),
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TOP FAN SPOTLIGHT',
              style: text.mono(
                theme.textTheme.labelSmall,
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
                letterSpacing: 1.0,
              ),
            ),
            Icon(
              Icons.emoji_events_outlined,
              color: colors.secondaryText,
              size: 20,
            ),
          ],
        ),
        const SizedBox(height: CoolSpace.x4),
        // Spotlight card
        CoolCard(
          backgroundColor: colors.cardSurfaceStrong,
          borderColor: colors.borderStrong,
          child: Row(
            children: [
              // Crown emoji circle
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  border: Border.all(color: colors.borderStrong),
                ),
                alignment: Alignment.center,
                child: const Text('👑', style: TextStyle(fontSize: 32)),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.membershipNumber,
                      style: text.rayonCondensed(
                        theme.textTheme.headlineSmall,
                        fontWeight: FontWeight.w900,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        RsTierBadge(tier: member.tier),
                        const SizedBox(width: 10),
                        Text(
                          '${_formatPoints(member.points)} PTS',
                          style: text.mono(
                            theme.textTheme.bodyMedium,
                            fontWeight: FontWeight.w700,
                            color: RsColors.rsNavyLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Trophy watermark
              Icon(
                Icons.emoji_events_rounded,
                color: colors.borderStrong.withValues(alpha: 0.3),
                size: 56,
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),
      ],
    );
  }
}

// ─── Supporter Rankings header ────────────────────────────────────────────

class _SupporterRankingsHeader extends StatelessWidget {
  const _SupporterRankingsHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: CoolSpace.x4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'SUPPORTER RANKINGS',
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              letterSpacing: 1.0,
            ),
          ),
          Text(
            '$count Registered',
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ranked member tile ──────────────────────────────────────────────────

class _RankedMemberTile extends StatelessWidget {
  const _RankedMemberTile({required this.member, required this.rank});

  final RsRegistryMember member;
  final int rank;

  static const _rankEmojis = ['👑', '🌟', '⚽', '⚡', '🥁'];

  String get _rankEmoji =>
      rank <= _rankEmojis.length ? _rankEmojis[rank - 1] : '🏅';

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Row(
        children: [
          // Avatar with rank badge
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.cardSurfaceStrong,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.borderStrong),
                  ),
                  alignment: Alignment.center,
                  child: Text(_rankEmoji, style: const TextStyle(fontSize: 24)),
                ),
                // Rank badge
                Positioned(
                  bottom: -2,
                  left: -2,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: RsColors.rsRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.appBackground, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: text.mono(
                        const TextStyle(fontSize: 14),
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Info column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.membershipNumber,
                  style: text.rayonCondensed(
                    theme.textTheme.titleMedium,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    RsTierBadge(tier: member.tier),
                    const SizedBox(width: 8),
                    Text(
                      _formatJoinDate(member.joinedAt),
                      style: text.rayon(
                        theme.textTheme.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Points
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPoints(member.points),
                style: text.mono(
                  theme.textTheme.titleMedium,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              Text(
                'Points',
                style: text.rayon(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────

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

// ─── Load more button ─────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.visibleCount, required this.onTap});

  final int visibleCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(CoolRadii.md),
          border: Border.all(color: colors.borderStrong),
        ),
        alignment: Alignment.center,
        child: Text(
          'Load more · $visibleCount loaded',
          style: text.mono(
            Theme.of(context).textTheme.labelMedium,
            fontWeight: FontWeight.w700,
            color: RsColors.rsNavyLight,
          ),
        ),
      ),
    );
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────

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

String _formatJoinDate(DateTime? date) {
  if (date == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Joined ${months[date.month - 1]} ${date.year}';
}
