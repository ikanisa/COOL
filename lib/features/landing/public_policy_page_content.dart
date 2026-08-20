part of 'public_content.dart';

const _publicPolicyPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/privacy',
    navLabel: 'Privacy',
    title: 'Privacy Policy and Data Deletion',
    intro:
        'Collect uses the minimum account, group and payment evidence needed to operate direct MoMo contribution records.',
    sections: [
      CollectPublicSectionData(
        title: 'Information Collect uses',
        body:
            'Collect stores account identifiers, group membership, payment requests, contribution records, notification preferences and audit evidence.',
        bullets: [
          'WhatsApp sign-in phone and six-digit Collect ID',
          'Optional profile MoMo number and group receiving route',
          'Opted-in MoMo receipt content and structured receipt facts',
        ],
      ),
      CollectPublicSectionData(
        title: 'How receipt data is handled',
        body:
            'Opted-in receipt content is sent to Collect servers and the OpenAI API for structured extraction. Raw receipts and full phone values are not displayed publicly.',
        bullets: [
          'OpenAI is used only for receipt extraction in this journey',
          'The model cannot update balances',
          'Server logs and public evidence must not contain receipt bodies, PINs or OTPs',
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
          'SMS access can be revoked separately in Android settings',
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
          'Do not email raw receipt screenshots unless support provides a protected channel',
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
        'These terms cover account access, groups, direct MoMo contributions and the contribution ledger.',
    sections: [
      CollectPublicSectionData(
        title: 'Using Collect',
        body:
            'Use accurate group, receiver and payment information. Do not impersonate others, create misleading groups or submit false payment claims.',
        bullets: [
          'Group owners manage membership and receiving setup',
          'Members approve MoMo payments outside Collect',
          'Collect may hold incomplete or disputed evidence for review',
        ],
      ),
      CollectPublicSectionData(
        title: 'Contribution records',
        body:
            'A ledger entry is created only after the server matches an official receipt to one pending payer request.',
        bullets: [
          'Duplicate transaction evidence cannot post twice',
          'Corrections and reversals remain audited',
          'Contact support when a contribution is missing or incorrect',
        ],
      ),
    ],
  ),
];
