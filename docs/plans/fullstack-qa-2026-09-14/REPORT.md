# Collect full-stack QA checkpoint

14 September 2026. **Review and execution goal remain in progress. No system
or mobile release acceptance is claimed.**

The [plan](PLAN.md) was saved before the execution goal was created in this
task. [STATUS.md](STATUS.md), [work-items.csv](work-items.csv),
[findings.csv](findings.csv) and [results.json](results.json) track execution.
Current scope export: [scope.csv](scope.csv), [scope-summary.json](scope-summary.json).

Latest local checkpoint after upstream reconciliation: **768 Flutter tests
passed, zero failures or skips; 69.84% measured line coverage; clean analysis**.
Source hygiene, 69 gate/tooling tests and 81 further script tests pass.
The scope-format and one test-format correction were verified separately
after that run; product source is unchanged. Full-system QA remains open.

## Verified local work

- The restored checkout passed Git integrity and tracked-file readability
  checks. The user's `.vscode/settings.json` change is preserved.
- QA infrastructure now uses a non-writing formatter over owned source,
  distinguishes fixture records from product passes and enforces both full
  mobile design gates in aggregate QA. The missing CI evidence-consistency
  target is implemented against the current contract.
- The mobile adapter now enforces separate bound implementer, independent
  visual and owner reviews, plus distinct usability, accessibility,
  performance and resilience results. Its 49 tests and 265 assertions pass.
  No actual approval was written.
- The actual member router and Admin router were compared with their
  catalogs. The omitted `/groups/join` compatibility alias now appears in
  the route catalog and native route matrix with its existing redirect.
  The current governed mobile inventory derives 135 cases per platform.
  Coverage of all material states, roles and dependencies is still incomplete.
- The initial Flutter baseline had 758 passes and seven failures. Repairs
  addressed the obsolete contract-path assertion, two lazy-scroll test
  failures, photo-only golden drift and the asset inventory. The subsequent
  full run had 766 passes and one failure: an obsolete fixed asset count.
  Exact inventory and hash validation were retained when that count was removed.
- CI-style random ordering exposed a further profile test isolation defect.
  The test now owns its offline cache key and checks persisted account data.
  All 47 tests in that file pass with both seeds `20260914` and `314159`.
  The full checkpoint rerun passes **767 tests, zero failures and zero skips**
  with four workers and seed `20260914`. Analysis, format and QA tooling checks
  pass on unchanged recorded source inputs.
- Pinned Deno 2.5.6 passed all 54 tests and type checking for all 38 TypeScript
  files across 11 Edge entrypoints. Notification MCP type checking and all
  30 tests pass locally. Twenty additional script test files passed 81 tests
  and 344 assertions using pure functions, mocks or temporary fake native tools.
  Those tests did not perform hosted cutovers, recovery restores or messages.
- CI's coverage calculation now counts covered source lines once instead of
  adding execution counts; missing or invalid data fails. Five regression
  tests pass. The first corrected measured result was 11,863 / 17,005 lines
  (69.76%), above the unchanged 40% threshold, from a run with one test failure.
  The subsequent passing 767-test checkpoint has the same 69.76% coverage.
- Ten original mobile reference images were restored byte-for-byte to their
  ignored governed paths after hash/dimension checks. Two existing website
  captures and the Home/Groups golden changes received implementing-agent
  visual review; see [VISUAL_CHECKPOINT.md](VISUAL_CHECKPOINT.md).

## Outstanding work and evidence limits

The initial local source was based on `caafcef15f83de9baae84c377e1a99bb49ed6920`.
Upstream `7be12232` was reconciled in local merge `dfc2a526`, preserving the
current task's design authority and the user's settings. See
[SOURCE_RECONCILIATION.md](SOURCE_RECONCILIATION.md). The reconciled run passed
768 tests and covered 11,876 / 17,005 source lines (69.84%).
Raw command logs and source manifests are retained under
`.cache/fullstack-qa/20260914T151002Z/`. Source-bound checkpoint runs record
unchanged input hashes after execution. Earlier diagnostics remain baseline
evidence and are not retroactively labelled final-source results.

Six source files exceed the existing CI 1,200-line limit. That gate has not
been lowered or bypassed. Hosted CI for the base commit did not start normal
job steps: GitHub's annotations report an account lock due to a billing issue.
That hosted prerequisite needs account-owner action. The latest inspected `main`
had two newer commits, including product and overlapping QA repairs, which
are now reconciled locally. The latest inspected main CI run also reports the
billing lock. Local changes have not run in hosted CI.
Adding a CI job is implementation evidence only.

Native build and disposable database capacity is unresolved. Two identified,
unused Collect Xcode intermediate directories were removed, initially raising
free space to 4.30 GiB. The latest measurement dropped to approximately
2.27 GiB; the shared host's free space changes during other work. Docker is
installed but stopped. No physical Android device is connected. Available
iOS 26.5 simulators are shut down; this task has not erased or reused their
account data. Chrome 152.0.7977.84 and Safari 26.6.2 are installed.

Website app screenshots fail the current runtime-freshness check and require
recapture. All four Groups navigation items are present in the original PNG;
the apparent missing icons in a reduced preview were a false positive.
No freshness hash was rewritten to bypass the required capture.

Android and iOS design acceptance remain blocked. Current release artifacts,
installation/readback proof, comprehensive case evidence, native reader/device
checks and actual independent/owner decisions are missing. Initial gate
failure counts were truncated by absent build provenance and are not complete
counts of visual defects. Backend replay, runtime security, financial
concurrency, provider integration, Admin/PWA/browser tasks, public routes and
performance/resilience coverage remain to be executed or expanded.

## Readiness distinctions

| Area | Current conclusion |
| --- | --- |
| Local technical tests | 768 Flutter tests pass on reconciled source; analysis, format and hygiene pass; remaining command inventory and runtime UAT incomplete |
| Backend correctness/security | Local Edge checks pass; database replay, RLS/RPC abuse, financial concurrency and live drift are unverified |
| Android / iOS fidelity | Both blocked; zero accepted native case records; no 100% match claim |
| Task usability / accessibility | Focused widgets pass; complete native and browser task traversal unverified |
| Performance / resilience | Coverage measurement is not performance; declared device/server measurements and failure recovery remain pending |
| Admin / installed PWA / public web | Source scope and widget evidence only; full route/role/platform review pending; public media stale |
| Builds / hosted CI / deployment | Native builds pending; hosted CI not validated for these changes; no deployment performed |
| Physical devices / providers / stores | Unverified; no provider settlement, distribution or store approval claimed |
| Independent review / owner acceptance | Not obtained or fabricated |

The next steps are source-size CI repairs, remaining coverage mapping and
isolated database/native target preparation, followed by actual end-to-end
tasks and remediation under the plan. The goal remains active.
