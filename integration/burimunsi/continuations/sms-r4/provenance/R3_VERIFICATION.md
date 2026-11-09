# SMS queue persistence and recovery — R3 verification

Date: 9 November 2026. Scope: shared source, synthetic host filesystem/process tests and inherited regressions. No Android or carrier acceptance claimed.

## Result

**543 executed local test/check cases passed; zero failed.** Forty pinned dependency hash checks also passed and are reported separately.

| Suite | Result | Cases |
|---|---|---:|
| python_tooling | passed | 18 |
| persistence_r3 | passed | 95 |
| policies_r2 | passed | 210 |
| buri_core | passed | 99 |
| buri_receiver | passed | 34 |
| buri_reliability | passed | 42 |
| mmoney_sms | passed | 45 |

The R3 persistence suite ran **95 named tests**, **11,505 assertions**, **4,540 malformed snapshot inputs**, and **19 child JVM processes**. These are overlapping coverage measures, not additive test counts. It includes 28 in-memory persistence fault cases (four transitions × seven faults), four host write-interruption hook cases, every partial journal-tail offset for the fixture, separate-process contention, and abrupt `Runtime.halt` during partial append and after force-before-return.

The R2 policy suite was rerun: 210 tests, 6,831 assertions and 2,000 deterministic state-machine events. The four inherited application suites and all 18 Python delivery tests passed. The installer upgrade test confirms that only the three new shared Kotlin files are added to either R2 native-source fixture; the plaintext host adapter is not installed.

## Exact source binding

Input set SHA-256:

`db35d011e8029470c19ebce8d3263a682057be2a61fb7dcdfd47015b1d6675fe`

`evidence/verification.json` records each of the 64 input-file hashes, JVM/compiler versions, compile and execution exit codes and compiled-jar hashes. Inputs were unchanged at completion and were compared again before packaging.

Compiler: Kotlin/JVM 1.9.0. Runtime: OpenJDK 21.0.12.1. Target bytecode: JVM 17. All six Kotlin compile/runtime phases returned zero. The overall successful local run returned zero.

The negative prerequisite run selected nonexistent Java/Kotlin executables. All six dependent Kotlin suites reported **blocked**, not passed; Python checks still executed. Overall exit code: **2**. Its separately named JSON record is included.

## What this establishes

Deterministic snapshot round-trip; original multipart/provider metadata preservation; strict malformed-data rejection; monotone, immutable journal history; atomic retained identity admission through the append-port contract; no upload effect after failed/unknown state writes; host reopen and process-interruption recovery; and safe source addition on temporary native checkouts.

## What remains blocked

Encrypted Android storage and Keystore lifecycle, live worker/lifecycle-fence wiring, intake/quarantine/checkpoint atomicity, legacy-queue migration, actual Collect checkout import, pinned Android builds/instrumentation, real hosted/database idempotency and physical carrier delivery. The host journal is plaintext and uses synthetic data only.

Checksums are not authentication. Complete valid-prefix rollback requires an external trusted high-water/lifecycle mechanism and is not detected here. Process termination is not physical power-loss or handset reboot qualification. No compaction/deletion/automatic repair or security certification is claimed.

See `docs/INTEGRATION.md`, `docs/PERSISTENCE_FORMAT.md`, `docs/MERGE_DECISIONS.md`, and `TASK_STATUS.json` for the exact handoff.
