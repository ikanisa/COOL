# Collect comprehensive system QA

Status: active. Started 13 September 2026 against `7be12232`. This plan implements
the owner's goal to review and test the entire system and fix identified defects.
It is not release approval. Existing reports are leads, not current test evidence.

## Scope and acceptance

The scope includes the Android and iOS member app, Admin web/PWA, public website,
authentication, all member and operator journeys, edge APIs, database migrations,
RLS/RPC permissions, both payment rails, reconciliation and ledgers, media,
notifications, privacy, security, accessibility, performance, recovery and release
operations. `docs/PRODUCT.md` supplies product behavior. The owner's
`revolut-design/SKILL.md` is the sole design authority; adaptive-product-design
supports journey and readiness review. Screenshots and contracts establish only
their stated evidence, not behavior or blanket visual acceptance.

Every feature must have a source inventory entry, relevant positive and negative
test cases, actual execution evidence, and resolution of material failures. Each
result records the build/source, environment, persona, geography, route/state,
procedure, expected/actual outcome and log or capture. Use pass, mismatch,
unverified, or not applicable with a reason. A passing aggregate cannot hide an
untested feature or critical/high failure. Missing platform, source comparator,
provider, deployment or human evidence stays open.

Use isolated synthetic accounts/databases for mutation, concurrency, deletion,
receipt ingestion and provider failure injection. Production review is read-only
unless separately authorized. Preserve signed-in devices, customer data, access
controls and financial behavior. Do not deploy a QA build as an approved release.
Do not regenerate visual baselines without viewing and reviewing the differences.

## Execution sequence

1. Inventory routes, features, roles, edge entrypoints, RPCs, tables, migrations,
   integrations and existing tests. Check CI commands and evidence gates against
   the actual repository. Capture runtimes, source hashes and environment limits.
2. Run current automated baselines: Flutter analysis and all unit/widget/golden
   tests, edge tests/type checks, release-tool regression tests, migration checks,
   notification tooling, asset integrity and secret/source hygiene. Fix broken
   test infrastructure before trusting its pass/fail claims.
3. Replay the complete migration history on an isolated Supabase platform; run
   SQL, HTTP authorization and concurrent financial/member tests. Compare deployed
   schema/function/configuration metadata read-only; versions alone are not schema
   equivalence. Exercise upgrade and restore paths separately from clean replay.
4. Walk every member, Admin and public route with realistic fixture data. Exercise
   complete tasks and recovery, recording actual redirected destinations. Verify
   native-only capabilities on their native runtime. Fix failures and repeat the
   affected path plus necessary regression coverage.
5. Run accessibility, responsive/localization, performance and lifecycle matrices;
   compare visible states against the matching design reference cohort. Obtain
   representative user task evidence and required owner annotations/signoff.
6. Reconcile all results against the feature/route/API/data inventory and every
   requirement below. Run current release gates and record deployment/provider
   evidence boundaries. Close only when the entire scope is proven; keep the
   active goal intact while work or evidence remains.

## Requirements and proof matrix

| ID | Area and required cases | Execution/proof required | Initial status |
| --- | --- | --- | --- |
| QA-01 | Toolchain, CI and evidence reliability | Pinned Flutter/Deno, real paths, failing missing/malformed evidence, correct coverage math, current-source hashes; shell/Ruby/Python regression tests | In progress: coverage calculation and two missing CI paths found |
| QA-02 | Auth and account lifecycle | WhatsApp OTP request/verify/resend, invalid/expired/replayed codes, rate limits, paste/autofill, session expiry/refresh, logout/account switch, interrupted invite, delete/export and reauthentication; UI plus HTTP/database proofs | Unverified |
| QA-03 | Geography, profile and permissions | Rwanda/diaspora, currency/phone/provider edits, verified identity invariants, numeric Collect ID, incomplete profile, consent/deny/revoke, Android integrity, unsupported platform alternatives | Unverified |
| QA-04 | Groups and membership | Public/private discovery, join/code/QR/share links, expired/invalid links, create requirements, roles/ownership/admin transfer/removal, concurrent edits, image upload/default/removal, roster paging/import, unavailable/deleted group | Unverified |
| QA-05 | Rwanda contribution journey | Amount precision/limits, correct payer and receiver, USSD call/return/cancel, pending/unknown states, repeat taps, receipt permission/capture/queue, authenticated deterministic parse and exact matching | Unverified |
| QA-06 | Diaspora contribution journey | Approved beneficiary maker/checker, unavailable/unapproved route disabled, currency/ref correctness, Revolut/SEPA handoff, pending until statement reconciliation, retries and provider return | Unverified |
| QA-07 | Financial data integrity | SMS/email/CSV/JSON/MT940/CAMT.053 evidence, malformed/oversized input, duplicate/canonical IDs, replay/concurrency/idempotency, exact amount/currency, independent allocation approval, immutable balanced journal, returns/exceptions/close/reopen audit | Unverified |
| QA-08 | Member history, settings and recovery | Home, Groups, Activity, Ledger and every settings/legal/help route; empty/loading/error/long content; Offline/Sync, cache age, reconnection/account cache isolation; correct Back/branch state and no blank screens | Unverified |
| QA-09 | Admin product journeys | All registered list/detail routes: members/groups/payees/transactions/reconciliations/ledgers/beneficiaries/statements/roles/notifications/flags/runtime/health/audit; sort/filter/page/search/export; permitted edits, stale data, bulk/partial failures and meaningful final outcomes | Unverified |
| QA-10 | Authorization and sensitive evidence | Anonymous/member/nonmember/owner/group-admin/operator/maker/checker/platform-admin matrix via direct API and SQL; cross-account/group isolation, escalation attempts, raw evidence requires permission+reason+audit; protected storage buckets | Unverified |
| QA-11 | Edge APIs and integrations | Inventory all deployed/source endpoints; verbs/CORS/auth/signatures/schema/limits/timeouts/retries/error redaction; parser/AI input isolation, no AI financial allocation; actual provider acknowledgments distinguished from final settlement | Unverified |
| QA-12 | Database lifecycle and operations | All 124 current migrations, clean replay and bounded upgrade, constraints/triggers/RLS/grants/search paths, indexes/query plans/volume, concurrent races, backups/restore/recovery consistency, cron/outbox behavior | Unverified |
| QA-13 | Notifications | FCM/APNs tokens/rotation, audience permissions, preference/consent, queue claim/retry/dedup/dead-letter, invalid tokens, delivery and taps/deep links, account switch; notification operator tool authorization | Unverified |
| QA-14 | Public website | Every generated route, mobile menu/footer/CTA/download/deep-link destinations, legal/support copy, 404 recovery, metadata/canonicals/robots/sitemap, fonts/images/contrast, deployed headers/content and current screenshot provenance | Unverified |
| QA-15 | Visual design, accessibility and localization | Every applicable route/state mapped to exact source cohort; shared tokens/typography/image hierarchy; Android/iOS independently; narrow/large/landscape, 200% text, 320px web reflow/zoom, keyboard/focus/modals/reader/targets/contrast/reduced motion, supported languages and data extremes | Unverified; mobile design gate required |
| QA-16 | Native and PWA resilience | Cold/warm start, permissions, SMS/camera/share/external app, background/kill/resume, offline/reconnect, storage quota/eviction, multi-tab/account isolation, active-task update/old client and rollback compatibility | Unverified |
| QA-17 | Performance and observability | Startup/frame/scroll/memory on representative devices, dense Admin lists and database volume/query plans, lab web load/interactions and available field data; traceable failures, redacted logs/alerts/health and recovery runbooks | Unverified |
| QA-18 | Release and end-to-end acceptance | Current mobile-design gate, artifact provenance/signing/permissions, store requirements, CI outcomes, staging/provider full journeys, production read-only drift/health and explicit human acceptance evidence; no unsupported production GO | Unverified |

## Coverage dimensions

For each affected feature, test signed-out, incomplete profile, Rwanda member,
diaspora member, nonmember, group owner/admin and the relevant operator role.
Include unauthorized and stale-role access directly at the server boundary.
For each data-backed screen, include loading, empty, populated, long/large data,
failure and recovery. For mutations, include validation, pending, rejected,
duplicate/retry, concurrent change, success and lost-response recovery. Currency,
identity and access assertions must hold across those states.

Native evidence must name Android/iOS and actual device/OS/build. Browser fixtures
prove only fixture browser behavior. Web review includes supported browser engines,
compact/tablet/desktop widths, keyboard and installed PWA where supported. Visual
results, task outcomes, accessibility, performance and resilience are independent.

## Current baseline and environment

- Clean starting revision: `7be122328d50e9b635b7fabc0513b82b10a0ea62`.
- Inventory: 74 Dart unit/widget test files, 12 native integration test targets,
  11 Deno test files across 38 TypeScript files, 26 Ruby regression test files,
  124 migrations. Counts are discovery, not proof of execution or completeness.
- An isolated detached worktree is used for current-source builds. Local evidence
  locator: `.cache/system-qa-20260913/active-path.txt`; logs contain commands,
  exit codes and source scope. Sanitized results will be recorded in `RESULTS.md`.
- Flutter 3.44.4 and Deno 2.5.6 runtimes are available in the previous local QA
  tool cache. Reuse tools, not historical result claims.
- On this host, Xcode.app, Docker.app and the default Android SDK are absent;
  only Apple command-line tools are selected. Native/database execution remains
  open while other configured runtimes and available connector targets are checked.
- Existing aggregate QA wrapper is not run blindly: it formats source, may build
  production artifacts, target a default physical device and consult deployed
  systems. Execute reviewed commands with explicit isolated targets instead.

## Finding register

| Finding | Impact | Closure evidence |
| --- | --- | --- |
| QA-F01: CI coverage sums hit counts and accepts missing/empty reports | A few repeatedly executed lines can satisfy the 40% threshold while most lines are uncovered | Correct unique covered-line calculation, fail-closed input checks and regression cases, real baseline report |
| QA-F02: CI integration lane targets missing `test/integration_smoke` | Job cannot exercise the intended journey smoke checks | Map current fixture journey tests into the lane, execute the exact command; native integration tests remain a separate requirement |
| QA-F03: CI M-Money lane targets missing `scripts/qa/check_momo_sms_contracts.sh` | SMS/financial contract lane cannot run | Restore an executable, fail-closed lane using current relevant Flutter/Deno tests; real SQL/device matching remains separately required |

QA-F01–03 have now been repaired and their local CI commands pass. See
`RESULTS.md` for the full baseline, the two additional test repairs, and open
Offline-golden/public-imagery findings. Next action: resolve those findings,
expand the traceability inventory and execute the database/API and rendered
journey lanes. All requirements retain their original scope.
