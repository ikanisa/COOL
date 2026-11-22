# Native integration boundaries and remaining work

## Intake and evidence

Decode live broadcasts with the application's existing Android adapter. Validate a coherent text PDU set before setting `envelopeValidated=true`; the common module does not decode bytes or prove that a supplied decoded body belongs to those bytes. Supply each original PDU as exact hex and the decoded metadata, including subscription, origin, sequence, concatenation reference/width, declared coding and service-centre timestamp. The synthetic policy fixtures use `00` as an opaque PDU marker behind an explicitly supplied validation decision. That marker is not a real SMS and is not evidence of Android decoder interoperability.

Construct `SmsInput`, call `MultipartPolicy.inspect`, and run the application's classifier. No Unicode normalization, trimming of the original body, fragment repair or insertion of missing fields is permitted. BuriMunsi requires `PDU_SET`; M-Money may screen `PROVIDER_BODY_ONLY` under its separate consented import contract. Neither source mode proves sender authenticity or physical-SIM identity.

A reject/hold blocks automatic upload and financial interpretation. The policy result leaves the supplied evidence available to its caller; it does **not** authorize indiscriminate persistence of OTPs or unrelated SMS. Preserve existing privacy admission and consent rules, avoid logging message bodies, and use only approved protected retention for evidence already legitimately admitted. Do not add a cloud fallback for classification failures.

Apply `DuplicatePolicy` within the same native transaction as original insertion, including durable duplicate/tombstone indexes. Same capture ID with different evidence is a conflict, not an overwrite. M-Money's same-source/exact-body case preserves the first original and separately retains any permitted repeat-observation evidence. Queue-full and reserve decisions must not advance an inbox checkpoint past uncaptured supported evidence. This delivery does not implement that Android checkpoint transaction.

## Original requests and durable identity

BuriMunsi uses a single-item `UploadBatch` whose operation ID is the original capture ID. M-Money freezes one to twenty originals under its existing batch operation ID. All items in this policy batch must share owner scope and binding; split different bindings **before** claiming any operation. Never split, reorder or replace a claimed batch to work around a timeout or a rejected acknowledgement.

`UploadBatch.payloadHash` fingerprints the frozen internal evidence; it is not a server-returned digest or proof that an arbitrary JSON serializer produced identical wire bytes. A native transport must serialize the same frozen request values and reuse the same operation ID on every retry. Keep M-Money's initial received-time/provider metadata frozen in its existing original rows; never use retry time as receipt time. The pure models do not replace those database rows.

A production `QueueStorePort` must provide atomic, durable `createIfUnbound` and revision-based `compareAndSet`. The transaction must cover original evidence, owner/generation, immutable batch, attempt counters, acknowledged outcomes and original-to-batch uniqueness indexes. Indexes must include terminal tombstones so an exhausted or acknowledged original cannot be silently assigned a new operation.

`COMMITTED` means the adapter has established its required durable boundary. `UNKNOWN` means persistence may or may not have occurred. Do not map an uncertain fsync/transaction result to `NOT_COMMITTED`, and never turn an uncertain write into permission to send. Recover by reading retained state. There is no reset/delete/recreate-corruption method on this port.

A native deserializer must reconstruct and validate the complete `QueueSnapshot`, including immutable originals and receipts, before returning `StoreRead.Present`. Unsupported storage versions, missing fields and broken invariants must return `Corrupt` or `Unavailable`, not an empty queue. A schema codec/migration and real durable port are remaining integration tasks, not supplied production implementations.

## Dispatch, stop and restart

Only dispatch `UploadOriginal` returned after a committed reservation. Before actual network I/O, re-read current state and use `DispatchPolicy.permitted` under the application's lifecycle/binding gate. The adapter must coordinate capture, pause, deletion, replacement and authority changes with that gate. Never retain bearer credentials in the policy objects or reports.

Use a positive, monotonically increasing local `sessionEpoch` for credential changes. Owner, installation, generation, binding ID/version and subscription are independently checked. A new epoch does not rebind old-owner evidence. A response from an old epoch or previous attempt cannot retire the current queue state.

A CAS winner prevents duplicate **reservation effects** in the host tests; it is not a claim that the network has exactly-once delivery. An effect may be lost after commit, and a remote service may commit while its response is lost. Restore/retry conservatively retains the original identity and requires server idempotency. The pure machine never creates a payment operation.

Call `Restore` for an interrupted worker only after the prior worker is known to be gone or stopped. Do not use it to bypass a live in-flight lease or create concurrent network sends. No new attempt is allowed from an exhausted/conflict state. An authorization hold can resume only with a newer local epoch; the original attempt count and request remain unchanged.

The clock is injected. Use a consistently defined, nonnegative, persistent time domain across snapshots. Wall-clock rollback blocks transitions, and a monotonic clock that resets after reboot needs an explicit, reviewed epoch mapping before reuse. Do not reset retry counters or time origins to conceal an inconsistent clock. Native clock persistence/reboot handling remains an acceptance item.

## Acknowledgements

Parse JSON without string/Boolean/number coercion or duplicate-key ambiguity. The module accepts already decoded maps; it does not validate the original JSON token stream or detect keys a permissive parser discarded. Pass integer contract versions as exact `Int` values. A positive HTTP status alone is not a durable acknowledgement.

Collect v2 requires exact owner and capture identity, version 2, Boolean `ok` and `stored`, a retained raw-SMS ID, and the SHA-256 of the exact original UTF-8 body. This is acknowledgement of raw custody, not member credit or payment posting.

M-Money v1 requires the complete expected acknowledgement set under schema version 1. Every submitted ID must appear exactly once; accepted/duplicate rows require a canonical UUID, and rejected rows require null canonical identity plus a bounded rejection code. No item is committed locally until the **entire** batch validates. Its wire response has no owner, generation or body hash: correlation relies on the frozen request, authenticated transport and local scope/session/attempt checks, not fabricated response fields.

A valid response first produces `ACK_PENDING`; native persistence must succeed before finalization. Finalization preserves original evidence and the acknowledgement. A mixed M-Money batch ends in `REJECTED` at batch level while retaining each accepted/rejected outcome; do not display the entire batch as accepted. Matching acknowledgement replay is a no-op. A different valid receipt for the same attempt is a retained conflict, not last-response-wins.

## Required follow-through

1. Reconcile this additive source against the chosen consolidated A03/A04 candidates. A baseline hash refusal requires review, not a force flag.
2. Implement production snapshot serialization/migration, durable port, atomic duplicate/batch indexes and inbox checkpoint integration. Wire the existing workers to the machine and transport fence without changing privacy admission or financial authority.
3. Compile both native variants with the pinned toolchain, then run Android JSON, lifecycle, Room/file/Keystore and WorkManager instrumentation. Test missing permissions, SIM changes, reboot/unlock, reinstall/replacement and stopped workers.
4. Prove ingestion idempotency and raw-custody acknowledgements against the actual services/database. Keep financial posting reconciliation separate.
5. Execute approved physical carrier scenarios and private consented PDU observations. No synthetic fixture pass closes this gate.

No hosted configuration, database, physical device or user's actual checkout was changed during this source-only delivery.
