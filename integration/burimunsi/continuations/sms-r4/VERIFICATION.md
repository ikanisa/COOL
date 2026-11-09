# SMS Policies R4 — measured verification

9 November 2026

**649 executed local test/check cases passed; zero failed.** Separately, 40 pinned-source hashes matched. The exact 75 source/test/tool/provenance inputs remained unchanged during execution. Source implementation is not external acceptance: every required Android, carrier and deployed-service gate remains blocked.

| Suite | Result | Test/check cases |
|---|---|---:|
| pinned_dependency_hashes | passed | 40 |
| python_tooling | passed | 22 |
| protected_r4 | passed | 102 |
| persistence_r3 | passed | 95 |
| policies_r2 | passed | 210 |
| buri_core | passed | 99 |
| buri_receiver | passed | 34 |
| buri_reliability | passed | 42 |
| mmoney_sms | passed | 45 |

`pinned_dependency_hashes` is not included in the 649 test/check total. The protected R4 suite contains 102 named tests, 898 assertions and 254 malformed-envelope attempts; fault cases and assertion counts overlap and must not be added to the case total. It tests actual Java AES-GCM, synthetic in-memory storage/checkpoint faults and 20 concurrent two-worker races. The R3 suite has 95 cases, 11,505 assertions, 4,540 malformed-snapshot inputs and 19 child processes. The R2 suite retains 210 cases and its synthetic state-model checks.

Toolchain observed: Kotlin/JVM 1.9.0 and OpenJDK 21.0.12.1; compilation target JVM 17. Runtime provider behavior on Android was not executed. ExistingAndroidKeystoreKey was compiled with shared source and inspected by delivery tests, not invoked on a handset.

## Fault boundaries

Capture, send reservation, acknowledgement staging and acknowledgement finalization are interrupted at checkpoint preparation, ciphertext replacement and checkpoint finalization. Injected cases include known no-write, unknown-before, unknown-after, exceptions before/after, and partial ciphertext replacement. Checkpoint partial writes are not modeled as legal: its required CAS contract is atomic. No failed/unknown write releases an upload effect.

Tests reject complete valid old ciphertext against a newer independent checkpoint; wrong scope/installation/generation/contract/store/key alias; changed sequence/version/length; altered ciphertext/tag/header; missing/invalid keys; missing or malformed checkpoints; invalid journals; and skipped/batched append records. One explicit boundary test demonstrates that jointly rolling back ciphertext AND an untrusted local checkpoint is not detectable. Production must not use that deployment model.

## Recovery and availability

Prepared plus exact complete new ciphertext can be finalized without a new operation ID or network effect. Prepared plus old/partial/missing ciphertext remains blocked; no automatic cancellation or evidence deletion is attempted. A missing or unavailable trusted backend blocks reads/admission. The native durable intake/quarantine path needed for offline receipt retention is still external work.

## Missing prerequisites

A fresh invocation with nonexistent Java and Kotlin paths returned **blocked, exit 2**, while the 22 independent Python checks still ran. `evidence/missing_prerequisite_verification.json` records that run. No missing test is marked passed.

## Reproduction

```sh
cd SMS_Policies_R4
python3 scripts/verify.py --output /tmp/sms-policies-r4-verification
```

Use a new output directory. Add `--require-external` to retain a nonzero exit while external acceptance is open. Logs, exits and exact inputs are in `evidence/verification.json`; named new cases are in `evidence/protected_r4.json`.

## Source and delivery integrity

Baseline R3 archive SHA-256: `706857f6d08c006d83caad1aa3d71e839207371362650497580d6509fc8c0e69`.

Executed input-set SHA-256: `1f636b84a400a803f013640e86643faa11ccf8aab48e56945b422a1c740cdbde`.

The R3-to-R4 patch is separately applied to a fresh R3 tree and checked against all executed input hashes; see `evidence/PATCH_VERIFICATION.json`. File-level manifest and SHA256SUMS bind the packaged bytes. Drive upload readback is recorded separately after the completed uploads, not inferred from a local archive.
