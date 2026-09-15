# Collect full-stack QA checkpoint

15 September 2026 (Africa/Kigali). **Review and execution goal remain in progress. No system
or mobile release acceptance is claimed.**

The [plan](PLAN.md) was saved before the execution goal was created in this
task. [STATUS.md](STATUS.md), [work-items.csv](work-items.csv),
[findings.csv](findings.csv) and [results.json](results.json) track execution.
Current scope export: [scope.csv](scope.csv), [scope-summary.json](scope-summary.json).

The latest [notification bridge checkpoint](NOTIFICATION_BRIDGE_CHECKPOINT.md)
fixes FQA-044: malformed queue counts could falsely pass the actual stdio
preflight. Both paths now validate all aggregate counts before listing work.
TypeScript and **37 Node tests** pass, including nine real stdio/HTTP mappings,
invalid input, denied/redirected requests and a one-attempt 15-second timeout.
These fixtures use synthetic credentials and make no provider send.

FQA-045 is fixed locally: the photo dependency lockfile is now included by Git,
and six already-reviewed encoded photo hashes are added to the asset inventory.
Installation from exact staged package/lock blobs and encoding checks pass.
The original missing-lock and source-hygiene failures are retained; the
corrected source-hygiene gate and redacted fallback secret scan pass.
The user has authorized commit and push to main; this checkpoint precedes
remote publication and does not establish deployment or release acceptance.

The [public image delivery checkpoint](PUBLIC_IMAGE_DELIVERY_CHECKPOINT.md)
adds full-resolution WebP delivery with original PNG fallbacks. Six photographs
fall from **11,259,743 to 1,230,960 bytes**; original PNGs, dimensions, alpha and
colour profiles are preserved. Colour pixels are lossy. The final component
passes **30 route/width comparisons and 24 fallback/accessibility/failure-state
comparisons**. Initial layout and capture failures remain in the evidence.
Codex's visual review is separate from independent or owner acceptance.

Three local HTTP/2 component samples score **83/84/84 on mobile and 99/99/99
on desktop**, with median LCP 4.458 s and 0.847 s. FQA-042 remains open against
the unchanged score requirement of 90. The retained published HTTP/3 baseline
is mobile 78/77/70 and desktop 97/98/97, including the mobile outlier; these
are different targets and do not establish a deployed performance gain.
Field Core Web Vitals and complete route/workload performance remain unverified.

Final tooling passes **168 Ruby tests / 768 assertions and nine Python tests**
with **552 stable inputs**. Locked image encoding and syntax checks pass.
The actual full static build still refuses stale native screenshots and
preserves its output preflight sentinel. No validator was bypassed. The prior
completion gate remains NO-GO, with static 11/56 and live 35/36; missing privacy
links and external evidence remain open. FQA-041 and FQA-043 retain their
local evidence/reporting repairs. No deployment or acceptance was performed.

The [PWA lifecycle checkpoint](PWA_CHECKPOINT.md) repairs three service-worker
defects locally. The latest [offline investigation](PWA_OFFLINE_CHECKPOINT.md)
adds two network probes while retaining all earlier checks. The installed
Chrome/macOS run has **21 passing checks and one failing online-state indicator
check**. Actual browser network blocking before and after reload is now verified:
the healthy server receives no probe and Chromium reports
`ERR_INTERNET_DISCONNECTED`. A minimal page reproduces the indicator failure
without Flutter in ordinary and installed windows; an upstream maintainer
attributes this class of issue to Chromium. FQA-040 remains open and the suite
remains failed. No physical-device offline outcome is inferred.
Installation, standalone rendering, origin-outage cold launch, failed-update
recovery and reconnect retain their separate evidence. Real sessions/actions
and the full platform matrix remain open. Of the original 413 application inputs, 412 match; only the photo asset
inventory differs. All 154 fixture artifact files remain unchanged. All six earlier and three new
task-created installations and profiles were removed.

The earlier full application checkpoint passed **867 Flutter tests**, with zero
failures or skips, 74.65% measured line coverage and 615 unchanged recorded
source inputs. Final analysis, formatting, source hygiene and the unchanged
CI size limit pass. See the [Admin checkpoint](ADMIN_CHECKPOINT.md) for the
new recovery, queue-navigation and search-semantics work. The earlier
769-test source-size checkpoint and its declaration/catalog checks remain
in [SOURCE_SIZE_CHECKPOINT.md](SOURCE_SIZE_CHECKPOINT.md).

The [Edge HTTP and OTP checkpoint](EDGE_CHECKPOINT.md) passes **66 Edge HTTP
checks, 94 PostgREST checks and all 22 selected SQL suites on schema 126**.
It fixes FQA-035: ignored OTP counter errors and a count/insert race could
bypass the five-request limit. The handler now requires a service-only atomic
reservation; two actual PostgreSQL concurrency scenarios verify the limit.
The migration must precede the Edge function in any later deployment.
Nothing was deployed or migrated on a hosted target.

Edge handlers ran behind real local HTTP listeners with recording synthetic
Auth/PostgREST dependencies and denied provider network access. The separate
PostgREST suite used real SQL with synthetic JWT/session records. These are
complementary layers, not a complete real Auth-to-WhatsApp journey. Current
Deno checks pass 54 tests and 38 files; 45 focused Flutter contracts pass.

Schema 126 derives from 124 clean migrations plus separate bounded upgrades
to 125 and 126. The original fixture completed PostgreSQL shutdown with
container exit 0; all copies were removed and its volume retained. The pinned
advisor returns zero ERROR/WARN and 232 INFO; 94 direct-access checks for 47
policy-free RLS tables pass. Uninterrupted current replay, restore and workload
measurements remain open. Historical schema125/82-check HTTP evidence is
retained in [DATABASE_CHECKPOINT.md](DATABASE_CHECKPOINT.md) and
[API_CHECKPOINT.md](API_CHECKPOINT.md).

The [public website checkpoint](PUBLIC_WEBSITE_CHECKPOINT.md) corrects the
earlier scope export to 337 entries (now 338 with the new migration), including 21 actual static website entry cases.
It reproduces and locally repairs two headings that overflow at 320 px;
95 CSS-preview geometry cases and 48 published menu keyboard cases pass.
The stronger link check exposes four broken Privacy/Terms links to three
missing destinations, so the current live gate fails at 35/36 checks.
At that website checkpoint, the combined tooling run passed 51 QA tests/232 assertions,
49 mobile-gate tests/265 assertions and three generator tests. At that website checkpoint, all 603
recorded Flutter inputs were unchanged from the 769-test run.
No website deployment or full static-build acceptance is claimed.

The latest isolated Admin build passes 72 ready-route cases across all
24 routes at three widths, ten failure/Retry journeys and twenty
signed-out/denied/loading/empty cases. Its source has 413 stable build inputs
and 154 hashed artifact files. Two confirmed defects are fixed locally:
missing Retry controls and lost queue context after record navigation.
The duplicate/unnamed search field is repaired, but its unfocused DOM value
still requires actual reader investigation; four of five additional browser
search observations pass and that finding remains open. The full regression
includes 91 access/recovery and seven navigation/semantics tests. The new
[route dependency map](admin-route-dependencies.csv) is source discovery,
not proof of complete live role/action behavior or visual acceptance.


The [member/native coverage checkpoint](COVERAGE_CHECKPOINT.md) repairs
FQA-036. The gate now reads 43 route specs and 56 material-state specs, retains
all legacy requirements and applies the seven declared variants to every base
ID. **966 cases per platform retain all 135 earlier requirements**. Twenty-one
legacy base IDs still lack an exact harness mapping; all remain required and
unaccepted. The [route map](member-route-dependencies.csv) records all 38 member
templates with 228 platform/identity factory and guard observations. These
callbacks and lexical API candidates do not prove rendered journeys.

Retained framework checks pass **87 focused Flutter tests, 132 Ruby tests /
663 assertions and nine Python tests**, plus the recorded analysis, source
hygiene, packaging, contract and evidence checks. Of its 527 inputs, 521 now
match: Makefile, the static builder, three public QA scripts and the previously
exercised lifecycle probe differ. Current tooling passes 168 Ruby tests /
768 assertions and nine Python tests on 552 stable inputs. The preceding
529-input tooling run retains 527 matching inputs, with Makefile and the
builder changed. New delivery files are included in the current source record.
Since the full 867-test Flutter run, 609/615 inputs match: two CI files,
Makefile, the photo asset inventory and the PWA/route-inventory tests differ. Original assets, product
Dart and platform source are unchanged in this continuation. No Flutter or
coverage rerun is claimed. Native gates remain blocked with zero accepted cases.

## Verified local work

- The restored checkout passed Git integrity and tracked-file readability
  checks. The user's `.vscode/settings.json` change is preserved.
- QA infrastructure now uses a non-writing formatter over owned source,
  distinguishes fixture records from product passes and enforces both full
  mobile design gates in aggregate QA. The missing CI evidence-consistency
  target is implemented against the current contract.
- The mobile adapter now enforces separate bound implementer, independent
  visual and owner reviews, plus distinct usability, accessibility,
  performance and resilience results. Its current 57 tests and 298 assertions pass.
  No actual approval was written.
- The actual member router and Admin router were compared with their
  catalogs. The omitted `/groups/join` compatibility alias now appears in
  the route catalog and native route matrix with its existing redirect.
  The current governed mobile inventory derives 966 cases per platform,
  retaining all 135 previous requirements.
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
- The local Edge helper now discovers all nested tests and all TypeScript
  sources across eleven entrypoints, checks the `.dvmrc` runtime through PATH
  or `DENO_BIN`, checks all eleven explicit JWT settings and captures both
  passing and failing evidence with source/config hashes. Its current run
  passes all 54 tests and 38 file checks. Nine helper regressions pass with
  83 assertions. The historical deployment script keeps its exact five-function
  target set; all three existing contract tests pass. The first new helper
  attempt rejected Deno's valid stable-version metadata; that parser error was
  repaired and the failed attempt retained. No hosted function was invoked.
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

Six source files previously exceeded the CI 1,200-line limit. They were
separated into cohesive declarations and generated catalog family parts;
the exact CI step now passes without changing its limit or exemptions.
Hosted CI for the base commit did not start normal
job steps: GitHub's annotations report an account lock due to a billing issue.
That hosted prerequisite needs account-owner action. The latest inspected `main`
had two newer commits, including product and overlapping QA repairs, which
are now reconciled locally. The latest inspected main CI run also reports the
billing lock. Local changes have not run in hosted CI.
Adding a CI job is implementation evidence only.

Native build capacity remains unresolved. After earlier ENOSPC and limited,
verified cache cleanup, shared disk space recovered independently, permitting
several isolated Admin builds. It fell below 1 GiB again, and one final build
stopped at the unchanged 3 GiB preflight. A separate retained attempt passed
after another recovery. This does not establish stable native matrix capacity;
the healthy output-location request remains open. Latest shared free space was
1.036 GiB at 00:15 UTC. Source, goldens, coverage
and raw evidence are preserved.

The exact owned database restarted with its pristine synthetic baseline and
scheduled/network workers disabled. All 21 SQL copies and both committed-race
copies were removed. A Docker stop returned container exit 137; recovery and a
focused financial regression then passed. PostgreSQL's own shutdown command
produced a completed-shutdown log and container exit 0. The volume is retained.
Earlier timeouts and the failed stop remain in evidence. Other project
processes and containers were not stopped or removed.
At the last device inventory, no physical Android device was connected and
available iOS 26.5 simulators were shut down; this task has not erased or reused
their account data. Chrome 152.0.7977.84 and Safari 26.6.2 were installed.

Website app screenshots fail the current runtime-freshness check and require
recapture. All four Groups navigation items are present in the original PNG;
the apparent missing icons in a reduced preview were a false positive.
No freshness hash was rewritten to bypass the required capture.

Android and iOS design acceptance remain blocked. Current release artifacts,
installation/readback proof, comprehensive case evidence, native reader/device
checks and actual independent/owner decisions are missing. Initial gate
failure counts were truncated by absent build provenance and are not complete
counts of visual defects. Current uninterrupted database replay, supported
upgrades, complete integrated Auth/Edge security, broader financial concurrency,
provider integration, Admin/PWA/browser tasks, remaining public
interactions, accessibility and performance/resilience coverage remain to be
executed or expanded.

## Readiness distinctions

| Area | Current conclusion |
| --- | --- |
| Local technical tests | Prior full run:867 Flutter passes; retained focused checks:87 passes. Retained Deno54 tests/38 checks and current Ruby 168 / Python 9 tooling pass. Full command/runtime coverage remains incomplete |
| Backend correctness/security | Schema126:22 SQL suites,94 PostgREST checks,66 Edge HTTP checks,two OTP races and pinned advisors pass. Earlier financial races retained. Integrated Auth/provider flow, uninterrupted replay, wider concurrency, performance and live drift remain incomplete |
| Android / iOS fidelity | Both blocked; 966 required cases per platform and zero accepted native records; no 100% match claim |
| Task usability / accessibility | Focused widgets, 48 public-menu keyboard cases, 30 public photo layout comparisons, 24 synthetic photo states and named Admin queue controls pass; unfocused restored search value and complete reader task traversal remain unverified |
| Performance / resilience | Published root mobile 70–78 fails and desktop 97–98 passes. Current local image-delivery component mobile 83–84 still fails and desktop 99 passes; field and other routes remain unverified. Admin Retry, shell outage/reconnect/failed-update recovery and isolated database restart/recovery verified; actual browser network blocking across reload verified; the Chromium online-state indicator, broader recovery, workload and device/server measurements remain open |
| Admin / installed PWA / public web | 102 synthetic Admin route/state cases retained. Installed PWA lifecycle:21/22 checks pass, including actual network blocking across reload; one browser online-state indicator check fails. Search reader evidence, real sessions/actions, remaining installed platforms, broken privacy links and stale media remain open |
| Builds / hosted CI / deployment | Native builds pending; hosted CI not validated for these changes; no deployment performed |
| Physical devices / providers / stores | Unverified; no provider settlement, distribution or store approval claimed |
| Independent review / owner acceptance | Not obtained or fabricated |

The next steps are expanded route/state/API coverage, current clean replay and
supported upgrades, runtime authorization, wider failure/concurrency cases and
representative performance measurements. Native builds require adequate
capacity. Actual end-to-end tasks and remediation continue under the plan.
There are 477 indexed checks, including preserved failed attempts;
overlapping tests are not an acceptance percentage. The ledger has 45 findings:
35 fixed locally, nine open and one preview false positive. The goal remains active.
