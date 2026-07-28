part of 'collect_landing_page.dart';

class _LandingHero extends StatelessWidget {
  const _LandingHero();

  @override
  Widget build(BuildContext context) {
    final compactViewport = MediaQuery.sizeOf(context).width < 600;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.38, -0.2),
          radius: 1.25,
          colors: [
            CollectColors.publicInkPurple,
            CollectColors.referenceChromeBlack,
            CollectColors.referenceChromeBlack,
          ],
          stops: [0, 0.56, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compactViewport ? 20 : 40,
            compactViewport ? 18 : 22,
            compactViewport ? 20 : 40,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                children: [
                  const _LandingNav(),
                  Padding(
                    padding: const EdgeInsets.only(top: 54, bottom: 64),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 920;
                        final copy = _HeroCopy(compact: isCompact);
                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              copy,
                              const SizedBox(height: 36),
                              const Center(
                                child: _HeroProductVisual(compact: true),
                              ),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 10, child: copy),
                            const SizedBox(width: 44),
                            const Expanded(
                              flex: 9,
                              child: _HeroProductVisual(),
                            ),
                          ],
                        );
                      },
                    ),
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

class _LandingNav extends StatelessWidget {
  const _LandingNav();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showLinks = constraints.maxWidth >= 1500;
        final compact = constraints.maxWidth < 680;
        final brand = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: CollectColors.brandPaper.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: CollectColors.brandPaper.withValues(alpha: 0.18),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 9),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: compact ? 22 : 24,
                  color: CollectColors.brandPaper,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Collect',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge?.copyWith(
                      color: CollectColors.brandPaper,
                      fontWeight: CollectTypography.weightBold,
                      height: CollectTypography.leadingSolid,
                    ),
                  ),
                  Text(
                    'By IKANISA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: CollectColors.brandPaper.withValues(alpha: 0.72),
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
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
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              brand,
              const SizedBox(height: 18),
              actions,
              const SizedBox(height: 14),
              const _CompactPublicLinks(),
            ],
          );
        }
        final topRow = Row(children: [brand, const Spacer(), actions]);
        if (!showLinks) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              topRow,
              const SizedBox(height: 14),
              const _CompactPublicLinks(),
            ],
          );
        }
        return Row(
          children: [
            brand,
            const Spacer(),
            const _NavLinks(),
            const SizedBox(width: 18),
            actions,
          ],
        );
      },
    );
  }
}

class _NavLinks extends StatelessWidget {
  const _NavLinks();

  @override
  Widget build(BuildContext context) {
    const links = [
      ('Home', '/'),
      ('Group Savings', '/group-savings'),
      ('Diaspora', '/diaspora'),
      ('Insurance', '/insurance'),
      ('CRaaS', '/craas'),
      ('Community Groups', '/community-groups'),
      ('Our Partners', '/our-partners'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 14,
          children: [
            for (final link in links)
              TextButton(
                onPressed: () => context.go(link.$2),
                style: TextButton.styleFrom(
                  foregroundColor: CollectColors.brandPaper.withValues(
                    alpha: 0.84,
                  ),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: CollectTypography.weightBold,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, CollectSpacing.target),
                ),
                child: Text(link.$1),
              ),
          ],
        );
      },
    );
  }
}

class _CompactPublicLinks extends StatelessWidget {
  const _CompactPublicLinks();

  @override
  Widget build(BuildContext context) {
    const links = [
      ('Home', '/'),
      ('Group Savings', '/group-savings'),
      ('Diaspora', '/diaspora'),
      ('Insurance', '/insurance'),
      ('CRaaS', '/craas'),
      ('Community Groups', '/community-groups'),
      ('Our Partners', '/our-partners'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final link in links)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton(
                onPressed: () => context.go(link.$2),
                style: TextButton.styleFrom(
                  foregroundColor: CollectColors.brandPaper,
                  backgroundColor: CollectColors.brandPaper.withValues(
                    alpha: 0.08,
                  ),
                  side: BorderSide(
                    color: CollectColors.brandPaper.withValues(alpha: 0.16),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, CollectSpacing.target),
                  textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
                child: Text(link.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _LandingButton extends StatelessWidget {
  const _LandingButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.onLight = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool outlined;
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final foreground = outlined && onLight
        ? CollectColors.inkPrimary
        : CollectColors.brandPaper;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CollectSpacing.target),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: outlined
              ? CollectColors.transparentColor
              : CollectColors.brandPeriwinkle,
          foregroundColor: foreground,
          side: outlined
              ? BorderSide(
                  color:
                      (onLight
                              ? CollectColors.inkPrimary
                              : CollectColors.brandPaper)
                          .withValues(alpha: 0.54),
                )
              : BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: CollectTypography.weightBold,
          ),
        ),
        onPressed: onPressed,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Credit-ready saving for Rwanda's daily economy",
          style: textTheme.displaySmall?.copyWith(
            color: CollectColors.brandPaper,
            fontSize: compact
                ? CollectTypography.sizeHeroCompact
                : CollectTypography.sizeMarketingHero,
            height: CollectTypography.leadingDisplay,
            fontWeight: CollectTypography.weightBold,
          ),
        ),
        const SizedBox(height: 26),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'From payment inclusion to credit conversion: Collect turns local ibimina and diaspora savings into verified ledgers, credit-ready files, collateral rules and insured repayment capacity.',
            style: textTheme.titleMedium?.copyWith(
              color: CollectColors.brandPaper.withValues(alpha: 0.76),
              fontSize: CollectTypography.sizeLead,
              height: CollectTypography.leadingResponsiveBody,
              fontWeight: CollectTypography.weightMedium,
            ),
          ),
        ),
        const SizedBox(height: 26),
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
        if (!compact) ...[const SizedBox(height: 34), const _HeroFlow()],
      ],
    );
  }
}

class _HeroFlow extends StatelessWidget {
  const _HeroFlow();

  @override
  Widget build(BuildContext context) {
    const items = [
      LandingStepData(
        icon: Icons.download_outlined,
        title: 'Save',
        body: '',
        color: CollectColors.brandPeriwinkle,
      ),
      LandingStepData(
        icon: Icons.bar_chart_outlined,
        title: 'Score',
        body: '',
        color: CollectColors.brandMintGreen,
      ),
      LandingStepData(
        icon: Icons.assignment_turned_in_outlined,
        title: 'Prepare',
        body: '',
        color: CollectColors.brandDustyRose,
      ),
      LandingStepData(
        icon: Icons.account_balance_outlined,
        title: 'Borrow',
        body: '',
        color: CollectColors.brandDustyRose,
      ),
      LandingStepData(
        icon: Icons.verified_user_outlined,
        title: 'Protect',
        body: '',
        color: CollectColors.publicSuccessAccent,
      ),
    ];
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 16,
      children: [
        for (var index = 0; index < items.length; index += 1) ...[
          _HeroFlowItem(data: items[index]),
          if (index < items.length - 1)
            Icon(
              Icons.arrow_forward,
              color: CollectColors.brandPaper.withValues(alpha: 0.48),
              size: 20,
            ),
        ],
      ],
    );
  }
}

class _HeroFlowItem extends StatelessWidget {
  const _HeroFlowItem({required this.data});

  final LandingStepData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: data.color.withValues(alpha: 0.38),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SizedBox.square(
              dimension: 64,
              child: Icon(
                data.icon,
                color: CollectColors.publicWhite,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: CollectColors.brandPaper,
              fontWeight: CollectTypography.weightBold,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroProductVisual extends StatelessWidget {
  const _HeroProductVisual({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final phonePreview = MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: const _PhoneMockup(),
    );
    if (compact) {
      return SizedBox(
        height: 520,
        child: FittedBox(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 320,
            height: 690,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [phonePreview],
            ),
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 88,
              child: Opacity(
                opacity: 0.46,
                child: SizedBox(
                  height: 360,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          CollectColors.brandPeriwinkle.withValues(alpha: 0.42),
                          CollectColors.brandMintGreen.withValues(alpha: 0.18),
                          CollectColors.referenceChromeBlack.withValues(
                            alpha: 0.24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(right: -12, top: 70, child: _LedgerPanel()),
            const Positioned(right: 14, bottom: 40, child: _DisciplinePanel()),
            phonePreview,
          ],
        ),
      ),
    );
  }
}
