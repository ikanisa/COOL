# Notification session race — telemetry-preserving source update

Source: `scripts/tests/notification_delivery_session_concurrency_uat.rb`.
SHA-256: `fe4ec9c41a837cbdadd6238c20a2767e2149ed976da6ef3ee8ff6c317fc8c827`.

**Ruby syntax: PASS. SQL not executed by the notification worker.** Root owns the backed-up fixture and actual concurrency execution. Migration141 and the current readiness report are unchanged.

## Root invocation

```sh
ruby scripts/tests/notification_delivery_session_concurrency_uat.rb
```

Capture complete stdout/stderr and the exit status. The harness still requires exact task-owned Docker labels/project/port55722, exactly141 migrations, disabled cron and pg_net, empty push tables and unused9973 synthetic identities. Run while no other actor is using the fixture. Success returns source/migration hashes, real backend blocking evidence and baseline/control restoration evidence.

## Preservation correction

The previous20-family fingerprint omitted realtime invalidations. This version dynamically snapshots **every ordinary table** in `public`, `auth`, `collect_hybrid`, `collect_security` and `collect_admin_access`, including all Auth tables and `app_realtime_events`.

Each owned literal query transaction and worker transaction emits its actual PostgreSQL transaction ID. Read-only query XIDs may also be captured; they produce no invalidation rows. Every prior telemetry row remains outside the deletion set. Worker output, including remaining output after a connection closes, is inspected for transaction IDs.

After both verified worker backends exit, cleanup rechecks table and control catalogs, takes the141 gate before locks, locks the telemetry table, requires no other active client transaction and refuses unknown telemetry triggers/references. It removes only exact newly created9973 rows and member records whose incoming references are absent, then removes telemetry with xmin in this run's observed transaction IDs or the cleanup transaction.

**Before committing**, it compares the complete application/Auth data digest and trigger/ACL/function digest with the original baseline. Any mismatch rolls cleanup back. Both are checked again after commit. No immutable financial guard or runtime grant is disabled. Sequence allocations are expressly not restored.

The earlier141 upgrade's telemetry delta remains preserved as part of the starting baseline unless root separately completes the reviewed disposition described in `TELEMETRY_QA_SOURCE.md`. This harness does not repair prior runs or delete unknown telemetry.

All prior registration, duplicate-claim, logout, live older-session replacement, invalidating UPDATE, user-ban and mixed Auth/reconciliation40001 scenarios remain present. Their current integrated run remains an acceptance requirement until root executes this exact source.
