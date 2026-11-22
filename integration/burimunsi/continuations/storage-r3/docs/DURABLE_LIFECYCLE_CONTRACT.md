# R3 authenticated journal and migration integration contract

## Scope and status

Implemented: authenticated append-only journal, strict migration plan, crash recovery protocol, existing-key Android JCA factory and separate product factories. Host verification passed. **Not implemented:** a decoder for the actual BuriMunsi/M-Money legacy persistence, durable old/new writer handover, new-key provisioning, native immutable archive copier, app/worker wiring or device acceptance. Do not turn the new factory on merely because this file exists.

The snapshot/reducer/coordinator contract is retained in `history/r2/docs/DURABLE_LIFECYCLE_CONTRACT.md`; the changes below supersede its host-only persistence description, not its evidence-retention rules.

## Source map

| Responsibility | Canonical source |
|---|---|
| Strict state/transition invariants | `policy/StorageLifecyclePolicy.kt` |
| Snapshot serialization/validation | `policy/LifecycleSnapshotCodec.kt` |
| Persist-before-effect orchestration | `policy/DurableStorageCoordinator.kt` |
| Legacy state and inventory plan | `policy/LegacyLifecycleMigration.kt` |
| AES-GCM framing, identity scope, key lookup port | `adapters/jvm/JournalRecordProtection.kt` |
| Append-only records, migration and pending promotion | `adapters/jvm/AppendOnlyLifecycleJournal.kt` |
| Existing Android Keystore lookup and secure factory | `adapters/android/AndroidLifecycleStorage.kt` |
| Content-based archive verifier, not copier | `policy/VerifiedEvidenceArchive.kt` |

The same shared sources are copied into `rw/ikanisa/storagepolicy` in each product core tree. Product factories are in its `android` subdirectory. The shared-copy check must pass after every change.

## Authentication envelope

Big-endian framing: four-byte magic `0x4c434531`, four-byte version `1`, twelve-byte provider-generated IV, ciphertext and sixteen-byte GCM tag. AAD encodes magic/version then length-prefixed UTF-8 product, owner, journal namespace and record identity. Bounds are checked before cipher processing. Exportable keys must be AES with 32-byte encoding; opaque Android keys require independently enforced AES-256 provisioning.

Record identities are `genesis`, `migration`, or `snapshot:<revision>`. The pending filename is not part of identity: a pending record and its committed counterpart represent the same revision and bytes. Product/owner/namespace substitution and revision substitution fail. Generation changes remain inside the encrypted snapshot; the journal namespace and key must remain stable across a legitimate replacement.

Encrypted reads never downgrade to `UnprotectedHostRecords`. That object exists only for retained host fixtures and callers deliberately choosing it. `AndroidLifecycleStorage` requires `AesGcmJournalRecords` and checks the existing key before a lock file can be created. Neither constructor provisions or replaces an alias.

Authentication verifies integrity and scope, not freshness. Removing a complete trailing sequence of valid records may still expose an older valid prefix. Mitigate with a separately trusted monotonic anchor before claiming rollback resistance. Do not label a GCM failure as a permanent-key-loss diagnosis.

## Persistent records and ordering

An already-created, private journal directory contains `.lock`, a permanent `genesis.anchor`, numbered `.snapshot` records and at most the pending record allowed by recovery. Migrated journals also retain a permanent `migration.anchor`. All paths and ancestors must pass the no-follow regular-file/directory requirements. Unknown entries, missing anchors, gaps, oversized files and unreadable paths block. An I/O error is never proof of absence.

Snapshot chain hashes bind exact decrypted canonical snapshots. Every new protected record uses CREATE_NEW, writes the full ciphertext, forces it, reads back the same bytes and decrypts/verifies it. Publication uses an atomic move without a non-atomic fallback. Directory forcing is a prerequisite for reported completion. Host success does not prove Android filesystem or flash durability.

For migration, the authenticated genesis plaintext is the 64-character initial snapshot digest, a colon and the 64-character migration marker digest. This couples migration provenance to genesis. Removing `migration.anchor` blocks the journal instead of silently turning it into a fresh provisioned store. The marker contains the exact original snapshot, revision, operation ID and artifact inventory and is not deleted after success.

## Legacy capture and handover obligations

Implement `LegacyLifecycleReadPort` in the product-specific integration layer. `frozen` must exclude every old writer, worker and replacement path while `capture` and adoption execute. Use one consistent lock order: legacy scope first, journal second. A process-local lock alone is insufficient where multiple processes or persisted workers can write. A lost process lock after a crash must not let an old implementation resume behind the new journal.

`capture(binding)` must perform a strict legacy decode and supply the entire state: unresolved write identity, cleanup manifest, receipt, removed/remaining artifacts, tombstones, archives, replacement target, current fault, prior write/replacement identities and used operation IDs. It must not invent a resolved outcome, empty set or new operation. Enumerate every retained artifact with exact ID, length and SHA-256, including relevant sidecars/key-wrapping records. Missing or unrecognized evidence is a blocked migration, not a repair opportunity.

The generic protocol compares the inventory against state evidence and repeats the captured plan before effects and publication. It does not discover arbitrary disk files or prove that a dishonest/incomplete product capture is complete. If active state.evidence does not enumerate historical archive/tombstone material that must remain, the product must also retain and protect those locations independently and must not delete them during migration.

Before enabling any new writer after migration, persist a product-level cutover gate that makes old writers refuse operation after restart. Test the gate and original operation IDs across application upgrades, worker restart, logout and reauthentication. Retain legacy evidence until an independently authorized retention operation; successful migration is not such authorization.

## Explicit migration sequence

```kotlin
// Product integration must supply the real frozen legacy read adapter and a
// pre-provisioned dedicated existing alias. This is a protocol sketch, not app wiring.
val plan = legacy.frozen {
    LegacyLifecycleMigration.prepare(binding, migrationOperationId, legacy.capture(binding))
}
val checkpoint = journal.adoptLegacy(plan, legacy, explicit = true)
```

The migration operation ID is allocated once and retained by the caller's audited intent; crash recovery must use that same ID and the same exact capture. Do not generate a fresh ID on each attempt. The plan is revalidated under the legacy lock during adoption. The new journal starts at revision zero, preserves every semantic field and adds the migration ID to used operations. Original revision and full original state remain in the marker.

Destination must be virgin for the first attempt, or contain only the exact matching bootstrap state for a retry. A normal initialized journal, a conflicting marker or an advanced target is rejected. No automatic in-place encryption of a plaintext R2 journal occurs; an explicit capture and separate destination are required.

Ordering: verify source → authenticated migration marker and directory force → linked authenticated genesis and directory force → authenticated initial pending snapshot and directory force → verify source again → atomic publication and directory force → verify committed snapshot and source. Complete existing records are compared, not overwritten. Empty/partial records are retained and blocked. There is intentionally no destructive discard/recreate recovery API.

## Recovery observations

| Interruption/evidence | Required result |
|---|---|
| Marker, genesis or pending file exists but is empty/partial | Block; retain exact bytes and old evidence |
| Complete matching marker/genesis with no later record | Resume same plan, not a new migration |
| Complete matching pending snapshot | Validate source and exact plan before publishing same ciphertext |
| Matching revision-zero snapshot published | Idempotent readback; no legacy deletion |
| Journal advanced after migration | Use normal journal recovery; migration cannot rewind it |
| Source changed, unreadable or cannot be frozen | Block; retain destination prefix and source |
| Wrong key/scope or corrupt authenticated record | Block; no plaintext retry, no regenerated alias |
| Journal/legacy paths missing unexpectedly | Classify and investigate; no silent fresh store |

## Android provisioning and operational wiring

Provision the dedicated key and no-backup directory through a separate explicit virgin-storage operation. Refuse unknown surviving evidence before doing so. The alias must be AES-256, AES/GCM/NoPadding capable and configured for the intended authentication/lifecycle behavior. No production secret is included in this package. Opaque-key algorithm/length and provider policy must be verified in Android instrumentation; the host cannot inspect a nonexistent Android provider.

Do not reuse a ledger-generation key that replacement destroys. Keep the journal key and permanent anchors outside cleanup manifests. Excluding a directory from backup is a product configuration and transport test, not a property conferred by accepting a `Path` argument. Callers must choose the actual app-private no-backup location and enforce its permissions.

Integrate the persist-first coordinator only after migration and handover are committed. Map actual deletion and absence probes, immutable archive copying, replacement-target creation and UI interruption states. Do not delete live database/WAL/key material while components still hold it open. Neither a free-space check nor a repeated button press may clear a pending command or authorize a replacement financial operation.

## Qualification gates

Run the supplied host runner and inspect its source-bound evidence first. Then compile/lint the integrated native candidate under its pinned toolchain and test real Android keys, forced writes, missing/corrupt anchors, process death, concurrent workers, first unlock, reboot, storage pressure, OEM behavior and power loss. Qualify authenticated backend receipts and authoritative database results independently. Add retention/compaction and an independent monotonic checkpoint before asserting those properties.

Passing `authenticated_migration` and `authenticated_process_restart` proves only the tested host behavior with synthetic fixtures. The Android factory's unavailable-provider check is a negative host test, never a native acceptance pass.
