# Final deployment and source-control checks

`operations-final-tests-result.json` was produced by actual execution after the
gateway25 bytes, provider separation, current migration guards and frontend
input boundaries were fixed. It captures the full backend source inventory,
additional tested source/workflow inputs, exact command arrays, exit status,
elapsed time and private log hashes. The same input snapshot was read back after
all commands; parity passed. This is local qualification, with no full Docker
stack or real-provider acceptance claim.

| Executed check | Result |
| --- | --- |
| `scripts.self_hosted.test_operations` | 14 tests passed, including actual age encryption/decryption/corruption refusal, migration envelopes, host/provider configuration, recovery extraction boundaries, current health fields and frontend-source inventory. |
| Six Node deployment/profile test files | TAP reports33 tests,33 passes,0 failures/skips. This includes the full Auth proxy, generated key behavior, web/worker credential separation and job/profile boundaries. |
| CI workflow/Make policy negative tests | 46 passed. Current native/Dart evidence, exact source selection, immutable action/toolchain boundaries and private-artifact exclusion cannot be omitted, masked or redirected. |
| Actual current CI policy inspection | Passed with no findings; hosted enforcement/execution remains explicitly false. |
| `make revolut-design-authority` | Passed authority hygiene; no visual-fidelity or golden-test acceptance claimed. |
| Frozen Deno entrypoint check | All six functions checked: member API, Admin API, main jobs, email jobs, gateway and signed SMS hook. |

The earlier `operations-tests-result.json` is a preliminary local summary. It
was not an execution-bound final-source receipt and must not substitute for the
new final record. Earlier24-migration native receipts and the failed installer
attempt retain their original scope.

An additional current-source guard exposed the historical fixture loader's
hard-coded24-migration digest branch. The corrected loader compares the exact
reviewed current list and verifies every additive digest. Its existing tamper
test then passed together with the current-native and actual-history guards;
the failing preflight happened before any native database mutation. Historical
profiles still apply only their selected prefixes.

The root run does not substitute for the complete Flutter suite, authenticated
Admin journeys, a signed Android artifact, real provider tests, recovery or
independent CI. Those outcomes remain separately recorded.
