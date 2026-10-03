# ARC-04 clean-cache Edge acceptance

Attempt3 completed at 2026-10-01T21:00:32.979914+00:00 with exit 0. Its output was already terminal after the interrupted turn; current readback verified the completion and there was no rerun. The maintained recipe executed from an exact private 134-file source copy with a genuinely empty Deno dependency cache. Every captured source hash still matches the current canonical closure.

Deno 2.5.6 and the unchanged nested frozen lock were enforced during cache resolution, compile and actual test execution. The Linux phase ran the actual decoder on native Linux ARM64 with Python 3.12.14 and hash-locked dependencies. Docker build layer reuse was permitted; the empty-cache claim is specifically about Deno dependencies, not Docker layers or host tools.

| Evidence | Result |
| --- | --- |
| Type checking | 83 files passed |
| Unit cohort | 31 files, 561 tests and 32 nested steps passed; zero failures or ignored |
| Completion and fixture contracts | 13 tests passed |
| Actual HTTP entrypoints | 91 checks passed, all 12 configured/source/literal loader names equal; each started once |
| Actual Linux decoder | 32 cases passed |
| Linux Deno integration | 14 tests passed; zero failed or ignored |
| Linux regression cohort | 155 tests passed; zero failed or ignored |
| Corrupted-lock negative | Actual runtime exit 10 before tests; valid copy's 3 existing tests pass |

The suites overlap in some consumers; the table must not be summed into a count of unique product behaviors. HTTP runtime permissions permit loopback only and explicitly deny provider endpoints. Thirteen fixture/completion tests reject replaced observations/generators/manifests, symlinks, missing/empty/malformed/ambiguous summaries, and failed or ignored nested steps. Existing permissions and assertions were retained. No fake import, dependency remapping or test omission was introduced.

The current runner explicitly includes the maintained Play Integrity actual-handler test. Literal imports expose all 12 actual handler closures to frozen cache resolution and type checking. Parity is checked against actual config and source directory entrypoints before execution. All 14 owned HTTP listeners closed; the unique decoder container was removed and its absence read back.

Both failures remain recorded. Attempt1 rejected a real nested-step completion line that its former parser did not understand. Attempt2 correctly failed cached-only execution when computed imports left iceberg-js outside the pre-resolved graph. Attempt3 followed the narrow parser and literal-entrypoint repairs and completed every mandatory phase. Historical preparation/closure-plan files remain dated pre-execution records and do not override attempt3's 134-file/83-type closure.

The SQL decoder packet is an immutable generated dated synthetic observation with its original generator, migrations and completed receipt bound by hashes. It is explained fixture evidence, not current SQL installation or hosted persistence. Provider calls were zero. Hosted GitHub execution, real Auth/platform JWT behavior, SQL/RLS, provider delivery/accuracy and the parent-owned global immutable candidate and release authority remain separate.

The dated [batch.json](batch.json), [current readback](current-readback.json), [completed canonical attempt](attempt3/canonical-batch.json), [canonical validation](attempt3/acceptance/validation.json) and [corrupted-lock probe](lock-probe.json) bind the results and source hashes. Canonical validation SHA-256: `c571eaa9660dc83fac31522b613c3874d0eb043a1ce5d60e91a7174e3ba511c5`.
