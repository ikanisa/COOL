# Count-only source financial inventory

This read-only PostgreSQL 17 query reports selected relationships among Collect
payments, evidence, MoMo transactions, SMS sources, ledger entries, posting
snapshots and Storage metadata. It returns aggregate counts only: no names,
phone numbers, record IDs, object keys, ciphertext, key labels or row bodies.
It does not import, merge, repair, authorize a write or compare with the cloud.

The SQL starts one `REPEATABLE READ READ ONLY` transaction with a 15-second
statement timeout, returns one JSON result, then rolls back. It refuses missing,
inherited or nonordinary required tables, missing SELECT privileges and active
row-security filtering instead of silently treating hidden rows as zero. Its
normal read locks can briefly delay conflicting DDL. The caller must select the
intended source connection and verify its identity independently; the SQL does
not authenticate a database, bind a deployment profile, freeze writers, or
exclude privileged concurrent DDL. A result with an open fence describes only
that point in time. Do not put credentials in command arguments or output logs.

For local execution use a separately verified, authorized source connection and
run `psql -X -v ON_ERROR_STOP=1 -f inventory.sql` through a secure credential
channel. The SQL requires current source tables including the native receipt
origin; it is not a portable schema migration and may refuse an older target.

The report distinguishes a nullable payment intent from a missing non-null
intent, and counts contribution entries separately from reversals. The
`coverage` counts identify records not connected by the selected relationships;
they may be legitimate unprocessed or retained records and are not automatic
errors or permission to delete them. Counts of missing or mismatched
relationships are investigative signals, not proof of a financial loss. The
object checks compare application **plaintext** digests to plaintext digests in
metadata/reservations and check the current namespace and AAD. They do not
compare those digests with the distinct ciphertext digest, read object bodies,
or prove decryption and key custody.

The visibility check is not a full catalog, trigger, role-graph, uniqueness,
business-invariant, provider, device-queue or dependency audit. It does not
establish that the selected source and cloud snapshots are simultaneous, that
principal records represent the same person, or that any unfinished/unknown
effect is safe to retry. Its `write_authorized`, `target_compared`,
`object_bytes_verified`, `key_compatibility_verified` and
`complete_dependency_graph_verified` fields are always false.

Run the synthetic PostgreSQL tests from the repository root, with the physical
PostgreSQL 17 binaries and pinned `pg` dependency already installed:

```sh
COLLECT_SYNTHETIC_PG_BIN=/absolute/physical/postgresql-17/bin \
  node --test --test-concurrency=1 \
  scripts/supabase/current-pg-transfer/financial-inventory/inventory.test.mjs
```

The tests use an owned socket-only fixture with invented data and incomplete
tables, check counterexamples and visibility refusals, and confirm cleanup.
They are not a production reconciliation or end-to-end migration test.
