import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_typography.dart';
import '../../shared/widgets/collect_chrome.dart';

const _customerCtaKey = ValueKey<String>('collect-customer-action');
const _collectUssdCode = '*182*8*1*41258*2000#';
const _collectWhatsAppNumber = '250795588248';
const _collectContactEmail = 'info@ikanisa.com';
const publicWebsitePaths = <String>{
  '/',
  '/group-savings',
  '/diaspora',
  '/insurance',
  '/craas',
  '/community-groups',
  '/privacy',
  '/terms',
};

const _publicPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/group-savings',
    navLabel: 'Group savings',
    title: 'Group savings that become credit evidence',
    intro:
        'Collect helps ibimina and savings groups move from informal contribution tracking to verified ledgers, daily saving discipline, consented statements and bank-ready evidence.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: '52%',
    metricALabel: 'adults in ibimina',
    metricB: '4.0M',
    metricBLabel: 'group savers',
    sections: [
      CollectPublicSectionData(
        title: 'From rotating payouts to accumulating capital',
        body:
            'Groups can keep the trust and rhythm of ibimina while adding auditable rules, savings targets, pooled capital, payout history and member-level performance records.',
        bullets: [
          'Group rules, member roles and contribution cycles',
          'Daily, weekly or monthly deposit records',
          'Transparent payout and fund movement history',
        ],
      ),
      CollectPublicSectionData(
        title: 'Verified records for your group',
        body:
            'Contribution events become structured proof that members can understand, treasurers can manage and borrowers can use when preparing a credit request.',
        bullets: [
          'SMS-backed and app-backed payment evidence',
          'Statement-ready group and member histories',
          'Credit-readiness signals based on consistency and tenure',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/diaspora',
    navLabel: 'Diaspora',
    title: 'Diaspora savings with custody and collateral rules',
    intro:
        'Collect gives diaspora groups a structured way to save together, keep custody records, ring-fence agreed collateral and prepare Rwanda investment pathways.',
    imageAsset: 'assets/brand/generated/collect_visual_qr_share.png',
    metricA: 'US\$0.5B+',
    metricALabel: 'remittance opportunity',
    metricB: 'Host bank',
    metricBLabel: 'custody model',
    sections: [
      CollectPublicSectionData(
        title: 'Save together outside Rwanda',
        body:
            'Diaspora members can organize around savings pools with clear group rules, custody records and transparent obligations before funds are used for investment.',
        bullets: [
          'Host-country group saving structure',
          'Custody records and statements',
          'Member visibility into commitments and balances',
        ],
      ),
      CollectPublicSectionData(
        title: 'Invest back with controlled risk',
        body:
            'A defined share of savings can be locked as collateral while eligible members pursue Rwanda investments such as property, SMEs, agriculture and productive assets.',
        bullets: [
          'Collateral lock based on group rules',
          'Evidence pack for loan review',
          'Final credit decision remains with the chosen credit provider',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/insurance',
    navLabel: 'Insurance',
    title: 'Embedded insurance for resilient repayment',
    intro:
        'Collect embeds protection around savings and credit journeys so health, death, income and climate shocks do not automatically destroy repayment discipline.',
    imageAsset: 'assets/brand/generated/collect_visual_momo_signal.png',
    metricA: 'GIPI',
    metricALabel: 'group income protection',
    metricB: 'CLMI/CIPI',
    metricBLabel: 'credit protection',
    sections: [
      CollectPublicSectionData(
        title: 'Protection at the point of contribution',
        body:
            'Insurance is designed into the savings and lending journey rather than sold as a separate afterthought. The result is clearer coverage, collection and claims context.',
        bullets: [
          'Group income protection insurance',
          'Credit life micro-insurance',
          'Credit income protection insurance',
        ],
      ),
      CollectPublicSectionData(
        title: 'Clear protection records',
        body:
            'Members and group leaders can see how protection connects to savings, contributions, premium events and repayment resilience.',
        bullets: [
          'Consent-aware member and group records',
          'Premium collection tied to savings activity',
          'Claims context connected to contribution history',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/craas',
    navLabel: 'CRaaS',
    title: 'Credit Readiness as a Service',
    intro:
        'CRaaS turns a loan inquiry into a bank-ready file with evidence quality, human completion, indexed documents, risk flags and a clear next step.',
    imageAsset: 'assets/brand/generated/collect_logo_color_variants_sheet.png',
    metricA: '0',
    metricALabel: 'credit-readiness agents',
    metricB: 'Bank-ready',
    metricBLabel: 'file output',
    sections: [
      CollectPublicSectionData(
        title: 'Before underwriting begins',
        body:
            'Collect prepares the borrower file before a bank spends time on formal credit analysis. The service improves evidence quality without making the credit decision.',
        bullets: [
          'Loan purpose, profile and affordability intake',
          'KYC, checklist and missing-document repair',
          'Indexed file, memo, risk flags and mitigants',
        ],
      ),
      CollectPublicSectionData(
        title: 'A support layer for borrowers',
        body:
            'CRaaS helps daily-income customers prepare cleaner documentation, stronger behavioural context and fewer incomplete files.',
        bullets: [
          'Verified savings discipline',
          'Collateral and insurance context',
          'Final approval remains with the chosen credit provider',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/community-groups',
    navLabel: 'Community groups',
    title: 'Community groups as distribution infrastructure',
    intro:
        'Collect treats trusted local groups as the strongest last-mile interface for savings, credit readiness, protection and family financial planning.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: '365',
    metricALabel: 'collections per borrower',
    metricB: '6.9x',
    metricBLabel: 'income multiplier scenario',
    sections: [
      CollectPublicSectionData(
        title: 'Local trust, structured operations',
        body:
            'Group leaders keep community trust while Collect adds records, workflows, permissions and member-ready reporting.',
        bullets: [
          'Treasurer and member workflows',
          'Group-level performance and exception handling',
          'Clear records for members and group leaders',
        ],
      ),
      CollectPublicSectionData(
        title: 'Beyond collections',
        body:
            'The group becomes a channel for saving, credit preparation, microinsurance, diaspora links and better household planning.',
        bullets: [
          'Savings mobilisation',
          'Microinsurance collection',
          'Diaspora and investment corridors',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/privacy',
    navLabel: 'Privacy',
    title: 'Privacy Policy',
    intro:
        'Collect protects customer information with clear consent, limited access and practical safeguards for savings, credit-readiness and insurance journeys.',
    imageAsset: 'assets/brand/generated/collect_visual_qr_share.png',
    metricA: 'Consent',
    metricALabel: 'customer control',
    metricB: 'Secure',
    metricBLabel: 'records handling',
    sections: [
      CollectPublicSectionData(
        title: 'Information we collect',
        body:
            'Collect may collect account details, group membership records, contribution activity, payment references, support messages and documents needed to run savings or credit-readiness services.',
        bullets: [
          'Identity and contact details provided by the customer',
          'Group rules, roles, contributions and payout records',
          'Support requests, consent choices and service messages',
        ],
      ),
      CollectPublicSectionData(
        title: 'How information is used',
        body:
            'Customer information is used to operate Collect, maintain ledgers, support savings groups, prepare credit-readiness files, improve service quality and respond to customer requests.',
        bullets: [
          'Operate app, USSD, WhatsApp and group workflows',
          'Prepare records customers request for savings and credit use',
          'Protect accounts, prevent misuse and support recovery',
        ],
      ),
      CollectPublicSectionData(
        title: 'Customer choices and contact',
        body:
            'Customers can ask for help, request corrections or raise privacy questions by email or WhatsApp.',
        bullets: [
          'Email: info@ikanisa.com',
          'WhatsApp: +250 795 588 248',
          'USSD: *182*8*1*41258*2000#',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/terms',
    navLabel: 'Terms',
    title: 'Terms of Service',
    intro:
        'These terms explain how customers use Collect for group savings, contribution records, credit-readiness support, insurance records and customer service.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: 'Customer',
    metricALabel: 'service terms',
    metricB: 'Clear',
    metricBLabel: 'group rules',
    sections: [
      CollectPublicSectionData(
        title: 'Using Collect',
        body:
            'Customers are responsible for providing accurate information, following their group rules and using Collect only for lawful savings, contribution and support activities.',
        bullets: [
          'Keep account and group information accurate',
          'Use app, USSD and WhatsApp channels responsibly',
          'Follow savings group rules approved by members',
        ],
      ),
      CollectPublicSectionData(
        title: 'Savings, credit-readiness and protection',
        body:
            'Collect helps customers keep records, organize group savings, prepare credit-readiness files and track protection details. Final credit decisions remain with the chosen credit provider.',
        bullets: [
          'Collect records contributions and group activity',
          'CRaaS prepares customer files before loan review',
          'Insurance records support repayment resilience',
        ],
      ),
      CollectPublicSectionData(
        title: 'Support and contact',
        body:
            'Customers can contact IKANISA for app access, group savings setup, account support or questions about these terms.',
        bullets: [
          'Email: info@ikanisa.com',
          'WhatsApp: +250 795 588 248',
          'Create group savings through WhatsApp',
        ],
      ),
    ],
  ),
];

class CollectLandingPage extends StatelessWidget {
  const CollectLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: CollectColors.brandPaper,
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _LandingHero()),
            SliverToBoxAdapter(child: _AudienceConversionSection()),
            SliverToBoxAdapter(child: _AppAccessSection()),
            SliverToBoxAdapter(child: _TrustProofSection()),
            SliverToBoxAdapter(
              child: _SectionBand(
                background: CollectColors.brandPaper,
                child: _SplitSection(
                  title: 'The rhythm gap for daily-income earners',
                  body:
                      'Income comes daily, but money systems are built for monthly cycles. Collect fits the daily rhythm: save today, insure today, repay today and build a record over time.',
                  steps: [
                    _StepData(
                      icon: Icons.person_outline,
                      title: 'Daily income',
                      body: 'Small, irregular earnings.',
                      color: CollectColors.brandDustyRose,
                    ),
                    _StepData(
                      icon: Icons.calendar_today_outlined,
                      title: 'Monthly systems',
                      body: 'High-friction files and lump-sum expectations.',
                      color: Color(0xFF84848C),
                    ),
                    _StepData(
                      icon: Icons.lock_outline,
                      title: 'Access denied',
                      body: 'Savings, credit and protection stay out of reach.',
                      color: CollectColors.brandOrangeRed,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionBand(
                background: Colors.white,
                child: _SplitSection(
                  title: 'How ibimina become verified records',
                  body:
                      'IKANISA moves trusted groups from rotational payout to accumulating capital, SMS-backed proof, auditable statements and credit-readiness signals.',
                  steps: [
                    _StepData(
                      icon: Icons.groups_outlined,
                      title: 'Form a group',
                      body: 'Members agree on rules and savings goals.',
                      color: CollectColors.brandPeriwinkle,
                    ),
                    _StepData(
                      icon: Icons.savings_outlined,
                      title: 'Save daily',
                      body: 'USSD, MoMo, app or agent-backed deposits.',
                      color: CollectColors.brandMintGreen,
                    ),
                    _StepData(
                      icon: Icons.receipt_long_outlined,
                      title: 'Verified ledger',
                      body:
                          'Pay-ins, fund movements and decisions in real time.',
                      color: CollectColors.brandDustyRose,
                    ),
                    _StepData(
                      icon: Icons.query_stats_outlined,
                      title: 'Credit signals',
                      body: 'Discipline, frequency and tenure build readiness.',
                      color: CollectColors.brandOrangeRed,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionBand(
                background: Color(0xFFF3FBF8),
                child: _SplitSection(
                  title:
                      'Diaspora savings with custody records and collateral rules',
                  body:
                      'Diaspora groups save together in the host country, maintain custody records, ring-fence agreed collateral and prepare eligible members for Rwanda investment.',
                  steps: [
                    _StepData(
                      icon: Icons.people_alt_outlined,
                      title: 'Diaspora group',
                      body: 'Members save together in the host country.',
                      color: CollectColors.brandMintGreen,
                    ),
                    _StepData(
                      icon: Icons.account_balance_outlined,
                      title: 'Custody records',
                      body: 'Savings records remain clear and traceable.',
                      color: CollectColors.inkPrimary,
                    ),
                    _StepData(
                      icon: Icons.verified_user_outlined,
                      title: 'Collateral lock',
                      body: 'An agreed share of the pool is ring-fenced.',
                      color: CollectColors.brandMintGreen,
                    ),
                    _StepData(
                      icon: Icons.location_on_outlined,
                      title: 'Invest in Rwanda',
                      body: 'Property, SMEs, startups, agriculture and assets.',
                      color: CollectColors.brandMintGreen,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _InsuranceSection()),
            SliverToBoxAdapter(child: _ProductMediaSection()),
            SliverToBoxAdapter(child: _CraasSection()),
            SliverToBoxAdapter(child: _StakeholderSection()),
            SliverToBoxAdapter(child: _CustomerActionSection()),
            SliverToBoxAdapter(child: _LandingFooter()),
          ],
        ),
      ),
    );
  }
}

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
            SliverToBoxAdapter(child: _PublicPageMetrics(data: data)),
            SliverToBoxAdapter(child: _PublicPageSections(data: data)),
            const SliverToBoxAdapter(child: _RelatedWebsitePages()),
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
            Color(0xFF151029),
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
                  const SizedBox(height: 64),
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
                                  fontSize: compact ? 42 : 68,
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
                                label: 'Get the app',
                                onPressed: () async => _openWhatsApp(
                                  'Hello IKANISA, I want to get the Collect app.',
                                ),
                              ),
                              _LandingButton(
                                label: 'Create group savings',
                                outlined: true,
                                onPressed: () async => _openWhatsApp(
                                  'Hello IKANISA, I want to create a Collect group savings account.',
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
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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

class _PublicPageMetrics extends StatelessWidget {
  const _PublicPageMetrics({required this.data});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Text(
              data.navLabel,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Flexible(
            flex: 2,
            child: Text(
              'A dedicated public page for ${data.navLabel.toLowerCase()}, with content structured for customers and search engines.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: CollectColors.inkSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
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
        children: [
          for (final section in data.sections) ...[
            _PublicContentSection(section: section),
            if (section != data.sections.last) const SizedBox(height: 42),
          ],
        ],
      ),
    );
  }
}

class _PublicContentSection extends StatelessWidget {
  const _PublicContentSection({required this.section});

  final CollectPublicSectionData section;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: CollectColors.referenceChromeBlack,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              section.body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: CollectColors.inkSecondary,
                height: 1.45,
              ),
            ),
          ],
        );
        final bullets = _BulletList(items: section.bullets);
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
            const SizedBox(width: 56),
            Expanded(flex: 5, child: bullets),
          ],
        );
      },
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

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
                const Icon(
                  Icons.check_circle,
                  color: CollectColors.brandMintGreen,
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

class _RelatedWebsitePages extends StatelessWidget {
  const _RelatedWebsitePages();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth < 760
              ? constraints.maxWidth
              : (constraints.maxWidth - 36) / 3;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Explore the Collect platform',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: CollectColors.referenceChromeBlack,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (final page in _publicPages.take(6))
                    SizedBox(
                      width: cardWidth,
                      child: _RelatedPageCard(page: page),
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

class _RelatedPageCard extends StatelessWidget {
  const _RelatedPageCard({required this.page});

  final CollectPublicPageData page;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.go(page.path),
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(20),
        foregroundColor: CollectColors.referenceChromeBlack,
        backgroundColor: CollectColors.brandPaper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE8E3F2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            page.navLabel,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: CollectColors.referenceChromeBlack,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            page.intro,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CollectColors.inkSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingHero extends StatelessWidget {
  const _LandingHero();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.38, -0.2),
          radius: 1.25,
          colors: [
            Color(0xFF171032),
            CollectColors.referenceChromeBlack,
            CollectColors.referenceChromeBlack,
          ],
          stops: [0, 0.56, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 22, 40, 0),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset(
                CollectBrandMark.appIconAssetPath,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: CollectColors.brandPaper,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collect',
                  style: textTheme.titleLarge?.copyWith(
                    color: CollectColors.brandPaper,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                Text(
                  'by IKANISA',
                  style: textTheme.labelSmall?.copyWith(
                    color: CollectColors.brandPaper.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        );
        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _LandingButton(
              label: 'Get the app',
              onPressed: () async => _openWhatsApp(
                'Hello IKANISA, I want to get the Collect app.',
              ),
            ),
            _LandingButton(
              label: 'Create group savings',
              outlined: true,
              onPressed: () async => _openWhatsApp(
                'Hello IKANISA, I want to create a Collect group savings account.',
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
      ('Group savings', '/group-savings'),
      ('Diaspora', '/diaspora'),
      ('Insurance', '/insurance'),
      ('CRaaS', '/craas'),
      ('Community groups', '/community-groups'),
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
                  textStyle: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 40),
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
      ('Group savings', '/group-savings'),
      ('Diaspora', '/diaspora'),
      ('Insurance', '/insurance'),
      ('CRaaS', '/craas'),
      ('Community groups', '/community-groups'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final link in links)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ActionChip(
                label: Text(link.$1),
                onPressed: () => context.go(link.$2),
                backgroundColor: CollectColors.brandPaper.withValues(
                  alpha: 0.08,
                ),
                side: BorderSide(
                  color: CollectColors.brandPaper.withValues(alpha: 0.14),
                ),
                labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CollectColors.brandPaper,
                  fontWeight: FontWeight.w900,
                ),
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
    return SizedBox(
      height: 44,
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
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
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
            fontSize: compact ? 42 : 72,
            height: 1.02,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 26),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'From payment inclusion to credit conversion: Collect turns local ibimina and diaspora savings into verified ledgers, credit-ready files, collateral rules and insured repayment capacity.',
            style: textTheme.titleMedium?.copyWith(
              color: CollectColors.brandPaper.withValues(alpha: 0.76),
              fontSize: 21,
              height: 1.42,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _LandingButton(
              label: 'Get the app',
              onPressed: () async => _openWhatsApp(
                'Hello IKANISA, I want to get the Collect app.',
              ),
            ),
            _LandingButton(
              label: 'Create group savings',
              outlined: true,
              onPressed: () async => _openWhatsApp(
                'Hello IKANISA, I want to create a Collect group savings account.',
              ),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 34),
          const _HeroFlow(),
          const SizedBox(height: 34),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroMetric(label: 'Financial inclusion', value: '96%'),
              _HeroMetric(label: 'Adults in ibimina', value: '52%'),
              _HeroMetric(label: 'Credit-readiness agents', value: '0'),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeroFlow extends StatelessWidget {
  const _HeroFlow();

  @override
  Widget build(BuildContext context) {
    const items = [
      _StepData(
        icon: Icons.download_outlined,
        title: 'Save',
        body: '',
        color: CollectColors.brandPeriwinkle,
      ),
      _StepData(
        icon: Icons.bar_chart_outlined,
        title: 'Score',
        body: '',
        color: CollectColors.brandMintGreen,
      ),
      _StepData(
        icon: Icons.assignment_turned_in_outlined,
        title: 'Prepare',
        body: '',
        color: CollectColors.brandDustyRose,
      ),
      _StepData(
        icon: Icons.account_balance_outlined,
        title: 'Borrow',
        body: '',
        color: CollectColors.brandOrangeRed,
      ),
      _StepData(
        icon: Icons.verified_user_outlined,
        title: 'Protect',
        body: '',
        color: Color(0xFF65C77B),
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

  final _StepData data;

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
              child: Icon(data.icon, color: Colors.white, size: 30),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: CollectColors.brandPaper,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.brandPaper.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CollectColors.brandPaper.withValues(alpha: 0.14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: CollectColors.brandPaper,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: CollectColors.brandPaper.withValues(alpha: 0.68),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroProductVisual extends StatelessWidget {
  const _HeroProductVisual({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const SizedBox(
        height: 520,
        child: FittedBox(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 320,
            height: 690,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [_PhoneMockup()],
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(34),
                  child: Image.asset(
                    'assets/brand/generated/collect_visual_group_momentum.png',
                    height: 360,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            const Positioned(right: -12, top: 70, child: _LedgerPanel()),
            const Positioned(right: 14, bottom: 40, child: _DisciplinePanel()),
            const _PhoneMockup(),
          ],
        ),
      ),
    );
  }
}

class _AudienceConversionSection extends StatelessWidget {
  const _AudienceConversionSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: Colors.white,
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
              action: 'Create group savings',
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
              color: CollectColors.brandOrangeRed,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionIntro(
                title: 'Three routes into one credit engine',
                body:
                    'Collect separates the public conversion paths while keeping one operating model underneath: verified saving behaviour, custody records, protection and human credit-readiness support.',
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
                'Members can start through the app, USSD or WhatsApp. The same entry point works for group treasurers, local savings groups and new savings communities.',
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
                    label: 'Get the app',
                    onLight: true,
                    onPressed: () async => _openWhatsApp(
                      'Hello IKANISA, I want to get the Collect app.',
                    ),
                  ),
                  _LandingButton(
                    label: 'Create group savings',
                    outlined: true,
                    onLight: true,
                    onPressed: () async => _openWhatsApp(
                      'Hello IKANISA, I want to create a Collect group savings account.',
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.referenceChromeBlack,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: CollectColors.brandPeriwinkle.withValues(alpha: 0.18),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.phone_iphone,
                  color: CollectColors.brandMintGreen,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Text(
                  'USSD quick save',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: CollectColors.brandPaper,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _collectUssdCode,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: CollectColors.brandPaper,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                      fontFeatures: const [],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Example: dial $_collectUssdCode to save RWF 2,000 into Collect.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CollectColors.brandPaper.withValues(alpha: 0.68),
                height: 1.38,
              ),
            ),
          ],
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

class _ProductMediaSection extends StatelessWidget {
  const _ProductMediaSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          const content = _SectionIntro(
            title: 'The product surface is more than group collections',
            body:
                'Collect turns contribution events into a portfolio of verified evidence: savings discipline, consented records, collateral commitments, insurance cover and credit-readiness workpapers that customers can use.',
          );
          const media = _MediaProofVisual();
          if (compact) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [content, SizedBox(height: 28), media],
            );
          }
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 7, child: media),
              SizedBox(width: 56),
              Expanded(flex: 6, child: content),
            ],
          );
        },
      ),
    );
  }
}

class _PhoneMockup extends StatelessWidget {
  const _PhoneMockup();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(38),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.26),
          width: 2,
        ),
        color: const Color(0xFF090912),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 34,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: SizedBox(
        width: 286,
        height: 650,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'collect',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.notifications_none,
                    color: Colors.white,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Total balance',
                style: CollectTypography.eyebrowLabel(
                  Colors.white.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '250,000 RWF',
                style: CollectTypography.amountDisplay(
                  Colors.white,
                ).copyWith(fontSize: 32),
              ),
              const SizedBox(height: 22),
              const _PhoneCard(
                title: "Today's savings",
                value: '2,000 RWF',
                meta: 'Daily target 2,000 RWF',
                color: CollectColors.brandMintGreen,
              ),
              const SizedBox(height: 12),
              const _PhoneCard(
                title: 'Group ledger',
                value: '62,000 RWF',
                meta: '+12% this month',
                color: CollectColors.brandPeriwinkle,
              ),
              const SizedBox(height: 12),
              const _ReadinessScore(),
              const Spacer(),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PhoneNav(
                    icon: Icons.home_filled,
                    label: 'Home',
                    active: true,
                  ),
                  _PhoneNav(icon: Icons.groups_outlined, label: 'Groups'),
                  _PhoneNav(icon: Icons.download_outlined, label: 'Save'),
                  _PhoneNav(icon: Icons.shield_outlined, label: 'Insure'),
                  _PhoneNav(icon: Icons.person_outline, label: 'Profile'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({
    required this.title,
    required this.value,
    required this.meta,
    required this.color,
  });

  final String title;
  final String value;
  final String meta;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: 0.72,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              meta,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessScore extends StatelessWidget {
  const _ReadinessScore();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: CollectColors.brandMintGreen,
                  width: 4,
                ),
              ),
              child: SizedBox.square(
                dimension: 54,
                child: Center(
                  child: Text(
                    '78',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: CollectColors.brandMintGreen,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'On track for bank-ready file',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneNav extends StatelessWidget {
  const _PhoneNav({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? CollectColors.brandPeriwinkle
        : Colors.white.withValues(alpha: 0.54);
    return Column(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontSize: 9,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _LedgerPanel extends StatelessWidget {
  const _LedgerPanel();

  @override
  Widget build(BuildContext context) {
    return _FloatingPanel(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group ledger',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nguruvu ibimina',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'This month',
            style: CollectTypography.eyebrowLabel(
              Colors.white.withValues(alpha: 0.52),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '62,000 RWF',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '+12%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CollectColors.brandMintGreen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final height in [38, 52, 44, 60, 56, 72, 84, 68, 92])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CollectColors.brandPeriwinkle.withValues(
                            alpha: height > 60 ? 0.95 : 0.42,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SizedBox(height: height.toDouble()),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisciplinePanel extends StatelessWidget {
  const _DisciplinePanel();

  @override
  Widget build(BuildContext context) {
    return _FloatingPanel(
      width: 210,
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: CollectColors.brandMintGreen,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Strong discipline',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: CollectColors.brandMintGreen,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Pay-ins consistent',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingPanel extends StatelessWidget {
  const _FloatingPanel({required this.child, required this.width});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF131520).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      ),
    );
  }
}

class _SectionBand extends StatelessWidget {
  const _SectionBand({
    required this.child,
    required this.background,
    super.key,
  });

  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 56),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SplitSection extends StatelessWidget {
  const _SplitSection({
    required this.title,
    required this.body,
    required this.steps,
  });

  final String title;
  final String body;
  final List<_StepData> steps;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final copy = _SectionIntro(title: title, body: body);
        final rail = _StepRail(steps: steps);
        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [copy, const SizedBox(height: 34), rail],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 340, child: copy),
            const SizedBox(width: 52),
            Expanded(child: rail),
          ],
        );
      },
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: CollectColors.referenceChromeBlack,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: CollectColors.inkSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.steps});

  final List<_StepData> steps;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 24,
      children: [
        for (var index = 0; index < steps.length; index += 1) ...[
          _StepTile(data: steps[index]),
          if (index < steps.length - 1)
            Icon(
              Icons.arrow_forward,
              color: CollectColors.inkMuted.withValues(alpha: 0.62),
            ),
        ],
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.data});

  final _StepData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 164,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: data.color.withValues(alpha: 0.22)),
            ),
            child: SizedBox.square(
              dimension: 74,
              child: Icon(data.icon, color: data.color, size: 34),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: CollectColors.referenceChromeBlack,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CollectColors.inkSecondary,
              height: 1.34,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsuranceSection extends StatelessWidget {
  const _InsuranceSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: const Color(0xFFFFF4F4),
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
      background: Color(0xFFF0F2FF),
      child: _SplitSection(
        title: 'CRaaS: from loan inquiry to bank-ready file',
        body:
            'AI creates scale; the IKANISA Credit Readiness Office creates trust, evidence quality and human completion before the bank starts formal credit analysis.',
        steps: [
          _StepData(
            icon: Icons.chat_bubble_outline,
            title: 'Loan inquiry',
            body: 'Member profile, purpose and loan need.',
            color: CollectColors.brandPeriwinkle,
          ),
          _StepData(
            icon: Icons.inventory_2_outlined,
            title: 'Collect file',
            body: 'Documents, checklist, KYC and gap repair.',
            color: CollectColors.brandPeriwinkle,
          ),
          _StepData(
            icon: Icons.task_alt,
            title: 'Bank-ready file',
            body: 'Indexed file, memo, risk flags and mitigants.',
            color: CollectColors.brandPeriwinkle,
          ),
          _StepData(
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
        body: 'Manage members, contributions, withdrawals and exceptions.',
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
      background: Colors.white,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8E3F2)),
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
                    'Start using Collect',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: CollectColors.referenceChromeBlack,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Get the app, create a group savings account, or dial USSD to save RWF 2,000 into Collect.',
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
                        label: 'Create group savings',
                        onPressed: () async => _openWhatsApp(
                          'Hello IKANISA, I want to create a Collect group savings account.',
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
                    const _AskMetrics(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 9, child: copy),
                  const SizedBox(width: 38),
                  const Expanded(flex: 8, child: _AskMetrics()),
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
        _ProofMetric(value: '96%', label: 'financial inclusion'),
        _ProofMetric(value: '23%', label: 'formal credit usage'),
        _ProofMetric(value: '52%', label: 'adults in ibimina'),
        _ProofMetric(value: 'US\$0.5B+', label: 'diaspora remittances'),
        _ProofMetric(value: '0', label: 'credit-readiness agents'),
        _ProofMetric(value: '90.4%', label: 'informal employment'),
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
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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

class _MediaProofVisual extends StatelessWidget {
  const _MediaProofVisual();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE8E3F2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final image = ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/brand/generated/collect_visual_momo_signal.png',
                height: compact ? 220 : 330,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            );
            const proof = _EvidenceStack();
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [image, const SizedBox(height: 18), proof],
              );
            }
            return Row(
              children: [
                Expanded(flex: 6, child: image),
                const SizedBox(width: 18),
                const Expanded(flex: 5, child: proof),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EvidenceStack extends StatelessWidget {
  const _EvidenceStack();

  @override
  Widget build(BuildContext context) {
    const items = [
      _EvidenceItem(
        title: 'Verified ledger',
        body: 'Contribution, payout and rule history.',
        icon: Icons.receipt_long_outlined,
      ),
      _EvidenceItem(
        title: 'Credit-readiness file',
        body: 'KYC, checklist, memo and gap repair.',
        icon: Icons.inventory_2_outlined,
      ),
      _EvidenceItem(
        title: 'Protected repayment',
        body: 'GIPI, CLMI and CIPI insurance rails.',
        icon: Icons.shield_outlined,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'An application-ready evidence pack',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: CollectColors.referenceChromeBlack,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        for (final item in items) _EvidenceRow(item: item),
      ],
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.item});

  final _EvidenceItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: CollectColors.brandPeriwinkle,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 42,
              child: Icon(item.icon, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: CollectColors.referenceChromeBlack,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CollectColors.inkSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
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

class _AskMetric extends StatelessWidget {
  const _AskMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: CollectTypography.amountLarge(
              CollectColors.referenceChromeBlack,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: CollectColors.inkSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AskMetrics extends StatelessWidget {
  const _AskMetrics();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        _AskMetric(value: 'RWF 35B+', label: 'deposits scenario'),
        _AskMetric(value: 'RWF 4.3B', label: '3-year bank income'),
        _AskMetric(value: '365', label: 'collections per borrower'),
        _AskMetric(value: '6.9x', label: 'income growth multiplier'),
      ],
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
                  label: 'Group savings',
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
                  label: 'Community groups',
                  onPressed: () => context.go('/community-groups'),
                ),
                _FooterLink(
                  label: 'Privacy',
                  onPressed: () => context.go('/privacy'),
                ),
                _FooterLink(
                  label: 'Terms',
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
                    'Customer support: app access, group savings setup, USSD help and account questions.',
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

class _EvidenceItem {
  const _EvidenceItem({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;
}

class CollectPublicPageData {
  const CollectPublicPageData({
    required this.path,
    required this.navLabel,
    required this.title,
    required this.intro,
    required this.imageAsset,
    required this.metricA,
    required this.metricALabel,
    required this.metricB,
    required this.metricBLabel,
    required this.sections,
  });

  final String path;
  final String navLabel;
  final String title;
  final String intro;
  final String imageAsset;
  final String metricA;
  final String metricALabel;
  final String metricB;
  final String metricBLabel;
  final List<CollectPublicSectionData> sections;
}

class CollectPublicSectionData {
  const CollectPublicSectionData({
    required this.title,
    required this.body,
    required this.bullets,
  });

  final String title;
  final String body;
  final List<String> bullets;
}

CollectPublicPageData publicPageForPath(String path) {
  return _publicPages.firstWhere((page) => page.path == path);
}

class _StepData {
  const _StepData({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
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
  position.animateTo(
    target.clamp(position.minScrollExtent, position.maxScrollExtent),
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
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
