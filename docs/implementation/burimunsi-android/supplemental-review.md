# SMS R4 and storage R3 source review

Reviewed on 9 November 2026 against the retrieved Drive source and the current Collect intake. These continuations are preserved under `integration/burimunsi/continuations/`. They are outside Android source sets and have not replaced the active receiver, command journal, authentication, or backend implementation. Incoming gateway uploads remain held.

## Preserved source and verification scope

`sms-r4/` contains the complete 135-file supplied SMS R4 package, including its classifiers, shared policy, pinned small dependency snapshots, synthetic tests, host adapter, scripts, original manifests, and historical evidence. Original bytes are preserved. Its `evidence/` folder records the supplier's earlier execution; fresh checks are recorded separately. Vendored BuriMunsi and M-Money fragments exist to reproduce the supplied host tests and are not active application sources.

`storage-r3/` is a deliberate subset of the 2,095-file original two-product delivery. It retains the shared policy, generic JVM/Android adapters, BuriMunsi factory and command-store coordinator, source documentation, and provenance. Dependency closure adds the exact supplied `Values.kt` and `OperationJournal.kt` beside `DurableOperationStore.kt`, three relevant Kotlin suites, and two separate-process restart probes. No complete obsolete BuriMunsi or M-Money application tree is imported.

`storage-r3/tools/verify_imported.py` is the new local harness for that subset. It checks shared/product copy identity, compiles the supplied policy, authenticated-migration and durable-lifecycle suites, validates their nonempty unique result identities, runs the two supplied restart probes, hashes its actual inputs and logs, and verifies that source bytes stay unchanged. It uses disposable synthetic files and jars. It does not invoke Gradle, application installers, a network, live data, or the original full two-product runner.

## SMS R4: implemented policy and missing production ports

The supplied implementation contains a real AES-GCM journal envelope and an executable two-phase checkpoint controller. It authenticates the configured owner, installation, generation, contract, store, key alias, sequence and complete encrypted header. Existing-key lookup does not generate a replacement key. Append ordering is checkpoint preparation, durable ciphertext CAS, then checkpoint finalization; only the completed sequence releases a committed result. Recovery may finalize the exact prepared new ciphertext and emits no network effect.

`TrustedCheckpointPort` and `CiphertextBlobPort` remain production adapter contracts. The package supplies no independently rollback-resistant checkpoint service or Android ciphertext transaction implementation. A checkpoint restored alongside the encrypted file cannot detect joint rollback. Missing trusted state is not permission to create an empty store.

Adoption still requires explicit initial provisioning, evidence-preserving migration from the existing native queue, and durable encrypted intake/quarantine while an offline phone cannot reach the checkpoint service. Otherwise a blocked admission path could lose newly arriving evidence. The package does not implement the native owner/SIM/lifecycle fence or worker/network wiring. Full-journal encryption is bounded but rewrites the retained journal per commit; no mobile memory, throughput or battery result is inferred.

`host/HostFileJournal.kt` is plaintext JVM/POSIX test infrastructure. It must not store real message evidence or be installed as an Android adapter. Synthetic in-memory checkpoint ports are likewise test fixtures.

## Storage R3: useful mechanisms and incompatible baseline

The append-only lifecycle journal preserves committed snapshots and unfinished records, verifies readback, uses cooperative process locks and host durability barriers, and refuses automatic repair or evidence deletion. Its AES-GCM record adapter authenticates scope and record identity. The Android factory requires an existing dedicated key and pre-created private directory; it does not provision them.

The generic `AppendOnlyLifecycleJournal` defaults to `UnprotectedHostRecords` for inherited host fixtures. Android construction must explicitly use the encrypted factory. Authenticated records alone do not detect removal of a whole valid history suffix; an independent trusted anchor is still absent. Host filesystem/process checks do not establish Android Keystore, flash, reboot or power-loss durability.

The preserved command-store baseline is incompatible with the active A04/recovery command contract: its `PendingOperation` has no owner-account/group fields, and its `OperationJournal.beginAttempt` permits another attempt for nonterminal SENT/UNKNOWN commands. These exact historical files are retained only to verify the supplied coordinator. They must not replace the active journal, weaken its single-dispatch rule, or be compiled into the active app by a broad source glob. Production `OperationRecordPort`, migration and cleanup wiring remain separate work.

## Fresh checks

The first SMS reproduction retained its failure evidence at `.cache/burimunsi-supplemental-verification-20261109/sms-r4/`: all 40 dependency pins matched; eight Python fixture cases encountered macOS's `/var` symbolic-link alias, and Kotlin CLI was absent from the initial PATH. No production path guard was relaxed.

Fresh corrected execution used the verified Kotlin CLI 2.4.21 and JDK 17.0.21.0.2, a canonical temporary directory, and an explicit Java temporary-directory property. Both runners exited zero and verified unchanged source inputs. All 135 original SMS package files were also compared with the retrieved source after execution and remain byte-identical.

| Host verification | Measured result |
| --- | --- |
| SMS dependency pins and Python delivery tests | 40 pins matched; 22 tests passed |
| SMS R4 encrypted journal/checkpoint tests | 102 tests passed, including 254 malformed inputs |
| Retained SMS R3 persistence tests | 95 tests passed, including 19 child processes |
| Retained SMS R2 policy tests | 210 tests passed |
| Retained BuriMunsi core / receiver / reliability checks | 99 / 34 / 42 passed |
| Retained small M-Money SMS dependency checks | 45 passed; no M-Money application adopted |
| Storage shared/product source copy identity | 10 exact pairs matched |
| Storage policy / authenticated migration / durable lifecycle checks | 207 / 62 / 100 passed |
| Authenticated migration / durable lifecycle restart probes | 14 / 7 passed |

Fresh evidence is at `.cache/burimunsi-supplemental-verification-20261109/sms-r4-canonical/verification.json` and `.cache/burimunsi-supplemental-verification-20261109/storage-r3/summary.json`, with per-command logs and input/log hashes. These counts describe distinct supplier suites; assertions, malformed-input cases and child processes are not additional test totals. The results establish local host behavior only. Android compilation/instrumentation, platform durability, trusted-service integration and production adoption were not performed by these checks.

None of these imported policies grants financial posting authority, substitutes for either product's acknowledgement contract, enables the live-upload hold, or proves native adoption.
