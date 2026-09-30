# Go / no-go decision

**Reviewed:** 28 September 2026. **Current decision:** **NO-GO for a new production release**. The active product scope is Rwanda-only, whole-RWF MTN MoMo/Airtel Money USSD group contributions. Earlier diaspora EUR/bank plans are historical and must not be represented as current release capability.

A GO decision requires evidence tied to one protected source commit and the exact signed installed artifacts:

- trusted source ownership, reviewed import/merge, restricted delivery access and protected CI/release credentials;
- approved Rwanda-only product, financial-finality and privacy/legal boundaries;
- deployed migration/function/RLS/grant parity, controlled SQL rollout, independent reconciliation, immutable balanced ledger, exceptions and reversal tests;
- accepted Google Play restricted-SMS declaration for the exact Android package/version, plus physical MTN/Airtel USSD, receipt, account-switch, retry and key-loss UAT;
- full Flutter, native, Edge, database and public/Admin web checks, with every material visual or interaction finding reviewed against the sole `revolut-design` skill;
- verified production web headers/cache behavior, notification delivery, monitoring, support and an isolated recovery rehearsal;
- current artifact hashes, store state, controlled pilot results, daily reconciliation, stop criteria and accountable owner approval.

The 28 September integration has local source and test evidence but remains uncommitted, the last full visual suite has five failing goldens, staged reconciliation approval SQL is unexecuted, and deployed/provider/device/store/owner evidence is incomplete. Older signed packages and dated store packets cannot approve the changed source. Local tests or a successful build alone do not satisfy the release conditions.

The historical database migration also contains an SMS self-finalizer that can post a review payment when invoked by a service-role caller. The local additive await-only containment and numbered receipt-v2 migrations passed an isolated **133/133 clean full-schema replay**; rollback-only financial and receipt UAT passed 40 and seven assertions. A guarded **127+6 historical-row upgrade** preserved the SHA-256 of 16 posted/review/receipt/journal rows and the RWF 1,500 balance, cancelled a forged payer intent, and passed nine further rollback-only assertions. The later Admin notification paging migration is **number 134** and passed a separate **134/134 clean PostgreSQL 17.6 replay**, ten rollback-only old/new JSON parity cases, and a small restored historical 133-to-134 upgrade preserving the selected financial hash, balance and all other table-data sections. These synthetic rehearsals do not establish representative historical volume, app rollback compatibility, staged reconciliation approval, deployed function or independent provider authenticity, so the financial release blocker remains. See [the financial packet](financial-core-2026-09-28/README.md), [notification packet](admin-notification-paging-2026-09-29/README.md) and [containment analysis](sms-finality-containment-2026-09-28/README.md).
