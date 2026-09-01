part of 'public_content.dart';

const _publicPolicyPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/privacy',
    navLabel: 'Privacy',
    title: 'Privacy Policy and Data Deletion',
    intro:
        'Collect uses the minimum account, group, MoMo and diaspora bank evidence needed to operate reconciled contribution records.',
    sections: [
      CollectPublicSectionData(
        title: 'Information Collect uses',
        body:
            'Collect stores account identifiers, profile details, group membership, MoMo or diaspora bank requests, contribution records, notification preferences and audit evidence.',
        bullets: [
          'WhatsApp sign-in phone and six-digit Collect ID',
          'Display name, user-confirmed country and country-derived local currency',
          'Rwanda MoMo provider and editable local 07 number',
          'Diaspora Revolut link, account name and account details',
          'Consented MoMo receipts and controlled bank evidence',
        ],
      ),
      CollectPublicSectionData(
        title: 'How payment evidence is handled',
        body:
            'Likely MoMo receipt SMS and diaspora bank evidence are sent to Collect servers for structured extraction and reconciliation. Raw evidence and full phone or account values are not displayed publicly.',
        bullets: [
          'Parsers cannot update balances',
          'Diaspora daily statements determine bank-settlement finality',
          'Server logs and public pages must not contain raw messages, PINs or OTPs',
        ],
      ),
      CollectPublicSectionData(
        title: 'Account deletion request',
        body:
            'Request account deletion in Settings > Account or contact info@ikanisa.com without reinstalling the app.',
        bullets: [
          'Identity and profile data are deleted or de-identified where allowed',
          'Ledger and audit evidence may be retained when required for security or dispute handling',
          'Support is available at +250 795 588 248',
        ],
      ),
      CollectPublicSectionData(
        title: 'Data deletion and correction request',
        body:
            'Contact info@ikanisa.com to request access, correction or deletion of eligible data.',
        bullets: [
          'Requests are verified before account data is changed',
          'Collect explains any record that cannot be deleted immediately',
          'Notification permission can be revoked separately in device settings',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/account-deletion',
    navLabel: 'Account deletion',
    title: 'Delete your Collect account.',
    intro:
        'Use the in-app account deletion journey or contact support if you cannot sign in.',
    sections: [
      CollectPublicSectionData(
        title: 'In the app',
        body: 'Open Settings > Account > Delete account and follow the checks.',
        bullets: [
          'Resolve active group-owner responsibilities first',
          'Confirm the deletion request',
          'The app signs out after the request completes',
        ],
      ),
      CollectPublicSectionData(
        title: 'Without the app',
        body:
            'Email info@ikanisa.com or use +250 795 588 248. Support will verify ownership before processing the request.',
        bullets: [],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/data-deletion',
    navLabel: 'Data deletion',
    title: 'Request deletion or correction of eligible data.',
    intro:
        'Collect reviews privacy requests against account security, group responsibilities and required ledger evidence.',
    sections: [
      CollectPublicSectionData(
        title: 'Submit a request',
        body:
            'Contact info@ikanisa.com and identify the Collect account using a safe verification method requested by support.',
        bullets: [
          'Never send a PIN or OTP',
          'Do not email raw receipts or bank screenshots unless support provides a protected channel',
          'You will receive an explanation of the completed action',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/terms',
    navLabel: 'Terms',
    title: 'Collect Terms of Service',
    intro:
        'These terms cover account access, private groups, Rwanda MoMo contributions, diaspora bank contributions and the contribution ledger.',
    sections: [
      CollectPublicSectionData(
        title: 'Using Collect',
        body:
            'Use accurate group and transfer information. Do not impersonate others, create misleading groups or submit false transfer claims.',
        bullets: [
          'User-created groups are private and created only on Android',
          'Members approve MoMo in USSD or bank transfers outside Collect',
          'Collect may hold incomplete or disputed evidence for review',
        ],
      ),
      CollectPublicSectionData(
        title: 'Contribution records',
        body:
            'A ledger entry is created only after the server reconciles an incoming MoMo receipt or diaspora bank transaction to one pending member request.',
        bullets: [
          'Duplicate transaction evidence cannot post twice',
          'Corrections and reversals remain audited',
          'Contact support when a contribution is missing or incorrect',
        ],
      ),
    ],
  ),
];
