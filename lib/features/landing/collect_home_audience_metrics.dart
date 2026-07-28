part of 'collect_landing_page.dart';

class _AudienceCard extends StatelessWidget {
  const _AudienceCard({required this.data});

  final _AudienceData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.brandPaper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: data.color.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 58,
                child: Icon(data.icon, color: data.color, size: 28),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              data.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: CollectTypography.weightBold,
                height: CollectTypography.leadingDisplayRelaxed,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CollectColors.inkSecondary,
                height: CollectTypography.leadingResponsiveBody,
              ),
            ),
            const SizedBox(height: 22),
            TextButton.icon(
              onPressed: () => _scrollToCustomerAction(context),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(data.action),
              style: TextButton.styleFrom(
                foregroundColor: CollectColors.referenceChromeBlack,
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProofMetrics extends StatelessWidget {
  const _ProofMetrics();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        _ProofMetric(value: '23%', label: 'Formal credit usage'),
        _ProofMetric(value: 'US\$0.5B+', label: 'Diaspora remittances'),
        _ProofMetric(value: '90.4%', label: 'Informal employment'),
      ],
    );
  }
}

class _ProofMetric extends StatelessWidget {
  const _ProofMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 176,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CollectColors.publicWhite.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: CollectColors.publicWhite.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: CollectTypography.amountLarge(CollectColors.brandPaper),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: CollectColors.brandPaper.withValues(alpha: 0.68),
                  fontWeight: CollectTypography.weightBold,
                  height: CollectTypography.leadingLabel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceData {
  const _AudienceData({
    required this.title,
    required this.body,
    required this.action,
    required this.icon,
    required this.color,
  });

  final String title;
  final String body;
  final String action;
  final IconData icon;
  final Color color;
}
