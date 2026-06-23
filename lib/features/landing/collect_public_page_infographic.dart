part of 'collect_landing_page.dart';

class _PublicPageInfographic extends StatelessWidget {
  const _PublicPageInfographic({required this.data});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    final steps = publicInfographicSteps(data.path);
    return _SectionBand(
      background: publicInfographicBackground(data.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            publicInfographicTitle(data.path),
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: CollectColors.referenceChromeBlack,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Text(
              publicInfographicBody(data.path),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: CollectColors.inkSecondary,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 30),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final columns = maxWidth >= 1120
                  ? 4
                  : maxWidth >= 840
                  ? 3
                  : maxWidth >= 620
                  ? 2
                  : 1;
              const gap = 14.0;
              final cardWidth = columns == 1
                  ? maxWidth
                  : (maxWidth - (gap * (columns - 1))) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var index = 0; index < steps.length; index += 1)
                    SizedBox(
                      width: cardWidth,
                      child: _InfographicStepCard(
                        data: steps[index],
                        index: index,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfographicStepCard extends StatelessWidget {
  const _InfographicStepCard({required this.data, required this.index});

  final LandingStepData data;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.92, end: 1),
      duration: CollectMotion.duration(
        context,
        Duration(milliseconds: 420 + (index * 80)),
      ),
      curve: CollectMotion.standard,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CollectColors.publicWhite.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CollectColors.publicLavenderBorder),
          boxShadow: [
            BoxShadow(
              color: data.color.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SizedBox.square(
                      dimension: 44,
                      child: Icon(data.icon, color: data.color, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    (index + 1).toString().padLeft(2, '0'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: CollectColors.inkSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                data.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: CollectColors.referenceChromeBlack,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CollectColors.inkSecondary,
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
