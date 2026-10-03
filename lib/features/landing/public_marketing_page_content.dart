// Generated from content/product/collect_capabilities.json.
// Registry SHA-256: 71d9288963e5cd13a78c6abd50f9c962081a5c841da3d5688849c8a36cadbefa
// Source observations only; no publication or provider approval.
part of 'public_content.dart';

const _publicMarketingPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/group-savings',
    navLabel: 'How it works',
    title: 'Rwanda MoMo contributions in one clear ledger.',
    intro:
        'Collect helps Rwanda groups organize members and review whole-RWF MoMo contribution records. It is a technology and record-keeping service. A pending request or receipt SMS is not a confirmed contribution. Production confirmation requires independently reconciled settlement evidence or an explicitly approved constrained finality policy.',
    sections: [
      CollectPublicSectionData(
        title: 'Create the group and invite members',
        body:
            'Private-group creation is available only on eligible Android builds, after SMS consent and device verification. iOS and web do not create private groups.',
        bullets: [
          'Members use six-digit Collect IDs',
          'Rwanda groups show their approved MoMo receiver',
          'Private group links can be rotated',
        ],
      ),
      CollectPublicSectionData(
        title: 'Approve with MoMo USSD',
        body:
            'Eligible Android members check the exact MTN MoMo or Airtel Money receiver and whole-RWF amount, then approve payment in the mobile network’s USSD prompt. The Collect app’s USSD handoff and receipt-SMS access require Android. iOS and web support group records and account controls; they do not provide this handoff or SMS intake.',
        bullets: [
          'Collect never asks for a MoMo PIN or payment provider OTP and does not hold customer funds. Your WhatsApp sign-in code is only for signing in to Collect.',
          'Members do not upload receipts or report transaction IDs',
          'Payment approval stays in the provider’s USSD prompt',
        ],
      ),
      CollectPublicSectionData(
        title: 'Review pending and reconciled records',
        body:
            'A pending request or receipt SMS is not a confirmed contribution. Production confirmation requires independently reconciled settlement evidence or an explicitly approved constrained finality policy.',
        bullets: [
          'The group total and payer total update together after governed posting',
          'Duplicate receipt evidence cannot post twice',
          'Incomplete or ambiguous receipts remain in the authorized Admin review queue',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/community-groups',
    navLabel: 'Community Groups',
    title: 'A contribution ledger for the groups people already trust.',
    intro:
        'Collect supports Rwanda savings circles, families, churches, teams, wedding committees and other member-led contribution groups.',
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
            'Member surfaces use Collect IDs and safe contribution status. Full phone numbers and MoMo receipts stay out of public pages.',
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
        'Collect accepts consented Android MoMo receipt SMS as candidate evidence and keeps contribution posting on the server.',
    sections: [
      CollectPublicSectionData(
        title: 'Evidence ingestion is controlled',
        body:
            'Eligible Android receiver devices request consent for newly arriving MoMo receipt SMS. Receipt intake requires authentication and duplicate protection.',
        bullets: [
          'Consent and permission state are recorded',
          'Only likely MoMo receipt messages are submitted',
          'iOS and web do not read receipt SMS',
        ],
      ),
      CollectPublicSectionData(
        title: 'Receipt facts stay separate from posting',
        body:
            'Deterministic parsers validate receipt facts without choosing a group or posting a balance.',
        bullets: [
          'References, amounts and transaction identifiers are normalized',
          'Raw evidence has separate audited reveal permission',
          'Failed, outgoing or incomplete messages do not post',
        ],
      ),
      CollectPublicSectionData(
        title: 'Governed reconciliation is required',
        body:
            'A pending request or receipt SMS is not a confirmed contribution. Production confirmation requires independently reconciled settlement evidence or an explicitly approved constrained finality policy.',
        bullets: [
          'Receiver, payer, exact whole-RWF amount and transaction identity must match',
          'Group and payer credits are created in one governed transaction',
          'The audit record and notification link to the same contribution',
        ],
      ),
    ],
  ),
];
