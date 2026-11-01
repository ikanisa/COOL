# Backend availability and history implementation — 2026-11-01

## Scope

This change preserves all sixteen historical migration files and the immutable financial ledger, source evidence, independent approval, unknown effects, source upgrade and stopped-work protocols. It adds two migrations created with Supabase CLI 2.122.0:

- `20261101012309_collect_admission_archive.sql`
- `20261101012310_collect_member_history_pagination.sql`

The maintained SQL sources are `supabase/schema-src/admission-archive.sql` and `member-history-pagination.sql`. The original Supabase project reference remains historical lineage; the additions do not introduce another fixed endpoint/project identity.

## Admission lifetime capacity

Safe final closes now create an immutable SHA-256 receipt of the complete original admission row and remove only its derived working-index entry. The original row is retained, unchanged, in `private.collect_fence_admissions`. Records with uncertain dispatches, unresolved work or stopped-work evidence are never archived by this path. No TTL, deletion, retry of an external effect or inferred provider settlement is introduced.

New private relations:

| Relation | Purpose |
|---|---|
| `collect_fence_working_admissions` | Bounded working-set index; deletion requires a matching, verified safe-settlement receipt. |
| `collect_fence_admission_archive` | Append-only hash receipt identifying the unchanged original settled row. |
| `collect_fence_admission_totals` | Transactionally maintained retained/archive counts. Standalone counter edits are rejected. |

`_collect_fence_resources()` uses one snapshot for counters and index consistency. Its ordinary admission queries no longer scan the lifetime history. `retainedAdmissions` remains the raw lifetime count; `workingAdmissions` is the capacity input. The 100,000 working-set bound and 8 effective active/unresolved bound remain. Budget version 4 explicitly reports no lifetime `retainedAdmissionLimit` and a 100,000 `workingAdmissionLimit`. The effective count excludes only exact already-accepted stopped-lifecycle proofs, while raw stopped counts and their retained unknown obligations remain visible. Latest release/source-upgrade checks use the verified working count.

Normal closes archive in their existing transaction. Existing safe history can be indexed out in bounded, repeat-safe batches using owner-only `private.collect_fence_archive_settled_v4(limit)`, limit 1–5,000. It uses original-row locking and `SKIP LOCKED`; it sends nothing and changes no business record. This can be invoked by an owner-only local maintenance schedule. `private.collect_fence_archive_status_v4(true)` performs an explicit full-history integrity audit under a short original-table lock; it is not on the request path. Installations with a large predecessor history should backfill bounded batches before traffic, inspect status and retain the receipts in ordinary database backups.

This is **logical archival in place**, not physical cold-storage/offsite archival and not a disk-retention policy. Original rows and archive receipts still need normal backup, capacity monitoring and restore qualification. Unknown work can still intentionally saturate the working set and requires genuine outcome/lifecycle review.

### Remaining deliberate control-history gates

The separate 9,998 operation-receipt admission threshold, 10,000 scheduler lifecycle proofs and 10,000 stopped-lifecycle proofs remain unchanged. These represent infrequent owner/control operations rather than ordinary request volume. They still need alerting and a separately reviewed long-term generation/archive protocol before their remaining capacity is exhausted. This implementation does not conceal or silently raise those safety limits. The production operator should alert on both working capacity and each retained control-history budget and record a capacity runway.

## Member history and balances

History contract version 2 and the `{revision, after}` cursor shape remain compatible. New optional inputs `p_from` (inclusive) and `p_before` (exclusive) accept canonical UTC timestamps with milliseconds. Invalid dates, reversed/empty ranges and noncanonical formats are rejected. The date range is part of the cursor identity.

The production query now returns at most `p_limit + 1` rows from SQL keyset pagination, with an existing maximum page size 50. It removes the 10,000-event refusal and the Edge-side full-history list/hash/slice. Exact SQL aggregates cover the complete matching history; gross credit/debit/own values cross the SQL/JavaScript boundary as decimal strings and must fit the exact integer transport range. Reversals and corrections remain visible beside their originals; provider settlement is never asserted.

Authority, current membership, all aggregates, revision and page come from one SQL statement and one MVCC snapshot. `private.assert_actor()` retains real managed/projected session checks. History no longer inserts/removes a mutation guard or acquires the global financial batch lock. Mutation paths retain their existing serialization.

`private.member_history_versions` provides group-scoped revisions advanced in the same transaction by relevant ledger, membership, group-title, payment-status and supporter-label changes. Cursor identity binds the subject, session, group, literal search, sort and date range. Clients must refresh after a relevant concurrent change; a cursor never overrides current authorization. Missing revision state fails closed.

Indexes support group/date ordering, both signed-amount orderings and collection/member aggregation. Exact totals still scan matching rows; very large histories should use date ranges and the final deployment still needs realistic query-plan/load qualification. A balance request now calculates all member-group totals and positive-balance supporters in one SQL statement, instead of two sequential aggregate requests per membership. Balances and history retain safe-integer checks.

## Retention and recovery coverage

All four archive/history private relations are explicitly classified as blocked shared operational/derived copies. The separately implemented `guest_upgrade_challenges` and `collect_deployment_identity` are also included as blocked shared classes. Unknown/unverified guest journal rows are not pruned: they preserve the identity-projection denial barrier. The private catalog accepts the complete archive quartet and explicitly known guest/deployment additions or the existing historical profiles; partial archive groups, missing stopped-work prerequisites and unknown relations are rejected. It does not wildcard-ignore unknown relations. Existing approved retention source/catalog bindings require review/rebinding after the additive schema. Logical archival is not represented as personal erasure or external outcome settlement.

## Validation

JavaScript syntax checks completed for the changed history/helper/payments modules. The native qualification runner is `scripts/supabase/testing/self-hosted-backend-runtime.ts`; it uses the real shipping Postgres adapter, admission protocol and history/balance handlers on a freshly provisioned original16 synthetic PG17 database, then applies these additions. Its source contains tests for predecessor backfill, unsafe archive refusal, actual runtime closure, >10,000 ledger events, all sort continuations, dates/search/scope, cursor invalidation, >100,000 retained admissions, eight stopped proofs, and revoked-session denial.

**Native qualification passed all 10 scenarios on PostgreSQL 17.11; the safe receipt is `backend-native-result.json`.** The run retained 100,026 original admission rows, verified 100,024 immutable archive receipts, preserved both preexisting unknown/lost records, and admitted real runtime work beyond the old 100,000 lifetime ceiling. Eight retained stopped proofs reduced the effective slot count to 0 while leaving the original unresolved rows and unknown obligations intact. It exercised 10,005 ledger rows with real Storage/accounting constraints and all four sort continuations, half-open dates, literal search, group denial, balanced aggregates, cursor invalidation and revoked-session denial. Five failed predecessor attempts are preserved outside the checkout; they exposed one corrected PL/pgSQL alias collision and fixture setup issues (Auth field, Storage journal/budget, server timezone), without relaxing any production guard. The runner uses synthetic Auth rows, synthetic financial records and explicit synthetic stopped-work evidence. This passing receipt does not prove real local GoTrue/Storage/provider operation, production capacity, independent key custody or whole-system recovery. No production service has been changed by this implementation.
