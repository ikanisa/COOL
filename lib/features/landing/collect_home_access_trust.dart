part of 'collect_landing_page.dart';

class _AudienceConversionSection extends StatelessWidget {
  const _AudienceConversionSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: CollectColors.publicWhite,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 860
              ? constraints.maxWidth
              : (constraints.maxWidth - 48) / 3;
          const audiences = [
            _AudienceData(
              title: 'For members and ibimina',
              body:
                  'Save daily, see the group ledger, build discipline and prepare a bank-ready credit file.',
              action: 'Create Group',
              icon: Icons.groups_outlined,
              color: CollectColors.brandPeriwinkle,
            ),
            _AudienceData(
              title: 'For diaspora savers',
              body:
                  'Pool savings with host-bank custody, ring-fence collateral and invest back into Rwanda.',
              action: 'Open a corridor',
              icon: Icons.public_outlined,
              color: CollectColors.brandMintGreen,
            ),
            _AudienceData(
              title: 'For borrowers and families',
              body:
                  'Prepare stronger credit records and keep repayment plans protected against shocks.',
              action: 'Prepare credit file',
              icon: Icons.account_balance_outlined,
              color: CollectColors.brandDustyRose,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionIntro(
                title: 'Three routes into one credit engine',
                body:
                    'Savings records, protection and credit-readiness support in one customer journey.',
              ),
              const SizedBox(height: 34),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  for (final audience in audiences)
                    SizedBox(
                      width: width,
                      child: _AudienceCard(data: audience),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppAccessSection extends StatelessWidget {
  const _AppAccessSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: CollectColors.brandPaper,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Get Collect or create a group savings account',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: CollectColors.referenceChromeBlack,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Members can start through the app or WhatsApp. The same entry point works for group treasurers, local savings groups and new savings communities.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: CollectColors.inkSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _LandingButton(
                    label: 'Get the App',
                    onLight: true,
                    onPressed: () async => _openWhatsApp(
                      'Hello IKANISA, I want to get the Collect app.',
                    ),
                  ),
                  _LandingButton(
                    label: 'Create Group',
                    outlined: true,
                    onLight: true,
                    onPressed: () async => _openWhatsApp(
                      'Hello IKANISA, I want to create a Collect group.',
                    ),
                  ),
                ],
              ),
            ],
          );
          const visual = _UssdCommandVisual();
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 30), visual],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 7, child: copy),
              const SizedBox(width: 56),
              const Expanded(flex: 6, child: visual),
            ],
          );
        },
      ),
    );
  }
}

class _UssdCommandVisual extends StatelessWidget {
  const _UssdCommandVisual();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CollectColors.referenceChromeBlack,
            borderRadius: BorderRadius.circular(38),
            border: Border.all(
              color: CollectColors.publicBlack.withValues(alpha: 0.72),
            ),
            boxShadow: [
              BoxShadow(
                color: CollectColors.brandPeriwinkle.withValues(alpha: 0.22),
                blurRadius: 38,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CollectColors.publicWhite.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: CollectColors.publicDarkInk,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: CollectColors.publicWhite.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.signal_cellular_alt,
                              color: CollectColors.brandMintGreen,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'MoMo USSD',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: CollectColors.brandPaper,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              'RWF',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: CollectColors.brandPaper.withValues(
                                      alpha: 0.58,
                                    ),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Dial to save',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: CollectColors.brandPaper.withValues(
                                  alpha: 0.64,
                                ),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: CollectColors.publicWhite.withValues(
                              alpha: 0.07,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: CollectColors.brandMintGreen.withValues(
                                alpha: 0.34,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _collectUssdCode,
                                maxLines: 1,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: CollectColors.brandPaper,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: CollectColors.brandMintGreen.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.savings_outlined,
                                color: CollectColors.brandMintGreen,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Save RWF 2,000 into Collect',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: CollectColors.brandPaper,
                                        fontWeight: FontWeight.w900,
                                        height: 1.2,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 12,
                  children: [
                    _PhoneKey(label: '1'),
                    _PhoneKey(label: '2'),
                    _PhoneKey(label: '3'),
                    _PhoneKey(label: '4'),
                    _PhoneKey(label: '5'),
                    _PhoneKey(label: '6'),
                    _PhoneKey(label: '*'),
                    _PhoneKey(label: '0'),
                    _PhoneKey(label: '#'),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Example: dial $_collectUssdCode to save RWF 2,000 into Collect.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CollectColors.brandPaper.withValues(alpha: 0.68),
                    height: 1.35,
                    fontWeight: FontWeight.w700,
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

class _PhoneKey extends StatelessWidget {
  const _PhoneKey({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CollectColors.publicWhite.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: CollectColors.publicWhite.withValues(alpha: 0.12),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: CollectColors.brandPaper,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustProofSection extends StatelessWidget {
  const _TrustProofSection();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CollectColors.referenceChromeBlack,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 58),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
                final copy = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Built for the missing middle of financial inclusion',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: CollectColors.brandPaper,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Rwanda has broad payment access, but formal credit conversion still needs better records, collateral rules, protection and application-ready files.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: CollectColors.brandPaper.withValues(alpha: 0.72),
                        height: 1.45,
                      ),
                    ),
                  ],
                );
                const metrics = _ProofMetrics();
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [copy, const SizedBox(height: 28), metrics],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 6, child: copy),
                    const SizedBox(width: 56),
                    const Expanded(flex: 7, child: _ProofMetrics()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
