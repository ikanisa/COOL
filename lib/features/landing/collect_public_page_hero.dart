part of 'collect_landing_page.dart';

class _PublicPageHero extends StatelessWidget {
  const _PublicPageHero({required this.data});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CollectColors.referenceChromeBlack,
            CollectColors.publicHeroPurple,
            CollectColors.referenceChromeBlack,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 22, 40, 72),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _LandingNav(),
                  SizedBox(height: data.isPolicy ? 44 : 64),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 920;
                      final copy = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: CollectColors.brandPaper,
                                  fontSize: compact
                                      ? (data.isPolicy ? 38 : 42)
                                      : (data.isPolicy ? 58 : 68),
                                  height: 1.02,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            data.intro,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: CollectColors.brandPaper.withValues(
                                    alpha: 0.74,
                                  ),
                                  fontSize: 20,
                                  height: 1.44,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 30),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _LandingButton(
                                label: 'Get the App',
                                onPressed: () async => _openWhatsApp(
                                  'Hello IKANISA, I want to get the Collect app.',
                                ),
                              ),
                              _LandingButton(
                                label: 'Create Group',
                                outlined: true,
                                onPressed: () async => _openWhatsApp(
                                  'Hello IKANISA, I want to create a Collect group.',
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                      final media = _PublicPageMedia(data: data);
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [copy, const SizedBox(height: 36), media],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 7, child: copy),
                          const SizedBox(width: 60),
                          Expanded(flex: 6, child: media),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicPageMedia extends StatelessWidget {
  const _PublicPageMedia({required this.data});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.publicWhite.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                data.imageAsset,
                height: 300,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox(height: 300),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DarkMetric(
                    value: data.metricA,
                    label: data.metricALabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DarkMetric(
                    value: data.metricB,
                    label: data.metricBLabel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.publicBlack.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: CollectColors.brandPaper,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: CollectColors.brandPaper.withValues(alpha: 0.64),
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
