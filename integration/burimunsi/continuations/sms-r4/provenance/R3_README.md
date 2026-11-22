# SMS queue persistence and recovery — R3

BuriMunsi / M-Money • 9 November 2026

R3 continues the verified R2 policy workstream with an executable, versioned snapshot codec, an append-only journal-backed `QueueStorePort`, stricter persisted-state/history validation, and a JVM/POSIX host file adapter. The mobile workers, encrypted Android storage, and deployed services have not been modified or qualified.

## Delivery status

The shared source and synthetic host tests are implemented. The full measured run is in `evidence/verification.json`; `VERIFICATION.md` summarizes its counts and limitations. Source implementation, local verification, and external acceptance remain separate in `TASK_STATUS.json`.

R3 is **additive**: every R2 policy source, adapter, fixture and pinned dependency remains byte-for-byte unchanged. `provenance/R2_BASELINE.json` records the inspected R2 input hashes. The three new shared Kotlin files can be added to an R2 installation without replacing its existing files. The plaintext host adapter is deliberately outside the mobile overlay.

## What changed

| Component | Behavior |
|---|---|
| `SnapshotCodec.kt` | Bounded version-1 binary encoding, exact original part fields and observation order, canonical derived-hash checks, strict enums/booleans/null handling, checksum and structural validation. Unknown versions, truncation, changed hashes, impossible states and trailing data fail closed. |
| `JournalFormat.kt` | Scope-bound, append-only hash-chain format; replay rebuilds the snapshot/duplicate index; validates revision/time/attempt monotonicity, immutable batches and retained acknowledgements. No skipped corrupt records, automatic truncation or reset. |
| `JournalQueueStore.kt` | Real `QueueStorePort` implementation over an atomic append port; compares the complete prior journal digest when appending. Original/capture and M-Money source/body uniqueness remain in the same committed history, including terminal records. |
| `ReservationGate` | Additional last-moment check for expired reservations, changed sessions/SIM/authority, changed classification and immutable batch bytes. The native lifecycle lock must cover the check and submission; this function is not a lock or a one-use token. |
| `HostFileJournal.kt` | Host-only plaintext POSIX reference with explicit fresh-directory provisioning, file/JVM locking, append-only writes, write barriers and injected interruption stages. It is NOT installed by the mobile overlay. |

No source assigns an SMS the authority to post money. Collect v2 and M-Money v1 acknowledgements remain separate. The queue persists retained/rejected receipts as evidence, not proof of a financial transaction.

## Reproduce

Prerequisites: Python 3.10+, Kotlin/JVM 1.9+, Java 17+, and a POSIX local filesystem for the host persistence suite. No network or external packages are used by the runner.

```sh
cd SMS_Policies_R3
python3 scripts/verify.py --output /tmp/sms-policies-r3-verification
```

The output directory must not already exist. The command executes the new persistence suite, the unchanged R2 policy suite, delivery/installer tests, and four pinned inherited suites. It records source hashes, compiler/runtime versions, stdout/stderr, compile and execution exit codes, and named new test cases.

Exit `0` means the executed local suites passed. Missing prerequisites produce `blocked` and exit `2`; failed checks produce exit `1`. External Android/carrier/service gates remain blocked even when local tests pass. `--require-external` keeps the command nonzero while these gates are open.

The host suite starts child JVMs to test reopen/recovery, concurrent reservations, abrupt process termination during a partial append, and abrupt termination after `force(true)` but before the result reaches the caller. This is **not** a handset reboot, power-loss, OEM filesystem or Keystore test.

## Additive source installation

Use a native project root. The installer checks pinned core dependency hashes, refuses unknown edits/collisions, and defaults to dry-run.

```sh
python3 scripts/install_overlay.py --application burimunsi --target /path/to/native/burimunsi
python3 scripts/install_overlay.py --application mmoney --target /path/to/M-Money_Native_Android
# After inspecting the plan, explicitly append --apply to the corresponding command.
```

Repeated identical installation is a no-op. The installer preserves existing R2 source files, does not install `host/`, and does not wire workers, change Gradle, migrate databases, alter authentication or enable SMS upload. A differing A03/A04 consolidated baseline must be reconciled explicitly; there is no force flag.

## Important boundaries

**The host journal is plaintext and for synthetic host tests only. Do not use it with real SMS evidence.** An Android adapter still needs authenticated encryption, Keystore lifecycle handling, interprocess transactions, intake/checkpoint integration and native fault testing. The codec itself is serialization, not encryption.

SHA-256 and the chain detect accidental corruption, record substitution and reordering within the supplied bytes. They do not authenticate a writer and do not detect restoration of an earlier *complete valid prefix* without a separate trusted high-water mark. Production anti-rollback/lifecycle binding remains open.

A torn or malformed journal blocks all reads/writes rather than trusting a surviving prefix. All existing bytes remain on disk for an explicit recovery procedure. No compaction, deletion, replacement, corruption repair or automatic migration is provided.

R2 did not define a persisted snapshot wire format, so version 1 is the first format of this R3 implementation. It is not an automatic converter for existing BuriMunsi/M-Money Android databases or encrypted files. An unknown version is retained and rejected.

Queue storage admits eligible batches only. Unsupported inbound messages and conflicting incoming observations must remain in the native intake/evidence store; this delivery does not implement that separate quarantine/checkpoint transaction. A failed capture must not advance the intake checkpoint.

No actual Collect checkout, APK, installed device, carrier connection, hosted service or database was modified. Existing BuriMunsi live-upload admission remains disabled in the application sources. The requested local `efficient-codex` skill path was not mounted and was not used.

## Package map

`src/` contains shared policies and separate app classifiers. `host/` contains the synthetic-only file port. `tests/persistence/` exercises serialization, replay, faults and process boundaries. `tests/kotlin/` and `tests/python/` retain and extend host regression checks. `vendor/` retains the pinned source dependencies. `docs/` contains format, integration and merge decisions; R2 documents are explicitly marked as historical. `evidence/` contains the measured current run. `SOURCE_MANIFEST.json` and `SHA256SUMS.txt` inventory the delivered bytes.
