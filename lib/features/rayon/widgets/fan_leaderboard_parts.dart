part of '../screens/fan_leaderboard_screen.dart';

// ─── Top 3 Spotlight ──────────────────────────────────────────────────

class _TopThreeSpotlight extends StatelessWidget {
  const _TopThreeSpotlight({required this.entries});

  final List<RsFanLeaderboardEntry> entries;

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: colors.borderStrong,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Text(
                'TOP FANS',
                style: text.mono(
                  theme.textTheme.titleMedium,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsGold,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int i = 0; i < entries.length; i++)
                _TopFanCard(
                  entry: entries[i],
                  medal: _medals[i],
                  isFirst: i == 0,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopFanCard extends StatelessWidget {
  const _TopFanCard({
    required this.entry,
    required this.medal,
    this.isFirst = false,
  });

  final RsFanLeaderboardEntry entry;
  final String medal;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(medal, style: TextStyle(fontSize: isFirst ? 40 : 30)),
        const SizedBox(height: 8),
        Container(
          width: isFirst ? 72 : 56,
          height: isFirst ? 72 : 56,
          decoration: BoxDecoration(
            color: colors.cardSurface,
            shape: BoxShape.circle,
            border: Border.all(
              color: isFirst ? RsColors.rsGold : colors.borderStrong,
              width: isFirst ? 3 : 2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '${entry.rank}',
            style: text.mono(
              TextStyle(fontSize: isFirst ? 28 : 22),
              fontWeight: FontWeight.w900,
              color: isFirst ? RsColors.rsGold : colors.primaryText,
            ),
          ),
        ),
        const SizedBox(height: 8),
        RsTierBadge(tier: entry.tier),
        const SizedBox(height: 4),
        Text(
          _formatXp(entry.totalXp),
          style: text.mono(
            theme.textTheme.labelMedium,
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        Text(
          'XP',
          style: text.rayon(
            theme.textTheme.bodySmall,
            fontWeight: FontWeight.w600,
            color: colors.tertiaryText,
          ),
        ),
      ],
    );
  }
}

// ─── Section Label ────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: text.mono(
            theme.textTheme.labelSmall,
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
            letterSpacing: 1.0,
          ),
        ),
        Text(
          '$count Fans',
          style: text.rayon(
            theme.textTheme.bodySmall,
            fontWeight: FontWeight.w600,
            color: colors.tertiaryText,
          ),
        ),
      ],
    );
  }
}

// ─── Leaderboard Tile ─────────────────────────────────────────────────

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({required this.entry});

  final RsFanLeaderboardEntry entry;

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
          // Rank badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              shape: BoxShape.circle,
              border: Border.all(color: colors.borderStrong),
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.rank}',
              style: text.mono(
                const TextStyle(fontSize: 16),
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RsTierBadge(tier: entry.tier),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.predictionCount} predictions',
                      style: text.rayon(
                        theme.textTheme.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                ),
                if (entry.predictionCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${entry.accuracy.toStringAsFixed(0)}% accuracy',
                    style: text.rayon(
                      theme.textTheme.bodySmall,
                      fontWeight: FontWeight.w600,
                      color: RsColors.rsNavyLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // XP
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatXp(entry.totalXp),
                style: text.mono(
                  theme.textTheme.titleMedium,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              Text(
                'XP',
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

// ─── Utility ──────────────────────────────────────────────────────────

String _formatXp(int xp) {
  if (xp >= 1000) {
    return '${(xp / 1000).toStringAsFixed(1)}K';
  }
  return xp.toString();
}
