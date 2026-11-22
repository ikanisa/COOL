# Privacy and compliance notes: Rwanda release scope

These are engineering controls and open review points, not a legal clearance. The current release is Rwanda-only MoMo group contributions; historical bank-transfer claims and data paths must not be presented as current capabilities.

- Public and member surfaces must not expose private phone numbers, raw SMS, full payer identity, Admin identifiers, or another member's restricted records. Self-service display and intentionally shared payment receiver contact must follow the actual product permission/consent scope.
- The ordinary member receipt flow captures eligible newly arriving MoMo SMS after explicit Android consent; it does not request SMS history or message sending. The separate internal receiver declares `READ_SMS`, and the distinct internal gateway declares `SEND_SMS`. Capture does not require a MoMo PIN/OTP or mobile-money account credentials. Assisted/operator notification sending has separate destination, consent and attempt evidence.
- Raw receipt evidence is protected separately and candidate evidence is not settlement confirmation. Verify capability, reason and audit controls for every exposed reveal path; do not infer universal coverage solely from the intended policy.
- Notification content must not contain raw evidence, credentials, PINs, OTPs or provider secrets. Verify each enabled template and transport against that boundary.
- Session, native secure-cache, browser cache, account switch, consent revocation and deletion behavior need physical-device and browser verification. Preserve legally required financial evidence under an approved retention schedule rather than asserting blanket deletion.
- Record actual processors, hosting/backup/log/AI locations, transfer basis, registration and incident-reportability decisions with the responsible privacy/legal owners. The repo alone cannot establish these approvals.
- Verify Play/App Store privacy labels, customer disclosures and reviewer access against the exact enabled Rwanda features and current signed build.

## Data classification and retention inventory

Existing phone hashes are **personal, pseudonymous identifiers**. They are not anonymous data. Dart's `HashUtils.phoneHash` uses an unkeyed SHA-256 digest of a normalized Rwanda number. The constrained telephone-number input space permits dictionary matching. Keep these identifiers under the same applicable access, purpose, export, processor and retention restrictions as the identity records they link. A 64-character digest alone is never evidence of anonymisation; verify exact normalization and matching for each current backend path.

| Data class | Current examples | Required treatment and remaining implementation |
| --- | --- | --- |
| Account/contact and MoMo identity | Curated `users` records; member MoMo identities; Auth identity/session links | Personal data. Limit disclosure to the authorized account/workflow; include derivatives and provider copies in owner review. |
| Phone matching identifiers | Sender/receiver hashes in contribution requests, retained receipts and evidence workflows | Personal/pseudonymous data. Retain historical matching facts under the approved financial/evidence schedule and holds; do not publish, log or send to AI merely because the value is hashed. |
| Raw and parsed receipt evidence | `sms_receipts`, protected receipt objects and processing outputs | Restricted personal/financial evidence. Verify capability/reason/audit reveal controls. A governed raw-body redaction or deletion workflow and approved horizon need separate review. |
| Financial records and confirmations | Payments, allocations, payment intents, provider confirmations and evidence links | Personal/financial records. Account deletion must preserve required ledger facts and legal holds; do not rewrite historical hashes or journals to satisfy a blanket deletion claim. |
| Assisted notification evidence | Outbox, claim/confirmation/attempt records and retained session evidence | Personal operational evidence. Define the appropriate schedule/hold and recovery treatment separately from a send or delivery conclusion; verify retained session and destination/body bindings against the exact candidate. |
| Roster sources, drafts and AI material | Private roster sources, extractions, revisions, editor/recovery drafts and results | Personal source/derivative data. Existing recovery TTLs do not establish complete source, vendor, export or backup erasure. Vendor/region/retention acceptance remains open. |
| Security, audit and support evidence | Auth/app audit, scoped service metrics, support and account-deletion requests | Personal or linkable operational data where actor/account identifiers exist. Minimize payloads; retain required security/dispute evidence under an approved schedule and record actual request progress. |
| Copies and derivatives | Exports, logs, backups, replicas and processor copies of every class above | Inherit the source classification. Track hold, expiry, deletion/redaction and provider/backup confirmation separately; absence from an app screen does not establish erasure. |

No duration or deletion approval is granted by this inventory. Privacy/backend/finance owners still need to approve the per-class schedule and legal-hold decisions. Until the governed workflow exists and its effects are verified, a queued account-deletion request is a request, not completed erasure. The current implementation findings BE-05, BE-11 and BE-13 remain open for those effects and owner decisions.

If the threat model requires a keyed phone identifier, plan a server-owned, versioned HMAC migration and rotation. Keep public request/content hashes separate. First prove Dart/native/SQL/Edge normalization, historical payer/receiver matching and compatibility; preserve immutable financial evidence and never replace current identifiers with an unplanned bulk hash rewrite. No hash algorithm or financial identity has changed in this update.

Source pointers: [`HashUtils`](../lib/core/security/hash_utils.dart), [receipt ingestion and access](../supabase/functions/_shared/domain/receipts.js), and the [curated baseline](../supabase/migrations/20261020134444_collect_curated_platform_baseline.sql). Source and local schema evidence are not a hosted data/processor inventory or legal clearance.
