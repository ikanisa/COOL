part of 'public_content.dart';

const _publicPolicyPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/trust',
    navLabel: 'Trust & Security',
    title: 'Security and trust',
    intro:
        'Collect protects personal data with limited access, practical safeguards, clear AI boundaries, and customer routes to access, correct or delete eligible data.',
    imageAsset: 'assets/runtime/collect_runtime/media/qr-share.png',
    metricA: 'Limited',
    metricALabel: 'Data access',
    metricB: 'Clear',
    metricBLabel: 'Customer rights',
    sections: [
      CollectPublicSectionData(
        title: 'Privacy at a glance',
        body:
            'Collect collects only the information needed to operate savings, contribution records, support, credit-readiness and insurance-related workflows.',
        bullets: [
          'Customer data is used to operate Collect and support requested workflows',
          'Personal data is not sold',
          'Sensitive access is limited by role and reason',
          'Deletion and correction request paths are available',
        ],
      ),
      CollectPublicSectionData(
        title: 'What we collect',
        body:
            'Collect may collect account, group, contribution, payment-reference, support and service-choice information needed to run the product and support customer requests.',
        bullets: [
          'Identity, contact, Collect ID and account details',
          'Group membership, roles, rules and contribution activity',
          'Payment references, support messages and service notifications',
          'Camera or image inputs only when a customer uses a QR, support or evidence feature',
        ],
      ),
      CollectPublicSectionData(
        title: 'How AI assists',
        body:
            "Collect does not use customers' private financial documents to train publicly available AI models.",
        bullets: [
          'AI may assist support, parsing, summaries or readiness workflows under controls',
          'Human review remains part of sensitive support and provider-review workflows',
          'Provider credit or insurance decisions are not made by Collect public website copy',
        ],
      ),
      CollectPublicSectionData(
        title: 'Security measures',
        body:
            'Collect uses access controls, transport security, audit logs and operational safeguards to protect customer information.',
        bullets: [
          'Data is protected in transit',
          'Raw sensitive records are minimized where possible',
          'Sensitive admin access is reason-gated and audited',
          'Security, dispute, payment and legal records may be retained where required',
        ],
      ),
      CollectPublicSectionData(
        title: 'Regulatory posture',
        body:
            'Collect supports customer records and provider workflows. Where regulated products are involved, the bank, insurer or approved provider remains responsible for its own regulated decision.',
        bullets: [
          'Funds are held through regulated financial-service partners where approved arrangements apply',
          'Banks and insurers make their own final decisions',
          'Customer rights and deletion routes remain available through IKANISA support',
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
    imageAsset: 'assets/runtime/collect_runtime/media/qr-share.png',
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
    imageAsset: 'assets/runtime/collect_runtime/media/qr-share.png',
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
    imageAsset: 'assets/runtime/collect_runtime/media/group-momentum.png',
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
    imageAsset: 'assets/runtime/collect_runtime/media/group-momentum.png',
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
