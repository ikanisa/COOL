# Receipt policy decision draft

This draft makes C18 review concrete. It records existing source behavior and the decisions required for an approved unattended receipt policy. Every decision is **pending**. No financial, disclosure, wording, language, catch-up, correction/resend or release approval is recorded. The user-selected Android sender and email operator are retained; the request to stop asking for owner names is respected.

| Decision | Current source evidence | Decision to record |
|---|---|---|
| F01 Financial event | A posted positive whole-RWF payment produces a balanced receipt journal and immutable snapshot. Verification/allocation/posting and stored provider evidence are distinct stages. | Which authenticated Rwanda inbound-evidence and reconciliation chain establishes primary-receipt eligibility? Local fixtures do not establish real provider settlement. |
| F02 Balances | The receipt freezes the allocated member's confirmed RWF balance within the collection and the collection's confirmed RWF total at posting. Current balances may subsequently change. | Approve the definitions and labels used in the message, and the permitted group-total disclosure. |
| F03 Recipient | Creation currently derives the active allocated account-independent member's MoMo contact. Enabled group policy and enabled member consent are required; app-linked members use existing push. | Confirm the allocated member as recipient when the payer differs, and resolve ambiguous allocation or changed contacts before creation/send authority. |
| F04 Disclosure/consent | The existing message includes both member and group balances. Consent has an enabled flag, method and revision; that alone does not record a reviewed language or group-total disclosure policy. | Choose whether primary SMS may disclose group totals and the explicit consent/evidence required. |
| F05 Wording | The fixed primary key is `buri_munsi.payment_received`, version1. Amount, balances, reference, body/hash and destination/hash are immutable receipt evidence. | Approve or replace the exact current copy through a versioned policy while retaining existing primary receipts. |
| F06 Language | Current copy uses Kinyarwanda wording with `Balance`/`Ref` labels; no approved per-member SMS-language/fallback contract exists. | Specify reviewed languages, the authoritative member preference and fallback. |
| F07 Catch-up | New eligible work is locally preserved during dispatch pause. Historical reconciliation returns `CATCHUP_POLICY_PENDING`; current consent/contact cannot reconstruct past revisions. | Specify lookback, historical/current consent rules, contact review and date/snapshot wording for missed receipts. |
| F08 Corrections | Reversals create compensating journal/snapshot evidence. Existing primary receipts remain retained. Pristine queued cancellation has separate original-request evidence. | Specify approved linked correction/resend conditions and exact text; each must preserve the original identity and evidence. |
| F09 Uncertainty | Busy, missing, timeout and malformed outcomes retain the original action identity. A recorded action or handset callback is distinct from delivery. | Specify the evidence and escalation needed to resolve uncertainty before any retry/resend. |

The current renderer's exact illustrative output for a **synthetic** payment of1,000 RWF, member snapshot12,000 RWF, collection snapshot95,000 RWF and reference`MTN-DEMO-001` is:

> BuriMunsi: Twakiriye ubwizigame bwawe bwa 1,000 RWF. Balance yawe: 12,000 RWF; balance y'itsinda: 95,000 RWF. Ref: MTN-DEMO-001.

This is an example of the retained code's wording, not approved copy or an actual receipt. Omitting a group total, adding transaction dates or choosing another language requires a reviewed rendering/policy change; existing stored messages must remain unchanged. Changing a template must not create another primary receipt for the same payment.

`decision-draft.json` records the nine pending decisions and hashes of five exact source files. Their source snapshots are retained. This document is product/approval evidence and introduces no design authority or runtime policy. It does not resolve privacy/vendor/carrier decisions, configure Auth, enable a sender or replace C32/C36 acceptance. `MANIFEST.json` covers this packet and excludes itself.
