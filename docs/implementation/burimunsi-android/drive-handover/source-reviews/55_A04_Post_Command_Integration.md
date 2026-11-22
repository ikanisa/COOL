# A04.2 — command outcome and presentation integration

Source candidate: **0.20.0-a04.2**, 9 November 2026. Parent: **0.20.0-a04.1**.

## Finding and reproduction

The A04.1 repository had already protected original command identity, owner-bound recovery,
strict financial status, cache deletion and durable journal cleanup. Its separate controller
and repository suites did not execute both real classes in the same process. A new combined
host harness exposed six failures in fourteen checks against that exact parent runtime.

After a verified commit, optional record readback could fail before the controller removed
the old displayed payment, selected beneficiary and editing form. The historical reversed/
corrected result is deliberately thrown by the repository as a warning after journal cleanup;
the old controller caught it as an ordinary error without invalidating its financial views.
In the synthetic transport fixture, tapping the stale selection could therefore dispatch a
second operation. This demonstrates an unsafe client submission opportunity, **not** a proven
second PostgreSQL credit: canonical server authority/version checks were not executed here.
An uncertain response also left stale actionable presentation in place, even though the
pending journal correctly blocked a new financial command.

The original test source is preserved under `history/a04.2-baseline-tests/` as non-executable
`.source` provenance. Its receipt binds all compilation inputs and the historical log digest.
Reproduce it against the unchanged delivered parent archive:

```sh
python3 scripts/reproduce_a04_baseline.py \
  --parent-archive /path/to/BuriMunsi_Complete_Source_v0.20.0-a04.1.zip \
  --output ../A04.1_reproduction_new
```

The historical test exits 1 with six expected failures. The wrapper exits 0 **only when that
expected failure is reproduced**; it does not mean the old candidate passed.

## Implemented correction

`BuriViewModel.command()` now invalidates in-memory records, navigation record snapshots,
consumed sheets, beneficiary/staff selections, draft state and pending export callbacks
before any post-command record read. This helper is used by allocation, enrollment,
staff creation/edit/actions and membership changes. It does not touch the durable journal,
receiving queue or financial authority.

For uncertain outcomes, a read-only journal check determines whether the pending evidence
still blocks another command. A storage-read failure fails closed. The original journal
is preserved; it is not reset, rebound, deleted or resubmitted by presentation recovery.
A definitive initial rejection retains the unsent draft and creates no commitment notice.

Read-only recovery now clears consumed presentation **before** refreshing records, rather
than only clearing the internal panel stack. A separate `commandNotice` records the already
verified outcome independently of a later network/record-read error. Confirmed and reversed/
corrected outcomes remain visible during failed or repeated refreshes. The notice is rendered
through the localized UI mapping and a polite accessibility live region. It is **session-only**,
not a persisted financial receipt; logout and reconstructed screens do not inherit it.
The new Kinyarwanda phrase remains subject to fluent operator review.

## Executable overlapping-workstream coverage

`native/burimunsi/scripts/verify_cross_layer.sh` compiles the actual controller, repository,
DTO decoder, journal, operation store and core together. Only Android platform glue, storage,
transport and JSON implementation are synthetic. The suite contains 63 checks covering:

- Successful commits with failed post-command refresh; consumed form removal; no reuse of
  the old selection; completed notice versus readback failure.
- Lost acknowledgements; pending/denied/conflicting/unsupported proofs; exact journal
  retention; read-only recovery; reversed and corrected outcomes and persistent warnings.
- Retained record-cache deletion and retained journal deletion; cleanup recovery without a
  second POST; unchanged synthetic receiving evidence.
- Same-owner token rotation with immutable original digest; changed-owner refusal before
  either status call; session expiry during the second proof read without screen resurrection.
- Enrollment, staff creation/disable and membership operations with nonfinancial status
  validation and a failing optional refresh; definitive rejection preserving the draft.

The suite is wired into `verify_all.sh`, hence into the source-bound A04 regression runner.
The original repository and authority code is byte-identical to A04.1. No backend, SQL,
receiver logic or pinned Android dependency has been changed in this continuation.

## Version, merge and import traceability

VersionName is `0.20.0-a04.2`, with Android versionCode advanced from 20 to 21. This is source
metadata only: no APK is claimed. `a04-merge-ledger.json` continues to account for all seven
original workstreams, preserving any original input bytes displaced by this continuation.
`a04-continuation-ledger.json` accounts for every parent file, every added path and zero
removed files. Changed parent bytes remain in content-addressed non-executable provenance.
Metadata hash-recursion exceptions are explicit and bound by the complete file manifest.

The importer recognizes exact A04.1 runtime/support hashes in addition to the original seven
branches. Unknown local edits still abort. Its actual-checkout apply step is not executed.
The revised import manifest also carries the combined harness so the installed overlay can
run the same host checks. The source package and exact patch are alternatives, not layers to
apply over arbitrary unverified working files.

## Acceptance boundary

Local tests are host/source evidence only. They do not verify Android Compose rendering,
TalkBack behavior, process death or Keystore durability; actual carrier/SIM behavior; hosted
canonical APIs; Cloudflare configuration; or PostgreSQL atomicity/idempotency. No genuine
financial instruction was submitted. The actual Collect checkout was not changed. Production
promotion and receiving uploads remain blocked pending their existing external requirements.

### Existing restoration test migration

The full regression found the two inherited reversed/corrected restoration assertions still checking the generic read-error field. They now require the independent command notice, a clear read-error field after successful refresh, and an unchanged mutation count. This intentionally follows the new outcome/read-error separation; neither warning visibility nor the no-POST invariant was relaxed.
