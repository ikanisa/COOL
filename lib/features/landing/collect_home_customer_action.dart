part of 'collect_landing_page.dart';

class _CustomerActionSection extends StatelessWidget {
  const _CustomerActionSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      key: _customerCtaKey,
      background: CollectColors.brandPaper,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CollectColors.publicWhite,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: CollectColors.publicLavenderBorder),
          boxShadow: [
            BoxShadow(
              color: CollectColors.brandPeriwinkle.withValues(alpha: 0.1),
              blurRadius: 38,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 860;
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start with Collect',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: CollectColors.referenceChromeBlack,
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'For group savings setup, app access or customer support, contact IKANISA.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: CollectColors.inkSecondary,
                      height: CollectTypography.leadingBody,
                    ),
                  ),
                  const SizedBox(height: 24),
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
                        onLight: true,
                        onPressed: () async => _openWhatsApp(
                          context,
                          'Hello IKANISA, I want to create a Collect group.',
                        ),
                      ),
                    ],
                  ),
                ],
              );
              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: 30),
                    const _ContactSummaryCard(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 9, child: copy),
                  const SizedBox(width: 38),
                  const Expanded(flex: 8, child: _ContactSummaryCard()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ContactSummaryCard extends ConsumerWidget {
  const _ContactSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(collectRuntimeConfigProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.brandPaper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CollectColors.publicLavenderBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact IKANISA',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: CollectTypography.weightBold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'WhatsApp ${config.whatsAppSupportDisplay}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: CollectTypography.weightBold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              config.supportEmail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: CollectTypography.weightBold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
