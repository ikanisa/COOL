# Managed Storage recovery readers

These modules keep Collect's two Storage recovery formats readable from a recovered checkout. They contain no credentials, actual metadata rows, object bodies, keys, local account paths or Root credential wrappers. Importing the modules does not dispatch requests or create files. They reuse the repository's current-archive helpers and native Storage transport without modifying them.

The qualified private predecessor captured eight metadata tables with 80 rows, then restored all cells and one enum into an owned local PG17 inert database. Its separate object-byte archive captured five objects totaling 618 bytes, checked metadata and versions before and after the reads, authenticated its encrypted readback, and restored byte-exact anonymous files offline. Those results belong to the private predecessor. They do not establish execution or adoption of this portable copy. The source pins and precise normalization are recorded in `NORMALIZED-DELTA.json`.

`storage.mjs` validates, encrypts and reads the metadata format, compiles its bounded read-only capture, and restores data into newly created `archive_data` and `archive_types` schemas. It does not recreate an operational Supabase Storage service, activate bucket permissions, replay generated expressions, restore signed URLs or upload object bodies. `counts.mjs` supplies the fixed catalogue/count preflight; `REFERENCE.json` is public schema metadata, not a backup of actual rows.

`objects.mjs` authenticates the separate object-byte format and materializes original opaque bytes as `001.opaque` through `005.opaque` with a private hash manifest. The capture interface remains restricted to the reviewed Collect project, private bucket, exactly five object bindings and 618 declared bytes. Each actual body receives an independent digest. This is intentionally a bounded recovery reader for that format and scope; changing the object population requires another reviewed implementation and fresh evidence.

For offline recovery, supply separately held ciphertext, its independently recorded archive hash and the matching key through the exported interfaces:

```js
import {readStorageMetadataBundle} from './storage.mjs';
import {restoreObjectsOffline} from './objects.mjs';

// All paths below come from the operator's private recovery inventory.
const metadata = await readStorageMetadataBundle({
  archivePath: metadataArchivePath,
  keyPath: metadataKeyPath,
  expectedArchiveSha256: metadataArchiveHash,
});
const objects = await restoreObjectsOffline({
  archivePath: objectArchivePath,
  keyPath: objectKeyPath,
  expectedArchiveSha256: objectArchiveHash,
  restoreDirectory: freshOfflineDirectory,
});
```

Keep returned metadata, decrypted payloads and keys private; do not print them. `restoreStorageMetadataInert` separately requires a reviewed `makeClient` factory and an owned loopback PG17 admin URL. Its caller must keep the PostgreSQL data directory and connection material outside the checkout, control logging, stop the owned server and verify closure. The helper receives no PostgreSQL filesystem path and cannot establish those custody conditions itself.

All archive, key and offline materialization outputs must remain outside the module-derived **whole checkout**, and outside any ancestor containing it. Each supplied output is checked before directory creation or transport dispatch. Object restore checks its output before opening ciphertext or keys. Physical private-directory checks still reject symlink aliases. Output children must be fresh where the interface creates them, with private physical 0700 parents and 0600 files; the direct metadata writer instead requires already-existing private archive and key directories. Keep keys and ciphertext in separate, non-nested directories. Local separation does not establish independent key custody or offsite recovery.

Capture is explicit. Metadata capture requires the reviewed count-proof hash and `executeReviewedReadOnly: true`. Object capture additionally requires the actual decrypted metadata snapshot, its source archive/snapshot hashes, caller-supplied in-memory credentials and reviewed transports. The repository provides no token discovery, login, new keys, grants, rotation, automatic retry or credential-fetch wrapper. Storage body access permits only bounded GET/HEAD through the native probe; it never calls the protocol's conflict-journaling reader. Two bounded read-only Management SQL snapshots reconcile the saved metadata with before/after content identities. `last_accessed_at` is retained separately as read bookkeeping. This comparison does not prove an atomic cross-service snapshot or storage quiescence.

Root runs the focused synthetic suites under the existing supervised, network-denied runtime with a private TMPDIR outside the checkout:

```sh
node --test --test-reporter=tap scripts/supabase/managed-storage-archive/storage.test.mjs scripts/supabase/managed-storage-archive/objects.test.mjs
```

The suites retain the predecessor's 12 metadata and 10 object definitions and add four output-refusal definitions: both metadata writers, object capture and offline object materialization. These check whole-checkout descendants and ancestors, zero transport calls, and no earlier output-directory creation. Expected total: 26 tests. `native-definition.mjs` retains the eight synthetic native cases and the qualified explicit C-collation fixture correction. It launches nothing on import; execution requires the separate reviewed local custody harness. Pure tests and inverse source normalization do not establish a new actual-data recovery run.

Portable-source verification is pending at preparation time. Preserve prior failed and successful evidence under its original pins. This folder does not establish independent key custody, availability of external PostgreSQL packages, full provider configuration/secrets recovery, operational restoration, disaster recovery, RPO/RTO or release acceptance. UI work, when relevant, follows Revolut Design from Jean Bosco Skills; these recovery scripts introduce no UI.
