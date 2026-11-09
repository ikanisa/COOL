# SMS queue, classification and retry policies — R2

**BuriMunsi / M-Money · 9 November 2026**

This delivery implements a shared, Android-independent Kotlin policy engine, separate BuriMunsi and M-Money classifier adapters, synthetic fixtures, deterministic queue tests, a fault-injected persistence port, and an additive source installer. It is an executable source workstream, not an installed application or a carrier qualification.

The original BuriMunsi SMS-R1 and M-Money v0.2.11 SMS source dependencies are pinned byte-for-byte in `vendor/PROVENANCE.json`. They are the inspected inputs for this workstream, not a declaration that these are the newest consolidated application versions. This package does not overwrite canonical v0.19, owner-bound recovery, UI, financial, operations or other concurrent workstreams.

## Implemented

| Policy | Result |
|---|---|
| Classification | BuriMunsi delegates to its pinned exact receipt grammar. M-Money retains its separate candidate-screening contract with stricter amount-literal, transaction-reference, Unicode/control and multi-statement rejection. Candidate screening is not a financial fact or permission to post money. |
| Evidence and multipart representation | Original parts and their order are defensively copied. Assembled text is derived without changing the originals. Missing, repeated, mixed, unsupported or ambiguous parts cannot become a complete live receipt. Provider text never claims original-PDU completeness. |
| Duplicate admission | Exact capture replays retain the first original; reused identities with changed evidence are conflicts. M-Money additionally follows its exact source/body duplicate rule. Capacity and live-capture reserve never evict retained evidence. |
| Queue transitions | Immutable original batches, original operation IDs, revision-based compare-and-set, explicit in-flight/uncertain/held/conflict/acknowledgement states, and two-step acknowledgement persistence. |
| Acknowledgements | Strict Collect v2 owner/capture/body-hash checks; separate M-Money v1 whole-batch coverage and typed status checks. M-Money v1 does not echo an owner, generation or body hash; frozen-request and local-session fencing are mandatory. |
| Retry limits | Five dispatch reservations including the initial attempt by default. Delays start at one second, double to a sixty-second cap, and stop at the attempt or twenty-four-hour age limit. Valid server delay is a lower bound, not shortened by the backoff cap. Exhaustion retains uncertain evidence. |
| Binding and SIM decisions | Missing/default/invalid subscription IDs, denied permission, unknown active subscriptions, changed binding, owner, installation or generation cannot authorize dispatch. A known other SIM is excluded, not guessed to be the bound SIM. |
| Persistence failures | Failed, indeterminate, thrown and conflicting writes never release a new send effect. Missing or corrupt storage is not silently recreated. A successfully staged acknowledgement survives interrupted finalization. |

The retry values above are engineering defaults, not carrier-prescribed limits. `RetryLimits` is configurable, and its boundaries are tested. Transport retries replay the **same original SMS ingestion request**, never a new financial operation.

## Reproduce the checks

Prerequisites: Python 3.10+, Kotlin/JVM 1.9+ and Java 17+. The supplied host run records the actual versions used. No external packages or network downloads are required.

```sh
cd SMS_Policies_R2
python3 scripts/verify.py --output /tmp/sms-policies-r2-verification
```

The output directory must not already exist. The command records compile/runtime exit codes, complete logs, test results, every test input hash and an aggregate source-set digest. Missing Kotlin/Java prerequisites produce `blocked` and exit code 2, never `passed`. Failed checks produce exit code 1. Exit code 0 means only that the requested **local host suites** passed; external acceptance remains blocked in the same JSON report. Add `--require-external` to keep the command nonzero while those gates are open.

The runner executes the new policy suite, Python delivery tests, and four pinned inherited suites: BuriMunsi core, receiver policies, host file/process reliability, and M-Money SMS input contracts. Their counts and scopes remain separate in `evidence/verification.json`.

## Source installation

The additive installer accepts a **native project root**, not an arbitrary repository root. It checks all pinned core dependency hashes and refuses unknown baseline edits or destination collisions.

```sh
# Inspection only: no files are written.
python3 scripts/install_overlay.py --application burimunsi --target /path/to/native/burimunsi
python3 scripts/install_overlay.py --application mmoney --target /path/to/M-Money_Native_Android

# Explicitly add the same sources after inspecting the plan.
python3 scripts/install_overlay.py --application burimunsi --target /path/to/native/burimunsi --apply
python3 scripts/install_overlay.py --application mmoney --target /path/to/M-Money_Native_Android --apply
```

Repeat application of identical sources is a no-op. The installer does not change workers, database schemas, manifests, Gradle configuration, authentication, financial authority or upload admission. It requires exclusive checkout access; it is not a security boundary against a malicious concurrent filesystem actor. An interrupted partial write is retained and causes a mismatch refusal on the next run.

**A differing consolidated baseline must be reconciled deliberately, not forced through these hash checks.** `docs/INTEGRATION.md` identifies the runtime work still required.

## What is not claimed

The new queue engine is **not wired into either Android application's production workers or durable storage** in this delivery. `QueueStorePort` is an integration contract, not a Room/Keystore implementation; the new fault store exists only in tests. The classifier adapters execute real pinned core policies, but they do not implement Android broadcast/PDU decoding. A platform adapter must establish that decoded metadata and text correspond to the supplied original PDUs.

No APK, installed-screen acceptance, handset storage durability, real carrier delivery, server idempotency, PostgreSQL commit behavior, pairing, token rotation, migration or deployment is established by these tests. Existing BuriMunsi upload admission remains disabled. The supplied `/Volumes/PRO-G40/.../efficient-codex/SKILL.md` path was not mounted in this runtime and was not used.

## Package map

`src/main/kotlin/` contains the shared policy engine; `src/adapters/` holds the two application-specific classifiers. `tests/` and `fixtures/` contain synthetic executable evidence. `vendor/` contains unchanged dependencies and source provenance. `scripts/` supplies verification and additive installation. `docs/` describes integration, merge decisions and coverage. `evidence/` contains the fresh measured run. `SOURCE_MANIFEST.json` and `SHA256SUMS.txt` inventory the delivered bytes.
