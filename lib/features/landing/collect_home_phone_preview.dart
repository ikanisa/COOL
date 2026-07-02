part of 'collect_landing_page.dart';

class _PhoneMockup extends StatelessWidget {
  const _PhoneMockup();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(38),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.26),
          width: 2,
        ),
        color: CollectColors.publicDeepInk,
        boxShadow: [
          BoxShadow(
            color: CollectColors.publicBlack.withValues(alpha: 0.42),
            blurRadius: 34,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: SizedBox(
        width: 286,
        height: 650,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'collect',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: CollectColors.publicWhite,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.notifications_none,
                    color: CollectColors.publicWhite,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Total balance',
                style: CollectTypography.eyebrowLabel(
                  CollectColors.publicWhite.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '250,000 RWF',
                style: CollectTypography.amountDisplay(
                  CollectColors.publicWhite,
                ).copyWith(fontSize: 32),
              ),
              const SizedBox(height: 22),
              const _PhoneCard(
                title: "Today's savings",
                value: '2,000 RWF',
                meta: 'Daily target 2,000 RWF',
                color: CollectColors.brandMintGreen,
              ),
              const SizedBox(height: 12),
              const _PhoneCard(
                title: 'Group ledger',
                value: '62,000 RWF',
                meta: '+12% this month',
                color: CollectColors.brandPeriwinkle,
              ),
              const SizedBox(height: 12),
              const _ReadinessScore(),
              const Spacer(),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PhoneNav(
                    icon: Icons.home_filled,
                    label: 'Home',
                    active: true,
                  ),
                  _PhoneNav(icon: Icons.groups_outlined, label: 'Groups'),
                  _PhoneNav(icon: Icons.download_outlined, label: 'Save'),
                  _PhoneNav(icon: Icons.shield_outlined, label: 'Insure'),
                  _PhoneNav(icon: Icons.person_outline, label: 'Profile'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({
    required this.title,
    required this.value,
    required this.meta,
    required this.color,
  });

  final String title;
  final String value;
  final String meta;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.publicWhite.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: CollectColors.publicWhite,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: CollectColors.publicWhite,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: 0.72,
                minHeight: 6,
                backgroundColor: CollectColors.publicWhite.withValues(
                  alpha: 0.1,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              meta,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: CollectColors.publicWhite.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessScore extends StatelessWidget {
  const _ReadinessScore();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.publicWhite.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: CollectColors.brandMintGreen,
                  width: 4,
                ),
              ),
              child: SizedBox.square(
                dimension: 54,
                child: Center(
                  child: Text(
                    '78',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: CollectColors.publicWhite,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: CollectColors.brandMintGreen,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'On track for bank-ready file',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: CollectColors.publicWhite.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneNav extends StatelessWidget {
  const _PhoneNav({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? CollectColors.brandPeriwinkle
        : CollectColors.publicWhite.withValues(alpha: 0.54);
    return Column(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontSize: 9,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _LedgerPanel extends StatelessWidget {
  const _LedgerPanel();

  @override
  Widget build(BuildContext context) {
    return _FloatingPanel(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group ledger',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: CollectColors.publicWhite,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nguruvu ibimina',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: CollectColors.publicWhite.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'This month',
            style: CollectTypography.eyebrowLabel(
              CollectColors.publicWhite.withValues(alpha: 0.52),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '62,000 RWF',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: CollectColors.publicWhite,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '+12%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CollectColors.brandMintGreen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final height in [38, 52, 44, 60, 56, 72, 84, 68, 92])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CollectColors.brandPeriwinkle.withValues(
                            alpha: height > 60 ? 0.95 : 0.42,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SizedBox(height: height.toDouble()),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisciplinePanel extends StatelessWidget {
  const _DisciplinePanel();

  @override
  Widget build(BuildContext context) {
    return _FloatingPanel(
      width: 210,
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: CollectColors.brandMintGreen,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Strong discipline',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: CollectColors.brandMintGreen,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Pay-ins consistent',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CollectColors.publicWhite.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingPanel extends StatelessWidget {
  const _FloatingPanel({required this.child, required this.width});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.publicPanelInk.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: CollectColors.publicBlack.withValues(alpha: 0.3),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      ),
    );
  }
}
