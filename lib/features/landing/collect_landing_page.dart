import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_typography.dart';

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
  '/impact',
  '/our-partners',
  '/privacy',
  '/account-deletion',
  '/data-deletion',
  '/terms',
};

const _publicPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/group-savings',
    navLabel: 'Group Savings',
    title: 'Group savings that become credit evidence',
    intro:
        'Cleaner records for ibimina, savings groups and members building financial proof together.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: '52%',
    metricALabel: 'Adults in ibimina',
    metricB: 'Credit-ready',
    metricBLabel: 'Saving records',
    sections: [
      CollectPublicSectionData(
        title: 'Run the group clearly',
        body: 'Keep the trust of the group. Add clean records.',
        bullets: [
          'Members and roles',
          'Contribution history',
          'Privacy-safe Collect IDs',
        ],
      ),
      CollectPublicSectionData(
        title: 'Make contributions easier to follow',
        body: 'Members pay in a familiar way and see a clear group record.',
        bullets: [
          'Amount and status',
          'One group activity view',
          'Less screenshot chasing',
        ],
      ),
      CollectPublicSectionData(
        title: 'Invite without friction',
        body: 'Share the group through the channels members already use.',
        bullets: [
          'Links and QR codes',
          'Chat app sharing',
          'Private payment details protected',
        ],
      ),
      CollectPublicSectionData(
        title: 'Support treasurers',
        body: 'Give leaders a cleaner way to answer member questions.',
        bullets: [
          'Paid and pending view',
          'Meeting-ready records',
          'Less manual follow-up',
        ],
      ),
      CollectPublicSectionData(
        title: 'Credit-ready evidence',
        body: 'Turn saving discipline into records members can use later.',
        bullets: [
          'Group statements',
          'Member histories',
          'Credit-readiness support',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/diaspora',
    navLabel: 'Diaspora',
    title: 'Diaspora savings with custody and collateral rules',
    intro:
        'A structured way for diaspora groups to save together and prepare Rwanda investment pathways.',
    imageAsset: 'assets/brand/generated/collect_visual_qr_share.png',
    metricA: 'US\$0.5B+',
    metricALabel: 'Remittance opportunity',
    metricB: 'Custody',
    metricBLabel: 'Ring-fenced rules',
    sections: [
      CollectPublicSectionData(
        title: 'Diaspora group saving structure',
        body: 'Give members a shared record before funds are committed.',
        bullets: [
          'Rules and roles',
          'Member balances',
          'Contribution statements',
        ],
      ),
      CollectPublicSectionData(
        title: 'Custody and collateral rules',
        body: 'Separate free savings from locked commitments.',
        bullets: [
          'Custody records',
          'Collateral rules',
          'Approved member commitments',
        ],
      ),
      CollectPublicSectionData(
        title: 'Rwanda investment pathways',
        body: 'Prepare clearer records for productive investment back home.',
        bullets: ['Property', 'SMEs', 'Agriculture and assets'],
      ),
      CollectPublicSectionData(
        title: 'Trust and communication',
        body: 'Keep members aligned with fewer side conversations.',
        bullets: [
          'Member visibility',
          'Support channel',
          'Partner-ready records',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/insurance',
    navLabel: 'Insurance',
    title: 'Embedded insurance for resilient repayment',
    intro:
        'Protection connected to saving, borrowing and repayment resilience.',
    imageAsset: 'assets/brand/generated/collect_visual_momo_signal.png',
    metricA: 'GIPI',
    metricALabel: 'Group income protection',
    metricB: 'CLMI/CIPI',
    metricBLabel: 'Credit protection',
    sections: [
      CollectPublicSectionData(
        title: 'Protection at the point of saving',
        body: 'Make protection part of the financial journey.',
        bullets: [
          'Group income protection',
          'Credit life cover',
          'Credit income protection',
        ],
      ),
      CollectPublicSectionData(
        title: 'Prepare for premiums',
        body: 'Help customers plan for cover before deadlines arrive.',
        bullets: [
          'Protection reserves',
          'Premium support',
          'Visible follow-up',
        ],
      ),
      CollectPublicSectionData(
        title: 'Simple product language',
        body: 'Explain what is protected and when it applies.',
        bullets: ['GIPI', 'CLMI', 'CIPI'],
      ),
      CollectPublicSectionData(
        title: 'Cleaner support records',
        body: 'Keep the savings and protection context together.',
        bullets: ['Member records', 'Protection history', 'Support path'],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/craas',
    navLabel: 'CRaaS',
    title: 'Credit Readiness as a Service',
    intro:
        'Support that turns customer records into a cleaner credit-readiness file.',
    imageAsset: 'assets/brand/generated/collect_visual_momo_signal.png',
    metricA: 'Readiness',
    metricALabel: 'File support',
    metricB: 'Bank-ready',
    metricBLabel: 'Customer handoff',
    sections: [
      CollectPublicSectionData(
        title: 'Prepare before asking for credit',
        body: 'Organize the customer story before the credit conversation.',
        bullets: [
          'Customer profile',
          'Loan purpose',
          'Missing-document support',
        ],
      ),
      CollectPublicSectionData(
        title: 'Use Collect records as proof',
        body: 'Show discipline through real saving and group records.',
        bullets: [
          'Savings discipline',
          'Group participation',
          'Protection context',
        ],
      ),
      CollectPublicSectionData(
        title: 'Human support to complete the file',
        body: 'Help customers close gaps before they submit.',
        bullets: ['Checklist support', 'Customer summary', 'WhatsApp help'],
      ),
      CollectPublicSectionData(
        title: 'Clear next step',
        body: 'Prepare a cleaner file for review.',
        bullets: [
          'Organized records',
          'Customer summary',
          'No approval promise',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/community-groups',
    navLabel: 'Community Groups',
    title: 'Community groups as distribution infrastructure',
    intro:
        'A mobile app for trusted groups that save, contribute and support members.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: 'Group',
    metricALabel: 'Member records',
    metricB: 'Mobile app',
    metricBLabel: 'Group operations',
    sections: [
      CollectPublicSectionData(
        title: 'Member app',
        body: 'A simple place to join, contribute and follow progress.',
        bullets: ['Join groups', 'Track contributions', 'Use Collect ID'],
      ),
      CollectPublicSectionData(
        title: 'Leader support',
        body: 'Give group leaders cleaner records for meetings and follow-up.',
        bullets: ['Member activity', 'Group sharing', 'Meeting records'],
      ),
      CollectPublicSectionData(
        title: 'Member journey',
        body: 'Reduce confusion after a member contributes.',
        bullets: ['Join', 'Contribute', 'Follow status'],
      ),
      CollectPublicSectionData(
        title: 'Trusted group support',
        body: 'Use groups as trusted channels for saving and support.',
        bullets: ['Local trust', 'Customer help', 'Reusable records'],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/impact',
    navLabel: 'Impact',
    title: "Impact for Rwanda's daily economy",
    intro:
        'Public market data shows the scale of the savings, payment, insurance and group-economy opportunity Collect is built to serve.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: '864M',
    metricALabel: '2024 payment txns',
    metricB: 'RWF 19,807B',
    metricBLabel: '2024 payment value',
    sections: [
      CollectPublicSectionData(
        title: 'Payment rails already operate at scale',
        body:
            'Rwanda already has payment rails with national reach and everyday customer familiarity.',
        bullets: [
          'Large active mobile-payment subscriber base',
          'Broad mobile-payment agent network',
          'Daily micro-savings via MoMo is operationally viable',
        ],
      ),
      CollectPublicSectionData(
        title: 'Informal saving is already a mass behavior',
        body:
            'Informal group saving is already a mainstream household behavior.',
        bullets: [
          'Informal groups and VSLAs are already active',
          'Cooperative distribution can scale nationally',
          'Savings behavior can become structured evidence',
        ],
      ),
      CollectPublicSectionData(
        title: 'Insurance market with a concrete renewal problem',
        body:
            'Insurance is a material market, and motor cover creates a concrete renewal use case for saving-linked protection.',
        bullets: [
          'Motor cover is a visible, recurring customer obligation',
          'Moto-taxi associations create a reachable segment',
          'Premium planning can be connected to savings behavior',
        ],
      ),
      CollectPublicSectionData(
        title: 'Moto-taxi customers are a visible distribution base',
        body:
            'Public market sizing identifies moto-taxi drivers as a concentrated, repeat-payment customer segment.',
        bullets: [
          'Kigali has a concentrated driver base',
          'The national driver base expands the channel',
          'Daily earning rhythm fits small recurring saving',
        ],
      ),
      CollectPublicSectionData(
        title: 'Public impact potential',
        body:
            'Collect connects existing savings behavior to cleaner records that can support inclusion, protection and future credit readiness.',
        bullets: [
          'More visible savings discipline',
          'Better prepared credit conversations',
          'Clearer insurance and repayment support',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/our-partners',
    navLabel: 'Our Partners',
    title: 'Our Partners',
    intro:
        'Collect gives banks, insurers, cooperatives and mobile-money partners a public-data-backed opportunity to serve existing savings behavior more clearly.',
    imageAsset: 'assets/brand/generated/collect_visual_momo_signal.png',
    metricA: 'RWF 351.3B',
    metricALabel: 'Insurance GWP',
    metricB: '169,570',
    metricBLabel: 'Payment agents',
    sections: [
      CollectPublicSectionData(
        title: 'Banks and deposit partners',
        body:
            'Rwanda already has large digital payment activity and a broad subscriber base for structured savings collection.',
        bullets: [
          'Mobile payments are already habitual',
          'Payment value is already material',
          'Savings collection can build on existing customer behavior',
        ],
      ),
      CollectPublicSectionData(
        title: 'Insurers',
        body:
            'The insurance market is already material, with motor cover a concrete use case for saving-linked protection.',
        bullets: [
          'Total insurance premiums show market depth',
          'Motor premiums show a practical entry point',
          'Recurring cover can be supported by recurring saving',
        ],
      ),
      CollectPublicSectionData(
        title: 'Cooperatives and savings groups',
        body:
            'Informal group saving is already part of household financial behavior and can become cleaner operating evidence.',
        bullets: [
          'Informal group saving is already widespread',
          'Ibimina and VSLAs already operate locally',
          'Groups can be stronger last-mile financial channels',
        ],
      ),
      CollectPublicSectionData(
        title: 'Mobile-money and agent networks',
        body:
            'Collect can sit on top of familiar payment rails rather than asking customers to learn a new payment behavior.',
        bullets: [
          'Agent networks are already broad',
          'Subscriber reach is already large',
          'Mobile money is already a familiar channel',
        ],
      ),
      CollectPublicSectionData(
        title: 'Moto-taxi associations',
        body:
            'Moto-taxi drivers are a visible segment for recurring saving, cover renewal and credit-readiness support.',
        bullets: [
          'Kigali has a concentrated driver base',
          'The national driver base expands the channel',
          'Daily income rhythm supports small repeated contributions',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/privacy',
    navLabel: 'Privacy Policy',
    title: 'Privacy Policy',
    intro:
        'Collect protects customer information with clear consent, limited access and practical safeguards for savings, credit-readiness and insurance journeys.',
    imageAsset: 'assets/brand/generated/collect_visual_qr_share.png',
    metricA: 'Consent',
    metricALabel: 'Customer control',
    metricB: 'Secure',
    metricBLabel: 'Records handling',
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
          'Operate app, WhatsApp and group workflows',
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
          'Support for customer records',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/account-deletion',
    navLabel: 'Account Deletion',
    title: 'Account Deletion',
    intro:
        'Collect customers can request account deletion from the app or by contacting IKANISA support.',
    imageAsset: 'assets/brand/generated/collect_visual_qr_share.png',
    metricA: 'Request',
    metricALabel: 'Customer control',
    metricB: 'Review',
    metricBLabel: 'Required records',
    sections: [
      CollectPublicSectionData(
        title: 'How to request deletion',
        body:
            'Open Collect settings and use the account deletion request option, or contact IKANISA support if you cannot access the app.',
        bullets: [
          'In app: Settings, then account deletion request',
          'Email: info@ikanisa.com',
          'WhatsApp: +250 795 588 248',
        ],
      ),
      CollectPublicSectionData(
        title: 'What happens next',
        body:
            'Support reviews the request, verifies account ownership where needed and starts deletion for account data that is no longer required to provide the service.',
        bullets: [
          'Access and profile data are reviewed',
          'Open groups or payment issues may need resolution first',
          'Support can confirm request status',
        ],
      ),
      CollectPublicSectionData(
        title: 'Records we may retain',
        body:
            'Some ledger, security, dispute, payment and legal records may be retained where required for audit, fraud prevention, customer support or legal compliance.',
        bullets: [
          'Savings ledger records needed for group accountability',
          'Security and abuse-prevention records',
          'Legal, tax, audit or dispute records',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/data-deletion',
    navLabel: 'Data Deletion',
    title: 'Data Deletion',
    intro:
        'Collect customers can ask IKANISA to delete or correct personal data that is no longer needed for the service.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: 'Data',
    metricALabel: 'Deletion request',
    metricB: 'Support',
    metricBLabel: 'Customer review',
    sections: [
      CollectPublicSectionData(
        title: 'Submit a data deletion request',
        body:
            'Use the in-app account deletion request, or contact IKANISA support with the phone number or Collect ID connected to your account.',
        bullets: [
          'In app: Settings, then account deletion request',
          'Email: info@ikanisa.com',
          'WhatsApp: +250 795 588 248',
        ],
      ),
      CollectPublicSectionData(
        title: 'Data covered by the request',
        body:
            'Requests may cover profile details, support messages, consent choices and other account data that Collect no longer needs to operate the service.',
        bullets: [
          'Account and contact details',
          'Support and consent records',
          'Service data no longer needed for active groups',
        ],
      ),
      CollectPublicSectionData(
        title: 'Limited retention',
        body:
            'Collect may retain limited records where needed for audit, group ledger integrity, security, disputes, payment reconciliation or legal obligations.',
        bullets: [
          'Ledger records needed by groups',
          'Fraud prevention and security records',
          'Legal, tax, audit or dispute records',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/terms',
    navLabel: 'Terms of Service',
    title: 'Terms of Service',
    intro:
        'These terms explain how customers use Collect for group savings, contribution records, credit-readiness support, insurance records and customer service.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: 'Customer',
    metricALabel: 'Service terms',
    metricB: 'Clear',
    metricBLabel: 'Group rules',
    sections: [
      CollectPublicSectionData(
        title: 'Using Collect',
        body:
            'Customers are responsible for providing accurate information, following their group rules and using Collect only for lawful savings, contribution and support activities.',
        bullets: [
          'Keep account and group information accurate',
          'Use app and WhatsApp channels responsibly',
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
          'Support for group savings setup',
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
                      color: CollectColors.publicMutedGrey,
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
                background: CollectColors.publicWhite,
                child: _SplitSection(
                  title: 'How ibimina become verified records',
                  body:
                      'IKANISA helps trusted groups turn saving discipline into clearer records, statements and credit-readiness signals.',
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
                      body: 'MoMo, app or agent-backed deposits.',
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
                background: CollectColors.publicMintSurface,
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
                _publicSummaryLabel(data),
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
    final steps = _publicInfographicSteps(data.path);
    return _SectionBand(
      background: _publicInfographicBackground(data.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _publicInfographicTitle(data.path),
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
              _publicInfographicBody(data.path),
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

  final _StepData data;
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
            Image.asset(
              'assets/brand/generated/collect_app_icon_rule.png',
              width: compact ? 38 : 42,
              height: compact ? 38 : 42,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.account_balance_wallet_outlined,
                color: CollectColors.brandPaper,
              ),
            ),
            const SizedBox(width: 10),
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
                  'By IKANISA',
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
      ('Impact', '/impact'),
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
      ('Group Savings', '/group-savings'),
      ('Diaspora', '/diaspora'),
      ('Insurance', '/insurance'),
      ('CRaaS', '/craas'),
      ('Community Groups', '/community-groups'),
      ('Impact', '/impact'),
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
                  minimumSize: const Size(0, 40),
                  textStyle: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
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
              fontWeight: FontWeight.w900,
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
              color: CollectColors.brandOrangeRed,
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

class _ProductMediaSection extends StatelessWidget {
  const _ProductMediaSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: CollectColors.publicWhite,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          const content = _SectionIntro(
            title: 'The product surface is more than group collections',
            body:
                'Collect helps customers turn group activity into records they can understand and use.',
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
          color: CollectColors.publicWhite.withValues(alpha: 0.26),
          width: 2,
        ),
        color: CollectColors.publicDeepInk,
        boxShadow: [
          BoxShadow(
            color: CollectColors.publicBlack.withValues(alpha: 0.42),
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
                      color: CollectColors.publicWhite,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.notifications_none,
                    color: CollectColors.publicWhite,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Total balance',
                style: CollectTypography.eyebrowLabel(
                  CollectColors.publicWhite.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '250,000 RWF',
                style: CollectTypography.amountDisplay(
                  CollectColors.publicWhite,
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
        color: CollectColors.publicWhite.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: CollectColors.publicWhite,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: CollectColors.publicWhite,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: 0.72,
                minHeight: 6,
                backgroundColor: CollectColors.publicWhite.withValues(
                  alpha: 0.1,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              meta,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: CollectColors.publicWhite.withValues(alpha: 0.62),
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
        color: CollectColors.publicWhite.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.12),
        ),
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
                      color: CollectColors.publicWhite,
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
                      color: CollectColors.publicWhite.withValues(alpha: 0.62),
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
        : CollectColors.publicWhite.withValues(alpha: 0.54);
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
              color: CollectColors.publicWhite,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nguruvu ibimina',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: CollectColors.publicWhite.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'This month',
            style: CollectTypography.eyebrowLabel(
              CollectColors.publicWhite.withValues(alpha: 0.52),
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
                    color: CollectColors.publicWhite,
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
                    color: CollectColors.publicWhite.withValues(alpha: 0.62),
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
        color: CollectColors.publicPanelInk.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CollectColors.publicWhite.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: CollectColors.publicBlack.withValues(alpha: 0.3),
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
          _StepData(
            icon: Icons.chat_bubble_outline,
            title: 'Loan inquiry',
            body: 'Member profile, purpose and loan need.',
            color: CollectColors.brandPeriwinkle,
          ),
          _StepData(
            icon: Icons.inventory_2_outlined,
            title: 'Collect file',
            body: 'Documents, checklist and missing-item support.',
            color: CollectColors.brandPeriwinkle,
          ),
          _StepData(
            icon: Icons.task_alt,
            title: 'Bank-ready file',
            body: 'Organized evidence and customer summary.',
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

class _MediaProofVisual extends StatelessWidget {
  const _MediaProofVisual();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.publicSoftLavender,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: CollectColors.publicLavenderBorder),
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
        body: 'Checklist, customer summary and missing-item support.',
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
              child: Icon(
                item.icon,
                color: CollectColors.publicWhite,
                size: 22,
              ),
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

  bool get isPolicy => path == '/privacy' || path == '/terms';
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

String _publicSummaryLabel(CollectPublicPageData data) {
  switch (data.path) {
    case '/group-savings':
      return 'Ibimina operating model';
    case '/diaspora':
      return 'Diaspora custody model';
    case '/insurance':
      return 'Protection layer';
    case '/craas':
      return 'Credit-readiness service';
    case '/community-groups':
      return 'Mobile group operations';
    case '/impact':
      return 'Inclusion to credit conversion';
    case '/our-partners':
      return 'Partner operating case';
    case '/privacy':
      return 'Customer information';
    case '/account-deletion':
      return 'Account deletion';
    case '/data-deletion':
      return 'Data deletion';
    case '/terms':
      return 'Service terms';
  }
  return data.navLabel;
}

String _publicInfographicTitle(String path) {
  switch (path) {
    case '/group-savings':
      return 'Group savings journey';
    case '/diaspora':
      return 'Diaspora savings pathway';
    case '/insurance':
      return 'Protection and premium flow';
    case '/craas':
      return 'From inquiry to bank-ready file';
    case '/community-groups':
      return 'What the app enables for a group';
    case '/impact':
      return 'Impact chain';
    case '/our-partners':
      return 'Partner value chain';
    case '/account-deletion':
      return 'Customer deletion request';
    case '/data-deletion':
      return 'Data deletion request';
  }
  return 'Collect workflow';
}

String _publicInfographicBody(String path) {
  switch (path) {
    case '/group-savings':
      return 'Start together. Save together. Build a record together.';
    case '/diaspora':
      return 'Save across borders with clearer rules and records.';
    case '/insurance':
      return 'Link saving behavior with protection and repayment resilience.';
    case '/craas':
      return 'Turn customer activity into a cleaner readiness file.';
    case '/community-groups':
      return 'Give trusted groups a simple mobile operating layer.';
    case '/impact':
      return 'Public market scale across payments, saving, insurance and reachable customer groups.';
    case '/our-partners':
      return 'Public data points for banks, insurers, cooperatives and payment partners.';
    case '/account-deletion':
      return 'Request deletion in app or through IKANISA support.';
    case '/data-deletion':
      return 'Ask support to delete or correct data that is no longer needed.';
  }
  return 'A clear workflow that shows how Collect turns activity into usable records.';
}

Color _publicInfographicBackground(String path) {
  switch (path) {
    case '/insurance':
      return CollectColors.publicSoftDanger;
    case '/craas':
      return CollectColors.publicSoftInfo;
    case '/diaspora':
      return CollectColors.publicMintSurface;
    case '/our-partners':
      return CollectColors.publicSoftNeutral;
    default:
      return CollectColors.publicWhite;
  }
}

List<_StepData> _publicInfographicSteps(String path) {
  switch (path) {
    case '/group-savings':
      return const [
        _StepData(
          icon: Icons.group_add_outlined,
          title: 'Start the group',
          body:
              'Set up a savings group with clear members, purpose and contribution rhythm.',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.dialpad_outlined,
          title: 'Invite members',
          body:
              'Share a link or QR code through the channels members already use.',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.sms_outlined,
          title: 'Track saving',
          body:
              'Members contribute and the group follows progress from one record.',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.receipt_long_outlined,
          title: 'Use the record',
          body:
              'Turn saving discipline into statements and credit-readiness evidence.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/diaspora':
      return const [
        _StepData(
          icon: Icons.public_outlined,
          title: 'Form pool',
          body: 'Diaspora members agree rules, roles and saving objectives.',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.account_balance_outlined,
          title: 'Custody record',
          body:
              'Savings history is organized into traceable records and statements.',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.lock_outline,
          title: 'Collateral lock',
          body: 'A defined portion can be ring-fenced under approved rules.',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.location_on_outlined,
          title: 'Rwanda pathway',
          body:
              'Evidence supports property, SME, agriculture or asset finance review.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/insurance':
      return const [
        _StepData(
          icon: Icons.savings_outlined,
          title: 'Reserve',
          body: 'Savings behavior can reserve toward premium obligations.',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.verified_user_outlined,
          title: 'Protect',
          body:
              'GIPI, CLMI and CIPI connect protection to the customer journey.',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Finance gap',
          body: 'Approved premium finance can pay the insurer directly.',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.health_and_safety_outlined,
          title: 'Recover',
          body:
              'Claims and repayment support use contribution and premium context.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/craas':
      return const [
        _StepData(
          icon: Icons.chat_bubble_outline,
          title: 'Inquiry',
          body: 'Understand the customer need.',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.inventory_2_outlined,
          title: 'File support',
          body: 'Organize records and missing items.',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.rule_outlined,
          title: 'Readiness notes',
          body: 'Prepare a clear customer summary.',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.account_balance_outlined,
          title: 'Handoff',
          body: 'Share a cleaner file for review.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/community-groups':
      return const [
        _StepData(
          icon: Icons.home_outlined,
          title: 'Join',
          body: 'Enter the group from a link or QR code.',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.groups_outlined,
          title: 'Save',
          body: 'Contribute and follow the group record.',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.settings_outlined,
          title: 'Track',
          body: 'See member activity and progress.',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.support_agent_outlined,
          title: 'Support',
          body: 'Get help without exposing private data.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/impact':
      return const [
        _StepData(
          icon: Icons.payments_outlined,
          title: '864M',
          body: 'Mobile payment transfers',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.account_balance_wallet_outlined,
          title: 'RWF 19,807B',
          body: 'Mobile payment transfer value',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.phone_android_outlined,
          title: '7,169,324',
          body: 'Active mobile payment subscribers',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.storefront_outlined,
          title: '169,570',
          body: 'Mobile payment agents',
          color: CollectColors.brandOrangeRed,
        ),
        _StepData(
          icon: Icons.handshake_outlined,
          title: '~60%',
          body: 'Adult informal group saving prevalence',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.shield_outlined,
          title: 'RWF 351.3B',
          body: 'Total insurance GWP',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.two_wheeler_outlined,
          title: 'RWF 67.6B',
          body: 'Motor insurance premiums',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.trending_up_outlined,
          title: '26.2%',
          body: 'Motor premium growth',
          color: CollectColors.brandOrangeRed,
        ),
        _StepData(
          icon: Icons.groups_outlined,
          title: '25,000',
          body: 'Kigali moto-taxi drivers',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.map_outlined,
          title: '70,000',
          body: 'National moto-taxi drivers',
          color: CollectColors.brandMintGreen,
        ),
      ];
    case '/our-partners':
      return const [
        _StepData(
          icon: Icons.payments_outlined,
          title: '864M',
          body: 'Mobile payment transfers',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.account_balance_wallet_outlined,
          title: 'RWF 19,807B',
          body: 'Mobile payment transfer value',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.phone_android_outlined,
          title: '7,169,324',
          body: 'Active mobile payment subscribers',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.storefront_outlined,
          title: '169,570',
          body: 'Mobile payment agents',
          color: CollectColors.brandOrangeRed,
        ),
        _StepData(
          icon: Icons.handshake_outlined,
          title: '~60%',
          body: 'Adult informal group saving prevalence',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.shield_outlined,
          title: 'RWF 351.3B',
          body: 'Total insurance GWP',
          color: CollectColors.brandMintGreen,
        ),
        _StepData(
          icon: Icons.two_wheeler_outlined,
          title: 'RWF 67.6B',
          body: 'Motor insurance premiums',
          color: CollectColors.brandPeriwinkle,
        ),
        _StepData(
          icon: Icons.trending_up_outlined,
          title: '26.2%',
          body: 'Motor premium growth',
          color: CollectColors.brandDustyRose,
        ),
        _StepData(
          icon: Icons.groups_outlined,
          title: '25,000',
          body: 'Kigali moto-taxi drivers',
          color: CollectColors.brandOrangeRed,
        ),
        _StepData(
          icon: Icons.map_outlined,
          title: '70,000',
          body: 'National moto-taxi drivers',
          color: CollectColors.brandMintGreen,
        ),
      ];
  }
  return const [];
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
