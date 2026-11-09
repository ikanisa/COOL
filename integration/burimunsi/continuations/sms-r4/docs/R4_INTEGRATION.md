# R4 integration contract

## Dependencies and construction

Instantiate one immutable `StorageBinding` for the authenticated contract/owner/installation/generation and explicit store/key identifiers. Resolve the approved existing AES key through `ExistingAesKey`; `ExistingAndroidKeystoreKey` is a lookup-only Android implementation. Missing, locked, invalidated or wrong keys must cause a hold, not key recreation.

Compose:

```kotlin
val cipher = AesGcmJournalCipher(existingKeyResolver)
val protectedLog = ProtectedJournalPort(storageBinding, cipher, ciphertextPort, trustedCheckpointPort)
val store = JournalQueueStore(protectedLog, storageBinding.scope)
val driver = CommitDriver(store, applicationQueueMachine)
```

The four injected variables refer to the explicit production configuration and qualified adapters. There is no included production checkpoint service and no fallback that substitutes an in-process map or sibling file.

## Fresh provisioning and migration

Normal `read`, `append`, `inspect` and recovery never create a store. Authorized provisioning must establish both the encrypted `JournalFormat.empty(scope)` envelope at sequence zero and its exact `JournalAnchor` in the independent trusted store. Expose no queue admission while one side is missing. Record a unique store identity and key alias scoped to the install generation; never reuse them for a replacement installation.

Existing R3 plaintext/native encrypted databases require a separate audited migration. Freeze intake safely, preserve original bytes and acknowledgements, verify the complete journal, allocate a new explicit store identity and prove the new anchor/ciphertext pair before switching. No such migration is shipped or claimed; do not feed a plaintext file into the ciphertext adapter or adopt whatever bytes happen to exist.

## Trusted side requirements

`TrustedCheckpointPort.read(contextHash)` must be authenticated, scoped, strongly consistent and unavailable rather than silently stale. `compareAndSet` must atomically compare the exact expected checkpoint, validate `CheckpointRules`, authorize the installation/owner, and durably persist the next state. COMMITTED must mean durable. Throws/timeouts/lost acknowledgements map to UNKNOWN. Missing/unavailable checkpoint state cannot be reset through this interface.

The backend must survive independently of rollback of the handset filesystem. Encryption of a local checkpoint is not equivalent to anti-rollback. An offline strategy must be designed explicitly; the supplied controller blocks while a required trusted dependency is unavailable. Retain live messages in the native encrypted intake/quarantine store, without advancing intake checkpoints prematurely.

## Ciphertext side requirements

`CiphertextBlobPort.replace` receives a complete retained encrypted journal, not a delta. Compare the SHA-256 of the existing complete ciphertext under an interprocess transaction. Write the new blob with platform-qualified write, rename and directory durability barriers. Return UNKNOWN for partial/uncertain writes and preserve interrupted artifacts for recovery. Never replace missing/corrupt data with an empty journal, delete old evidence, or return success after a failed barrier.

Do not use R3's plaintext `HostFileJournal` as this port. R4 fault tests use in-memory synthetic ports; R3's real POSIX process tests exercise the older plain adapter and are reported separately.

## Runtime ordering

1. Persist incoming original evidence and multipart metadata in the native intake transaction, including unsupported/conflicting input.
2. Admit only the original eligible immutable batch through `CommitDriver.capture` after trusted store readiness.
3. On startup inspect the protected journal. For a pending checkpoint, explicitly run `recoverPrepared`. Do not dispatch a queue effect from recovery.
4. Restore queue state using the existing original operation ID. Lost acknowledgements/uncertain outcomes never authorize another financial operation.
5. Hold the qualified native lifecycle/ownership/SIM fence across `ReservationGate.permitted` and request submission. R4 does not implement this lock or invoke network I/O.
6. Stage and finalize only contract-valid acknowledgements through the same committed storage path. Preserve rejected/conflicting receipts and terminal duplicate ownership.

## Failure outcomes

| Condition | Result |
|---|---|
| Committed checkpoint matches full authentic journal | Reads permitted; normal queue policy still applies. |
| Old valid ciphertext against a newer trusted checkpoint | Hold; no adoption, retry reset, creation or deletion. |
| Prepared checkpoint and exact new ciphertext | Explicit recovery may finalize it. No network effect is returned. |
| Prepared checkpoint and old/partial/missing ciphertext | Hold for authorized recovery; no cancel-to-old operation. |
| Key loss, wrong key, invalid version, scope change or corruption | Hold and retain evidence. |
| Both local ciphertext and an improperly local checkpoint restored together | Not detectable; such a deployment violates the trusted-port requirement. |

## Acceptance gates

Complete Android key/provider tests, durable transaction tests, independent checkpoint-service CAS/auth/rollback tests, lock/worker integration, legacy migration and retention tests, actual source-candidate merge tests, native builds and instrumentation, network/database acknowledgement/idempotency tests, and physical SIM/carrier/reboot/replacement tests before production designation. Maintain independent fields for source completion, executed local tests and external acceptance.
