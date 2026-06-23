part of 'collect_landing_page.dart';

class _InsuranceSection extends StatelessWidget {
  const _InsuranceSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: CollectColors.publicSoftDanger,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const cards = [
            _ProductData(
              title: 'GIPI',
              subtitle: 'Group income protection',
              body:
                  'Short-term benefit when verified income interruption affects earning ability.',
              icon: Icons.favorite_border,
            ),
            _ProductData(
              title: 'CLMI',
              subtitle: 'Credit life micro-insurance',
              body:
                  'Outstanding balance protection on death or permanent disability.',
              icon: Icons.shield_outlined,
            ),
            _ProductData(
              title: 'CIPI',
              subtitle: 'Credit income protection',
              body:
                  'Scheduled repayments covered for a period after verified income disruption.',
              icon: Icons.health_and_safety_outlined,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionIntro(
                title: 'Embedded insurance for repayment resilience',
                body:
                    'Credit without protection is fragile. Collect embeds group and credit-linked protection so health, death, accident, income or climate shocks do not automatically destroy savings discipline.',
              ),
              const SizedBox(height: 34),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: constraints.maxWidth < 760
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 48) / 3,
                      child: _ProductCard(
                        data: card,
                        color: CollectColors.brandDustyRose,
                      ),
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

class _CraasSection extends StatelessWidget {
  const _CraasSection();

  @override
  Widget build(BuildContext context) {
    return const _SectionBand(
      background: CollectColors.publicSoftInfo,
      child: _SplitSection(
        title: 'CRaaS: from loan inquiry to bank-ready file',
        body:
            'Support for customers who need a cleaner file before approaching a provider.',
        steps: [
          LandingStepData(
            icon: Icons.chat_bubble_outline,
            title: 'Loan inquiry',
            body: 'Member profile, purpose and loan need.',
            color: CollectColors.brandPeriwinkle,
          ),
          LandingStepData(
            icon: Icons.inventory_2_outlined,
            title: 'Collect file',
            body: 'Documents, checklist and missing-item support.',
            color: CollectColors.brandPeriwinkle,
          ),
          LandingStepData(
            icon: Icons.task_alt,
            title: 'Bank-ready file',
            body: 'Organized evidence and customer summary.',
            color: CollectColors.brandPeriwinkle,
          ),
          LandingStepData(
            icon: Icons.account_balance,
            title: 'Lender decision',
            body: 'Final credit decisions remain with the chosen provider.',
            color: CollectColors.brandPeriwinkle,
          ),
        ],
      ),
    );
  }
}

class _StakeholderSection extends StatelessWidget {
  const _StakeholderSection();

  @override
  Widget build(BuildContext context) {
    const stakeholders = [
      _ProductData(
        title: 'Members',
        subtitle: 'Daily savers and borrowers',
        body: 'Save, view balances, follow rules and prepare credit evidence.',
        icon: Icons.groups_outlined,
      ),
      _ProductData(
        title: 'Group treasurers',
        subtitle: 'Records, roles and payouts',
        body: 'Review members, contributions and meeting-ready records.',
        icon: Icons.account_balance_outlined,
      ),
      _ProductData(
        title: 'Diaspora savers',
        subtitle: 'Save together for Rwanda',
        body: 'Build visible pools, commitments and investment pathways.',
        icon: Icons.verified_user_outlined,
      ),
      _ProductData(
        title: 'Borrowers',
        subtitle: 'Credit-readiness support',
        body: 'Turn saving discipline into a stronger credit file.',
        icon: Icons.policy_outlined,
      ),
      _ProductData(
        title: 'Families',
        subtitle: 'Protection against shocks',
        body: 'Keep repayment plans resilient with embedded cover records.',
        icon: Icons.public_outlined,
      ),
    ];
    return _SectionBand(
      background: CollectColors.publicWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionIntro(
            title: 'Built around customer journeys',
            body:
                'Collect supports members, treasurers, diaspora savers, borrowers and families with clear journeys from saving to credit-readiness.',
          ),
          const SizedBox(height: 34),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              for (final item in stakeholders)
                SizedBox(width: 228, child: _SmallStakeholder(data: item)),
            ],
          ),
        ],
      ),
    );
  }
}

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
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'For group savings setup, app access or customer support, contact IKANISA.',
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
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CollectColors.inkSecondary,
                height: 1.42,
              ),
            ),
            const SizedBox(height: 22),
            TextButton.icon(
              onPressed: () => _scrollToCustomerAction(context),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(data.action),
              style: TextButton.styleFrom(
                foregroundColor: CollectColors.referenceChromeBlack,
                textStyle: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
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
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.data, required this.color});

  final _ProductData data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 62,
            child: Icon(data.icon, color: color, size: 30),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: CollectColors.referenceChromeBlack,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                data.subtitle,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: CollectColors.referenceChromeBlack,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CollectColors.inkSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallStakeholder extends StatelessWidget {
  const _SmallStakeholder({required this.data});

  final _ProductData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: CollectColors.inkPrimary.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, color: CollectColors.inkPrimary, size: 26),
            const SizedBox(height: 12),
            Text(
              data.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data.body,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CollectColors.inkSecondary,
                height: 1.34,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactSummaryCard extends StatelessWidget {
  const _ContactSummaryCard();

  @override
  Widget build(BuildContext context) {
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
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'WhatsApp +250 795 588 248',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _collectContactEmail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingFooter extends StatelessWidget {
  const _LandingFooter();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CollectColors.referenceChromeBlack,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 28,
              runSpacing: 18,
              children: [
                SizedBox(
                  width: 280,
                  child: Text(
                    'Collect by IKANISA',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: CollectColors.brandPaper,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _FooterLink(label: 'Home', onPressed: () => context.go('/')),
                _FooterLink(
                  label: 'Group Savings',
                  onPressed: () => context.go('/group-savings'),
                ),
                _FooterLink(
                  label: 'Diaspora',
                  onPressed: () => context.go('/diaspora'),
                ),
                _FooterLink(
                  label: 'Insurance',
                  onPressed: () => context.go('/insurance'),
                ),
                _FooterLink(
                  label: 'CRaaS',
                  onPressed: () => context.go('/craas'),
                ),
                _FooterLink(
                  label: 'Community Groups',
                  onPressed: () => context.go('/community-groups'),
                ),
                _FooterLink(
                  label: 'Impact',
                  onPressed: () => context.go('/impact'),
                ),
                _FooterLink(
                  label: 'Our Partners',
                  onPressed: () => context.go('/our-partners'),
                ),
                _FooterLink(
                  label: 'Privacy Policy',
                  onPressed: () => context.go('/privacy'),
                ),
                _FooterLink(
                  label: 'Terms of Service',
                  onPressed: () => context.go('/terms'),
                ),
                _FooterLink(
                  label: _collectContactEmail,
                  onPressed: () async => _openEmail(),
                ),
                _FooterLink(
                  label: '+250 795 588 248',
                  onPressed: () async => _openWhatsApp(
                    'Hello IKANISA, I need support with Collect.',
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    'Customer support: app access, group savings setup and account questions.',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: CollectColors.brandPaper.withValues(alpha: 0.66),
                      fontWeight: FontWeight.w700,
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

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed ?? () => _scrollToCustomerAction(context),
      style: TextButton.styleFrom(
        foregroundColor: CollectColors.brandPaper.withValues(alpha: 0.78),
        textStyle: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      child: Text(label),
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

class _ProductData {
  const _ProductData({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String body;
  final IconData icon;
}

void _scrollToCustomerAction(BuildContext context) {
  final position = Scrollable.maybeOf(context)?.position;
  if (position == null) return;
  final target = position.maxScrollExtent - 220;
  final offset = target.clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
    position.jumpTo(offset);
    return;
  }
  position.animateTo(
    offset,
    duration: CollectMotion.medium,
    curve: CollectMotion.standard,
  );
}

Future<void> _openWhatsApp(String message) async {
  final url = Uri.https('wa.me', '/$_collectWhatsAppNumber', {'text': message});
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

Future<void> _openEmail() async {
  final url = Uri(
    scheme: 'mailto',
    path: _collectContactEmail,
    queryParameters: {'subject': 'Collect support'},
  );
  await launchUrl(url, mode: LaunchMode.externalApplication);
}
