# Complete native encrypted recovery — staged contract

This slice supplies native maintenance APIs, complete raw ciphertext preservation,
and same-key inactive validation. It grants no delivery, backend acknowledgement,
signing authority or permission to activate a restored target.

## Actual callers

`GatewayEncryptedStore.exportRecovery(destination, cancelled)` acquires
`GatewayCycleGate`, then `GatewayJournal.PROCESS_LOCK`. Every current store writer
and callback reader shares the process lock. A busy cycle refuses immediately.
Raw source files are never opened through `AtomicFile.openRead`; source .bin,
.bak and .new bytes therefore remain unchanged.

`GatewayEncryptedStore.restoreRecovery(archive, trustedManifestSha256,
freshDestination, cancelled)` restores into a fresh private target, outside the
active installation. It first fsyncs an inactive marker, preserves an exact
`original/` copy, and validates a separate inactive `view/`. A final RESULT.json
is published only after validation completes. Its `key_validated` field is false
for an unavailable Android storage alias: opaque bytes are retained, with no
validated-decryption claim. A wrong key or malformed evidence fails, leaving the
archive and inactive target intact. Incomplete targets must never be merged or
promoted; use a fresh target after investigation.

An internally stored plaintext inactive fence is deny-only. The private recovery
store also has an immutable constructor fence. Journal resume/reservation,
SignedBackend enrollment/configuration/reconcile/mutations, enrollment/identity
writes, Bridge initialization and AndroidRuntime enrollment verification all
refuse restored authority. Historical identity/enrollment remains evidence.
The tools never copy signing private keys, grants, private credentials or permissions;
never clear stop; and never enqueue, replay or send a request. There is no
operator file-picker/MethodChannel export/restore flow in this slice.

## Streaming and closure

Directory inventory pages contain at most eight names. Copy/hash I/O uses 4 KiB
buffers. Each ciphertext part is bounded to 512 KiB + 29 bytes. Manifest NDJSON
lines are bounded to 1024 bytes; paths are flat named files, with leaf symlinks,
traversal and duplicate targets refused. Trusted caller-supplied manifest SHA256
is checked in addition to each part's full SHA256 and size. A second streaming
source pass rejects changes, additions or missing files before the final seal.
Memory is bounded by one reader object/index node and eight inventory entries;
total time and disk scale with retained evidence. The snapshot holds the process
lock across export and can delay callbacks; cancellation is checked between
files/work pages. This is a maintenance operation, not an online incremental
snapshot. Recovery tooling requires API26 for streaming directory access.

Validation preserves raw originals before normalizing committed backups in the
view. It validates original stop/control before establishing another durable
stop, then uses actual source-bound migration, hot-original repair, cold terminal
publication and late readers. It checks all indexed roots/nodes/leaves and full
object hashes; exact original UUIDs/bytes/digests; receipts and callback/protocol
aliases; terminal/cold/observational evidence; late-work/body/receipt links;
legacy catalog references; pending sources and durable reader ceilings. Unknown
object families, malformed identities and missing referenced files fail closed.
Uncommitted .new bytes are retained as raw crash evidence and never interpreted
as committed authority. V1 observations never prune a hot original. A newly
bound late V2 request requires its own exact receipt before becoming handled.

## Key and activation limits

Production validation reads the existing nonexportable AES key from Android
Keystore alias `collect.gateway.storage.v1`; it never generates or imports a
replacement. AES-GCM retains each original filename's AAD. Matching signing
identity does not prove storage-key compatibility. Test-only crypto seams use
synthetic keys and do not establish device behavior or portable recovery.

A new device cannot decrypt this archive through these APIs. New enrollment,
credential revocation/rotation, read-only backend reconciliation and any approved
portable-key design are separate work. Source and original targets remain intact
for that investigation. JobScheduler extras, permissions, SIM selection, app
configuration and non-journal preferences are outside this journal snapshot.
No ready-for-live, delivery, RPO/RTO or physical power-loss claim follows from
local encryption/filesystem proofs.
