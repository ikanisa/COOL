# Upgrade telemetry trace and exact disposition — source only

The original140→141 upgrade passed its session assertions but left ten realtime invalidation rows. The recorded pre141 baseline contains560 telemetry rows;123 other domain-table fingerprints and the financial snapshot were unchanged. This document does not replace or alter that failed preservation result.

**Worker execution:** nine offline helper guard tests pass; Python compilation passes. No database, provider or real dump-decoder calls were made by the worker. SQL and actual dump parsing remain root-owned and unexecuted for these new sources.

## Current141 fixture: trace first, never replay seed/verify

`scripts/tests/notification_upgrade_telemetry.py` is restricted to the existing dedicated local Docker project/port, exact141 registry, disabled cron/pg_net, removed9972 graph, empty push queue and no other active client transaction. It uses these preserved inputs:

- `.cache/notification-sessions-20260930/pre141.dump`
- `docs/release/notification-session-fencing-2026-09-30/pre141-domain-fingerprints.json`

Root invocation from repository root:

```sh
python3 scripts/tests/notification_upgrade_telemetry.py trace \
  --output .cache/notification-sessions-20260930/telemetry-trace-01.json
```

Trace mode runs `pg_restore` **only as an offline decoder to stdout**, selecting one table and supplying no database connection option. It parses the exact COPY shape and refuses duplicate/unknown rows. Its PostgreSQL transaction is explicitly read-only. PostgreSQL canonicalizes the exported rows and must reproduce the saved560-row hash; every old row must still match exactly, and the123 non-telemetry fingerprints and124-table catalog must match. The output lists the added events with IDs, content, xmin groups and timestamps. It cannot delete anything.

The original run did not record transaction IDs. The helper therefore labels retrospective attribution **unproven**. Counts, timestamps and areas are a consistency check, not fabricated historical evidence. Root must review the isolated runner/logs and explicitly attribute the observed phase XIDs before any disposition. If that attribution cannot be established, retain the telemetry and the failed baseline result; do not guess XIDs or delete unknown events.

## Optional reviewed disposition

Only after root reviews the trace, invoke `apply` with the **exact file SHA-256 printed by trace** and the three attributed observed XIDs:

```sh
COLLECT_NOTIFICATION_TELEMETRY_QA=reviewed_isolated_trace \
python3 scripts/tests/notification_upgrade_telemetry.py apply \
  --trace .cache/notification-sessions-20260930/telemetry-trace-01.json \
  --trace-sha256 <EXACT_REVIEWED_FILE_SHA256> \
  --seed-xid <ATTRIBUTED_SEED_XID> \
  --migration-xid <ATTRIBUTED_MIGRATION_XID> \
  --verify-xid <ATTRIBUTED_VERIFY_XID> \
  --output .cache/notification-sessions-20260930/telemetry-disposition-01.json
```

Angle-bracket values are operator inputs, not runnable guessed defaults. Apply refuses changed trace/backup/baseline bytes, any intervening domain change, any changed/deleted baseline event, unknown event areas/XIDs, unexpected triggers/references, or anything outside the reviewed phase pattern:

| Phase | Rows | Areas |
| --- | ---: | --- |
| Seed | 5 | 1 profiles +4 notifications |
| Migration | 2 | 2 notifications |
| Verify/graph removal | 3 | 1 profiles +2 notifications |

In one owner transaction it takes the141 gate and locks the telemetry table. It deletes exactly ten approved rows matching **ID + complete row JSON + xmin**. Before commit, all124 fingerprints must equal the original pre141 baseline, including all560 old telemetry rows; otherwise deletion rolls back. It then verifies again after commit and records the exact removed rows and root-attributed XIDs separately from original evidence. No migration, financial row, role, trigger or grant is changed.

Keep the fixture free of other actors. If response/output capture fails after commit, inspect state before retrying; the helper intentionally refuses an already-changed trace.

## Future fresh upgrade runs

Updated `notification_session_upgrade_seed.sql` captures its transaction ID, exact pre-seed telemetry rows and exact seed telemetry IDs in the synthetic QA record. It prints a `NOTIFICATION_SESSION_UPGRADE_TRACE:` JSON line.

Updated `notification_session_upgrade_verify.sql` captures the141 migration XID directly from the still-existing synthetic device and matching delivery tuple **before removing them**, and captures its own verification XID. It refuses unknown added events, checks the exact5/2/3 pattern, prints the exact telemetry disposition, removes only the three attributed transactions' new rows and proves exact pre-seed telemetry equality before commit. Session assertions, in-app-content preservation and guarded member cleanup remain in place.

These updated fixtures are for a **new, backed-up140→141 exercise only**. The current141 graph has already been removed; do not rerun them blindly. Future runners must retain the new trace lines and look for the PASS marker rather than require stdout to equal one old line. Earlier source hashes and SQL results remain dated evidence; these new fixture versions are not yet SQL-validated.

`telemetry-source-validation.json` lists current source hashes, offline command results and logs. No whole production acceptance ID is closed.
