# Collect full-stack QA execution plan

Prepared: 14 September 2026. Workspace: `/Users/jeanbosco/Projects/Recovered-PRO-G40/COOL`.

Purpose: review the entire Collect system, reproduce failures, improve the existing QA automation, fix defects within the reviewed scope, and verify the resulting system through current, traceable evidence. The execution goal must be created after this plan is saved. Planning and initial discovery do not establish product readiness.

## 1. Scope and authority

| Surface or layer | Current implementation | Required review |
| --- | --- | --- |
| Android member app | `lib/main.dart`, `lib/app/router.dart`, `lib/features/`, `android/` | Every reachable route, alias, overlay, supported role/state, native bridge and complete member task |
| iOS member app | Same shared Flutter app, `ios/` | Separate native evidence, iOS restrictions, permissions, lifecycle, keyboard, accessibility and external returns |
| Member browser runtime | Member app web build and route adapters, where supported | Discover production availability; test supported browser journeys and unavailable native capabilities; fixture browser captures cannot certify native apps |
| Authenticated Admin | `lib/main_admin.dart`, `lib/admin/` | All declared routes, list/detail actions, role restrictions, financial operations and actual backend persistence |
| Installed Admin PWA | `web/`, Admin build/hosting scripts, `deploy/admin.wrangler.jsonc` | Browser and installed modes, account/cache boundaries, offline behavior, session recovery and active-work updates |
| Public website | `lib/main_public.dart`, `lib/features/landing/`, `content/legal/`, `scripts/public_static_site_build.rb`, `web/public/`, `deploy/public.wrangler.jsonc` | Both Flutter public rendering and deployed static output; all marketing/legal routes, menus, CTAs, media, metadata and responsive states |
| Backend and data | `supabase/migrations/`, `supabase/functions/`, SQL/RPC tests in `scripts/` | Schema, grants/RLS, storage, API contracts, authentication, money invariants, concurrency, privacy and recovery |
| Device/provider integrations | Android SMS/USSD, Play Integrity, app links, WhatsApp OTP, FCM/APNs, bank ingestion | Boundary validation, retries, deduplication, lifecycle, truthful pending states and provider evidence |
| Operator tooling | `tools/collect-notification-mcp/` | Type checks, tests, operator authorization, session renewal/concurrency, outbox controls and transport boundaries |
| Shared infrastructure | `.github/workflows/`, `Makefile`, `scripts/`, `third_party/file_saver/`, deployment manifests | Reproducibility, complete test discovery, build provenance, configuration, secrets, observability and release gates |

This scope covers the COOL/Collect repository and its deployed services. Sponsored groups such as Buri Munsi and Gikundiro are Collect product data here; this plan does not expand into unrelated application repositories.

Design authority is solely [`revolut-design`](/Users/jeanbosco/.codex/skills/revolut-design/SKILL.md), including [`MOBILE-DESIGN-100`](/Users/jeanbosco/.codex/skills/revolut-design/references/mobile-design-100.md). Apply the skill's quality standard and operational procedures F01–F08, V01–V08, A01–A10, M01–M06, W01–W06, S01–S06 and P01–P08 where applicable. Repository contracts, screenshots and reports bind product evidence; they cannot override that authority.

Preserve Collect's identity, current routes/navigation, terminology, real content, geographic payment rails, permissions and business rules. Native Dark · Glow, Business/operator and public marketing comparators remain distinct cohorts. Map Home blue, Groups teal, Activity purple, Profile rewards-family violet/blue and WhatsApp login blue-indigo where applicable, with the correct quiet task/overlay and semantic treatments. These examples do not limit the colour/state inventory. Source marks and private account images remain reference-only. Keep legitimate existing Revolut/SEPA handoff terminology where it describes Collect's actual payment rail.

## 2. Verified starting point

Discovery was performed on branch `codex/recovered-pro-g40-2026-09-10`, HEAD `caafcef15f83de9baae84c377e1a99bb49ed6920`.

| Observation | Current result | Consequence |
| --- | --- | --- |
| Git object integrity | `git fsck --full --no-dangling` exited 0 | Healthy Git baseline; not a build or release result |
| Tracked-file readability | 1,464 files read; no read errors | The current restored source can be reviewed |
| Existing user modification | `.vscode/settings.json` | Preserve it throughout QA |
| Test inventory | 73 Flutter test files, 12 integration test files, 11 Edge test files | File counts only; full tests have not been rerun for this plan |
| Backend inventory | 124 local SQL migrations, 11 Edge Function entry points | Reconcile live state afresh; local counts do not prove deployment |
| Design authority bundle | Skill `verify_bundle.py` passed | Bundle integrity only; full external collection and app fidelity remain separate |
| Mobile contract | `--check-contract --json` returned `contract_valid` | Does not establish visual acceptance |
| Android mobile design gate | Blocked; 20 findings at the initial evidence-validation stage | Restore/verify exact reference evidence, then rerun; this is not a complete count of UI defects |
| CI target contract | CI calls missing `revolut-parity-evidence-consistency` | Repair the missing evidence check without weakening its intended enforcement |
| Build capacity | Approximately 2.2 GiB available during discovery | Resolve build headroom before high-growth native builds |

Additional tooling issues visible in source: the aggregate QA runner's format check can modify files; its fixture mode emits simulated pass records; and the local Edge gate lists five function entry points while the repository contains eleven. Audit those boundaries before using aggregate results. Simulated runner tests may test the runner itself, but must never count as product QA passes.

Older reports are investigation leads. Refresh previously reported Flutter failures, asset-manifest/screenshot fingerprint drift, CI availability and remote migration history against this source and current services. Do not import old pass/failure counts as current results.

## 3. Execution sequence

Responsibilities below describe work ownership, not appointed reviewers or delegated agents. Execute within this task, using the existing test frameworks. Independent visual review and owner acceptance require actual separate evidence.

### P0 — Establish trustworthy QA execution

Owner: QA/infrastructure. Start immediately; prerequisite for high-growth builds and any mutating test.

1. Save source/tool/configuration fingerprints, current working changes, disk capacity and command exit codes. Use the internal SDK paths from `../dev-env.sh`; retain dependency lockfiles and signing material.
2. Review each reused script for target selection, dotenv loading, network calls, installs, database writes, notifications, formatting, cleanup and evidence writes. Classify commands as local read-only, isolated test mutation, live read-only or external mutation.
3. Fix QA plumbing locally: restore the missing CI evidence check, use a non-writing format check, make complete test/function discovery explicit, and ensure failed/skipped/unverified work cannot become a pass. Add only meaningful regression tests for these controls.
4. Verify build capacity against expected output/cache growth and retained evidence. Serialize large builds; resolve capacity using identified expendable generated data or an available healthy destination. Do not touch the damaged SSD, recovery originals, user data or signing assets.
5. Inventory available emulators/simulators, physical devices, browser versions, local database facilities and authenticated read-only service access. Record exact unavailable prerequisites and continue independent local work.

Exit: a reproducible local baseline, reliable runner behavior and explicit environment boundaries. No production install/reset, live payment or message is used merely to prove QA works.

### P1 — Build one complete coverage map

Owner: QA/product/design. Depends on source integrity; can proceed while capacity is resolved.

1. Reconcile actual member router branches/aliases, `adminRoutePaths` and helper-generated routes, `publicWebsitePaths`, static-site output and all deep links. A search for literal `path:` lines alone misses generated routes.
2. Inventory components and non-route surfaces: sheets, menus, dialogs, pickers, confirmations, system prompts, share/file exports, receipts, notifications and unavailable-route screens.
3. Join each task to its repository/model, API or RPC, tables/storage, permissions, background jobs and expected final outcome. Inventory all 11 Edge entry points and supporting operator tooling.
4. Record platform, supported version, viewport/orientation, theme, keyboard/text/accessibility state, authentication, role, membership, ownership, geography/payment rail and network state. English is the currently declared app locale; test supported regional data formats and long content without inventing localization support.
5. Extend the existing mobile contract and route/state fixtures only when coverage is missing. Derive a review view from those sources; do not maintain a competing hand-written mobile case count.
6. Bind every applicable visual case to a direct comparator, component/pattern comparator or explicit adaptation. Record cohort, date/build if known, region/theme, dimensions, reference hash, private location and limitations. Recover only the exact missing references and verify their hashes. Read the applicable native atlas/findings before visual changes.

Exit: every discovered surface/task has a test owner role, applicable cases, expected result, test method and evidence requirement. Unsupported cases need a product reason and proof the path remains unavailable. Pairwise sampling may support secondary configuration analysis, but cannot replace mandatory mobile cases or critical permission/payment branches.

### P2 — Run the technical and security baseline

Owner: application/backend engineering and QA. Depends on P0 command review; follows the P1 inventory.

Run existing format, analyzer, Flutter unit/widget/golden, integration-smoke, Deno type/test, migration-validation, script tests, secret scan, product-boundary and source/evidence hygiene checks. Include the notification MCP and the controlled `file_saver` fork's relevant platform compatibility checks. Capture every failure before fixing it. Deterministically reproduce order-sensitive/flaky failures and record the seed/environment; quarantined or skipped tests remain unverified.

Trace authentication and authorization from UI to server: session expiry/revocation, OTP abuse/replay, JWT and internal-function boundaries, cross-account/group access, role escalation, RLS/grants, storage access, raw-evidence reveal, audit trails, webhook validation and unsafe exported content. Inspect client bundles/logs for privileged credentials. Exercise adversarial cases only against isolated test targets; authorized production inspection remains read-only.

Exit: all inventoried suites have current results, and every failure or missing test is linked to a finding. Fix critical/high code defects before dependent acceptance claims. A passing contract test does not substitute for a runtime security or data check.

### P3 — Prove backend and financial correctness

Owner: backend/QA. Depends on an isolated database and synthetic fixtures.

Replay migrations on a disposable database and rehearse upgrades from the supported prior schema. Run the existing SQL/RPC, linked-journey, concurrency, privacy/lifecycle and Edge-auth UAT. Verify functions configured without platform JWT verification have the intended alternative protection; do not mechanically change their configuration.

For every critical scenario below, assert API results and committed database effects, including the absence of unintended effects. Test retry, concurrency, crash/restart and out-of-order events, not only sequential happy paths. Verify list pagination, indexes/query plans and reconciliation performance with representative synthetic volumes. Reconcile current deployed migration/function/configuration fingerprints through authorized read-only access; document drift without automatically deploying or repairing migration history.

Exit: no incorrect posting, cross-account exposure, authorization bypass, lost acknowledged write or silent reconciliation discrepancy in covered scenarios. Backup availability is separate from an isolated restore rehearsal; record tested recovery point/time and remaining operational limits.

### P4 — Review Android and iOS member journeys

Owner: mobile/design/accessibility QA. Depends on route/state mapping and relevant backend contracts.

Exercise each mapped route and complete task using isolated fixture builds, then validate test-account integration where available. Cover startup, WhatsApp auth/recovery, Home/Featured Groups/Explore, join/create/manage, covers/photo pickers, profile and MoMo number/code persistence, contribution review/handoff/return, Activity/ledger, permissions, preferences, notifications, account deletion and help/legal flows. Verify platform/geographic/membership restrictions explicitly.

Capture native Android and iOS separately at supported compact/large sizes, landscape, open keyboard, default/enlarged text, supported themes and reduced motion. Use real VoiceOver/TalkBack task traversal where available. Test denied permissions, settings return, interrupted intent, expired session, offline/reconnect and cold/warm/process-death recovery. Native SMS/USSD/attestation claims require physical-device/provider evidence beyond simulators.

Inspect the actual selected reference and current target together. Correct shared tokens and components before route-specific layout. Recheck every affected consumer and all current owner annotations, including their related states. Preserve account data on existing signed-in devices.

Exit: Android and iOS each have their own behavior, visual, accessibility, performance and resilience results. Browser fixtures cannot approve a native build. Production visual acceptance additionally requires exact artifact installation/readback and all MOBILE-DESIGN-100 reviews.

### P5 — Review Admin and installed PWA workflows

Owner: Admin/backend/design QA. Depends on permissions and representative backend fixtures.

Test all declared Admin routes, including list/detail states, Groups, Users, Members, the four financial Operations pages, SMS receipts, Notifications, Audit Logs, Settings, Feature Flags, System Health and Admin Users. Verify maker/checker separation, denied/read-only actions, expired sessions, sensitive reveal reason/audit, stale edits, concurrent approvals, import/export, search/filter/sort/pagination, selection scopes and partial failures where supported.

Use the same synthetic record IDs through member UI, API/database and Admin to verify persisted fields, counts, amounts and statuses. Separately inspect authorized live identifiers read-only; fixture data cannot prove production synchronization.

Review Business/operator visual density and state treatments at compact/tablet/desktop widths. Verify table headers, keyboard sorting/scrolling, modal focus return, reflow and screen-reader tasks. In installed mode test logout/account switch, private cache isolation, quota/storage failures, offline cold launch, reconnect, draft acknowledgement, update with active work, old tabs and supported version compatibility.

Exit: all Admin tasks and supported PWA platform/browser combinations have current evidence. A manifest, HTTP 200 or one Chromium install is insufficient for complete PWA acceptance.

### P6 — Review the public website and app entry paths

Owner: public-web/design QA. Depends on public-route inventory and current app media.

Compare Flutter public rendering with generated static routes and approved content. Walk every menu, footer, section link, CTA, app-store/deep link, contact affordance and 404 path. Check truthful geographic/product claims, legal content consistency, canonical redirects, indexing policy, titles/descriptions, structured data, sitemap/robots and private Admin exclusion. Do not submit messages, forms or search-index notifications as a QA shortcut.

Use public marketing comparators for hero crop, typography, sections, image tabs, CTA geometry and responsive navigation. Cover 320 CSS-pixel reflow, representative phone/tablet/desktop sizes, actual breakpoints, keyboard, zoom/enlarged text and reduced motion. Test missing/slow images/fonts and loading stability. Refresh app screenshots from the correct current runtime and synthetic data, retaining source/artifact hashes; never bypass the media-freshness check.

Run existing static, rendered-browser, contrast, Lighthouse and live read-only gates. Compare current deployed asset hashes with the reviewed build when accessible. Lab results, field performance, deployment freshness and source design fidelity stay separate.

Exit: every declared public route and conversion path has functional/responsive/content evidence and no unreviewed media drift. Public changes cannot be marked deployed based on a local build.

### P7 — Cross-system resilience, performance and operations

Owner: QA/infrastructure across all surfaces. Baseline performance budgets before remediation and measurements; dependencies are the relevant P3–P6 journeys.

Measure native startup, frame/scroll performance, memory and lifecycle on named devices; measure web loading/interactions/layout stability and backend latency/query plans under declared datasets and network conditions. Use the skill's verified benchmarks and repository budgets; establish any missing app-specific budgets before optimization and label them as project targets. Report distributions, sample size, environment and lab/field limits.

Exercise interrupted writes, duplicate dispatch, delayed provider evidence, background work, network loss during commit, service unavailability, revoked credentials, queue overflow/backpressure, storage failure, update compatibility and recovery. Trace a synthetic event across client, edge, database/outbox and Admin using safe correlation IDs. Verify useful redacted errors/logs and operational failure visibility. Provider send/delivery/settlement are distinct outcomes.

Exit: critical tasks retain correct outcomes under tested failures and measured performance meets declared budgets. Unsupported or unavailable hardware/provider conditions remain explicitly unverified.

### P8 — Remediate, regress and assemble acceptance evidence

Owner: engineering/QA; independent reviewer and owner supply their own acceptance.

Prioritize reproduced critical/high defects, then material visual mismatches and medium/low issues. Distinguish product defects, test/tooling defects, stale evidence, source-reference gaps and external prerequisites. Each repair needs a root cause, minimal coherent change, suitable regression evidence and retest of affected consumers. Do not add unrelated features or replace Collect's workflows.

Run the required suites and relevant builds on the final source. Refresh evidence invalidated by source, reference, contract or artifact changes. Run Android and iOS design gates separately, plus Admin/PWA, website, backend and release-evidence gates. Review actual gate payloads and subcheck statuses as well as exit codes. Never turn an aggregate return-code exception into an all-system pass.

Assemble a report with coverage denominators, current findings, source/artifact fingerprints, exact tested environments, remaining dependencies and separate technical, visual, deployment, provider, store and owner statuses. Prepare any later production change as a concrete reviewable artifact; this QA request itself does not publish, deploy, migrate production or send external messages.

Exit: all required coverage is executed and evidenced, relevant tests pass, no open critical/high defect or material design mismatch remains, and required mobile acceptance reviews bind the same artifacts. If necessary external evidence is unavailable, keep the affected milestone incomplete and continue other work; do not invent approval or certify mobile completion while its design gate fails.

## 4. Critical scenario catalogue

Expand these scenario families into the governed route/state and backend cases. They are a starting catalogue, not a coverage cap.

| ID | End-to-end scenario | Required assertions |
| --- | --- | --- |
| J01 | WhatsApp onboarding, wrong/expired/replayed code, resend, logout and session recovery | Correct identity; limits/recovery; no secret disclosure; coherent retained profile and session |
| J02 | Profile country/provider/MoMo number alone or number plus code; save and relaunch | UI → model → RPC → database → reread consistency; geographic changes preserve legitimate data |
| J03 | Featured Groups/Explore, public/private discovery, join/rejoin, revoked membership | Correct visibility; private identifiers protected; no duplicate membership under concurrency |
| J04 | Android private-group creation, SMS consent, attestation, cover selection | Atomic group/media result; interrupted creation recovery; iOS/unavailable-client restriction verified |
| J05 | Rwanda amount entry → intent → USSD return → receipt → ledger/Admin | Whole RWF; exact receiver/payer/amount/time/transaction match; handoff remains pending |
| J06 | Duplicate/replayed/ambiguous/late/reversed/malformed SMS and interrupted encrypted queue upload | At-most-one financial posting; bounded safe retry; unmatched evidence posts nothing; consent/account isolation |
| J07 | Diaspora beneficiary activation → reference → external transfer → statement reconciliation | Independent maker/checker; inactive details unusable; SMS/email alone cannot finalize settlement |
| J08 | CSV/JSON/MT940/CAMT statement import, duplicate/partial/malformed files and concurrent matching | Precision/currency/reference integrity; deduplication; controlled exceptions; balanced immutable journal |
| J09 | Manual allocation, daily close/reopen, concurrent approval and raw-evidence reveal | Exact amount/currency; no self-approval; current permissions; reason/audit; no journal mutation |
| J10 | Member and Admin lists/history/overview over the same records | IDs/amounts/statuses/counts agree; pagination stable; rejected access returns no private data |
| J11 | Hybrid roster/member import and relationship changes | Validation, deduplication, correct member identity, group scoping and atomic/explicit partial outcomes |
| J12 | Notification outbox, preferences, token expiry, retries and operator bridge | No unintended send; delivery idempotency; permission checks; session renewal locking and correct account |
| J13 | Account deletion/privacy lifecycle, logout/account switch and installed caches | Policy-consistent retention; access revoked; no leaked prior-account content; audit preserved |
| J14 | Deep links, share/export, permissions, interrupted tasks and reauthentication | Correct authorized return; reachable controls; no duplicate intent or loss of acknowledged data |
| J15 | Public route → app download/open/help/legal destination | Real destination; correct Collect identity/content; responsive and accessible task path |

Each family needs success plus applicable invalid/denied/empty/loading/pending/error/offline/retry branches. Monetary assertions use exact decimal/minor-unit rules and the product's actual supported currencies. No test enters a real MoMo PIN or treats a provider handoff as settlement.

## 5. Existing command map

Run from the workspace root unless noted. This map identifies reuse candidates, not blanket permission to run side-effecting scripts. Review modes and target binding in P0 first. Save raw logs under ignored `.cache/fullstack-qa/<run-id>/` and redact before publishing summaries.

| Work | Commands or existing tools | Constraint |
| --- | --- | --- |
| Tool paths | `source ../dev-env.sh` | Internal SDK/runtime paths; preserve pinned dependencies |
| Format/analyze/tests | `dart format --output=none --set-exit-if-changed lib test integration_test`; `flutter analyze --no-pub`; `flutter test --no-pub --concurrency=1` | Record baseline, test failures and native/platform differences; inventory other owned Dart sources too |
| Script/CI contracts | Existing `scripts/tests/`, `.github/workflows/`, `Makefile` | Select local tests after checking their behavior; validate referenced commands and all applicable entry points |
| Hygiene | `make release-secret-scan`; `make collect-product-boundary-scan`; `make revolut-parity-source-hygiene` | Redacted output; distinguish stale evidence from runtime defect |
| Design contract/tool tests | `make mobile-design-contract mobile-design-gate-test` | Validity is separate from full acceptance |
| Android design acceptance | `make mobile-design-gate` | Mandatory fail-closed gate; no skipped cases or fake approval |
| iOS design acceptance | `ruby scripts/qa/mobile_design_gate.rb --ios --json` | Separate platform/artifact result |
| Reference bundle/gallery | Skill `scripts/verify_bundle.py`; `make review-gallery` | Verify collection separately; gallery never writes acceptance |
| Migration/backend validation | `scripts/migrations/validate_supabase_migrations.sh`; `make supabase-linked-uat-local`; `make supabase-lifecycle-uat`; `make supabase-concurrent-join-uat`; `make supabase-edge-auth-uat` | Bind an isolated database; rollback alone does not neutralize external side effects |
| Financial/security SQL | Existing `scripts/*uat.sql`, `scripts/tests/`, bank-transfer and Admin-security UAT | Run local synthetic fixtures; inspect wrappers for linked-production defaults |
| Edge Functions | CI's Deno test/type-check discovery; `scripts/audits/collect_edge_function_local_gate.rb` | Expand/reconcile five-function helper scope to all eleven entry points; retain test discovery |
| Operator MCP | `pnpm check`; `pnpm test` in `tools/collect-notification-mcp` | Use approved pinned runtime/dependency setup; no live-send tools |
| Native QA | `integration_test/`, route/material-state, keyboard, lifecycle, permission, network and performance scripts | Disposable fixture targets; physical-device evidence for device/provider claims |
| Admin/PWA | `make admin-web-build`; `make admin-pwa-gate`; `make admin-pwa-hosting-gate`; existing browser/render/runtime scripts | Build after capacity check; map all routes and actual roles; installed modes separate |
| Public web | `ruby scripts/public_static_site_build.rb`; `bash scripts/public_website_ci_gate.sh static`; existing rendered/browser/contrast/Lighthouse scripts | Preserve media freshness checks; separate static and Flutter paths |
| Live read-only | Admin/public live gates, Supabase inventory/advisor/readiness and deployment/CI status inspection | Current authorized access, low-impact reads, redacted results; no automatic remediation of live services |
| Final aggregate | `make repo-wide-qa-uat`, release artifact/evidence gates | Run only after P0 makes behavior safe and scope explicit; inspect all subresults; fixture mode cannot satisfy acceptance |

## 6. Evidence, triage and completion

Keep this plan and `STATUS.md` as the execution index. `work-items.csv` is the work ledger. During execution, produce:

- `scope.csv`: generated review view linking canonical routes/states, APIs and existing tests; every row has an applicability decision.
- `findings.csv`: stable ID, category, impact/severity, surface/route/state, reproduction, expected/actual, environment, evidence, responsible role, fix and retest links, status.
- `results.json`: check ID, exact command/mode, target, timestamps, exit code and parsed status, source/config/artifact hash, evidence hash/path and coverage references.
- Ignored raw logs/media under `.cache/fullstack-qa/<run-id>/`; private source originals remain in their governed private locations.
- `REPORT.md`: final cross-system assessment with evidence links, unresolved dependencies and separate release decisions.

Use `pass`, `mismatch`, `unverified` or `not_applicable` with reason for test results; `pending`, `in_progress`, `blocked` or `complete` for work items. Finding categories separate code defects from tooling failures, stale evidence and unavailable external inputs. A pass requires an actual test on a named build/environment. N/A needs a product reason and evidence; an unavailable device or comparator is unverified.

Critical means a reproduced wrong financial outcome, data exposure, false completion or irrecoverable critical-task failure. High means a primary task/access method fails or material evidence is missing for the declared exact-fidelity claim. Medium/low reflect lesser impact with documented recovery. Missing screenshots are not automatically critical code defects.

Report five independent experience results per surface: design fidelity, task usability, accessibility, performance and resilience. Report backend correctness/security, CI/builds, deployment, physical/provider tests, store review and owner acceptance separately. Any percentage must disclose numerator, denominator, exclusions and method. Neither a test count nor a checklist percentage equals visual pixel parity.

Mobile completion requires every applicable case/criterion and owner annotation, exact installed-artifact proof, current source/contract/reference hashes, implementer review, independent visual review and owner acceptance. Never lower the gate, remove cases, fabricate signoffs, mask a material difference or regenerate goldens without visual review. A reviewed accessibility adaptation preserves the selected visual identity and records its evidence.

Update status after each milestone and substantial finding. Recheck failures after repairs, then run the required regression set on the final source; repeat broader tests only when changes or unresolved failures justify it. Keep unavailable external evidence visible and continue independent work. Creating the plan or goal does not complete the QA review.
