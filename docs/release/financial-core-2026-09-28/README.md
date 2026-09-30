# Isolated financial schema and receipt evidence — 28 September 2026

**Decision: production NO-GO.** These are synthetic, local PostgreSQL/Supabase-platform checks. No hosted migration, provider transaction, real SMS, signed app, or owner approval is represented here.

The task-owned fixture was a new Supabase CLI local project at `.cache/financial-qa-20260928`, with Docker labels confirming project `collect_financial_qa_20260928` and the exact checkout workdir. It had a synthetic bootstrap owner because the historical public-group seed requires one. It contained no customer/provider data, and cron jobs were not launched. The clean replay applied all **133/133** numbered application migrations then present on PostgreSQL 17.6. Every migration's SHA-256 in [clean-replay.json](clean-replay.json) was checked again against that source snapshot after copying this report. The new Rwanda onboarding profile, strict payer match, SMS await-only, and durable receipt-v2 migrations are included. A later [Admin notification paging candidate](../admin-notification-paging-2026-09-29/README.md) adds migration **134**; this original clean replay does not cover it. The separate notification packet records a later clean 134/134 replay and a guarded 133-to-134 upgrade of a restored copy of this fixture.

The rollback-only [hybrid financial UAT log](hybrid-direct-ussd-uat.stdout) records **40 passing assertions**. They include empty Rwanda onboarding, rejection of foreign/mixed profiles, identity and route conflicts held for review, no credit from SMS observation alone, independent synthetic provider confirmation, idempotent retries, balanced journal, reversal, and historical read projections. The rollback-only [receipt-v2 UAT log](receipt-v2-uat.stdout) records **seven passing assertions** for the server's v2 receipt contract and acknowledgement behavior. Both transactions ended with `ROLLBACK`.

| Evidence or executed source | SHA-256 |
| --- | --- |
| `clean-replay.json` | `15dd36bf91b16c5a3774a196be806f0a208587aad6e8b21cf9de435ae6b43a70` |
| `hybrid-direct-ussd-uat.stdout` | `34c6e2c5b726c8c653c194be2fb3b51d58202407f229efde95041ac357990061` |
| `receipt-v2-uat.stdout` | `330bccf1e5fea49d011423ee1544445555ef4124739ae85a8f6a6f257b4aaa34` |
| `scripts/tests/clean_migration_replay.rb` at the original clean replay | `c179bd2cd326ef1511fe4098d9fb8d970f429d3d95d173be5595bfd4fc28c2bc` |
| `scripts/tests/hybrid_direct_ussd_financial_core_uat.sql` | `8f00c44101f6c50a1ac8e7437ccb58033172222771fecd6e636d447456941fc5` |
| `scripts/hardening/receipt_v2_uat.sql` | `798e3c8978cfc0ccd4e6b567167dba93b9e2525a56987726f843d2c7d9832c9c` |

The replay is a **clean installation** check. It does not establish an upgrade from realistic historical rows, a rollback/roll-forward migration strategy, concurrent worker behavior, deployed grants/RLS/function parity, provider evidence authenticity, or late-receipt policy. The staged reconciliation approval SQL remains separate from the numbered migrations and requires financial owner approval and independent evidence before live application. Keep D09, F02–F04 and F07–F10 open until their full acceptance criteria are met.

## Bounded historical-row upgrade rehearsal

A second run reset only the task-owned `collect_financial_qa_20260928` local project after confirming it contained one synthetic bootstrap Auth user, no payment/SMS rows, no active replay process, and that the completed clean replay reports above were preserved. The [predecessor report](historical-pre.json) applied the first **127/127** numbered migrations through `20260925190000_rwanda_momo_only.sql` on a fresh Supabase platform fixture. The guarded [seed](../../../scripts/tests/historical_financial_upgrade_seed.sql) committed one provider-confirmed RWF 1,500 payment with legacy and canonical journals, one unconfirmed intent-backed review candidate with a deliberately forged payer hash, and one unmatched attested SMS. These are synthetic records, not a provider transaction or customer-data sample.

The [pre-upgrade snapshot](historical-pre-snapshot.json) recorded **16 full financial/evidence rows** under SHA-256 `c294b544c37c730475fda5d76c6b8c5471a3c12535ff345fd7e3dc914281a9d4`, one posted and one review payment, a pending forged intent, RWF 1,500 group balance, and receipt contract version 0. The guarded [continuation report](historical-upgrade.json) applied the remaining **6/6** migrations through `20260928174000_attested_receipt_v2_contract.sql`. The [post-upgrade snapshot](historical-post-snapshot.json) retained the same 16-row hash, posted/review statuses and RWF 1,500 balance, while the forged intent became `cancelled` and the contract advanced to version 2. The migration also created an open `intent_identity_unverified` operator exception for the review payment; it did not credit that candidate.

The rollback-only [post-upgrade SQL](../../../scripts/tests/historical_financial_upgrade_verify.sql) passed **9 assertions** ([output](historical-verify.stdout)): exact provider-confirmed posting and balanced legacy/canonical journals, unchanged balances, the cancelled unverified intent and open exception, service-only receipt/finality grants, the SMS-only finalizer returning `awaiting_reconciliation` without a new payment or ledger entry, and a new Auth user receiving an empty Rwanda onboarding profile. The [post-UAT snapshot](historical-post-uat-snapshot.json) exactly matches the post-upgrade snapshot; [state readback](historical-post-uat-state.json) confirms the temporary Auth user was rolled back and the fixture still has one Auth user, two payments, three raw SMS rows and 133 migrations. Run `python3 scripts/tests/verify_historical_financial_upgrade.py` to recheck report provenance, all 133 executed migration hashes, snapshot equality and UAT readback against current source.

| Historical rehearsal file | SHA-256 |
| --- | --- |
| `historical-pre.json` | `05997d842c3f9c705cff33f6d5966590f0ce2c97f8572f887c9e1fa25eb51bf5` |
| `historical-pre-snapshot.json` | `6a292141d24862749501b657616d12a543eb0c1ae69f7dc701800a609d9e4ee8` |
| `historical-upgrade.json` | `86033a14862290fec4441f7e0719451092335e7f5a9a716cf34acd77c28a5ad2` |
| `historical-post-snapshot.json` and matching `historical-post-uat-snapshot.json` | `8e68e83fc4e1e856d1964cd72227b5be810df901397f28386cb0bbd1424871fd` |
| `historical-post-uat-state.json` | `5c8e095277272fc7a9855b571d914c6861f69239f3f448c7e558f440ad116ccc` |
| `historical-verify.stdout` | `1732e0fd0d5583dd852bf5f14281d04395a5cd4fdab5e44849f717e4324876e8` |
| `scripts/tests/historical_financial_upgrade_seed.sql` | `f6f21d438775142d49b9d344e418b799a1c6c04769406a1c9b535a72af8d557b` |
| `scripts/tests/historical_financial_upgrade_snapshot.sql` | `cf4764d70e46ea14fd1ed96069c82070ef82a5d1dd3afe11f27105386ebf2b3a` |
| `scripts/tests/historical_financial_upgrade_verify.sql` | `317d057a54f168f314323463c8ad8ed471241e36c33400fea2ca8688e4fe7353` |
| `scripts/tests/clean_migration_replay.rb` at the historical replay | `8b2245d8ac5ff3263689c56ac21aab6d9c494ba73cad7d136714222a9266fe61` |

This resolves the prior **empty-schema-only upgrade evidence gap**, but D09 remains open. The seed is deliberately small and synthetic; the upgrade rehearsal alone does not prove representative historical volume, mixed installed-client behavior, a backward migration, hosted/full-environment recovery, staged reconciliation approval, hosted deployment parity, independent provider authenticity, or rollback/roll-forward on the exact signed candidate. F02 and release GO remain blocked separately.

On 29 September, the [notification upgrade packet](../admin-notification-paging-2026-09-29/README.md) carried a hash-verified archive of this unchanged 133-migration historical fixture into a separate empty database and applied migration 134. Its selected financial rows, RWF 1,500 balance and every non-migration table-data section stayed unchanged. This is another local synthetic step for D09; representative history, incompatible clients and hosted release behavior remain open.

## Synthetic database restore and ACL negative control

The upgraded task-owned fixture was exported as a PostgreSQL 17.6 custom archive, SHA-256 `c84940178f575ea8b0b1e9fa61f63246f7a306981b772587787bbb9719fd02a3`. The archive remains in ignored `.cache` storage because it contains synthetic Auth/SMS rows; it is not placed in the release documentation. A first `pg_restore --clean --if-exists --single-transaction --exit-on-error` into a **prebootstrapped** local Supabase `postgres` database exited zero and all 1,327 table rows matched, but schema/ACL parity failed. The restored target granted `anon` and `authenticated` execution on the receipt-v2 function and `anon` SELECT on profiles where the source denied all three. This [negative-control report](restore-prebootstrapped-rejected.json) rejects that target. The exact mechanism of the grant drift has not been isolated; a successful import and matching data are insufficient acceptance evidence.

The same archive was then restored in one transaction into a **new empty `template0` database** in the separate task-owned local fixture. Cron jobs were disabled; `pg_net` was bound to empty `template1` with batch size zero. The [repeatable verifier](../../../scripts/tests/verify_financial_synthetic_restore.py) and [sanitized report](synthetic-empty-database-restore.json) compare the live source and restored database: **129 COPY table sections, 1,327 rows, four sequence statements, global roles, extension versions and the selected 16-row financial snapshot match**. Full schema, functions, policies and ACL dump text also matches after removing PostgreSQL's random `\\restrict` tokens and normalizing two specific redundant CHECK-expression parentheses; effective receipt/profile denials are unchanged. The second target passes this **synthetic database-only** restore check.

This adds a current-version, full-database local restore rehearsal to O02 and D09. It is not a restore of current hosted production, Storage object bytes, provider configuration or secrets; no approved RPO/RTO, off-site backup or signed-candidate rollback/roll-forward was verified. O02, D09 and release GO remain open.

## Local financial role-boundary rehearsal

The guarded [rollback-only SQL](../../../scripts/tests/financial_role_boundary_uat.sql) ran against the same 133-migration historical fixture and passed **17 assertions** ([sanitized output](role-boundary-uat.stdout)). It checked anonymous/member/service receipt and finality execute grants, denied direct raw-SMS and money-table access, anonymous denial of a private group's payment route, and RLS denial on populated Admin configuration tables. A synthetic non-admin Auth user could not read the private group's payment history or use Admin payment detail, raw-SMS reveal, allocation or reversal RPCs; the private group owner could still see its posted payment. The test printed no raw SMS body. The transaction rolled back, and the 16-row financial/evidence snapshot remained byte-for-byte equal to the pretest snapshot, SHA-256 `c294b544c37c730475fda5d76c6b8c5471a3c12535ff345fd7e3dc914281a9d4`.

| Role-boundary evidence | SHA-256 |
| --- | --- |
| `scripts/tests/financial_role_boundary_uat.sql` | `b7a5739c30f5c26fc8c1ef4ba1e604670e2feeda2a46bb4a1261d99173677339` |
| `role-boundary-uat.stdout` | `57ec53f81d2232510361c6727ab64a98817fef0486df3cd8feb6d740db61f38c` |

This role-boundary script is a synthetic local subset of S08 and S09. It does not test every receiver/operator/service action, session revocation, the deployed gateway, or the authorized hosted grants and RLS. Those acceptance checks and production GO remain open.

## Local Admin approval, role and session fencing

The separate guarded [rollback-only Admin SQL](../../../scripts/tests/admin_permission_revocation_uat.sql) passed **15 assertions** ([sanitized output](admin-permission-revocation-uat.stdout)) on the same 133-migration fixture. A synthetic WhatsApp-approved `platform_owner` with a fresh Auth session could read a payment and reveal one synthetic raw SMS with a reason; the reveal created one sensitive-access audit row. Without changing that JWT, revoking approval, revoking the role and expiring the session each immediately denied payment detail or raw-SMS reveal and hid the Admin identity. A session predating renewed approval or a renewed role remained ineligible, and a JWT without a session ID could not gain Admin permission. No raw body was printed. The SQL rolled back; the synthetic user and audit row were absent afterward, and the same 16-row financial/evidence SHA-256 remained `c294b544c37c730475fda5d76c6b8c5471a3c12535ff345fd7e3dc914281a9d4`.

| Admin fencing evidence | SHA-256 |
| --- | --- |
| `scripts/tests/admin_permission_revocation_uat.sql` | `4e9b73e416409f8e9f38c25d87393fd035d2bfa473366d41a413810e20917e82` |
| `admin-permission-revocation-uat.stdout` | `11adaca3e3d37cb788bf6f5af8016efcd0cca45698edb98064495b1b6551a0b7` |

S09 remains open for deployed role/action and step-up testing, concurrent revocation races, complete operator journeys and current signed-candidate evidence. The local fixture is not a hosted Admin approval or release authorization.

## Late intent and device-clock boundary characterization — 29 September

The guarded [rollback-only SQL](../../../scripts/tests/late_intent_boundary_uat.sql) exercised six synthetic attested SMS and intent cases on the full 133-migration restored schema. The [sanitized result](late-intent-boundary-results.txt) shows that an active on-time intent and a device time 14 minutes before intent creation create **review-only** candidates awaiting independent provider confirmation. At exact intent expiry, one minute after expiry with an earlier device receipt, after the two-hour evidence window, and with a device time 16 minutes before creation, the allocator returns `needs_review` and creates no payment. A direct service-role call to the private post helper is denied; a privileged direct call with the expired intent fails its active-intent guard. None of the six cases added a posted payment or ledger entry. The transaction rolled back, and the independent restore verifier still matched all 1,327 source rows, schema/ACL, roles and the 16-row financial snapshot.

The current SQL checks device evidence from 15 minutes before intent creation through two hours after expiry, but it first marks all elapsed pending intents `expired` and requires `pending` plus `expires_at > now()` before creating an intent-backed candidate. **A receipt uploaded after expiry therefore never uses the apparent two-hour matching allowance**, even when its attested device time is inside that window. It is held for review. This is the current behavior, not an approved late-receipt policy. The financial owner must decide whether such evidence always remains unlinked for operator review or may form a review-only candidate during a bounded grace period; neither path may post credit without independent provider confirmation. Representative clock integrity, upload delay, concurrency, deployed behavior and operator resolution remain open.

| Boundary evidence | SHA-256 |
| --- | --- |
| `scripts/tests/late_intent_boundary_uat.sql` | `9c8b10b1c2620295f1c39444732ae8a1ee3526ac5ad1771965ec98d26387b136` |
| `late-intent-boundary-results.txt` | `f6a6b85a4e50b59b4dde1f63b5c89ba7aab17f1e6077d8e3591a8a1ddb4d99bc` |
