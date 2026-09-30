# Recovery of the first roster concurrency fixture

Source preparation only, 30 September 2026. No database calls were made by the author. Migration142 remains frozen.

The first run’s baseline cleanup rolled back. Preserve its full backup, stdout/stderr and source; never rerun the seeding harness against the retained9954 graph.

## Root invocation

```sh
COLLECT_ROSTER_RECOVERY_QA=failed_9954_run ruby scripts/tests/roster_import_provenance_recovery_uat.rb --trace /absolute/new/recovery142-trace.json
```

Review the complete rollback rehearsal and compute its SHA-256. Apply only that exact successful trace:

```sh
COLLECT_ROSTER_RECOVERY_QA=failed_9954_run ruby scripts/tests/roster_import_provenance_recovery_uat.rb --apply /absolute/new/recovery142-trace.json TRACE_SHA256
```

Both phases require the exact task container/project labels/host55722, migration142, cron off, network batch zero, no notification token/delivery queues, two9954 actors, eight source receipts, five commits and no concurrent workers. Backup SHA256 is pinned to `500e66e7de0c0720aa8107b41b9c95444676411cf5fe2fe2711f667439732ed2`.

The archive decoder does not restore SQL. Only strictly parsed COPY blocks from selected schemas are loaded into temporary baseline tables; all other dump commands are discarded. The table catalog must match all131 backup tables. Successful generated values are rebuilt by temporary tables’ existing generated-column expressions. Root should retain any archive parsing failure and request correction rather than broaden parsing indiscriminately.

Every deleted realtime event is bound to an observed XID from exact synthetic owned rows. The script refuses unmatched telemetry, unknown incoming references, unexpected immutable triggers, changed data/controls since rehearsal, or any incomplete full-baseline restoration. Only the five named provenance guards are disabled and re-enabled inside the cleanup transaction. No financial guard is changed. The original rows are preserved, and sequence counters are not restored.

The control comparison proves before/after recovery stability; no original first-run control digest was persisted by the failed harness. The immutable first-run source and migration hashes plus root’s retained backup remain separate evidence.

## Decoder receipt fixture

`scripts/tests/roster_import_provenance_receipts_uat.sql` emits two `ROSTER_RECEIPT_JSON|` envelopes with actual SQL-issued source, initial-preview, human-review, commit, replay and post-commit read receipts. Each includes exact synthetic browser/review/commit requests for cross-layer binding. It is rollback-only and uses separate unused9965 identities. The AI candidate is a controlled fixture over a synthetic solid PNG; no provider extraction is asserted. Run only after the9954 recovery and with `PGOPTIONS=-c collect.roster_provenance_qa=isolated_clone`.
