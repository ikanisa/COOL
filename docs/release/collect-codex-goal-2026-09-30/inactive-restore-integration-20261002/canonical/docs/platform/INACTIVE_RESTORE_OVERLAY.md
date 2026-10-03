# Inactive business authority after an isolated restore

The existing restore remains an archive comparison by default. Its new optional `--inactive-overlay` step stops business execution only inside the newly created isolated restore target. It runs after the original table/sequence, schema/ACL, global-role, exact source/catalog and both-tier worker comparisons pass. Those original receipts remain unchanged. A separate owner receipt records the target stop; the original captured policy is never described as having been inactive.

Use a fresh, reviewed source contract and its associated database report, role report, extension metadata and worker snapshot. Keep the existing encrypted archive, Vault, source, TLS, RAM-only target and cleanup controls. This option cannot be combined with historical migration rehearsal and requires both `--worker-snapshot` and an explicit reason.

```sh
ruby scripts/tests/production_archive_restore.rb \
  --source-contract /approved/current-source-contract.json \
  --source-contract-sha256 APPROVED_CONTRACT_SHA256 \
  --database-report /approved/database-report.json \
  --roles-report /approved/roles-report.json \
  --extension-metadata /approved/extension-metadata.json \
  --worker-snapshot --inactive-overlay \
  --inactive-reason 'Isolated restore retained inactive pending controlled recovery' \
  /approved/new-restore-report.json
```

This example contains paths and a hash placeholder. It does not create or approve a source contract. The helper refuses missing guard versions, missing comparisons, inconsistent source or SQL, unsafe target/non-superuser owner/context, busy locks, excess identity counts, exhausted revisions, unexpected private evidence or cron metadata, expiry and unavailable ordinary-owner `cron.alter_job` permission. It never grants permission or falls back to a privileged owner.

The one transaction:

- Pauses the actual operations policy, enables its emergency stop, disables catch-up and advances the fence.
- Disables the successor, worker, history-maintenance and telemetry configurations and advances their revisions. It appends the ordinary immutable worker configuration history and the exact binding produced by its unchanged capture trigger.
- Disables the real hybrid SMS flag through its unchanged database-owner governance trigger. The exact resulting runtime audit and realtime invalidation UUID remain linked.
- Revokes every admitted pending/active operations identity and gateway device, retaining original UUIDs, public keys, owner/session, activation and expiry fields. Existing one-way guards prohibit reuse or reactivation of those old keys.
- Deactivates only the two exact postgres-created receipt cron jobs using the existing owner API, preserving their IDs, schedules, commands and creators.
- Publishes an immutable private logged stop capsule and finite before/after digests, with the actual database owner, reason, source/archive/comparison/tool associations and explicit `financial_action=false`, `send_action=false`, `resume_required=true`.

No original payment, allocation, ledger, approval, run, sender arm, callback, worker job, quota charge, scan cursor, uncertain outcome, cold object or original lookup UUID is removed or completed by the stop. The future preference in `collect_automation.operating_policy` retains its original guarded value. An already armed native invocation cannot be recalled by this database transaction. Authenticated late observations on original primary/successor routes remain investigable and do not reopen authority or establish carrier delivery.

The transaction uses existing TRY advisory fences, identity-table NOWAIT admission fences and exact row NOWAIT locks, followed by protected READ COMMITTED catalog/state checks. Partial acquisitions and all deltas roll back on refusal, including automatic configuration bindings and flag invalidations. Later nested reads and cron calls retain bounded lock, statement and owner-process deadlines. The source-catalog and exact own-transaction invalidation checks may scan their finite target relations; no deep indexed cost claim is made for those checks.

Private evidence files include the input UUID, tooling vector, owner diagnostic and separate result association. On an interrupted or uncertain owner response, preserve them and claim no completion. If the same owned target still exists, a trusted owner can regenerate the exact script from the saved input and original contract using the helper; only `expires_at` may be refreshed to the existing 120-second admission bound. Original UUID replay verifies every permitted current row, immutable derived row, private capsule schema and digest before returning the prior receipt. A changed input, reopened state, missing object or conflicting evidence is refused. Do not invent a new UUID to resolve an unknown original outcome. The enclosing restore caller reports failure and retains evidence on any overlay error; its original lifecycle may remove the disposable target.

Logged stop state can survive a postmaster process restart in the same running target, data directory and tmpfs lifetime. The normal disposable target is removed during cleanup. This does not prove container restart, power loss, target deletion, off-site durability, key escrow, production credential/role parity or an approved RPO/RTO.

Resume requires explicit controlled owner work through the existing authenticated enrollment, proof and activation flows, fresh operations and gateway keys and a fresh gateway installation. Reconcile original native journals, pending/unknown sends and retained approvals before separately re-enabling any policy, flag, configuration or cron. This helper contains no automatic resume or unrevocation action.

The bounded local proof reuses selected205 database bytes and separately admits exact current208 guard definitions. Synthetic retained test-session preparation and service/Auth test claims are fixture setup, never overlay mutations or archive Auth-parity evidence. Full current208 encrypted-archive recovery, hosted privilege parity, Vault cryptography, native/scheduler packaging and physical-device recovery remain separate acceptance work.
