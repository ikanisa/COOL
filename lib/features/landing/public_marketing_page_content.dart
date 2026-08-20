part of 'public_content.dart';

const _publicMarketingPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/group-savings',
    navLabel: 'How it works',
    title: 'Direct MoMo contributions with a clear group ledger.',
    intro:
        'Collect connects one member request to one official MoMo receipt. The group owner receives the payment directly, while Collect keeps the contribution record accurate.',
    sections: [
      CollectPublicSectionData(
        title: 'Create the group and invite members',
        body:
            'An Android group owner completes SMS access setup, creates the group and shares a private link or QR code.',
        bullets: [
          'Members use six-digit Collect IDs',
          'The receiving MoMo number comes from the owner profile',
          'Private group links can be rotated',
        ],
      ),
      CollectPublicSectionData(
        title: 'Contribute through MoMo',
        body:
            'A member enters the amount in Collect, completes the payment through MoMo and waits for the official receipt.',
        bullets: [
          'Collect never asks for a PIN or OTP',
          'Members do not paste receipts or report transaction IDs',
          'Payment approval stays outside Collect',
        ],
      ),
      CollectPublicSectionData(
        title: 'See one balanced update',
        body:
            'The receipt posts only when it matches one active request by amount, payer, receiver, time and transaction identity.',
        bullets: [
          'The group total and payer total update together',
          'Duplicate receipts cannot post twice',
          'Incomplete or ambiguous receipts remain unposted for review',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/community-groups',
    navLabel: 'Community Groups',
    title: 'A contribution ledger for the groups people already trust.',
    intro:
        'Collect supports savings circles, families, churches, teams, wedding committees and other member-led contribution groups.',
    sections: [
      CollectPublicSectionData(
        title: 'Use the group structure that fits',
        body:
            'Choose a group purpose, invite the right members and keep each contribution visible to the people who should see it.',
        bullets: [
          'Ikimina and recurring savings groups',
          'Family, community and member-support groups',
          'Church, sport and event contributions',
        ],
      ),
      CollectPublicSectionData(
        title: 'Keep private details private',
        body:
            'Member surfaces use Collect IDs and safe contribution status. Full phone numbers and raw SMS evidence stay out of public pages.',
        bullets: [
          'Private group access is membership-gated',
          'Payer-level balances are visible only to the payer and authorized group roles',
          'Public evidence must contain no customer receipt data',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/trust',
    navLabel: 'Trust',
    title: 'Permission, parsing and posting are separate controlled steps.',
    intro:
        'Collect explains SMS access before Android asks, uploads only opted-in payment notifications and keeps transaction posting on the server.',
    sections: [
      CollectPublicSectionData(
        title: 'SMS access is explicit',
        body:
            'The owner sees why receive-only SMS access is needed and can review or revoke access in device settings.',
        bullets: [
          'No SMS access before in-app consent',
          'Encrypted offline queue for temporary network loss',
          'Background and restarted-app recovery are covered by the same consent',
        ],
      ),
      CollectPublicSectionData(
        title: 'OpenAI extracts receipt facts',
        body:
            'The Supabase Edge Function sends redacted receipt content to the OpenAI Responses API with a strict structured-output schema.',
        bullets: [
          'The model cannot choose a group or post a balance',
          'Phone values are hashed before the parsed event is stored',
          'Failed, outgoing, promotional and balance-only messages do not post',
        ],
      ),
      CollectPublicSectionData(
        title: 'Postgres enforces the match',
        body:
            'A locked database function checks receiver ownership, payer identity, amount, time window, confidence and transaction uniqueness.',
        bullets: [
          'One exact pending request is required',
          'Group and payer credits are created in one transaction',
          'The audit record and notification are linked to the same payment',
        ],
      ),
    ],
  ),
];
