# Storage policies R3 — implementation and verification

9 November 2026 · BuriMunsi and M-Money

## Delivery result

R3 adds authenticated journal records, an evidence-preserving legacy-state adoption protocol, and product-specific factory entry points for an existing Android Keystore alias. These changes are included in both application core source trees. The host regression run passed with exit code 0 and unchanged source inputs. Three incremental patches reconstructed all 1,900 source inputs byte-for-byte against the exact R2 baseline. There are 17 added or modified code/harness paths: five in each application and seven shared/test/tool paths; no prior application source file was removed.

This does **not** mean the applications now use the new journal. The product-specific legacy decoders, durable handover from old writers, alias provisioning, application/worker wiring, immutable archive copying and Android qualification remain open. No working Collect checkout, real ledger, hosted service or production installation was changed. This is not a new consolidated A04 candidate and does not silently replace parallel workstreams.

## Implemented

### Authenticated journal storage

`adapters/jvm/JournalRecordProtection.kt` adds AES-GCM envelopes for snapshots and permanent anchors. Associated data binds product, owner, journal namespace and record identity. The encryption provider generates the IV; the implementation requires a 12-byte IV and uses a 128-bit authentication tag. Exportable keys must be 32-byte AES keys; opaque Android keys must satisfy the separately enforced provisioning contract. A host key is synthetic and is not a production credential.

An encrypted reader never retries plaintext when authentication fails. Wrong keys, owners, products, namespaces, record identities, malformed envelopes and tampered ciphertext block reads. Missing/inaccessible keys do not authorize key generation or replacement. Authentication failure is not labelled proof of permanent key loss.

The append-only journal now supports these envelopes while preserving R2's no-follow path checks, bounded files, revision compare-and-set, per-directory/process locking, forced writes, exact readback, chained history and explicit pending promotion. Pending and committed filenames refer to the same authenticated record identity so promotion retains the exact ciphertext. Unprotected records remain an explicitly selected host-fixture mode, not an error fallback. Android factories do not expose that mode.

### Explicit legacy-state adoption

`policy/LegacyLifecycleMigration.kt` captures a validated state and exact artifact inventory. A plan records the original snapshot, original revision, operation ID, artifact IDs, sizes and hashes. It preserves pending writes, original command identities, partial cleanup, deletion receipts, tombstones, replacement intent, faults and operation-use history. Only the new journal revision becomes zero; the migration operation is added to used operations. The original revision remains recorded permanently.

`AppendOnlyLifecycleJournal.adoptLegacy` requires explicit authorization, authenticated storage, an exact plan and a frozen legacy read port. It rechecks the source before effects and before publication, writes and verifies an authenticated migration marker, links that marker to the permanent genesis anchor, writes the initial pending snapshot and then publishes the same bytes. A repeated exact completed bootstrap is idempotent. An advanced target is never rewound.

Complete interrupted records can resume only under the same plan. Empty, truncated, corrupt or conflicting marker/anchor/pending records block without deletion, truncation or rewriting. There is no automatic repair by creating an empty ledger. The migration port exposes no deletion operation and the protocol never removes old files.

The read port is an explicit integration contract, not a parser for either actual legacy database. Its `frozen` implementation must really stop old writers for the full operation. After handover, a durable product gate must prevent them from restarting. The protocol's source-change checks do not replace that requirement.

### Android and product factory source

`adapters/android/AndroidLifecycleStorage.kt` looks up an existing `AndroidKeyStore` secret key through JCA and opens the authenticated journal in a caller-supplied pre-created private/no-backup directory. Missing keys or directories do not trigger provisioning. `BuriMunsiLifecycleStorage` and `MMoneyLifecycleStorage` set separate product scopes. Canonical shared files are copied byte-for-byte into each product; the runner verifies the copies.

Both product factories and the canonical Android factory compile in the supplemental `evidence/current/product_factory_host_compile.json` check, but the real AndroidKeyStore provider was not exercised. The test on this host verifies refusal when that provider is unavailable. There is no new key-provisioning UI, native migration transaction or automatic application switch in this delivery.

## Verification actually executed

All results below come from `evidence/current/summary.json` and its hash-bound logs, not previous runs.

| Executed check | Result | Boundary |
|---|---:|---|
| New authentication and migration checks | 62 passed | Host JCA, synthetic keys and disposable files |
| New separate-JVM interruption/restart cases | 14 passed | Process termination, not power loss |
| Retained R2 codec/coordinator/filesystem checks | 100 passed | Host adapters and explicit doubles |
| Retained R2 separate-JVM recovery/concurrency cases | 7 passed | Includes competing processes |
| Retained R1 policy/opening/command-store checks | 207 passed | Platform-independent logic |
| Retained M-Money deletion/replacement checks | 21 passed | Actual functions with transaction doubles |
| Runner self-tests | 7 passed | Prerequisite and output controls |
| BuriMunsi Node suite | 1,515 passed | Local JavaScript tests |
| BuriMunsi selected core/repository/presentation/HTTP suites | Passed | Detailed per-suite results in the log |
| M-Money Python regressions | 149 passed | Local tooling/source contracts |
| M-Money resilience checks | 29 passed | Host Kotlin |
| M-Money opening/headroom checks | 290 passed | Host Kotlin |
| M-Money storage SQL checks | 9 passed | Host SQLite, not Android SQLCipher |
| Both product factory sources | Host compilation passed | JCA signatures only; no Android provider execution |
| Incremental patch application | 3 passed | Fresh exact R2 copies, full input comparison |

The 62 named checks include loops over each mutated envelope byte and truncated prefix, multiple lifecycle phases and all 14 injected persistence boundaries. Do not reinterpret those loops as additional independent test methods or combine all counts into device coverage.

The 14 process cases halt a fresh JVM at migration marker, genesis and initial snapshot boundaries: created, written, forced and directory-forced, plus publication and publication-directory-forced. Empty created records remain blocked and byte-identical. Complete recoverable records resume; original legacy bytes and every pre-existing retained record are compared before and after. Renamed pending records retain the original ciphertext hash.

Toolchain recorded by the runner: Kotlin 1.9.0, Java 21, Node and Python versions in `evidence/current/tool-*.log` and summary metadata. This is not the pinned native Android toolchain. Earlier evidence remains under `evidence/previous-r2`, `evidence/previous-r1` and preserved source histories; it cannot certify R3.

## Reproduce

From the extracted `storage-policy-delivery` root:

```sh
python3 tools/run_storage_checks.py --output ../storage-r3-verification
```

The output directory must be new. Exit 0 means selected local checks executed and passed. Missing prerequisites report blocked; failures report failed. `--require-native-acceptance` retains a nonzero result because native/service acceptance has not been supplied. Do not replace that distinction with a production flag.

Use `patches/r3/README.md` only against the exact R2 baseline. `CHANGE_LEDGER.json` binds every before/after hash; `PATCH_VERIFICATION.json` records actual reconstruction. Copying individual files into an independently consolidated checkout requires conflict review and fresh testing.

## Remaining requirements

1. **Receiving-repository reconciliation:** merge R1/R2/R3 changes with the authoritative consolidated Collect candidate without discarding parallel source edits. Version names/codes of the applications were not changed in this workstream.
2. **Real legacy-state decoder and durable cutover:** map each actual product journal/database into the full capture contract, enumerate complete sidecars/key records, stop old writers, persist the handover gate and wire application/worker reads and writes to the chosen storage authority. Pending or unknown outcomes must retain their original operation IDs.
3. **Key and directory provisioning:** explicitly provision a dedicated non-exportable AES-256 alias and private no-backup directory only under an audited virgin-store workflow. The alias must outlive retained journal and archived generations and must not appear in generation cleanup. Resolve lifecycle/rotation and inaccessible-key policy without silent regeneration.
4. **Native archive/replacement adapters:** implement immutable archive copying and readback, product-specific file deletion/absence probes, exact target creation and recovery UI. The generic verifier and coordinator are not substitutes for these implementations.
5. **Native and service qualification:** build/lint intended variants; run Android Room/SQLCipher, Keystore, process death, storage pressure, first unlock, reboot, OEM and power-loss tests. Qualify real backend receipts and PostgreSQL outcomes separately.
6. **Retention and rollback policy:** define safe journal capacity/compaction and an independent trusted monotonic checkpoint. Authenticated records do not detect removal of a complete valid history suffix. The adapter currently blocks at capacity and never compacts by deleting evidence.

`ACTION_REGISTER.json` keeps source completion, local verification, native adoption and external acceptance as separate fields. No approval or acceptance is inferred from host results.

## Provenance and delivery organization

The exact R2 archive and original product archive hashes are linked through `ORIGIN.json` and `history/r1/ORIGIN.json`. R1 and R2 documentation and registers are retained under `history/`. The R3 ZIP contains both full source trees, shared adapters, tests, logs, patch ledger, manifests and reproduction instructions. There are no generated test JARs, real keys or installed dependencies added by R3.

Drive organization remains: **BuriMunsi → 02 Engineering Delivery and Versions → Production Audit and Collect Integration Handover → Storage Policies**. Earlier deliveries are preserved, not overwritten; R3 has its own subfolder. The two original source inputs have a dedicated subfolder. A separate conversation-file index maps the individual delivery files and duplicate local references to their Drive locations.

The referenced local `/Volumes/PRO-G40/.../efficient-codex/SKILL.md` was not mounted and was not used.

## Platform references

These official references informed the implementation contract; they are not evidence of passing device tests.

- Android KeyGenParameterSpec.Builder, randomized encryption and key properties: https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder
- Android Cipher, authenticated encryption and associated data: https://developer.android.com/reference/javax/crypto/Cipher
- Java Cipher, GCM IV uniqueness and AEAD verification: https://docs.oracle.com/en/java/javase/24/docs/api/java.base/javax/crypto/Cipher.html
