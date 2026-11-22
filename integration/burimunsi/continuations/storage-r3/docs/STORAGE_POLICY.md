# Storage lifecycle and retained-evidence contract

## Scope

This delivery implements deterministic Kotlin/JVM policy, host filesystem checks, a BuriMunsi operation-store coordinator, and targeted source changes in the two supplied applications. M-Money and BuriMunsi keep separate identities, storage formats and application contracts. Sharing a policy package does not merge their APIs or financial authority.

The generic `StorageLifecyclePolicy` is a pure reducer. Returned states are **proposed durable states**, not evidence that a disk write happened. The host tests execute that reducer and simulate interruption around each persisted-state boundary. They do not establish Android filesystem, Room, SQLCipher, Keystore, multiprocess or power-loss durability.

## Record opening and pending writes

`RecordOpeningPolicy` considers the base record, `.bak` and `.new` separately. The observation vocabulary is ABSENT, FILE, EMPTY, UNSAFE and UNREADABLE. Only a positively observed absence of all three is fresh. An unreadable directory, broken symlink, empty file, surviving backup or unfinished write is not absence.

Precedence is unreadable, unsafe, pending write, backup requiring explicit recovery, empty/corrupt, existing record, fresh. A pending or backup record is retained without automatic promotion or deletion. The encrypted adapters no longer call an opening operation that implicitly removes `.new` or restores a backup over the base record. A failed write closes the stream but does not use `failWrite` as an evidence-removal shortcut.

A missing wrapping alias is never recreated over surviving evidence in its key scope. BuriMunsi uses the common `buri-` record scope. M-Money uses its existing separate database and session scopes. Read paths never create keys. This fail-closed behavior trades availability for preservation; a reviewed explicit recovery action is still required for blocked pending/backup records.

`ProtectedFileAccess` uses non-following observations, permits only the known base/backup/pending members for explicit deletion, and verifies absence afterward. It does not recursively erase directories. Its process-local checks do not eliminate filesystem races with another process or prove physical persistence.

## State transitions

| Durable state | Permitted next step | Evidence retained on interruption/failure |
|---|---|---|
| ACTIVE | Begin a new write with its original operation ID and digest; or begin explicitly authorized deletion | Existing artifact inventory and binding |
| WRITE_PENDING | Confirm the same verified write; otherwise remain blocked | Original operation ID, digest, original evidence; no new operation or deletion |
| DELETE_REQUESTED | Persist a validated, owner/generation/revision-bound deletion receipt | Immutable cleanup manifest and original evidence |
| CLEANUP_PENDING | Remove only authorized manifest members, verify each absence, then persist progress | Receipt, manifest and remaining evidence; failure never becomes COMPLETE |
| TOMBSTONED | Remain closed; or begin explicit replacement with a distinct generation | Deletion receipt and tombstone; no automatic fresh ledger |
| REPLACEMENT_PENDING | Confirm creation of the reserved target and its new, disjoint artifact set | Old tombstone/archive proof and the same replacement intent |

Corrupt ACTIVE storage may enter explicit replacement only with a verified archive proof that covers the exact retained artifact inventory. The original product and owner are unchanged, the generation must be new, and newly created artifacts cannot overwrite the retained ones. A tombstoned generation needs no archive because authorized cleanup has already been verified. Archive proof is a trusted adapter input: the reducer does not copy files or cryptographically authenticate arbitrary strings.

### Required durable adapter ordering

1. Serialize the operation and recheck the exact current owner, product, generation and revision.
2. Persist the returned intent or receipt, verify its committed readback, and only then execute the next external effect.
3. Treat a failed or uncertain write as unresolved. Reopen and compare the original identity and digest; never authorize a new operation from uncertainty.
4. Execute cleanup only against the persisted manifest. An unlink return value, free-space estimate or caught exception is not a verified absence.
5. Persist each confirmed absence before claiming completion. Retain the terminal tombstone after final cleanup.
6. On restart, resume the same pending intent; do not infer a new generation from an empty or unreadable path.

These are adapter obligations. The full generic lifecycle snapshot is not newly persisted into either application's Android database in this delivery. A durable schema/codec and crash-qualified adapter for that generic coordinator remain integration work, explicitly separated from the completed reducer.

## Repetition, failure and stale responses

Repeating the same pending write, deletion or replacement request is a no-op. A different ID cannot replace an unresolved operation. A previously used operation ID cannot be reused in the generic lifecycle. Effect tokens bind the operation ID to the product, owner, generation and revision. Every observed failure advances the revision; an earlier successful health probe cannot clear a newer failure.

A repeated cleanup observation is idempotent at the current revision. A late acknowledgement or repeated acknowledgement with an obsolete revision is refused without changing state; the caller rereads the current state instead of replaying effects blindly. Writes are blocked while deletion, cleanup or replacement is pending.

Free space alone does not clear failure. `confirmHealthWrite` requires a verified current recovery write and is limited to recoverable active I/O, storage-full or permission states. It cannot resolve a pending command or a key/corruption problem.

## Corruption classification

`StorageFailureClassifier` traverses a bounded, cycle-safe exception chain using typed exceptions and exact platform class names, not message text. It distinguishes transient I/O, storage full, permissions, unavailable keys, permanent key invalidation, malformed records, authentication failures, unsupported versions and unknown faults. An AES-GCM authentication failure is **not** proof that a key was permanently lost. Neither classification nor a generic exception authorizes deletion or recreation.

The classifier is supplied as reusable policy; Android exception presentation and all platform exception variants are not claimed to be fully wired or device-qualified.

## BuriMunsi integration

`DurableOperationStore` implements actual command-record coordination behind `OperationRecordPort`. Before deleting a resolved active command, it writes and verifies a terminal tombstone containing the original command, body hash, owner scope, attempt count and terminal outcome. Only that persisted proof authorizes active-record removal. After verified absence, it writes and verifies cleanup completion.

`load()` is read-only. Failed reads are not converted to null. A tombstone/active-record identity conflict, resurrected retired command or inconsistent body hash blocks without deleting either record. A failed removal keeps the command's terminal outcome and a pending-cleanup flag. `OperationJournal` treats pending cleanup as a blocker, so a committed operation with incomplete local cleanup does not authorize another financial submission.

`AndroidOperationStore` encodes these records separately in the existing encrypted store. Version 1 is explicit; the former versionless active record has a narrow legacy read path. Integral counters are checked without string/Boolean/fraction coercion. The retained repository checks compile the production coordinator and AndroidOperationStore against explicit Context, JSON, transport and storage doubles, not the Android runtime.

The tombstone slot retains the **latest** terminal command. It remains while a later active command is unresolved and is replaced only when that later command has a verified terminal outcome. It is not an unbounded accounting journal or a substitute for server-side financial records. Tombstones include command content and remain inside the encrypted application storage; this package contains synthetic fixtures, not user command data.

## M-Money integration

`DeletionFinalizer` now rejects conflicting receipt IDs or deletion timestamps, makes repeated identical receipts idempotent, and fences cleanup completion on the installation ID, owner, generation, deletion operation, receipt and timestamp. Receipt persistence failure does not authorize cleanup; cleanup failure leaves the receipt pending. Tests execute the actual production functions with explicitly identified in-memory transaction doubles.

`LedgerReplacement` retains the existing explicit user-choice entry point, rejects reused generation/installation identities and already-admitted replacement identities, and compares the complete prior installation again after cleanup before publishing the replacement. `RecoveryPolicy` uses the shared compatibility guard: COMPLETE without a receipt is insufficient; ordinary pending deletion cannot be bypassed. The pre-existing informed data-loss choice for lost access is not represented as proof that inaccessible cloud data was deleted.

The existing M-Money destructive replacement path is **not** converted into the generic archive-preserving replacement coordinator by this patch. In particular, the host replacement tests prove row/identity retention in the transaction double after failures, not restoration of credentials already removed by an authorized cleanup callback. Persisted cross-resource replacement intents, recovery after that native boundary, and physical durability remain separate integration/acceptance requirements. No generic failure handler calls replacement or deletion automatically.

## Qualification boundary

Host temporary-file checks demonstrate local filesystem behavior in this runtime. Simulated cuts demonstrate policy ordering. Host SQLite checks exercise synthetic SQL transactions and process termination. None establishes Android encrypted-storage durability, Keystore recovery after alias loss, OEM transfer behavior, power-loss durability, PostgreSQL commit behavior or production acceptance.
