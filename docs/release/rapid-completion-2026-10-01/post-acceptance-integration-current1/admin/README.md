# Final integrated Admin and browser/PWA verification

## Accepted local scope

[Final receipt](browser-acceptance.json): **PASS**, 89 named browser checks and 56 route states (28 signed out; 28 synthetic approved email owner). Email sign-in, tab isolation, reload denial, exact departed-session logout, A→B→A, Public/Admin separation, static cache privacy, warm/failed updates, offline sign-out and actual installed-PWA offline launch passed.

The final immutable candidate has **2,175 files / 187 migrations**. Candidate manifest: `24b1719665694a2f09b18ee78e8cf6d4e33f416a5fd0c42edd747f0f22867a6a`. [Inputs](browser-inputs.json) bind the strict current2 export and the other owner's **657/657 affected cases across 19 suites**, with 295 candidate source bindings and separately verified external proof/dependency inputs. Those VM suites were reused; this lane ran no VM or SQL suite.

[Source guard](executed-consumers.json) has **632** declared runtime/script entries. It records source bindings and unchanged before/after bytes; it does not establish that every source file or feature was executed. Exact behavior is identified by the 89 named checks in [the actual report](browser-evidence/report.json). Route records use login, synthetic empty, unavailable or permission-denied states. Joined-history/inbox-v2 positive browser scenarios remain outside this run; their affected SDK/widget and SQL receipts are separate.

## Actual build and causal recovery sequence

1. Session **48445**, exit **1**: original build blocked while the original font-subset engine wrote stdout. [Original terminal](original-command-terminal.json), [sample](font-subset-observation.txt), SDK excerpt and original logs remain preserved. No browser started.
2. Session **62990**, exit **1**: both actual Admin and Public production build commands passed after the approved private I/O correction. All 56 route states and 69 checks passed, then the driver timed out while re-entering email after reload. [Report and captures](corrected-build-browser-failure/report.json) remain unchanged.
3. Session **26520**, exit **0**: a private focus-corrected retained-bundle continuation passed **89/89**. Both built bundles were copied and hash-checked against step 2. **No third Admin or Public build ran.** [Terminal](continuation-command-terminal.json), [private harness patch](private-focus-and-retained-public.patch), [admission](private-harness-admission.json).

There were **two Admin build attempts and one successful final artifact**. `production_admin_build_executed_once` refers to that single successful final artifact; `production_admin_build_attempts` is explicitly `2`.

[Private SDK admission](private-sdk-admission.json) retains the exact original engine binary separately from the I/O wrapper. The reader drains all original stdout concurrently, retaining a bounded 65,536-byte prefix plus total count/SHA; original stdin, arguments, stderr, font outputs and genuine exit status are preserved. All three actual engine executions exited zero and drained fully. The original cached SDK is unchanged. The original sample proves a blocked write and the SDK's exit-before-drain ordering; it does not measure the original unread byte count.

The private driver brings the actual page forward, pointer-clicks the current named field and waits two animation frames before typing. The original native geometry and exact value assertions remain and now require document focus. No JavaScript value injection, fake acknowledgement, application change or weakened selector assertion was used.

## Portable artifacts and integrity

- [Artifact manifest](artifact-manifest.json): **154 Admin files / 53 Public files**, copied byte-identically into `artifacts/admin-build/` and `artifacts/public-build/`.
- [Declared SDK inputs](browser-sdk-prepared.json), [private SDK](browser-private-sdk-inputs.json), [168 dependency packages](browser-packages-prepared.json), [85 browser tool inputs](browser-tool-inputs.json), [wrapper interpreter](wrapper-runtime-inputs.json): no drift.
- Command logs and current captures are in `browser-evidence/`; earlier failures are in `original-build-failure/` and `corrected-build-browser-failure/`.
- A packaging-only first attempt used the wrong directory for reused command logs; its failure is retained. The accepted packager resolves exact `reused_from` origins, verifies the original hashes and copies those original logs. It restarted no test, build or browser.
- [Live readback](live-executed-source-readback.json) is separate from acceptance of the immutable candidate.
- `SHA256SUMS.json` seals every owned packet file except itself, including the portable artifacts.

No database, hosted or provider calls, real email delivery, physical-device acceptance, new native build or Revolut visual-fidelity certification are claimed.
