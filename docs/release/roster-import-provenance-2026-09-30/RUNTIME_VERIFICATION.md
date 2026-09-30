# Roster provenance142 — isolated runtime verification

Root-executed results, 30 September2026 (Africa/Kigali). **Scoped local passes;
production acceptance remains open.** The task project is
`collect_fin_concurrency_qa_20260929`, container
`supabase_db_collect_fin_concurrency_qa_20260929`, host PostgreSQL port55722.
Both Docker project labels and the local project/port configuration were checked.
Cron launches remained off and pg_net batch size remained zero. No provider,
hosted Auth or deployed-project mutation was performed.

## Executed results

| Evidence | Result | Preservation proof |
| --- | --- | --- |
| [Corrected142 application](apply142.json) | PASS from verified clean141 | All124 predecessor application/Auth table fingerprints unchanged; five new private provenance tables empty |
| [Rollback SQL UAT](rollback142.json) |96 assertions PASS | All129 selected application/Auth table fingerprints restored |
| [Recovery rehearsal](recovery142-trace-attempt2.json) | PASS, then ROLLBACK | Exact131-table backup baseline reconstructed; failed graph remained unchanged after rehearsal |
| [Pinned recovery application](recovery142-applied.json) | PASS | All131 backup table fingerprints restored and current control fingerprints unchanged |
| [Corrected concurrent run](concurrency142-attempt2.json) |11 scenarios PASS | All131 baseline table fingerprints and controls restored; synthetic graph removed; zero worker sessions remain |
| [Actual SQL receipts](receipts142.json) | Two workflows PASS | Actual deterministic and synthetic-AI source/review/commit/replay/read receipts emitted; all131 table/control fingerprints restored by rollback |

The actual SQL-to-Dart decoder is a separate follow-up check using
`receipts142.stdout`. This document does not claim it passed before its command,
source and result are separately retained.

## Corrected concurrency coverage

The retained result observes actual blocking PostgreSQL sessions for duplicate
source acquisition, duplicate human review, duplicate commit, both serialization
orders of session/role/feature revocation, competing parent reviews and a newer
review invalidating a queued commit. It additionally validates exact replay after
a deliberately ignored response, changed-payload denial, one member/audit per
commit and unchanged financial rows. Model extraction and Auth HTTP transactions
are controlled fixtures; actual provider and GoTrue integration remain open.

The corrected harness persists a new checkpoint before seeding, captured top-level
transaction IDs, exact owned-row child transaction attribution, scenario results
and cleanup outcome. It deletes only the owned synthetic graph and attributed
telemetry, temporarily disables only the five named provenance guards, restores
them inside the same transaction, and fails rather than committing any incomplete
baseline restoration. No financial guard is changed.

## Preserved failures and root correction

- The original142 concurrency attempt failed its cleanup assertion. Its source,
  stdout/stderr and [execution record](concurrency142-execution.json) remain.
  Child transaction IDs generated inside successful SQL exception blocks had not
  been included in telemetry cleanup. No eleven-case pass is assigned to that run.
- The authoritative pre-run dump is
  `.cache/roster-provenance-20260930/pre-concurrency142.dump`, SHA256
  `500e66e7de0c0720aa8107b41b9c95444676411cf5fe2fe2711f667439732ed2`.
  Root additionally backed up the failed graph before recovery, SHA256
  `32d59a34a3658f6adddf8b58b0e61a56682f9e8e1f05f3c6030124a5b384b7ad`.
- Recovery attempt1 stopped before cleanup because `auth.schema_migrations`
  grants the fixture's postgres role SELECT without a privilege permitting an
  exclusive table lock. A direct catalogue/lock check identified that exact
  relation. The original recovery source and failed execution are retained.
- Root corrected recovery to hold ACCESS SHARE only on that read-only Auth
  registry, retaining ACCESS EXCLUSIVE on the other130 selected tables. Quiet
  fixture, source/backup hashes and complete final baseline checks remain.
  PostgreSQL's [LOCK privilege rules](https://www.postgresql.org/docs/17/sql-lock.html)
  explain this distinction. No privilege grant was added to force recovery.
- The successful rollback trace SHA256 is
  `cf71e34e12e6178c8532c30bb63e018e407f2b7dac8b8337ed90c369845eb546`.
  Apply required that exact trace plus unchanged current data/control fingerprints.
  Attribution uses142 surviving exact-owned rows across53 observed transaction
  IDs. The failed run had no contemporaneous top-XID checkpoint; this limitation
  remains explicit. Unattributed telemetry would have prevented cleanup.

## Limits and remaining work

These results run on clean141 plus synthetic bootstrap/roster identities. Original
populated financial history was preserved in verified backups before clean replay;
it is not present in this clean fixture. Representative124-to-current hosted
upgrades, API/body/configuration parity, real Auth/provider/operator journeys,
browser-reload recovery and complete frozen-candidate acceptance remain required.

PostgreSQL sequence counters are neither rolled back nor reset by these tests.
The backup binaries and original checkpoints currently reside in the task cache;
their hashes are retained, but this is not verified external backup delivery.
SQL142 is frozen at SHA256
`75a315d8a41c2c19f62f2fcd4557e27cb7c14e3f9ebe251f57b18e748d7349d7`.
The root runtime manifest binds the exact source, logs and results for this scope.
