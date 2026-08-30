part of 'public_content.dart';

const _publicMarketingPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/group-savings',
    navLabel: 'How it works',
    title: 'SEPA bank contributions with a clear group ledger.',
    intro:
        'Collect gives every member a unique EUR transfer reference, opens Revolut for the bank transfer, and records the contribution after statement reconciliation.',
    sections: [
      CollectPublicSectionData(
        title: 'Create the group and invite members',
        body:
            'A member creates the group and shares a private link or QR code. Every group uses the same approved Collect EUR beneficiary.',
        bullets: [
          'Members use six-digit Collect IDs',
          'Approved bank details are shown in the app',
          'Private group links can be rotated',
        ],
      ),
      CollectPublicSectionData(
        title: 'Contribute by bank transfer',
        body:
            'A member enters the EUR amount, copies the unique reference, opens Revolut and sends a bank transfer to the saved beneficiary.',
        bullets: [
          'Collect never asks for a bank password, PIN or OTP',
          'Members do not upload receipts or report transaction IDs',
          'Payment approval stays outside Collect',
        ],
      ),
      CollectPublicSectionData(
        title: 'See one balanced update',
        body:
            'The receipt posts only when bank evidence and the daily statement match one active request by reference, EUR amount and transaction identity.',
        bullets: [
          'The group total and payer total update together',
          'Duplicate evidence and statement lines cannot post twice',
          'Incomplete or ambiguous receipts remain in the admin review queue',
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
            'Member surfaces use Collect IDs and safe contribution status. Full phone numbers and raw bank evidence stay out of public pages.',
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
    title: 'Evidence, reconciliation and posting are separate controls.',
    intro:
        'Collect accepts controlled bank SMS, email and statement evidence while keeping transaction posting on the server.',
    sections: [
      CollectPublicSectionData(
        title: 'Evidence ingestion is controlled',
        body:
            'Member apps request no SMS permission. Authorized operational channels ingest bank notifications with authenticated endpoints and duplicate protection.',
        bullets: [
          'No member inbox access',
          'SMS and email are candidate evidence, not settlement finality',
          'Daily bank statements remain authoritative',
        ],
      ),
      CollectPublicSectionData(
        title: 'Deterministic parsers extract receipt facts',
        body:
            'Supabase Edge Functions validate EUR bank evidence into a strict schema without allowing a parser to choose a group or post a balance.',
        bullets: [
          'References, amounts and transaction identifiers are normalized',
          'Raw evidence has separate audited reveal permission',
          'Failed, outgoing or incomplete messages do not post',
        ],
      ),
      CollectPublicSectionData(
        title: 'Postgres enforces the match',
        body:
            'A locked database function checks the transfer reference, exact EUR amount, transaction uniqueness, daily statement and independent allocation controls.',
        bullets: [
          'One exact pending transfer request is required',
          'Group and payer credits are created in one transaction',
          'The audit record and notification are linked to the same contribution',
        ],
      ),
    ],
  ),
];
