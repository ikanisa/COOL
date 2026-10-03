The three existing fixture `require-await` findings are resolved. Only `supabase/functions/prepare-roster-import/handler_test.ts` changed, from SHA `572d7d8b00ba433a4733ad452a2808f0e5d68c32d8f8804694ae717d2ce8222b` to the exact reviewed SHA `c4e75c3d2d75056ed05c57e5e85d0ff07253422549778d434ccd76594b3fbe8d`. The prior proposal report remains in `README.md` as its preparation-stage record; this document records the applied result.

The shared source was still the reviewed base before application. All 18 current source inputs then matched the privately passing candidate exactly, with only this test file differing from the original cohort. `application.json` records the comparison and source snapshots are retained under `before/` and `after/`.

The private helper invokes the three fixture bodies synchronously and converts thrown errors to Promise rejections. Existing event/assertion/state order, every return/error predicate, all test cases, and the internal/outbound PDF filename assertions remain intact. Decoder fixture awaits are untouched. Formatting-only braces and assertion wrapping are explicitly recorded in the proposal comparison. No artificial await, delayed `.then`, lint exclusion, test prewarm, skipped case or exception suppression was added.

Actual current-source checks used pinned Deno 2.5.6 and the unchanged frozen lock, with cached-only dependency resolution and no runtime network/environment/read/run permissions. Four maintained entries cover helper requests, strict response handling, real synthetic import handler behavior, and extraction evaluation. Each of the following completed with exit code 0:

| Check | Actual result |
| --- | --- |
| Frozen cached-only type compilation (`deno test --no-run`) | PASS |
| Affected regression cohort | 109 passed, 0 failed |
| Default lint, helper + helper tests + handler tests | PASS |
| Formatting, all three files | PASS |

`applied-verification.json` retains exact commands, timestamps and before/after hashes. Original stdout/stderr are stored for every phase. All 18 current inputs, the 18 private comparison inputs, the Deno binary, executed verifier, and 87 cached remote sources stayed identical throughout. There were no live provider or database calls.

The sealed filename-minimization packet's 77 indexed leaves and read-only AI review's 9 indexed leaves were independently rehashed again after this application. Their batch/index hashes and original failure evidence remain unchanged. In particular, the previous packet's full three-file lint failure is still the truthful historical result; this new packet supplies the subsequent corrected lint proof. The preparation script's too-strict dedented-byte comparison failure is retained with its original executed script and explicit correction.

This closes only the three test-fixture lint findings. Production/helper behavior remains the approved filename-minimization implementation. Admin disclosure, processor/project/region/retention acceptance, material input minimization, real extraction accuracy/spend controls, native/hosted acceptance, complete BE-13 and production readiness remain open. No product source, provider policy, Admin, SQL, legal, lock, model, endpoint or quota changes were made in this fixture slice.
