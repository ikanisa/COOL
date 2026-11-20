# BuriMunsi cloud data transfer

This directory contains a source-specific, fenced, one-time transfer and its
owned PostgreSQL rehearsals. It imports the selected 29-table business graph;
it does not establish general production readiness or re-create old sessions,
grants, operational jobs or the complete source audit archive.

`source-reader.mjs` reads only the named local source database in a bounded,
repeatable-read transaction. Its command-line output is count-only; its library
result and compiler commands contain private rows and must remain in memory.
`compile.mjs` binds the graph with a custody-key HMAC, validates source/target
catalogues, identity collision checks, financial/SMS links and destination
ciphertext object proofs, and constructs parameterized inserts. The former
owner remains an inert historical actor; the original native Admin account ID
is rebound to the existing verified Cloud owner. Old PINs, grants and sessions
are retired. Original SMS IDs, owners, object paths and AAD remain unchanged.

`managed-preflight.mjs` performs read-only checks on the fenced source and the
exact pinned Supabase project. `managed-import.mjs --apply` is the explicit,
one-shot transaction executor for this cutover. It requires independently
fenced writers and zero effective unretired admissions, exact Cloud TLS/owner
identity, a verified 48-object destination proof, and acceptable parameter
logging. It preserves disjoint Cloud Storage journals already recorded as
committed after validating their relationships and exact postimages; it locks
and verifies the Cloud Storage namespace. It installs the lineage/receipt and
retention catalog, imports the graph, forces deferred checks, installs the
pinned historical replay guard and authorized history reader, verifies graph
and actor postimages, records the exact migration, and restores all temporary
owner policies and the original fence guard before commit. It recaptures the
source and rechecks object-proof HMACs before committing.

The original attempt's key, intent and rolled-back result remain preserved.
Attempt 002 uses separate exclusive private custody-key, intent and result
files. It first proves the prior transaction rolled back by checking its HMACs,
receipt-table absence and migration-history absence. A committed receipt is
stored in `private.collect_migration_import_receipts` in the same transaction.
If the COMMIT acknowledgement or receipt readback is uncertain, do not retry;
reconcile the target receipt and migration history first. Back up the separate
lineage custody key under independently protected recovery custody. A rollback
or successful receipt does not establish app, API, encryption-key, device or
release acceptance.

`rehearseMaintenance` remains fixture-only. The separate managed entry points in
`maintenance.mjs` verify the exact target peer and exclusive fenced maintenance
frame. The narrowly scoped initial-account helper is a separate transaction;
it requires an independently prepared, pinned bootstrap SQL input and does not
revive old device grants or sessions.

Checks:

```
node --test --test-concurrency=1 \
  scripts/supabase/cloud-data-transfer/compile.test.mjs \
  scripts/supabase/cloud-data-transfer/existing-storage.test.mjs \
  scripts/supabase/cloud-data-transfer/lineage.test.mjs \
  scripts/supabase/cloud-data-transfer/maintenance.test.mjs \
  scripts/supabase/cloud-data-transfer/graph-rehearsal.test.mjs
node scripts/supabase/cloud-data-transfer/managed-chain-graph.test.mjs --managed-lifecycle --text-subjects
node scripts/supabase/cloud-data-transfer/bootstrap-maintenance.test.mjs
```

The rehearsals use owned, socket-only temporary PostgreSQL 17 clusters. Source
rows are held only in memory or the protected temporary fixture, which is
removed after confirmed shutdown. The managed-chain test uses the full managed
migration lineage with a synthetic Cloud owner and synthetic object ETags. The
independent encrypted full-source capture must retain operational, admission,
legacy audit and delegation records excluded from the active graph. Source data
key compatibility, archive recovery, and authorized device/API end-to-end
behavior require their own verification.
