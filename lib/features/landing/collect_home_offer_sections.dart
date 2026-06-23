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
