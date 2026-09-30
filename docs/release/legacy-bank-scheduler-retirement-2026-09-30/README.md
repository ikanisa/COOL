# Legacy bank scheduler retirement — source candidate 143

Status: **implemented in local source; database acceptance and deployment remain pending**.
This packet does not claim that any hosted job has been disabled. The worker made
no database, provider or hosted mutations. It did not change migration142, any
bank API, or financial data. Source test results are not PostgreSQL execution.

## Finding and correction

The bank control-plane migration scheduled `collect-daily-bank-reconciliation`
with `30 21 * * *`. The later Rwanda-only migration revoked client/service access
to bank operations but left that owner-executed job active. The retained hosted
catalogue lists its command MD5 as `0682a2a141329919f696e8ec4627fb30`, which matches
the original migration's exact command. The snapshot does not disclose the job's
owner, database, host or port; those fields remain deployment readback gates.

Migration `20260930110000_retire_legacy_bank_scheduler.sql`:

- Accepts only the canonical name, exact original command, original schedule,
  owner `postgres` or `supabase_admin`, current database, `localhost`, and current
  server port. Unknown same-name metadata stops the whole transaction for review.
- Sets only `active=false` through `cron.alter_job`; preserves job identifiers,
  definitions, completed run history, and every financial/historical table.
- Serializes against cron metadata changes and disables restricted RLS filtering
  for this owner-only check so hidden jobs produce an error, not partial coverage.
- Requires `cron.launch_active_jobs=off` and no recorded nonterminal run for the
  canonical job. It neither changes scheduler configuration nor cancels sessions.
- Records an immutable private retirement receipt, bounded to two rows by the
  admitted owner set and uniqueness. It records command SHA256, prior activity,
  owner/database, constant reason/version, time and installer; no raw command or
  credentials are copied to the audit table.
- Rejects audit UPDATE, DELETE and TRUNCATE. PUBLIC, anon, authenticated and
  service_role have no table or helper privileges. The helpers are invoker-only.
- Reruns without modifying receipts for a still-disabled identical job. A missing,
  renamed, altered or reactivated audited job fails review; its old receipt cannot
  silently authorize another retirement. Privileged owner administration remains
  outside this boundary; this migration does not modify the cron extension's
  triggers or try to constrain a database owner.

Canonical command SHA256:
`58ca13bd6915f92b194de581f89815718ac50a5d702055a4df3f07c0486bd597`.

## Verification produced by this worker

Exact commands, runtime versions, exit codes and logs are in `verification.json`
and `logs/`. `source-manifest.json` binds the new files and relevant unchanged
upstream evidence. `source-snapshot/` retains the candidate source separately from
future edits. `artifact-manifest.json` binds the retained packet.

The focused suite comprises 9 Ruby source-contract tests and 9 Python snapshot
comparison tests. The former inspect SQL text; the latter test fabricated local
JSON fixtures and demonstrate that the readback comparator refuses changed
financial hashes, history, unrelated jobs, missing receipts and forged activity.
These tests do not execute SQL, check pg_cron privileges, or validate PL/pgSQL
runtime semantics. See the exact results rather than inferring live acceptance.

A separate worker reviewed the candidate read-only and reported no blocking
source defect. Its explicit boundaries were differently named bank jobs and
actual scheduler-process draining, both retained below. After that review, a
local lock-order check added the same cron-table lock ahead of audit DDL during
full migration replay, so migration and helper acquire cron before audit. The
focused checks were rerun on the final source.

`legacy_bank_scheduler_retirement_uat.sql` prepares 32 database assertions,
including real API role switches, fresh retirement of a synthetic second owner,
command/owner/database/schedule/host/port rejection, drift and in-flight run
rejection, audit immutability, repeat-call identity, all original cron/history
rows and hashes of every public/collect_hybrid business base table. It requires
exact143, an isolated clone marker, disabled cron launches and pg_net batch zero;
all synthetic writes are rolled back. **It has not been executed by this worker.**

## Root-owned isolated acceptance sequence

After142 recovery/races/receipt acceptance, use the existing isolated fixture:

1. Confirm the fixture identity and set the task marker
   `collect.legacy_bank_scheduler_qa=isolated_clone`. Keep actual launcher
   scheduling off and `pg_net.batch_size=0`; do not merely infer this from a
   client connection string.
2. Run `scripts/tests/legacy_bank_scheduler_snapshot.sql` at exact142 and retain
   the returned JSON. It captures counts/hashes of every public/collect_hybrid
   business base table, job metadata with command hashes, and complete cron
   history hashes. No underlying row or command contents are printed.
3. Apply the frozen143 migration using the root-owned guarded runner and record
   its exact migration hash. Expected existing job routing must be confirmed.
4. Run the snapshot script at exact143. Compare the two returned JSON files:

   ```sh
   python3 scripts/tests/verify_legacy_bank_scheduler_upgrade.py before143.json after143.json
   ```

5. Run `scripts/tests/legacy_bank_scheduler_retirement_uat.sql` and retain its
   actual 32-check result and rollback proof. Its guard requires exactly one
   original canonical receipt in the existing isolated fixture; a different
   fixture must be deliberately reviewed rather than weakening that guard.
6. Rerun the migration in the isolated environment and verify receipt hashes and
   job/history state remain unchanged. The in-function no-op check is also covered
   by the rollback UAT; full migration reapplication is a separate acceptance step.

## Staging/deployment and remaining limitations

- Confirm deployed pg_cron version, installer table/function privileges, full job
  visibility, and actual owner/database/host/port. The retained hosted catalogue
  only proves the canonical name/schedule/command digest and active flag.
- Arrange an owner-approved scheduler maintenance interval, confirm the launcher
  has received its configuration reload, and drain already dispatched/queued bank
  commands before applying143. The SQL checks configuration and run-history state;
  they do not prove scheduler-process acknowledgement or cancel existing work.
  Where run logging is incomplete, obtain direct running-session evidence too.
- Read back active canonical job count zero, exact audit receipt, unchanged other
  jobs, preserved historical/financial baselines, and role/ACL denial after apply.
  Only then restore the prior scheduling configuration for other jobs. The
  migration itself never changes that configuration.
- An unexpected job identity/routing or retirement drift requires owner review.
  Do not broaden the match, unschedule all same-name jobs, remove audit receipts,
  delete bank history or reopen the legacy API to force a pass.
- Existing differently named jobs or deliberate future owner reconfiguration are
  not automatically removed. This correction is limited to the verified canonical
  scheduled bank path and does not close all X02/O01 operational acceptance.
- There is no automatic rollback that reactivates the bank job. Before commit,
  PostgreSQL rollback restores the whole transaction. After commit, preserve the
  receipt/history and use a reviewed forward correction; historical product scope
  must not be reopened by a generic rollback script.

## Primary compatibility references

The pg_cron source defines the partial-update contract for
[`cron.alter_job`](https://github.com/citusdata/pg_cron/blob/v1.6.4/pg_cron--1.3--1.4.sql),
the job table's owner-based
[RLS policy](https://github.com/citusdata/pg_cron/blob/v1.6.4/pg_cron.sql), and the
superuser SIGHUP context for
[`cron.launch_active_jobs`](https://github.com/citusdata/pg_cron/blob/v1.6.4/src/pg_cron.c).
These references explain the candidate's assumptions; they do not establish the
version or permissions of the target deployment.
