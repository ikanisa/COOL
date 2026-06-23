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
    title: 'Group savings with clearer records',
    intro:
        'Cleaner records for ibimina, savings groups and members managing contributions together.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: 'Setup',
    metricALabel: 'Group rules',
    metricB: 'Statements',
    metricBLabel: 'Treasurer visibility',
    sections: [
      CollectPublicSectionData(
        title: 'Run the group clearly',
        body: 'Keep the trust of the group. Add clean records.',
        bullets: [
          'Members and roles',
          'Contribution history',
          'Private payment details protected',
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
        title: 'Prepare support files',
        body:
            'Turn contribution history into records members can use when they ask for support.',
        bullets: ['Group statements', 'Member histories', 'Request summaries'],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/diaspora',
    navLabel: 'Diaspora',
    title: 'Diaspora group savings records',
    intro:
        'Diaspora groups can organize savings records and prepare information for Rwanda-focused discussions.',
    imageAsset: 'assets/brand/generated/collect_visual_qr_share.png',
    metricA: 'Group records',
    metricALabel: 'Member contributions',
    metricB: 'Preparation',
    metricBLabel: 'Rwanda discussions',
    sections: [
      CollectPublicSectionData(
        title: 'Diaspora group structure',
        body: 'Give members a shared record before decisions are made.',
        bullets: [
          'Rules and roles',
          'Member balances',
          'Contribution statements',
        ],
      ),
      CollectPublicSectionData(
        title: 'Readable contribution history',
        body: 'Keep savings activity easier to review and explain.',
        bullets: ['Group records', 'Member summaries', 'Support notes'],
      ),
      CollectPublicSectionData(
        title: 'Rwanda-focused preparation',
        body: 'Prepare cleaner information for future Rwanda discussions.',
        bullets: ['Purpose notes', 'Member requests', 'Supporting records'],
      ),
      CollectPublicSectionData(
        title: 'Trust and communication',
        body: 'Keep members aligned with fewer side conversations.',
        bullets: [
          'Member visibility',
          'Support channel',
          'Request-ready records',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/insurance',
    navLabel: 'Insurance',
    title: 'Insurance record support',
    intro:
        'Collect can help organize insurance-related records where approved providers are involved.',
    imageAsset: 'assets/brand/generated/collect_visual_momo_signal.png',
    metricA: 'Records',
    metricALabel: 'Customer support',
    metricB: 'Providers',
    metricBLabel: 'Final decisions',
    sections: [
      CollectPublicSectionData(
        title: 'Organize insurance-related records',
        body:
            'Keep relevant customer, group and contribution details easier to review.',
        bullets: ['Customer details', 'Contribution history', 'Support notes'],
      ),
      CollectPublicSectionData(
        title: 'Support approved provider workflows',
        body:
            'Collect supports records and communication; providers remain responsible for product decisions.',
        bullets: [
          'Provider review',
          'Customer follow-up',
          'Decision boundaries',
        ],
      ),
      CollectPublicSectionData(
        title: 'Avoid unclear promises',
        body:
            'The website does not say IKANISA issues policies or pays insurance benefits.',
        bullets: ['Records only', 'Provider decisions', 'WhatsApp support'],
      ),
      CollectPublicSectionData(
        title: 'Cleaner support records',
        body:
            'Keep the savings and insurance-support context together when customers ask questions.',
        bullets: ['Member records', 'Support history', 'Clear next steps'],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/craas',
    navLabel: 'CRaaS',
    title: 'Credit Readiness as a Service',
    intro:
        'Collect helps customers organize documents, contribution history, and request summaries before a provider review.',
    imageAsset: 'assets/brand/generated/collect_visual_momo_signal.png',
    metricA: 'Readiness',
    metricALabel: 'File support',
    metricB: 'Provider',
    metricBLabel: 'Final decision',
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
        bullets: ['Organized records', 'Customer summary', 'Provider decision'],
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
    title: 'Impact through clearer savings records',
    intro:
        'Collect describes impact through customer-facing outcomes and source-backed public facts only.',
    imageAsset: 'assets/brand/generated/collect_visual_group_momentum.png',
    metricA: '864M',
    metricALabel: 'Adults financially included across Sub-Saharan Africa',
    metricB: 'RWF 19,807B',
    metricBLabel: 'Rwanda financial inclusion transaction value reference',
    sections: [
      CollectPublicSectionData(
        title: 'Cleaner group records',
        body:
            'Savings groups can keep clearer member and contribution records.',
        bullets: [
          'Member histories',
          'Treasurer visibility',
          'Meeting-ready statements',
        ],
      ),
      CollectPublicSectionData(
        title: 'Better prepared support requests',
        body:
            'Customers can organize documents, contribution history and request summaries before review.',
        bullets: [
          'Customer summary',
          'Contribution history',
          'Missing-item checklist',
        ],
      ),
      CollectPublicSectionData(
        title: 'Careful public claims',
        body:
            'Published numbers require a source register before they appear on the website.',
        bullets: [
          '864M adults financially included across Sub-Saharan Africa',
          'RWF 19,807B transaction value reference',
          '7,169,324 adults, 169,570 groups and ~60% savings participation references',
          'RWF 351.3B, RWF 67.6B, 26.2%, 25,000 and 70,000 source-backed references',
        ],
      ),
      CollectPublicSectionData(
        title: 'Decision boundaries',
        body:
            'Collect prepares records and support files. Providers make financial-service decisions under their own rules.',
        bullets: [
          'Credit provider review',
          'Approved insurance provider review',
          'WhatsApp support',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/our-partners',
    navLabel: 'Our Partners',
    title: 'Our Partners',
    intro:
        'Collect works with approved organizations that need clearer savings-group records and customer support files.',
    imageAsset: 'assets/brand/generated/collect_visual_momo_signal.png',
    metricA: '864M',
    metricALabel: 'Adults financially included across Sub-Saharan Africa',
    metricB: 'RWF 19,807B',
    metricBLabel: 'Rwanda financial inclusion transaction value reference',
    sections: [
      CollectPublicSectionData(
        title: 'Financial-service providers',
        body:
            'Collect can help customers prepare clearer records before a provider review.',
        bullets: [
          'Contribution history',
          'Customer summary',
          'Provider decision boundary',
        ],
      ),
      CollectPublicSectionData(
        title: 'Cooperatives and savings groups',
        body:
            'Groups can use Collect to keep member activity and contribution records easier to review.',
        bullets: ['Group setup', 'Member records', 'Treasurer visibility'],
      ),
      CollectPublicSectionData(
        title: 'Community organizations',
        body:
            'Organizations can direct customers to the app and WhatsApp support for questions.',
        bullets: [
          'Public app download',
          'WhatsApp inquiries',
          'Support follow-up',
        ],
      ),
      CollectPublicSectionData(
        title: 'Careful partner claims',
        body:
            'The website does not publish partner names, discussions or regulatory claims without separate approval.',
        bullets: [
          '864M adults financially included across Sub-Saharan Africa',
          'RWF 19,807B transaction value reference',
          '7,169,324 adults, 169,570 groups and ~60% savings participation references',
          'RWF 351.3B, RWF 67.6B, 26.2%, 25,000 and 70,000 source-backed references',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/privacy',
    navLabel: 'Privacy Policy',
    title: 'Privacy Policy and Data Deletion',
    intro:
        'Collect protects customer information with clear customer choices, limited access, practical safeguards, and account and data deletion request paths for savings, support, credit-readiness and insurance journeys.',
    imageAsset: 'assets/brand/generated/collect_visual_qr_share.png',
    metricA: 'Choice',
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
          'Payment references, support messages, service choices and service notifications',
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
          'WhatsApp: +250 795 588 248 with the phone number or Collect ID connected to the account',
          'IKANISA may verify account ownership before processing the request',
        ],
      ),
      CollectPublicSectionData(
        title: 'Data deletion and correction request',
        body:
            'Customers can also ask IKANISA to delete or correct personal data that is no longer needed for Collect. When an app account is deleted, associated user data is deleted unless limited retention is required for legitimate security, fraud-prevention, ledger, dispute, payment, audit, tax, legal or regulatory reasons.',
        bullets: [
          'Request deletion or correction by app or WhatsApp',
          'Email: info@ikanisa.com',
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
          'WhatsApp: +250 795 588 248',
        ],
      ),
      CollectPublicSectionData(
        title: 'Data covered by the request',
        body:
            'Requests may cover profile details, support messages, service choices and other account data that Collect no longer needs to operate the service.',
        bullets: [
          'Account and contact details',
          'Support and service records',
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
        'These terms explain how customers use Collect for group savings, contribution records, credit-readiness support, insurance-related support records and customer service.',
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
        title: 'Savings, credit-readiness and insurance support',
        body:
            'Collect helps customers keep records, organize group savings, prepare credit-readiness files and organize insurance-related support records. Final credit decisions remain with the chosen credit provider.',
        bullets: [
          'Collect records contributions and group activity',
          'CRaaS prepares customer files before provider review',
          'Insurance-related records support customer questions',
        ],
      ),
      CollectPublicSectionData(
        title: 'Support and contact',
        body:
            'Customers can contact IKANISA for group savings setup, account support, questions or inquiries about these terms.',
        bullets: [
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
      return 'Diaspora group records';
    case '/insurance':
      return 'Protection layer';
    case '/craas':
      return 'Credit-readiness service';
    case '/community-groups':
      return 'Mobile group operations';
    case '/impact':
      return 'Source-backed public facts';
    case '/our-partners':
      return 'Partner support model';
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
      return 'Insurance support workflow';
    case '/craas':
      return 'From inquiry to support file';
    case '/community-groups':
      return 'What the app enables for a group';
    case '/impact':
      return 'Impact chain';
    case '/our-partners':
      return 'Partner support workflow';
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
      return 'Keep customer records clearer when an approved provider is involved.';
    case '/craas':
      return 'Turn customer activity into a cleaner readiness file.';
    case '/community-groups':
      return 'Give trusted groups a simple mobile operating layer.';
    case '/impact':
      return 'Collect keeps public impact claims tied to sourced facts and customer-facing outcomes.';
    case '/our-partners':
      return 'The public website names no partner discussions unless separately approved.';
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
          body: 'Turn contribution history into statements and support files.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/diaspora':
      return const [
        LandingStepData(
          icon: Icons.public_outlined,
          title: 'Form the group',
          body: 'Members agree roles, rules and saving objectives.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Track contributions',
          body: 'Savings history is organized into readable group records.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.inventory_2_outlined,
          title: 'Prepare information',
          body: 'Members keep the records needed for discussion and support.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.location_on_outlined,
          title: 'Discuss next steps',
          body:
              'Any financial-service decision remains with the relevant provider.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/insurance':
      return const [
        LandingStepData(
          icon: Icons.support_agent_outlined,
          title: 'Customer request',
          body: 'Understand the insurance-related question.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Record support',
          body: 'Organize relevant customer and group records.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.verified_user_outlined,
          title: 'Provider review',
          body: 'Approved providers review under their own rules.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.chat_bubble_outline,
          title: 'Support follow-up',
          body: 'IKANISA support helps customers understand next steps.',
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
          title: 'Provider review',
          body: 'Credit decisions remain with the financial provider.',
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
          icon: Icons.receipt_long_outlined,
          title: 'Group records',
          body: 'Cleaner contribution histories.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.inventory_2_outlined,
          title: 'Support files',
          body: 'Better prepared customer requests.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.rule_outlined,
          title: 'Provider boundaries',
          body: 'Credit and insurance decisions remain with providers.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.fact_check_outlined,
          title: 'Source register',
          body: 'Public numbers require separate source evidence.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/our-partners':
      return const [
        LandingStepData(
          icon: Icons.support_agent_outlined,
          title: 'Customer need',
          body: 'A group or customer asks for support.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Collect records',
          body: 'Contribution history and request context are organized.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.rule_outlined,
          title: 'Provider review',
          body: 'The relevant organization reviews under its own rules.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.chat_bubble_outline,
          title: 'Support follow-up',
          body: 'IKANISA helps with questions and next steps.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
  }
  return const [];
}
