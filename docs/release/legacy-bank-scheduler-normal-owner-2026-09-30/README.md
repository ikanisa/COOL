# Legacy bank scheduler retirement — normal owner workflow

This packet supersedes the original source-only candidate and its `cron.job` table-lock failure. The original candidate, failed runtime logs and earlier generated sources are preserved. Runtime results must come from the root operator; pure source tests do not establish a database pass.

## Implementation

Migration 143 runs as the ordinary job owner (`postgres` in the isolated fixture), with existing cron SELECT and `cron.alter_job` rights. It requires no cron DML/MAINTAIN grant, superuser installer, global scheduler setting change, cancellation call or bank-function execution. It requires full cron visibility and existing `pg_read_all_stats` access.

Each transaction must start at SERIALIZABLE isolation before any snapshot is acquired. A same-value schedule change through `cron.alter_job` acquires the owner-authorized row lock. An external owner edit committed after that snapshot causes a serialization failure; the operator retries the complete transaction after a fresh readback.

The migration creates one immutable `paused_pending_verification` receipt. Installation does **not** claim retirement is verified. Two subsequent calls to `collect_hybrid.verify_legacy_bank_scheduler_retirement()` are required:

1. In a separate SERIALIZABLE transaction after the migration commits, capture and commit a server-authoritative observation.
2. In another SERIALIZABLE transaction, at least 30 seconds after that observation timestamp, repeat the checks and commit a final `retired_verified` receipt.

The interval is measured from a readback that happened after the pause committed. It does not claim an interval measured from the first observation transaction's commit timestamp. A long-held pause transaction cannot manufacture the required postcommit observation.

Both phases require the exact canonical name, owner, command, schedule, database, host and port; GMT/UTC runtime; run logging; one stable launcher process; a five-minute margin around the daily UTC launch; no recent/nonterminal history or live bank command; and unchanged historical content/counts. Replays perform these checks again. The final receipt binds authoritative readback digests and distinct transaction IDs. Digests are audit references to checked server state.

Three private bounded tables retain pause, observation and final verification. RLS has no client policies, API roles have no table/helper privileges, and UPDATE/DELETE/TRUNCATE triggers reject changes. No financial table is modified.

## Primary-source basis

The pinned [pg_cron 1.6.4 job metadata source](https://raw.githubusercontent.com/citusdata/pg_cron/v1.6.4/src/job_metadata.c) builds an UPDATE, restricts nonsuperusers to their own jobs, temporarily uses the extension owner and restores the caller (`AlterJob`, copied-source lines 1238–1408). Supplying no attributes is rejected. Supplying the unchanged schedule exercises the real UPDATE and row lock.

The pinned [pg_cron 1.6.4 scheduler source](https://raw.githubusercontent.com/citusdata/pg_cron/v1.6.4/src/pg_cron.c) accepts metadata invalidations in its loop, refreshes task state, and caps poll waits at one second. `jobCanceled` handles already launched tasks whose active state becomes false; the previous blanket assertion that disabling cannot cancel dispatched work is therefore superseded. The 30-second observation interval is a conservative operational margin, supported by repeated authoritative checks; it is not a claim about a guaranteed launcher wall-clock deadline under arbitrary resource starvation. Runtime timezone/logging settings cannot safely be toggled with ordinary transactional SQL, so this packet does not fabricate those negative runtime tests.

Source snapshots and their license are retained under `primary-source/`, bound by its manifest. The SQL pins the reviewed extension version; a different version fails review.

## Root-only isolated execution

Exact fixture: `collect_fin_concurrency_qa_20260929`, container `supabase_db_collect_fin_concurrency_qa_20260929`, host port 55722/server port 5432. No other local or hosted database is authorized by these scripts. The test scripts require the fixture's existing launch-off/net-zero settings without changing them.

1. Preserve an immutable pre-run database backup and baseline fingerprints. Root owns the database exclusively while these tests run.
2. Before installing 143, run:

   ```sh
   ruby scripts/tests/legacy_bank_scheduler_concurrency_uat.rb --execute canary142 NEW_CANARY_OUTPUT_DIRECTORY
   ```

   The six cases prove the actual normal-owner API snapshot/row-lock behavior, including commit and rollback in both orders, changed schedule and duplicate request serialization. A real `pg_blocking_pids` relation is required. The harness writes its baseline checkpoint before editing and checks exact business/job/history/audit restoration after each case.
3. On version 142, run `populated142-143-rollback.sql` and `populated142-143-adversarial-rollback.sql` with psql as `supabase_admin`. This role is used only to seed historical/malformed fixture states. The scripts switch to ordinary `postgres` before the exact migration and every tested helper call; those operations assert no superuser or cron DML/MAINTAIN rights. Everything is rolled back, including the migration, fixture states and audit tables. Both succeeded and failed nonempty historical rows must be preserved and bound. The adversarial script covers same-count history-content drift, running/starting/incomplete/recent runs and owner/name/routing/additional-job failures.
4. Capture a fresh version-142 snapshot using `legacy_bank_scheduler_snapshot.sql` as postgres, with the fixture-only `collect.legacy_bank_scheduler_qa='isolated_clone'` session marker. This marker does not disable providers or establish isolation by itself.
5. Install the frozen migration as postgres, recording the migration registry entry atomically before the migration's COMMIT. An existing READ COMMITTED wrapper must be replaced with SERIALIZABLE before acquiring any snapshot. Capture a paused version-143 snapshot and compare:

   ```sh
   python3 scripts/tests/verify_legacy_bank_scheduler_upgrade.py BEFORE.json PAUSED.json paused
   ```

6. Execute and commit the first verification call in a new SERIALIZABLE transaction. Preserve its exact readback result. Immediate retries in the same transaction must fail `25001`; a new transaction before 30 seconds must fail `55000` without adding a final receipt.
7. Wait at least 30 seconds from the returned observation timestamp, then execute and commit the second verification call in another SERIALIZABLE transaction. Preserve the result, including the authoritative readback and final receipt.
8. Capture the final snapshot and run the comparator with phase `verified`; run the rollback-only `legacy_bank_scheduler_retirement_uat.sql` as postgres.
9. Run:

   ```sh
   ruby scripts/tests/legacy_bank_scheduler_concurrency_uat.rb --execute verified143 NEW_VERIFIED_OUTPUT_DIRECTORY
   ```

   The nine cases add actual pause/verification helpers, reactivation in both lock orders, duplicate verification and exact fresh retries. Require full baseline restoration and no surviving test sessions.
10. Freeze the tested source/artifact hashes and root runtime receipts. The database remains at verified 143 with its canonical job inactive; no provider or production acceptance is implied.

The checkpoint recovery path restores only the known canonical owner-API fields and checks exact baseline parity. It does not delete an unexpected job/history/audit graph or silently overwrite earlier run output. A failed cleanup is recorded and requires root investigation.

## Source verification

Run the Ruby retirement and snapshot source tests, Python upgrade-comparator tests, and Ruby syntax checks. The comparator's mutation cases reject active jobs, changed money/history, changed routing, duplicate/missing receipts, same-transaction phases, short/inconsistent intervals and unbound/malformed evidence. These source checks are distinct from the runtime steps above.

## Acceptance bounds

Local acceptance requires the normal-owner installation, nonempty historical rollback rehearsal, both postcommit verification transactions, actual blocking concurrency cases, negative authorization/immutability tests and complete fingerprint restoration. The workflow is intended to run with the launcher enabled as well, but these provider-isolated local tests do not exercise real enabled bank dispatch. Runtime version/timezone/logging/launcher changes fail review and are not automatically repaired. The verified state does not prevent a privileged owner from editing the job later; every replay rechecks drift.
