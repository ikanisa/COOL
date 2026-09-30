# Collect local database implementation — 30 September 2026

## Current verified state

[Attempt1 validation](attempt1/validation.json) consolidates21 actual runtime
packets with222 bound input hashes and a fresh read-only local source readback.
The exact isolated fixture `collect_fin_concurrency_qa_20260929` contains146
migration registry entries and143 application/Auth/Realtime/migration tables.
Its canonical143–146 registry source hashes equal the current migration files.

The ordinary installer is `postgres`, without superuser or cron DML/MAINTAIN
privileges. Global cron launches remain off and pg_net batch size remains zero.
No hosted, Auth-provider, bank, notification-provider or AI-provider call was made.

| Implementation | Actual local evidence | Remaining integration |
| --- | --- | --- |
|143 bank scheduler retirement |32 normal-owner/role/immutability checks;6 canary and9 verification blocking races; nonempty historical/adversarial rollback; separate pause/observation/final transactions with71.034822-second observation; exact reapply; current canonical job inactive |Final frozen clean/populated replay and original production hosted acceptance |
|144 roster reload recovery |Actual receipts/adversarial rollback;6 blocking races with complete136-table restoration; separate client packet with91 roster,57 workbook and1 actual Chromium adapter tests |Full current browser/tab/session/PWA lifecycle |
|145 uncertain OTP recovery |56 rollback checks,9 legacy-v2 upgrade checks and6 blocking races; corrected256-character validation; exact failed-graph recovery to139-table baseline |Current Edge HTTP integration; full final integrated source set |
|146 roster resource/source integrity |29 quota/permission checks;7 blocking races including stale REPEATABLE READ40001; source verification→142 review/commit→144 reload; lost cleanup-ACK repair; complete143-table/control restoration |Current Edge HTTP integration; final clean/populated rehearsal |

**Only local goalL02 is closed by this packet.** The24-item local register keeps
23 items open. The original production register keeps101 checks open and the
production release decision remains NO-GO. Test counts from separate scopes are
not summed into a whole-system total.

## Corrections and retained failures

The first145 runtime candidate used an unsupported PostgreSQL regex repetition
bound. The corrected source separates the256-character limit from anchored ASCII
syntax, and its actual256/257/empty/non-ASCII cases pass. Both sources and the
atomic local registry correction are preserved in the OTP packet.

The first145 concurrency run passed five scenarios and failed the sixth fixture
setup because it attempted a correctly denied private-table read. A reviewed
trace identified the exact synthetic graph by full row bodies and transaction IDs.
The recovery restored every original139-table fingerprint and control before a
corrected six-scenario rerun passed. No unknown rows were removed.

The original146 candidate used a policy row lock without changing its row version.
Review identified stale REPEATABLE READ quota counting. The corrected same-value
UPDATE creates a PostgreSQL row-version conflict; an actual stale-snapshot waiter
aborts40001, leaving exactly four reservations and40000 engineering cost units.
These units represent resource exposure, not provider invoices or prices.

## Evidence limits

- Backups remain private under `.cache/local-offline-backups-20260930`; their hashes
  and decodable archive listings are retained. No whole database restore occurred.
- PostgreSQL sequence allocations are not reset. Full table fingerprints include
  business, Auth, Realtime and migration rows; controls include grants, routines,
  policies, constraints and triggers. Cron metadata/history are compared separately.
- Early scheduler/144 outer recorders omitted an explicit process exit field.
  Completed typed inner receipts, logs and complete before/after snapshots remain.
  No historical exit code was invented. The current recorder rejects a missing or
  failing exit status; eight corruption tests verify this behavior.
- Last complete clean migration replay remains141. Scoped sequential application
  through146 does not establish a clean146 replay or representative customer-data
  acceptance. Those final-goal checks remain open.
- Retained hosted124 metadata was not refreshed. Local146 is not a hosted rollout.

## Registers

The prior local register and production revision4 are hash-preserved under
[prior-registers](attempt1/prior-registers/preservation.json). Current registers
preserve every original ID and acceptance requirement:

- [24 local implementation goals](../LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md)
- [Original production requirements, revision5](../PRODUCTION_REMAINING_TASKS_2026-09-30.md)
- [Revision5 integrity validation](../production-remaining-tasks-2026-09-30.validation.json)
