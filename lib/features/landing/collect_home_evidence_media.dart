part of 'collect_landing_page.dart';

class _MediaProofVisual extends StatelessWidget {
  const _MediaProofVisual();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.publicSoftLavender,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: CollectColors.publicLavenderBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final image = ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/brand/collect_runtime/media/mobile-money-ussd-signal.png',
                height: compact ? 220 : 330,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            );
            const proof = _EvidenceStack();
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [image, const SizedBox(height: 18), proof],
              );
            }
            return Row(
              children: [
                Expanded(flex: 6, child: image),
                const SizedBox(width: 18),
                const Expanded(flex: 5, child: proof),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EvidenceStack extends StatelessWidget {
  const _EvidenceStack();

  @override
  Widget build(BuildContext context) {
    const items = [
      _EvidenceItem(
        title: 'Verified ledger',
        body: 'Contribution, payout and rule history.',
        icon: Icons.receipt_long_outlined,
      ),
      _EvidenceItem(
        title: 'Credit-readiness file',
        body: 'Checklist, customer summary and missing-item support.',
        icon: Icons.inventory_2_outlined,
      ),
      _EvidenceItem(
        title: 'Protected repayment',
        body: 'GIPI, CLMI and CIPI insurance rails.',
        icon: Icons.shield_outlined,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'An application-ready evidence pack',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: CollectColors.referenceChromeBlack,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        for (final item in items) _EvidenceRow(item: item),
      ],
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.item});

  final _EvidenceItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: CollectColors.brandPeriwinkle,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 42,
              child: Icon(
                item.icon,
                color: CollectColors.publicWhite,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: CollectColors.referenceChromeBlack,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CollectColors.inkSecondary,
                    height: 1.35,
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

class _EvidenceItem {
  const _EvidenceItem({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;
}
