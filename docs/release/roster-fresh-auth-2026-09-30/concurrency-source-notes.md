# Migration 149 concurrency source handover

Status: **SOURCE ONLY; no database execution or concurrency PASS claim.**

Runner: `scripts/tests/roster_fresh_auth_concurrency_uat.rb`.

Root exclusively executes it against the exact quiet ordinary-owner fixture
`collect_fin_concurrency_qa_20260929`, installed149/latest20260930170000,
provider transports disabled and unused9988 namespace. It requires
`COLLECT_ROSTER_PROVENANCE_QA=isolated_clone`, a new absolute
`COLLECT_ROSTER_CHECKPOINT` path, and the root-reviewed current migration hash
in `COLLECT_ROSTER_FRESH_AUTH_MIGRATION_SHA`. Use UTF8 Ruby execution.

## Implemented scenario source

- Exact concurrent transfer replay, distinct request denial and read-only lost-response status.
- Both winner directions: checkpoint/review/stage/execute/commit against transfer.
- Actual old Auth-session deletion followed by fresh transfer, review and explicit commit.
- Pre-established Repeatable Read snapshots against current-session, approval,
  role and both required permission revocations; only40001/42501 accepted.
- Overlapping feature revocation and source TTL crossing while blocked.
- A to B to C lineage and8 handoffs;19 human reviews and40 intents across branches.
- Pre-established Repeatable Read distinct-import actor-draft ceiling40 and
  distinct-request source ceiling100, requiring40001 rather than stale success.

All-table fingerprints dynamically include the listed application/Auth/migration
schemas and cron job/history tables. Catalog fingerprints bind routines, ACL/RLS,
constraints, columns, policies, triggers and cron configuration. Cleanup derives
owned import IDs from namespace upload roots plus immutable transfer edges,
then resource, committed group and member IDs. It refuses unattributed owned
rows and unknown foreign-key references before temporarily disabling only the
10 named immutable DELETE guards. Full baseline/control equality is checked
before cleanup commit and again afterward. Only observed top-level/owned-row
child transaction IDs and cleanup transaction telemetry are removed.
Sequence counters are deliberately not reset; that limitation is reported.

## Remaining root review / limitations

Ruby syntax is the only verification performed by the source author. SQL/runtime
compatibility, decoder fixture receipt keys, actual lock waits, quota setup,
restoration behavior and current migration receipt contract remain unverified.
The migration was still being edited when this source was handed over.

Current source does not yet implement both winner directions for authority and
feature revocation, provider preview/failure/source completion versus transfer,
or JWT-expiry overlapping transfer. Those remain explicit missing scenarios,
not covered by the eventual PASS of the currently listed scenarios.

The short-TTL fixture and quota-fill awaiting sources are owner-only seed INSERTs
through enabled descendant guards; they do not pretend to be service/provider
upload acceptance. Root must preserve a backup and this source before execution.
