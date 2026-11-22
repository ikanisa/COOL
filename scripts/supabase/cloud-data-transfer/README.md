# BuriMunsi Cloud graph verification

This directory contains graph compilation, lineage verification, protected Storage
journal checks and isolated PostgreSQL rehearsals for the selected Collect Cloud
project. The managed migration history contains the recorded cutover SQL and
remains the source for historical database replay.

The compiler binds the graph with a custody-key HMAC, validates relation
catalogues, identity collisions, financial and SMS links and destination object
proofs, and constructs parameterized inserts. The former owner remains an inert
historical actor. The original native Admin account maps to the verified Cloud
owner. The compiler retires historical PINs, grants and sessions while preserving
SMS IDs, object paths and associated data. The review-only compiler returns
private rows in memory and reports a non-authorizing summary.

The managed-chain rehearsal uses synthetic rows and an owned, socket-only
PostgreSQL 17 cluster. It checks the managed migration chain, the fenced import
transaction, lineage and actor postimages, history guards, temporary policy
restoration and managed retention controls. Finance and SMS graph behavior also
has synthetic compiler and lineage tests.

```sh
node --test --test-concurrency=1 \
  scripts/supabase/cloud-data-transfer/compile.test.mjs \
  scripts/supabase/cloud-data-transfer/existing-storage.test.mjs \
  scripts/supabase/cloud-data-transfer/lineage.test.mjs \
  scripts/supabase/cloud-data-transfer/recovery-capsule.test.mjs
node scripts/supabase/cloud-data-transfer/managed-chain-graph.test.mjs --managed-lifecycle --text-subjects
```
