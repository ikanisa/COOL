import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';

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
    title: 'Privacy Policy and Data Deletion',
    intro:
        'Collect protects customer information with clear consent, limited access, practical safeguards, and account and data deletion request paths for savings, support, credit-readiness and insurance journeys.',
    imageAsset: 'assets/brand/generated/collect_visual_qr_share.png',
    metricA: 'Consent',
    metricALabel: 'Customer control',
    metricB: 'Delete',
    metricBLabel: 'Request path',
    sections: [
      CollectPublicSectionData(
        title: 'Information we collect',
        body:
            'Collect may collect information needed to create and support an account, operate savings groups, keep contribution records, verify support requests, and prepare customer-requested credit-readiness or insurance records.',
        bullets: [
          'Identity, contact, Collect ID and account details provided by the customer',
          'Group membership, roles, rules, contribution activity and payout records',
          'Payment references, support messages, consent choices and service notifications',
          'Camera or image inputs only when a customer uses a QR, support, or evidence feature',
        ],
      ),
      CollectPublicSectionData(
        title: 'How information is used',
        body:
            'Customer information is used to operate Collect, maintain group records, support savings workflows, prepare records customers request, protect accounts, prevent misuse, and respond to customer support or deletion requests.',
        bullets: [
          'Operate app, WhatsApp, support and group workflows',
          'Prepare savings, contribution, credit-readiness and insurance support records',
          'Protect accounts, prevent misuse, investigate disputes and support recovery',
          'Improve reliability, customer support and service quality',
        ],
      ),
      CollectPublicSectionData(
        title: 'Sharing and service providers',
        body:
            'Collect does not sell customer personal data. Information may be shared only when needed to operate the service, support customer requests, process payment or support workflows, meet legal obligations, or work with service providers under appropriate controls.',
        bullets: [
          'Payment, messaging, hosting, analytics, security and support service providers',
          'Banks, insurers, cooperatives, group leaders or partners only when required for a customer-requested workflow',
          'Authorities, auditors or dispute handlers where legally required',
        ],
      ),
      CollectPublicSectionData(
        title: 'Security and retention',
        body:
            'Collect uses access controls, transport security and operational safeguards to protect customer information. Records are kept only as long as needed for the service, customer support, security, audit, dispute, payment reconciliation, tax, legal or regulatory reasons.',
        bullets: [
          'Data is protected in transit and access is limited by role',
          'Raw sensitive records are minimized where possible',
          'Ledger, security, dispute, payment and legal records may be retained where required',
        ],
      ),
      CollectPublicSectionData(
        title: 'Account deletion request',
        body:
            'Customers can request deletion of their Collect account and associated account data from inside the app or from this public web resource without reinstalling the app.',
        bullets: [
          'In app: Settings, then account deletion request',
          'Email: info@ikanisa.com with the phone number or Collect ID connected to the account',
          'WhatsApp: +250 795 588 248 with the same account details',
          'IKANISA may verify account ownership before processing the request',
        ],
      ),
      CollectPublicSectionData(
        title: 'Data deletion and correction request',
        body:
            'Customers can also ask IKANISA to delete or correct personal data that is no longer needed for Collect. When an app account is deleted, associated user data is deleted unless limited retention is required for legitimate security, fraud-prevention, ledger, dispute, payment, audit, tax, legal or regulatory reasons.',
        bullets: [
          'Request deletion or correction by app, email or WhatsApp',
          'Support reviews open groups, unresolved payments and required records',
          'Support can confirm request status and explain retained record categories',
        ],
      ),
      CollectPublicSectionData(
        title: 'Customer choices and contact',
        body:
            'Customers can ask privacy questions, request access, correction, account deletion or data deletion, and get support through IKANISA contact channels.',
        bullets: [
          'Email: info@ikanisa.com',
          'WhatsApp: +250 795 588 248',
          'Website: https://collect.ikanisa.com/#/privacy',
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

class LandingStepData {
  const LandingStepData({
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

String publicSummaryLabel(CollectPublicPageData data) {
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

String publicInfographicTitle(String path) {
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

String publicInfographicBody(String path) {
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

Color publicInfographicBackground(String path) {
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

List<LandingStepData> publicInfographicSteps(String path) {
  switch (path) {
    case '/group-savings':
      return const [
        LandingStepData(
          icon: Icons.group_add_outlined,
          title: 'Start the group',
          body:
              'Set up a savings group with clear members, purpose and contribution rhythm.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.dialpad_outlined,
          title: 'Invite members',
          body:
              'Share a link or QR code through the channels members already use.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.sms_outlined,
          title: 'Track saving',
          body:
              'Members contribute and the group follows progress from one record.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Use the record',
          body:
              'Turn saving discipline into statements and credit-readiness evidence.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/diaspora':
      return const [
        LandingStepData(
          icon: Icons.public_outlined,
          title: 'Form pool',
          body: 'Diaspora members agree rules, roles and saving objectives.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.account_balance_outlined,
          title: 'Custody record',
          body:
              'Savings history is organized into traceable records and statements.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.lock_outline,
          title: 'Collateral lock',
          body: 'A defined portion can be ring-fenced under approved rules.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.location_on_outlined,
          title: 'Rwanda pathway',
          body:
              'Evidence supports property, SME, agriculture or asset finance review.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/insurance':
      return const [
        LandingStepData(
          icon: Icons.savings_outlined,
          title: 'Reserve',
          body: 'Savings behavior can reserve toward premium obligations.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.verified_user_outlined,
          title: 'Protect',
          body:
              'GIPI, CLMI and CIPI connect protection to the customer journey.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Finance gap',
          body: 'Approved premium finance can pay the insurer directly.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.health_and_safety_outlined,
          title: 'Recover',
          body:
              'Claims and repayment support use contribution and premium context.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/craas':
      return const [
        LandingStepData(
          icon: Icons.chat_bubble_outline,
          title: 'Inquiry',
          body: 'Understand the customer need.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.inventory_2_outlined,
          title: 'File support',
          body: 'Organize records and missing items.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.rule_outlined,
          title: 'Readiness notes',
          body: 'Prepare a clear customer summary.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.account_balance_outlined,
          title: 'Handoff',
          body: 'Share a cleaner file for review.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/community-groups':
      return const [
        LandingStepData(
          icon: Icons.home_outlined,
          title: 'Join',
          body: 'Enter the group from a link or QR code.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.groups_outlined,
          title: 'Save',
          body: 'Contribute and follow the group record.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.settings_outlined,
          title: 'Track',
          body: 'See member activity and progress.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.support_agent_outlined,
          title: 'Support',
          body: 'Get help without exposing private data.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/impact':
      return const [
        LandingStepData(
          icon: Icons.payments_outlined,
          title: '864M',
          body: 'Mobile payment transfers',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.account_balance_wallet_outlined,
          title: 'RWF 19,807B',
          body: 'Mobile payment transfer value',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.phone_android_outlined,
          title: '7,169,324',
          body: 'Active mobile payment subscribers',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.storefront_outlined,
          title: '169,570',
          body: 'Mobile payment agents',
          color: CollectColors.brandOrangeRed,
        ),
        LandingStepData(
          icon: Icons.handshake_outlined,
          title: '~60%',
          body: 'Adult informal group saving prevalence',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.shield_outlined,
          title: 'RWF 351.3B',
          body: 'Total insurance GWP',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.two_wheeler_outlined,
          title: 'RWF 67.6B',
          body: 'Motor insurance premiums',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.trending_up_outlined,
          title: '26.2%',
          body: 'Motor premium growth',
          color: CollectColors.brandOrangeRed,
        ),
        LandingStepData(
          icon: Icons.groups_outlined,
          title: '25,000',
          body: 'Kigali moto-taxi drivers',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.map_outlined,
          title: '70,000',
          body: 'National moto-taxi drivers',
          color: CollectColors.brandMintGreen,
        ),
      ];
    case '/our-partners':
      return const [
        LandingStepData(
          icon: Icons.payments_outlined,
          title: '864M',
          body: 'Mobile payment transfers',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.account_balance_wallet_outlined,
          title: 'RWF 19,807B',
          body: 'Mobile payment transfer value',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.phone_android_outlined,
          title: '7,169,324',
          body: 'Active mobile payment subscribers',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.storefront_outlined,
          title: '169,570',
          body: 'Mobile payment agents',
          color: CollectColors.brandOrangeRed,
        ),
        LandingStepData(
          icon: Icons.handshake_outlined,
          title: '~60%',
          body: 'Adult informal group saving prevalence',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.shield_outlined,
          title: 'RWF 351.3B',
          body: 'Total insurance GWP',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.two_wheeler_outlined,
          title: 'RWF 67.6B',
          body: 'Motor insurance premiums',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.trending_up_outlined,
          title: '26.2%',
          body: 'Motor premium growth',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.groups_outlined,
          title: '25,000',
          body: 'Kigali moto-taxi drivers',
          color: CollectColors.brandOrangeRed,
        ),
        LandingStepData(
          icon: Icons.map_outlined,
          title: '70,000',
          body: 'National moto-taxi drivers',
          color: CollectColors.brandMintGreen,
        ),
      ];
  }
  return const [];
}
