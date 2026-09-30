# Roster provenance concurrency — prepared source

Date: 30 September 2026. The author ran **Ruby syntax only** and made no database calls. The root-owned database run must establish the assertions below independently.

Harness: `scripts/tests/roster_import_provenance_concurrency_uat.rb`.

Frozen source SHA-256: `94fd6a7e7859ad2f220b88cf6419dcc99f46701411fd32eafc33ccd1f4a1e1b9`.

Pinned migration 142 SHA-256: `75a315d8a41c2c19f62f2fcd4557e27cb7c14e3f9ebe251f57b18e748d7349d7`. This is the corrected SQL source; the earlier failed compile source is retained separately.

## Exact invocation

Run from the repository root, after other fixture tests have disconnected:

```sh
COLLECT_ROSTER_CHECKPOINT=/absolute/new/roster142-checkpoint.json COLLECT_ROSTER_PROVENANCE_QA=isolated_clone ruby scripts/tests/roster_import_provenance_concurrency_uat.rb > docs/release/roster-import-provenance-2026-09-30/concurrency-result.json 2> docs/release/roster-import-provenance-2026-09-30/concurrency.stderr
```

It accepts only task-owned Docker project `collect_fin_concurrency_qa_20260929`, container `supabase_db_collect_fin_concurrency_qa_20260929`, verified project labels/configuration, host port **55722**, database/owner `postgres`, exactly142/latest `20260930100000`, disabled cron, `pg_net.batch_size=0`, and empty notification token/delivery tables. It requires unused `99540000` IDs, Auth phones `250788954001`/`250788954002`, and roster phones `+250789954…`. Existing bootstrap operators and financial rows are preserved; no RACE fixture is required.

## Prepared real overlap scenarios

The two psql workers hold actual RPC transactions open. Every race requires `pg_blocking_pids` to identify the other worker and an observed PostgreSQL lock wait before releasing the first transaction.

1. Duplicate upload request: one source/consent/extraction attempt; waiting duplicate receives `roster_import_in_progress`.
2. Duplicate human review: one immutable reviewed revision and the same acknowledgement.
3. Duplicate commit: one new membership/group/audit and a bound replay acknowledgement.
4. Auth session deletion before commit: commit waits and is denied without membership effects.
5. Commit before Auth session deletion: one commit completes, then deletion proceeds.
6. Actual Admin role revocation before commit: commit waits and is denied.
7. Commit before actual Admin role revocation: one commit completes, then revocation proceeds.
8. Actual feature-toggle RPC before commit: flag row lock serializes the call; disabled flag denies commit.
9. Commit before feature-toggle RPC: commit's shared flag row lock keeps the flag enabled through the atomic operation.
10. Competing parent revisions: the waiting stale-parent request cannot branch immutable review history.
11. Newer review before queued old-revision commit: the stale commit is denied; the latest reviewed revision can subsequently commit.

Additional checks simulate a lost successful acknowledgement and retry the exact commit payload, reject changed retry content, validate all CommitReceipt fields, and prove financial tables did not change. All source/provider responses are explicitly synthetic; provider HTTP and hosted Auth calls remain **zero**.

## Cleanup boundary

The script captures all ordinary/partitioned tables in the application/private/Auth/realtime/migration schemas plus schema/relation ACLs, RLS, routines, constraints and triggers. Before seeding it persists a new root-selected checkpoint containing full per-table fingerprints, controls and the original feature flag. It incrementally records transaction IDs emitted by its own sessions, then attributes child transaction IDs through exact synthetic source/review/commit/group/batch/member/audit rows. Successful PostgreSQL exception blocks can create these child IDs even when no error is thrown.

Before cleanup it closes or terminates only its verified worker PIDs and confirms both are gone. Under the141 exclusive gate and table locks, it verifies exactly the five known `roster_provenance_immutable` guards and rejects unknown DELETE guards or incoming foreign-key references. Only these five guards are temporarily disabled for deleting this synthetic graph. They are re-enabled in the **same transaction**. Feature-flag fields changed by the actual toggle RPC are restored from the complete prior record. Original telemetry is preserved; only observed top-level IDs, child IDs evidenced by exact owned graph rows, and the cleanup transaction ID are removed. Collection cleanup IDs are retained from source-linked create receipts before those receipts are removed. Per-table original/current residual fingerprints appear in retained errors if cleanup fails. The primary scenario failure is kept distinct from a cleanup failure.

The complete data and control fingerprints must match the original baseline **before cleanup commits**, and are checked again afterward. Any failure rolls back the cleanup and trigger state changes. No financial immutability trigger is disabled. PostgreSQL sequence counters are not restored or reset, and the result explicitly distinguishes this from row/control restoration.

## Source validation

`ruby -c scripts/tests/roster_import_provenance_concurrency_uat.rb`: **Syntax OK**. Logs and source/runtime hashes are retained in `concurrency-source-validation.json`. Syntax validation does not establish SQL parsing, lock order, successful cleanup, or production acceptance.

## Failed first run and guarded recovery

The first root run reached cleanup but failed its full-baseline comparison; the cleanup transaction rolled back. Its original source and source validation packet are retained under `sources/concurrency-attempt1-*`, and root execution artifacts remain unchanged. The source diagnosis is omitted child-subtransaction telemetry IDs; root must independently verify recovery. No first-run pass is claimed.

`roster_import_provenance_recovery_uat.rb` decodes the pinned pre-concurrency backup into temporary baseline tables. Its first `--trace` run rolls all cleanup changes back. Only a second `--apply TRACE_PATH TRACE_SHA256` invocation can commit, after proving current data and controls match the reviewed trace. Every event absent from the backup must have an independently attributed owned-row XID; an unexplained event prevents cleanup. All 131 selected table fingerprints and the control fingerprint must match before commit. Sequence counters are expressly excluded.
