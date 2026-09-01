part of 'public_content.dart';

const _publicMarketingPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/group-savings',
    navLabel: 'How it works',
    title: 'Local MoMo and diaspora bank contributions in one clear ledger.',
    intro:
        'Rwanda members contribute through MoMo USSD. Diaspora members use Revolut or bank transfer. Collect records either rail only after matching evidence is reconciled.',
    sections: [
      CollectPublicSectionData(
        title: 'Create the group and invite members',
        body:
            'Android members can create a private group and share its link or QR code. Public discovery is reserved for platform-sponsored groups such as Buri Munsi and Gikundiro.',
        bullets: [
          'Members use six-digit Collect IDs',
          'Rwanda groups show their approved MoMo receiver',
          'Private group links can be rotated',
        ],
      ),
      CollectPublicSectionData(
        title: 'Use the right rail for your country',
        body:
            'A Rwanda member enters a whole-RWF amount and opens MoMo USSD. A diaspora member receives the approved beneficiary and reference, then opens Revolut or a banking app.',
        bullets: [
          'Collect never asks for a MoMo PIN, bank password or OTP',
          'Members do not upload receipts or report transaction IDs',
          'Payment approval stays in USSD or the banking app',
        ],
      ),
      CollectPublicSectionData(
        title: 'See one balanced update',
        body:
            'A receipt posts only when trusted evidence matches one active request by receiver, sender, amount, time window and transaction identity. Diaspora settlement retains its bank-statement control.',
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
            'Member surfaces use Collect IDs and safe contribution status. Full phone numbers, MoMo receipts and bank evidence stay out of public pages.',
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
        'Collect accepts consented Android MoMo receipt SMS in Rwanda and controlled bank evidence for diaspora while keeping transaction posting on the server.',
    sections: [
      CollectPublicSectionData(
        title: 'Evidence ingestion is controlled',
        body:
            'The Android app requests SMS receipt access only for Rwanda MoMo use. Diaspora bank evidence uses controlled operational channels with authenticated endpoints and duplicate protection.',
        bullets: [
          'Consent and permission state are recorded',
          'Only likely MoMo receipt messages are submitted',
          'Diaspora bank statements remain authoritative for settlement',
        ],
      ),
      CollectPublicSectionData(
        title: 'Deterministic parsers extract receipt facts',
        body:
            'Supabase Edge Functions validate MoMo and diaspora bank evidence into strict schemas without allowing a parser to choose a group or post a balance.',
        bullets: [
          'References, amounts and transaction identifiers are normalized',
          'Raw evidence has separate audited reveal permission',
          'Failed, outgoing or incomplete messages do not post',
        ],
      ),
      CollectPublicSectionData(
        title: 'Postgres enforces the match',
        body:
            'Locked database functions check the correct rail, receiver, payer, exact amount, time window, transaction uniqueness and independent allocation controls.',
        bullets: [
          'One exact pending contribution request is required',
          'Group and payer credits are created in one transaction',
          'The audit record and notification are linked to the same contribution',
        ],
      ),
    ],
  ),
];
