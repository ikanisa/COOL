# Collect full-stack QA status

Updated: 15 September 2026 (Africa/Kigali).

Plan: [PLAN.md](PLAN.md). Work ledger: [work-items.csv](work-items.csv).

Overall state: execution is active. QA runner and CI repairs, initial technical
tests, route inventory reconciliation, isolated database replay and focused
regressions have been completed locally. P0, P1, P2, P3, P5, P6, P7 and P8 remain in progress. Full-system QA and
mobile acceptance are incomplete. See [REPORT.md](REPORT.md),
[findings.csv](findings.csv), [scope.csv](scope.csv), [results.json](results.json)
and the [database](DATABASE_CHECKPOINT.md) and latest
[source-size checkpoint](SOURCE_SIZE_CHECKPOINT.md), followed by the
[public website checkpoint](PUBLIC_WEBSITE_CHECKPOINT.md) and latest
[Admin checkpoint](ADMIN_CHECKPOINT.md). The latest backend continuation is
the [Edge HTTP and OTP checkpoint](EDGE_CHECKPOINT.md), which supersedes the
earlier [HTTP authorization checkpoint](API_CHECKPOINT.md). The newest coverage
continuation is the [member/native coverage checkpoint](COVERAGE_CHECKPOINT.md).
The [PWA lifecycle checkpoint](PWA_CHECKPOINT.md) is followed by the latest
[offline investigation](PWA_OFFLINE_CHECKPOINT.md). The latest continuation is
the [public image delivery checkpoint](PUBLIC_IMAGE_DELIVERY_CHECKPOINT.md),
following the [public performance checkpoint](PUBLIC_PERFORMANCE_CHECKPOINT.md).

Goal task ID: `01a0a06a-73fb-7c23-81a6-36149a29e347`. The goal executes all nine phases of PLAN.md, tracks the 25 work items, fixes confirmed in-scope defects and produces current acceptance evidence. No token budget was specified. Goal creation is not completion of the review.

## Current checkpoint

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

The full P0–P8 scope remains active. The [PWA lifecycle checkpoint](PWA_CHECKPOINT.md)
reproduces and repairs three service-worker defects locally: an unusable
navigation fallback, stale HTML-only updates and caching of non-asset responses.
The worker now uses its installed root shell, versions the final HTML and
worker template, and limits its cache to declared static assets. An injected
precache failure leaves the previous controller and shell usable.

The latest real Chrome/macOS installed run has **22 checks: 21 pass and one
fails**. Installation, standalone rendering, cold launch during an origin outage
and reconnect pass. Two new probes prove actual browser network blocking before
and after reload: the healthy server receives no request and Chrome reports
`ERR_INTERNET_DISCONNECTED`. The original online-state flag assertion still fails
and was retained. A minimal page reproduces it in ordinary tabs and installed
windows without Flutter; an upstream maintainer attributes this class of issue
to Chromium. FQA-040 stays open and the suite remains failed. Real accounts,
actions/drafts, readers, physical offline startup and remaining platforms are
unverified. See the [offline investigation](PWA_OFFLINE_CHECKPOINT.md).

The worker was packaged around the existing backend-free synthetic Admin
fixture: 412/413 application inputs still match; only the photo asset inventory
differs. All 154 original artifact files still match.
Retained framework regression passes **87 focused Flutter tests, 132 Ruby tests with
663 assertions, and nine Python tests**. Analysis, source hygiene, packaging
gates, contract validation and evidence consistency pass. All 527 recorded
inputs stayed unchanged during those earlier checks. Six now differ:
Makefile, the static builder, three public QA scripts and the previously
exercised lifecycle probe; new delivery files are additional inputs. Current
Ruby/Python tooling is verified above. Product Dart and original assets retain
their earlier regression. No Flutter suite was rerun for this public pipeline change.

The earlier full Flutter run retains 867 passes and 74.65% measured coverage;
609 of its 615 inputs remain unchanged. Two CI files, Makefile, the photo asset
inventory and two expanded test files differ. Product Dart, original assets and platform source are unchanged. No new
full-suite run or coverage measurement is claimed. The user's settings hash
is preserved. The six earlier and three new owned PWA installations were
removed and read back; their synthetic profiles were deleted after process
exit. Build evidence remains.

The [member/native coverage checkpoint](COVERAGE_CHECKPOINT.md) retains its
966 required cases per platform, including all 135 previous requirements.
Both actual native gates remain blocked with zero accepted case records.
The route map covers 38 templates and 228 factory/guard callbacks; destination
screens were not mounted. Twenty-one legacy IDs lack an exact harness mapping.
Complete task/state/role/API/comparator coverage remains open. No independent
or owner decision was created. Shared free space was **2.24 GiB at 01:24 UTC**
and remains unstable, so native build capacity is unresolved. Four owned local
HTTP/2 servers and their temporary TLS directory were removed and verified.
All browser capture reports record closure; the database fixture remains stopped.

The [Edge checkpoint](EDGE_CHECKPOINT.md) retains 22 SQL suites on schema 126,
94 checks over 84 PostgREST requests, 66 Edge HTTP checks and two real OTP
concurrency scenarios. No backend source changed in this continuation. The
schema derives from 124 clean migrations plus separate upgrades to 125 and 126;
uninterrupted replay, restore, representative workload and integrated real
Auth-to-provider journeys remain open. The fixture remains stopped with its
volume retained. Scope discovery remains 338 entries including 126 migrations.
No hosted CI, deployment, provider or native acceptance is implied.

## Earlier checkpoints (retained history)

- Initial HEAD: `caafcef15f83de9baae84c377e1a99bb49ed6920`; working branch: `codex/recovered-pro-g40-2026-09-10`.
- The two newer upstream commits were reconciled in local merge `dfc2a526`, after QA checkpoint `2dd34026`. The current user-supplied design rule and settings modification are preserved. Nothing was pushed.
- `git fsck --full --no-dangling`: exit 0. All 1,464 tracked files were readable.
- Existing `.vscode/settings.json` modification is preserved.
- Initial inventory: 73 Flutter test files, 12 integration test files, 124 local migrations, 11 Edge Function entry points and 11 Edge test files. A router-inventory regression test file was subsequently added. These are file counts, not passed-test counts.
- Revolut skill bundle verifier passed. External collection integrity and implementation fidelity are separate.
- Mobile contract is valid. Ten exact original references were restored to ignored paths after hash/dimension verification. Android and iOS remain blocked; absent release provenance prevents complete case evaluation. At that checkpoint the governed inventory derived 135 cases per platform, with zero recorded acceptance cases. This is not yet a complete all-state coverage denominator.
- The missing CI evidence-consistency target is implemented. Formatting checks no longer write files or traverse ignored generated dependencies. The aggregate runner enforces both full mobile gates and reports fixture results as unverified. Regression tests cover these controls.
- The mobile adapter now requires separate implementer, independent visual and owner records and four separately evidenced quality results. All 49 gate tests pass locally. The real acceptance file is unchanged and blocked.
- Initial Flutter baseline: 758 passed and 7 failed. Test/tooling defects, an additional stale asset-count assertion and an order-dependent shared test cache were repaired. Two photo-only golden changes were visually reviewed against the selected comparator; only those baselines were refreshed. The pre-reconciliation checkpoint passed all 767 tests with seed 20260914 and four workers, with no skips or changed source inputs. Coverage is 11,863 / 17,005 lines (69.76%).
- Flutter analysis, formatting and source hygiene pass. All 54 Deno tests and all 38 Edge TypeScript file checks pass using pinned Deno 2.5.6. Notification MCP type checking and 30 tests pass. Twenty further script test files pass 81 tests and 344 assertions. CI coverage for the MCP package is added; hosted runs for the baseline were blocked before starting by an account billing lock, and these changes have not run there.
- The line-coverage gate now counts each executed source line once and rejects missing evidence; its 40% threshold is unchanged. Six files exceeded CI's separate 1,200-line limit at that checkpoint and are now repaired below. Upstream reconciliation is complete locally: all 768 Flutter tests pass on stable reconciled source, with coverage of 11,876 / 17,005 lines (69.84%), analysis clean and all 69 gate/tooling tests passing. A subsequent test-format correction and scope CSV line-ending correction were verified separately; product code is unchanged from that run.
- Scope export contains 337 platform/entrypoint rows, including 38 member paths, 24 Admin paths, nine Flutter public paths, 21 static website entries, 125 migrations, 11 Edge entries and nine MCP tools. The static inventory uses its actual Ruby builder and includes aliases, app/share paths and redirects. The previously omitted `/groups/join` alias now has route catalog and native-test coverage. Roles, overlays, states and dependency mapping remain incomplete.
- A new task-owned Supabase fixture passed 124 clean migrations and one bounded upgrade to 125. This is two recorded runs, not an uninterrupted 125-migration replay. That first checkpoint had 17/21 passing SQL suites; the current continuation passes all 21 on the same 125-migration schema, with every copy removed.
- FQA-025 confirmed that general group-read permission exposed member rosters to public-group outsiders and unrelated platform operators. The local migration restores owner-or-active-member access, including valid linked/claimed member records. The regression reproduced 14 failures before the fix; all 48 access checks and all five affected SQL suites pass after it. No hosted migration was applied.
- The task-target tests pass eight tests/14 assertions. At the database checkpoint the combined QA tooling target passed 28 tests/98 assertions. SQL suites use separate synthetic copies with source/log hashes, rollback and persisted-count checks. API gateway, scheduled/network execution, concurrency, device and provider outcomes are not established by these tests.
- FQA-015 is repaired locally. The Edge helper discovers nested tests and every TypeScript file, resolves Deno through PATH or DENO_BIN and verifies `.dvmrc`, preserves failed attempts, rejects ignored/empty tests and binds source/config hashes. Its current run passes 54 tests and 38 file checks across all eleven functions. Nine helper regressions pass; the combined QA tooling target now passes **37 tests/181 assertions**. The historical cutover retains exactly five functions and passes its three existing contract tests; nothing was deployed.
- FQA-020 is repaired locally. All six oversized files were separated into existing-library parts, repository instance methods in a mixin, and generated catalog family parts. The exact CI size step passes at the unchanged 1,200-line limit. **769 Flutter tests pass**, zero failures/skips, with unchanged recorded source inputs. Final analysis/format/hygiene pass; coverage is 11,876/17,006 lines (69.83%). Five moved declaration groups are byte-identical and all 44 catalog records match their source. Three generator tests and their Make target pass; a pinned CI job was added but has not run remotely. Both native design gates remain blocked on current source.
- FQA-028 and FQA-029 are repaired locally. The static route extractor passes seven regressions. Published geometry across 19 requested paths and four widths found two heading overflows at 320 px. A shared CSS adaptation removes them in a published-HTML/local-CSS preview: all 95 geometry cases pass across five widths. The implementing agent inspected the selected Revolut marketing reference and before/after screenshots. No production change or full static build acceptance is claimed.
- Published menu keyboard behavior passes 48 cases across 16 routes and three verified widths. The original live gate passed 35/35, but the new destination check finds four broken Privacy/Terms links to three missing pages. The current gate fails at 35/36 checks; FQA-030 remains open. The final combined tooling run passes 51 QA tests/232 assertions, 49 mobile-gate tests/265 assertions and three generator tests. At that website checkpoint, all 603 recorded Flutter application/test/asset/platform inputs were unchanged from the 769-test run. The newer Admin regression is recorded below.
- Website app screenshots need recapturing: their current runtime fingerprint does not match. Updating the asset byte inventory does not change this failed freshness result.
- **Latest application test run: 867 Flutter tests pass**, with zero failures/skips and 615 inputs unchanged during that run. Coverage is 12,744 / 17,072 lines (74.65%). Final analysis, formatting, source hygiene and the unchanged 1,200-line CI step pass. The final Admin evidence build passed with 413 stable source inputs and 154 hashed output files. Both native design gates remain blocked.
- FQA-031 and FQA-032 are fixed locally: identity/record errors offer Retry without weakening access checks, and list search/filter/sort/page/scroll survive record navigation within the same Admin identity. Ninety-one access/recovery tests and seven navigation/semantics tests are included in the final regression. Account changes discard saved view preferences; record data is always fetched again.
- All 24 Admin routes now have a source permission/RPC map. On the final isolated browser build, 72 ready-route cases, ten failure/Retry journeys and twenty signed-out/denied/loading/empty cases pass. The published Admin hosting gate passes seven response checks. Complete action/modal outcomes, runtime server enforcement, installed PWA behavior, reader tasks and visual acceptance remain open.
- FQA-033 is partially repaired: the queue search now exposes one enabled named field and can be edited after return. Four of five additional browser search observations pass; the unfocused DOM value remains empty until focus despite visible restored text and a passing Flutter semantics-value assertion. The observation is retained for actual reader verification, and the finding remains open.
- Disk capacity recovered independently enough for several web builds, then fell below 1 GiB again. One final browser build stopped below its unchanged 3 GiB preflight; a later capacity recovery allowed a separate successful build. This fluctuation leaves native capacity unresolved. The exact owned database was subsequently restarted and verified. Current SQL, concurrency and pinned advisor checks pass below. After a stop returned container exit 137, recovery and a focused financial rerun passed; PostgreSQL then completed its own shutdown and the container exited 0. Its volume is retained. Other projects were not stopped or removed. Earlier source/golden/evidence-preserving cache cleanup remains separately recorded. The healthy output-location request is still open. At the last device inventory, no physical Android device was connected and no iOS simulator was booted.

- FQA-026 is fixed locally: all **21 selected SQL suites pass on current schema 125**, with source/log hashes, explicit rollback, unchanged counts and successful clone cleanup. The four legacy fixtures now preserve seed accounts, use current approved Admin sessions, and exercise attested SMS ingestion plus separate candidate/finality stages.
- Two committed SQL races pass with both workers observed at the same barrier. Concurrent join produces one membership/audit/queued owner notification. Concurrent finality produces one payment/provider confirmation and one balanced journal receipt with exactly two credit-projection rows. The first finality harness escaping failure is retained separately.
- The existing pinned v2.101.0 advisor query returns zero ERROR/WARN and 230 INFO. All 92 direct-table privilege checks for the 46 policy-free RLS tables pass. The 93 unindexed foreign keys and 91 unused-index observations require representative workload review; no index/grant/policy was changed.
- FQA-034 is fixed locally: bounded Docker clients preserve partial output and uncertain outcomes; SQL reporting preserves primary and cleanup failures and never drops an unconfirmed creation. That backend checkpoint passed **64 tests / 307 assertions**; the newer HTTP continuation is recorded below. Other legacy helpers remain under review.
- The finality SQL regression also passes after fixture restart/recovery. PostgreSQL shutdown is now confirmed by its completed-shutdown log and container exit 0. All test copies are gone and the original synthetic baseline remains intact. Shared capacity was about 2.7 GiB at the later check, so native capacity remains unresolved.
- Since the 867-test Flutter run, **614 of its 615 inputs remain unchanged**. The sole change is the Makefile line registering the new Ruby SQL-runner regression. No Dart, Flutter test, asset or platform input changed; the Flutter run is retained as earlier evidence, not described as newly rerun. The user's settings hash remains unchanged.

- The latest isolated HTTP run passes **82 checks across 73 PostgREST requests plus persisted/source assertions** on schema 125. Synthetic JWT/session checks cover forged metadata, invalid signatures, expired/malformed tokens, missing/cross-user sessions, approval/activation retries, a distinct new session, immediate revocation, private API boundaries and both roster RPCs across public/private groups. Exact denial contracts distinguish permission errors from malformed requests.
- Persisted HTTP effects confirm one approval audit, two distinct candidate sessions, no role from denied requests and no financial/SMS/outbox data. All five attempted API containers and database copies were removed; setup/adapter failures remain recorded. The original fixture baseline is unchanged, PostgreSQL completed shutdown and its container exited 0. No hosted, real OTP, provider or native outcome is implied.
- The current QA tooling regression passes **75 tests / 365 assertions**, with zero failures/errors/skips across ten files and unchanged recorded inputs. It includes eleven HTTP target/transport/reporting tests. Since the prior Flutter run, Makefile remains the sole changed input of 615; it now registers both SQL and HTTP Ruby tests. Settings and all 125 migration hashes remain unchanged. At 21:19 UTC, free space was 1.482 GiB, so native build capacity remains unresolved.

## Milestones

| Phase | State | Next action |
| --- | --- | --- |
| P0 — Trustworthy QA execution | in_progress | Complete script/CI discovery and stable native/current-replay capacity planning |
| P1 — Complete coverage map | in_progress | Complete task/overlay/role/API/comparator links, reconcile 21 legacy native IDs and establish member browser support |
| P2 — Technical/security baseline | in_progress | Extend passing HTTP authorization to remaining Admin/member actions, integrated real Auth/Edge/SQL flows and hosted drift checks |
| P3 — Backend/financial correctness | in_progress | Complete uninterrupted current replay, representative upgrades/restore and broader financial concurrency; 22 SQL suites and two OTP races pass; earlier financial race evidence is retained |
| P4 — Android/iOS member journeys | pending | Build current isolated native candidates and execute the expanded matrix |
| P5 — Admin/PWA workflows | in_progress | Expand role/action/geography, readers and supported installed platforms; network blocking now verified, while the Chromium online-state indicator and physical offline startup remain open |
| P6 — Public website | in_progress | Complete the mobile performance budget after partial image delivery repair, resolve missing privacy destinations, finish route/accessibility coverage and recapture native media before full build checks |
| P7 — Resilience/performance/operations | in_progress | Extend root lab performance to other routes and field evidence; continue native/member/Admin/database workloads, real sessions and cross-system recovery |
| P8 — Remediation/regression/acceptance | in_progress | Continue reproduced-defect repairs; exact native proof and real reviews remain outstanding |

There are 45 findings in the ledger: 35 fixed locally, nine open and one
closed as a preview false positive. This is a triage count, not a completion
percentage. Open findings cover incomplete scope, stale website media,
missing mobile acceptance evidence, build capacity, broken privacy links,
the remaining Admin search accessibility observation, hosted CI billing and
the reproduced Chromium online-state emulation symptom and mobile website
performance. Consult the ledger for exact statuses.

No production deployment, production migration, external message, store
submission, signed-in device reset or release approval has been performed.
Raw checkpoint evidence is under `.cache/fullstack-qa/20260914T151002Z/`.
There are 477 indexed checks, including preserved failures and invalid measurements.
