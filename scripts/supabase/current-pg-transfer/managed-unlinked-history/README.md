# Managed unlinked SMS history: qualified parts and remaining work

The production migration is **not implemented or released** by this directory.
`managedTransfer()` always returns `managed_transfer_unqualified` without
calling any adapter. There is no managed database connection, Storage client,
credential reader, active-job writer, financial writer, production scheduler
control or cutover command here. Do not treat an offline witness as permission
to alter Supabase. The user-selected existing cloud account remains primary;
the exact four source/target Auth and application IDs are not established by
this code, by an email match, or by the aggregate source counts.

## Findings from the actual source

The retained receipt in the 14 November assessment observed 33 local SMS
receipt paths, including 10 with and 23 without financial links. The 23
unlinked had 22 `not_applicable` and one `unallocated` allocation state;
three associated jobs had SQL-NULL posting facts. The observation was
unfenced and covered selected columns only. It is not proof of current source
contents, source identity across snapshots, complete provenance or object
custody.

The actual `burimunsi_native_receipt_origins` row has foreign keys to an
unresolved observation, a collection scope, original application principal,
native account, device grant, capture/admitting sessions and the SMS receipt.
The receipt/origin invariant is deferred to commit and also requires a matching
native job, original owner, request, object digest and object key. Requests and
unresolved observations have their own account, scope, device, session and
request bindings and immutable/fenced triggers. Transaction scopes bind the
native origin and receiving account. Other tables, including financial-work,
lease and discovery history, may reference the same origin. A real graph and
its dependency order must be established from the exact deployed catalogue and
a fresh source snapshot, including all foreign keys, trigger functions and
role/policy behavior. The simplified quarantine fixture is not that catalogue.

`private.burimunsi_native_sms_post_candidates` can select completed, accepted,
unlinked jobs with incoming, outgoing or unknown transaction events, including
SQL-NULL posting facts; after re-parsing, further processing can reach payment
and ledger operations. The owned PostgreSQL test in this directory executes the
actual selector function body extracted from the pinned migration, with
invented rows and a stubbed jobs-admission guard. It verifies eligibility
conditions, not the live guard, scheduling state or provider behavior. Copying
historical rows into active job tables before effective writer and worker
exclusion would risk new work and is explicitly unsupported.

An observation source UUID is derived from the original principal and request
UUID. Replacing the original principal with the cloud principal while keeping
the old source ID changes that derivation and can invalidate native retries.
The original source/request/principal relation therefore needs a documented
historical-provenance and replay design. A new ID requires cascading analysis
of foreign keys, keys, body/object references, request fingerprints and AAD;
retaining an old historical principal must not silently create a new active
identity or credential. This component does neither.

The application's ciphertext is JSON containing AES-256-GCM version, key ID,
nonce and authenticated encrypted bytes. SMS AAD is
`sms:<source-id>:<plaintext-object-sha256>`. The original owner is separately
bound into the protected-storage reservation and put metadata/fingerprints.
Thus equal AAD alone does not prove that a changed owner scope is safe. Source
and target key identifiers do not prove equal key material. The current
managed project, actual key registry, provider object bytes, object metadata,
delete intents and source authority have not been examined by this code.

## Offline encrypted witness component

`retainOfflineWitness` is a deliberately bounded building block for a future
trusted supervisor. It receives, in memory, a canonical independently pinned
plan, the original application ciphertext, the source and target candidate
32-byte decryption keys, and a separate 32-byte witness-custody key. It reads
no credentials or environment variables. It checks:

- The original principal/request/source-ID derivation and represented original
  owner scope, SMS key, AAD, request fingerprint, reservation fingerprint,
  committed put fingerprint and matching object-metadata snapshot.
- The ciphertext length and SHA-256, application document format and key ID,
  AES-GCM authentication under both supplied keys, plaintext object hash,
  length and native SMS body hash. The supplied target key ID must match the
  ciphertext key ID. It reports whether the selected target owner derives the
  same source ID, without deciding what that means for migration authority.
- Native payload structure sufficient for the selected worker's source checks.
  A conservative unsupported shape is refused. This verifies supplied bytes
  and supplied metadata relationships only; no supplied key, ID, metadata or
  digest is independently established as belonging to a live project.

For one operation UUID in an existing physical, user-owned 0700 directory, the
component exclusively creates a private subdirectory and fsyncs it. Its intent,
original ciphertext plus validation result, and receipt are separately
AES-256-GCM encrypted with fresh nonces and operation/record-bound AAD. It
writes no plaintext SMS or encryption keys to disk. It authenticates the local
readback before reporting success. `reconcileOfflineWitness` authenticates the
stored plan, artifact and receipt and checks their binding; it performs no
write, no decryption-key recheck and no provider lookup. A pre-existing
operation ID returns `reconciliation_required`. An incomplete or ambiguous
claim/receipt returns `custody_unconfirmed_do_not_retry`; it does not authorize
a new attempt. This one-use guard is local to one directory and operation ID;
it is not a global per-SMS claim, a cross-system transaction or a production
dispatch journal. Deleting or replacing that directory defeats its memory.

The witness key must be retained in separately protected custody. The caller
must keep plan, buffers and keys out of logs, arguments, environment, swap and
crash dumps as appropriate. The code clears its own mutable key/plaintext
buffers where practical; JavaScript strings and runtime copies cannot be
reliably erased. A trusted same-user host, Node runtime, OS, loader, filesystem
and caller are assumed; file hash/mode checks do not defeat a malicious
same-user replacement or a compromised host. This code has not been
independently qualified for real sensitive inputs and is not a generic secure
vault or a complete encrypted backup.

## Steps still needed for a real migration

1. Establish an independently reviewed cloud-primary mapping for the exact
   intended Auth and application accounts; do not infer other users or merge
   accounts by email. Bind it to a fresh source identity and capture.
2. Qualify the exact managed migration chain, catalogue, privileges,
   triggers, RLS, deferred invariants, source and target backups and recovery.
   Prove exclusion or safe drainage of source/target writes, schedulers, mobile
   queues, workers and already admitted actors. Preserve uncertainty about any
   earlier external action rather than treating a missing receipt as absence.
3. Capture and reconcile the complete real observation, request, receipt,
   transaction, parse history, job, scope, account, grant, session, consent,
   lease and related graph under effective controls. Design what historical
   principals, revoked credentials and source IDs mean without enabling replay.
4. Qualify a managed Storage adapter and trusted private credential supervisor.
   Verify actual object bytes and version/metadata, original reservation/put/
   object state and delete-intent absence; independently verify which target
   decryption keys are configured and protect key/AAD compatibility. Resolve
   owner-scope and fingerprint transformations against actual application
   behavior. The existing object-transfer coordinator still refuses managed
   dispatch and its synthetic behavior is not proof of provider semantics.
5. Implement an independently reviewed durable per-source one-use claim and
   pre-dispatch journal for each external effect, conditional/create-only
   provider operations, explicit lost-ack/late-completion handling and
   reconciliation across database, Storage and workers. An absent readback does
   not prove a timed-out operation can no longer commit. The local witness
   journal in this directory covers no external operation.
6. Implement a real, non-replaying import/reconciliation path for the exact
   deployed schema, keep the existing financial safeguards, and prove final
   row/object/identity consistency under exclusion before any production
   release. Mobile and integration tests must exercise the final deployed
   behavior. No staging project is required by these steps.

## Synthetic verification

From the physical checkout:

```sh
env -i PATH=/usr/bin:/bin LANG=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/current-pg-transfer/managed-unlinked-history/*.test.mjs
```

Tests use invented secrets, data and private temporary directories; the
PostgreSQL test creates and removes an owned socket-only PG17 cluster. They
exercise actual application encryption compatibility, wrong keys, owner/AAD
and metadata mismatch, encrypted custody, one-use and lost-ack reconciliation,
tampering, real selector semantics and UUID derivation. They do not contact
any provider or existing database. The manifest is for reproducibility and
independent review; it does not attest the host or authorize production use.
