part of 'collect_landing_page.dart';

class _PublicPageHero extends StatelessWidget {
  const _PublicPageHero({required this.data});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    final compactViewport = MediaQuery.sizeOf(context).width < 600;
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
          padding: EdgeInsets.fromLTRB(
            compactViewport ? 20 : 40,
            compactViewport ? 18 : 22,
            compactViewport ? 20 : 40,
            compactViewport ? 48 : 72,
          ),
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
                                      ? (data.isPolicy
                                            ? CollectTypography.sizePageCompact
                                            : CollectTypography.sizeHeroCompact)
                                      : (data.isPolicy
                                            ? CollectTypography.sizePolicyHero
                                            : CollectTypography.sizePublicHero),
                                  height: CollectTypography.leadingDisplay,
                                  fontWeight: CollectTypography.weightBold,
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
                                  fontSize: CollectTypography.sizeTitle,
                                  height: CollectTypography.leadingIntro,
                                  fontWeight: CollectTypography.weightMedium,
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
                                  context,
                                  'Hello IKANISA, I want to get the Collect app.',
                                ),
                              ),
                              _LandingButton(
                                label: 'Create Group',
                                outlined: true,
                                onPressed: () async => _openWhatsApp(
                                  context,
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
              child: _PublicSemanticMedia(role: data.mediaRole),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stackMetrics =
                    constraints.maxWidth < 360 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final first = _DarkMetric(
                  value: data.metricA,
                  label: data.metricALabel,
                );
                final second = _DarkMetric(
                  value: data.metricB,
                  label: data.metricBLabel,
                );
                if (stackMetrics) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [first, const SizedBox(height: 12), second],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: first),
                    const SizedBox(width: 12),
                    Expanded(child: second),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicSemanticMedia extends StatelessWidget {
  const _PublicSemanticMedia({required this.role});

  final CollectPublicMediaRole role;

  @override
  Widget build(BuildContext context) {
    final icon = switch (role) {
      CollectPublicMediaRole.group => Icons.groups_2_outlined,
      CollectPublicMediaRole.payment => Icons.payments_outlined,
      CollectPublicMediaRole.share => Icons.qr_code_2_outlined,
    };
    final label = switch (role) {
      CollectPublicMediaRole.group => 'Group records',
      CollectPublicMediaRole.payment => 'Mobile money flow',
      CollectPublicMediaRole.share => 'Share and verify',
    };
    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 300,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CollectColors.referencePaymentsPurple,
                  CollectColors.referenceAssetNavy,
                  CollectColors.referenceChromeBlack,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: CollectColors.publicWhite.withValues(alpha: 0.12),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -24,
                  top: -18,
                  child: Icon(
                    icon,
                    size: 190,
                    color: CollectColors.publicWhite.withValues(alpha: 0.08),
                  ),
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CollectColors.publicWhite.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CollectColors.publicWhite.withValues(
                          alpha: 0.18,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Icon(
                        icon,
                        size: 86,
                        color: CollectColors.brandPaper,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                fontWeight: CollectTypography.weightBold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: CollectColors.brandPaper.withValues(alpha: 0.64),
                fontWeight: CollectTypography.weightBold,
                height: CollectTypography.leadingLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
