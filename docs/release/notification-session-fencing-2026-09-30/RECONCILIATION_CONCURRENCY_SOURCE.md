# Reconciliation concurrency harness — authored source, not SQL acceptance

Source: `scripts/tests/reconciliation_workflow_concurrency_uat.rb`.
SHA-256: `807f85da100d5335b4b40798fc17e2abce6b884445b937baf99c13be58e1bc6a`.

The worker executed **Ruby syntax checking only: PASS**. The worker made no database, Auth or provider calls. Root must back up and verify the dedicated fixture before running the harness; SQL syntax, accounting and concurrent lock behavior remain unverified until that execution succeeds. Migration141 remains frozen.

## Root invocation

From the repository root, with root's verified local Docker fixture available:

```sh
COLLECT_RECONCILIATION_QA=isolated_clone ruby scripts/tests/reconciliation_workflow_concurrency_uat.rb
```

Capture stdout and stderr separately and record the exit code. Success prints JSON with exact source/migration hashes, observed backend PID/blocker evidence, accounting assertions and restoration fingerprints. Failure raises an error, including any cleanup failure; retain the baseline backup and logs for investigation. Do not treat a Ruby syntax pass as a SQL pass.

## Required fixture

- Exact Docker project and labels `collect_fin_concurrency_qa_20260929`, configured port55722 and matching actual port binding.
- PostgreSQL owner connection, exactly141 migrations through `20260929180000`, installed session gate, cron disabled and pg_net batch size0.
- Empty push token/delivery tables, unused `99830000` graph, unused synthetic phones/collection slug/payment references and no existing test worker sessions.
- No other actors running during execution or cleanup. Root owns the backup, execution and recovery decisions.
- Named immutable DELETE guards must all exist and be enabled before seeding; unknown additional BEFORE DELETE guards cause refusal.

## Real two-session scenarios

Synthetic maker/checker identities have verified phone approval, platform-owner roles and AAL2 sessions newer than their grants. All review proposals, independent approvals, finalization authorization and finalization use the actual public APIs. Service-role direct gateway access is tested and must remain denied.

1. One finalizer holds its completed transaction; a duplicate waits, then returns replay. Assert one provider confirmation, one canonical receipt, two balanced journal lines, two compatibility ledger rows and one audit fact for each proposal/approval/finalization/provider confirmation.
2. Auth-session deletion commits first. Finalization waits at the outer gate, then refuses the revoked actor without changing financial/review/payment-audit rows.
3. Finalization owns the transaction first. Auth deletion waits, then succeeds after posting commits.
4. Actual Admin role revocation owns the roster first. Finalization waits and then refuses without financial mutation.
5. After actual role reactivation and a fresh maker session, finalization wins first; actual role revocation waits and succeeds afterwards.

Lock overlap is established using observed backend PIDs, advisory wait events and `pg_blocking_pids`, with bounded polling. The script checks that blocked finalizers have not already acquired review/payment mutation locks. In the Auth-revoke-first case, it also observes the exact ungranted shared141 advisory request and asserts there is no granted Admin roster advisory lock. The roster key uses the signed one-bigint key split and its separate advisory key space, so a different advisory lock cannot satisfy the assertion. It does not infer overlap from a fixed sleep.

## Cleanup and preservation

This committed race harness needs cleanup beyond rollback-only UAT. Root explicitly authorized this **synthetic fixture only** procedure:

1. Close both worker connections and verify their PIDs/application names are gone. Termination, if necessary, targets only a previously observed matching PID/name.
2. Recheck the application catalog/control fingerprint. In one owner transaction, acquire the141 gate before table locks, refuse other active actors, and lock the exact immutable tables.
3. Validate and temporarily disable only these five named guards:
   - `collect_security.reconciliation_reviews.reconciliation_review_immutable`
   - `public.ledger_entries.ledger_entries_prevent_delete`
   - `collect_hybrid.momo_journal_entries.hybrid_momo_journal_entries_immutable`
   - `collect_hybrid.momo_journal_lines.hybrid_momo_journal_lines_immutable`
   - `collect_hybrid.momo_balance_snapshots.hybrid_momo_snapshots_immutable`
4. Refuse unknown incoming references, remove only fresh9983-linked financial/review/Auth/profile/member rows, and immediately restore all five enabled trigger states. Incoming member FKs are checked before deleting exact now-unlinked synthetic members.
5. Delete realtime invalidations only when their `xmin` matches an observed test transaction ID or the cleanup transaction. Earlier fixture telemetry, including the previously observed141 upgrade delta, is preserved as baseline.
6. **Before committing cleanup**, compare every application table plus Auth users/sessions against the baseline digest and compare complete trigger/ACL/function fingerprints. A mismatch raises and rolls back both cleanup and temporary trigger-state changes. Recheck after commit.

The baseline is dynamically enumerated across `public`, `collect_hybrid`, `collect_security`, `collect_admin_access`, plus `auth.users` and `auth.sessions`. It includes private reviews, all financial families, balances, audits, member records and `app_realtime_events`, not merely anticipated changed tables. PostgreSQL sequence allocations are not rolled back or reset and are expressly excluded from row-data restoration claims.

This QA procedure changes no runtime grants and is not an approved production cleanup operation. No acceptance ID is closed by the authored harness.
