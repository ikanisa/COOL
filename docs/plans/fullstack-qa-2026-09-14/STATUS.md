# Collect full-stack QA status

Updated: 14 September 2026.

Plan: [PLAN.md](PLAN.md). Work ledger: [work-items.csv](work-items.csv).

Overall state: execution is active. QA runner and CI repairs, initial technical
tests, route inventory reconciliation and focused regressions have been
completed locally. P0, P1, P2 and P8 remain in progress. Full-system QA and
mobile acceptance are incomplete. See [REPORT.md](REPORT.md),
[findings.csv](findings.csv), [scope.csv](scope.csv) and [results.json](results.json).

Goal task ID: `01a0a06a-73fb-7c23-81a6-36149a29e347`. The goal executes all nine phases of PLAN.md, tracks the 25 work items, fixes confirmed in-scope defects and produces current acceptance evidence. No token budget was specified. Goal creation is not completion of the review.

## Current evidence

- HEAD: `caafcef15f83de9baae84c377e1a99bb49ed6920`; existing branch: `codex/recovered-pro-g40-2026-09-10`.
- `git fsck --full --no-dangling`: exit 0. All 1,464 tracked files were readable.
- Existing `.vscode/settings.json` modification is preserved.
- Initial inventory: 73 Flutter test files, 12 integration test files, 124 local migrations, 11 Edge Function entry points and 11 Edge test files. A router-inventory regression test file was subsequently added. These are file counts, not passed-test counts.
- Revolut skill bundle verifier passed. External collection integrity and implementation fidelity are separate.
- Mobile contract is valid. Ten exact original references were restored to ignored paths after hash/dimension verification. Android and iOS remain blocked; absent release provenance prevents complete case evaluation. The governed inventory currently derives 135 cases per platform, with zero recorded acceptance cases. This is not yet a complete all-state coverage denominator.
- The missing CI evidence-consistency target is implemented. Formatting checks no longer write files or traverse ignored generated dependencies. The aggregate runner enforces both full mobile gates and reports fixture results as unverified. Regression tests cover these controls.
- The mobile adapter now requires separate implementer, independent visual and owner records and four separately evidenced quality results. All 49 gate tests pass locally. The real acceptance file is unchanged and blocked.
- Initial Flutter baseline: 758 passed and 7 failed. Test/tooling defects, an additional stale asset-count assertion and an order-dependent shared test cache were repaired. Two photo-only golden changes were visually reviewed against the selected comparator; only those baselines were refreshed. The full checkpoint run now passes all 767 tests with seed 20260914 and four workers, with no skips or changed source inputs. Coverage is 11,863 / 17,005 lines (69.76%).
- Flutter analysis, formatting and source hygiene pass. All 54 Deno tests and all 38 Edge TypeScript file checks pass using pinned Deno 2.5.6. Notification MCP type checking and 30 tests pass. Twenty further script test files pass 81 tests and 344 assertions. CI coverage for the MCP package is added; hosted runs for the baseline were blocked before starting by an account billing lock, and these changes have not run there.
- The line-coverage gate now counts each executed source line once and rejects missing evidence; its 40% threshold is unchanged. Six existing files exceed CI's separate 1,200-line limit. The latest remote main contains two newer commits, including overlapping QA and product fixes; reconciliation is in progress while preserving the design instructions supplied in this task.
- Scope export contains 324 platform/entrypoint rows, including 38 actual member paths, 24 Admin paths, nine public paths, 124 migrations, 11 Edge entries and nine MCP tools. The previously omitted `/groups/join` alias now has route catalog and native-test coverage. Roles, overlays, states and dependency mapping remain incomplete.
- Website app screenshots need recapturing: their current runtime fingerprint does not match. Updating the asset byte inventory does not change this failed freshness result.
- Approximately 2.2 GiB was available at discovery. Removing two verified-unused Collect Xcode intermediate caches increased measured free space from 2.57 to 4.30 GiB. Large native-build capacity is still unresolved. Docker is installed but not running; no physical Android device is connected, and no iOS simulator is booted.

## Milestones

| Phase | State | Next action |
| --- | --- | --- |
| P0 — Trustworthy QA execution | in_progress | Complete script/CI discovery and native/database capacity planning |
| P1 — Complete coverage map | in_progress | Extend the generated route map with overlays, roles, states, APIs and comparator mapping |
| P2 — Technical/security baseline | in_progress | Finish post-repair Flutter regression, remaining script tests and runtime security cases |
| P3 — Backend/financial correctness | pending | Establish isolated database and execute invariant/concurrency cases |
| P4 — Android/iOS member journeys | pending | Build current isolated native candidates and execute the expanded matrix |
| P5 — Admin/PWA workflows | pending | Bind route/permission fixtures and browser/installed platform matrix |
| P6 — Public website | in_progress | Recapture current native app media, then run static and rendered website checks |
| P7 — Resilience/performance/operations | pending | Establish named environments, budgets and failure scenarios |
| P8 — Remediation/regression/acceptance | in_progress | Continue reproduced-defect repairs; exact native proof and real reviews remain outstanding |

No production deployment, production migration, external message, store
submission, signed-in device reset or release approval has been performed.
Raw checkpoint evidence is under `.cache/fullstack-qa/20260914T151002Z/`.
