part of 'public_content.dart';

const _publicPolicyPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/privacy',
    navLabel: 'Privacy',
    title: 'Privacy Policy and Data Deletion',
    intro:
        'Collect uses the account, group and MoMo receipt evidence needed to operate reconciled Rwanda contribution records.',
    sections: [
      CollectPublicSectionData(
        title: 'Information Collect uses',
        body:
            'Collect stores account identifiers, Rwanda MoMo profile details, group membership, contribution requests, contribution records, notification preferences and audit evidence.',
        bullets: [
          'Six-digit Collect ID and the phone number or email used to sign in',
          'Google account identifier and verified email if you choose Google where enabled',
          'Rwanda profile and RWF currency',
          'Rwanda MoMo provider and editable local 07 number',
          'Members are identified by Collect ID; personal names from MoMo receipts stay in access-controlled Admin records',
          'Consented MoMo receipt evidence',
        ],
      ),
      CollectPublicSectionData(
        title: 'Signing in',
        body:
            'You can sign in with an email code or, where enabled, Google. Google sign-in requests OpenID identity, email and basic profile access to create or link your Collect member account.',
        bullets: [
          'Supabase provides Collect authentication, database and private evidence storage; Cloudflare provides web hosting, API forwarding and security challenges',
          'Records and recovery copies from the earlier Cloudflare backend may remain; changing providers does not erase them',
          'Collect stores your Google account identifier and verified email if you choose Google',
          'Verification, session and security records remain after a sign-in code expires; expiry does not delete those records',
        ],
      ),
      CollectPublicSectionData(
        title: 'How payment evidence is handled',
        body:
            'Likely MoMo receipt SMS is sent to Collect servers for structured extraction and reconciliation. Raw evidence and full phone values are not displayed publicly.',
        bullets: [
          'Parsers cannot update balances',
          'Matched MoMo receipt evidence determines ledger posting',
          'Server logs and public pages must not contain raw messages, PINs or OTPs',
        ],
      ),
      CollectPublicSectionData(
        title: 'Account deletion request',
        body:
            'Open Settings > Security > Delete data to verify your identity and submit an account deletion request for review. For help without the app, contact info@ikanisa.com.',
        bullets: [
          'Submitting a request does not delete your account',
          'Reviewing a request does not delete retained financial or audit records',
          'Contact: +250 795 588 248',
        ],
      ),
      CollectPublicSectionData(
        title: 'Data deletion and correction request',
        body:
            'Contact info@ikanisa.com to request access, correction or deletion of eligible data.',
        bullets: [
          'A request and a completed data change are separate outcomes',
          'Check request status or contact support for the outcome and any records that need to be retained',
          'Notification permission can be revoked separately in device settings',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/account-deletion',
    navLabel: 'Account deletion',
    title: 'Request deletion of your Collect account.',
    intro:
        'Send a request for review. Your account remains accessible while the review is pending.',
    sections: [
      CollectPublicSectionData(
        title: 'In the app',
        body:
            'Open Settings > Security > Delete data, verify your identity and submit the request for review.',
        bullets: [
          'Submitting a request does not delete your account',
          'A confirmed receipt records your request for review',
          'Check or refresh request status in the app',
        ],
      ),
      CollectPublicSectionData(
        title: 'Without the app',
        body:
            'For help with a request, contact info@ikanisa.com or +250 795 588 248.',
        bullets: [
          'Contacting support does not itself confirm that a request was recorded or your account was deleted',
          'Never send a PIN or OTP',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/data-deletion',
    navLabel: 'Data deletion',
    title: 'Request deletion or correction of eligible data.',
    intro:
        'Account deletion requests are submitted for review. A request does not itself establish that retained records were changed.',
    sections: [
      CollectPublicSectionData(
        title: 'Submit a request',
        body:
            'For an account deletion request, open Settings > Security > Delete data. For help or a correction request, contact info@ikanisa.com.',
        bullets: [
          'Never send a PIN or OTP',
          'Do not email raw receipts unless support provides a protected channel',
          'Submitting a request does not delete your account',
          'A confirmed in-app account-deletion receipt records your request for review',
          'Check or refresh your in-app account-deletion request status',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/terms',
    navLabel: 'Terms',
    title: 'Collect Terms of Service',
    intro:
        'These terms cover account access, private groups, Rwanda MoMo contributions and the contribution ledger.',
    sections: [
      CollectPublicSectionData(
        title: 'Using Collect',
        body:
            'Use accurate group and transfer information. Do not impersonate others, create misleading groups or submit false transfer claims.',
        bullets: [
          'User-created groups are private; creating a group does not enable payments or SMS access',
          'Members approve MoMo in USSD',
          'Collect may hold incomplete or disputed evidence for review',
        ],
      ),
      CollectPublicSectionData(
        title: 'Contribution records',
        body:
            'A ledger entry is created only after the server reconciles an incoming MoMo receipt to one pending member request.',
        bullets: [
          'Duplicate transaction evidence cannot post twice',
          'Corrections and reversals remain audited',
          'Contact support when a contribution is missing or incorrect',
        ],
      ),
    ],
  ),
];
