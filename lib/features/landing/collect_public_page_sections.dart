part of 'collect_landing_page.dart';

class _PublicPageSections extends StatelessWidget {
  const _PublicPageSections({required this.data});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: CollectColors.brandPaper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.isPolicy ? 'Details' : 'How it works',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: CollectColors.referenceChromeBlack,
              fontWeight: CollectTypography.weightBold,
            ),
          ),
          const SizedBox(height: 28),
          for (var index = 0; index < data.sections.length; index += 1) ...[
            _PublicContentSection(
              section: data.sections[index],
              index: index,
              isPolicy: data.isPolicy,
            ),
            if (index < data.sections.length - 1) const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}

class _PublicContentSection extends StatelessWidget {
  const _PublicContentSection({
    required this.section,
    required this.index,
    required this.isPolicy,
  });

  final CollectPublicSectionData section;
  final int index;
  final bool isPolicy;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isPolicy
            ? CollectColors.publicWhite
            : CollectColors.publicWhite.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CollectColors.publicLavenderBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionNumber(index: index),
                const SizedBox(height: 18),
                Text(
                  section.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: CollectColors.referenceChromeBlack,
                    fontWeight: CollectTypography.weightBold,
                    height: CollectTypography.leadingTitle,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  section.body,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: CollectColors.inkSecondary,
                    height: CollectTypography.leadingBody,
                  ),
                ),
              ],
            );
            final bullets = _BulletList(
              items: section.bullets,
              isPolicy: isPolicy,
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [copy, const SizedBox(height: 24), bullets],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: copy),
                const SizedBox(width: 48),
                Expanded(flex: 5, child: bullets),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionNumber extends StatelessWidget {
  const _SectionNumber({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.referenceChromeBlack,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          '0${index + 1}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: CollectColors.brandPaper,
            fontWeight: CollectTypography.weightBold,
          ),
        ),
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items, this.isPolicy = false});

  final List<String> items;
  final bool isPolicy;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: isPolicy
                      ? CollectColors.brandPeriwinkle
                      : CollectColors.brandMintGreen,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: CollectColors.referenceChromeBlack,
                      height: CollectTypography.leadingSupporting,
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
