part of 'collect_landing_page.dart';

class _PublicPageSummary extends StatelessWidget {
  const _PublicPageSummary({required this.data});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: CollectColors.publicWhite,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 880;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                publicSummaryLabel(data),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: CollectColors.brandPeriwinkle,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.navLabel,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: CollectColors.referenceChromeBlack,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.intro,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: CollectColors.inkSecondary,
                  height: 1.45,
                ),
              ),
            ],
          );
          final proof = Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _PublicProofTile(value: data.metricA, label: data.metricALabel),
              _PublicProofTile(value: data.metricB, label: data.metricBLabel),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 24), proof],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: heading),
              const SizedBox(width: 48),
              Expanded(flex: 5, child: proof),
            ],
          );
        },
      ),
    );
  }
}

class _PublicProofTile extends StatelessWidget {
  const _PublicProofTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CollectColors.brandPaper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CollectColors.publicLavenderBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: CollectColors.referenceChromeBlack,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: CollectColors.inkSecondary,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
