part of 'collect_landing_page.dart';

class CollectPublicPage extends StatelessWidget {
  const CollectPublicPage({required this.data, super.key});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CollectColors.brandPaper,
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _PublicPageHero(data: data)),
            SliverToBoxAdapter(child: _PublicPageSummary(data: data)),
            if (!data.isPolicy)
              SliverToBoxAdapter(child: _PublicPageInfographic(data: data)),
            SliverToBoxAdapter(child: _PublicPageSections(data: data)),
            if (!data.isPolicy)
              const SliverToBoxAdapter(child: _CustomerActionSection()),
            const SliverToBoxAdapter(child: _LandingFooter()),
          ],
        ),
      ),
    );
  }
}

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
              fontWeight: FontWeight.w900,
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
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  section.body,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: CollectColors.inkSecondary,
                    height: 1.45,
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
            fontWeight: FontWeight.w900,
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
                      height: 1.35,
                      fontWeight: FontWeight.w700,
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
