# Collect repository cleanup and refactoring plan

21 November 2026 · Implementation in progress · Working checkout based on `34dcf6ee1`

Companion evidence and implementation results are in the [full-stack code audit](../assessments/2026-11-18-full-stack-code-audit.md). The sequence below makes the codebase easier to change while preserving Collect's Rwanda group-contribution workflows, BuriMunsi's Staff and Admin Sync roles, and the Admin panel's scoped actions. Each work package has one owner and an independently reviewable diff. Start with the packages that determine source and runtime identity.

### Current source and release status

At 17:21 UTC on 20 November, QA served the React session fix on v16 at 100% and production served React v37 on the managed project. Both returned HTTP 200 for an anonymous session. The open-tab upgrade and a real signed-in operator journey remain outstanding. The owner deferred further artifact qualification while disk cleanup continues. [Admin session evidence](../implementation/2026-11-20-react-admin-session-route-recovery.json)

The current COLLECT workspace is `/Volumes/PRO-G40/COLLECT`. The working checkout is `main-source` and its linked Git store is beside it. The seven source and cleanup commits were reconciled with the published source on `main`. Concurrent storage cleanup removed the previous build-evidence directory, the working qualification archive and seven APKs from an interrupted eight-package build. The historical full-tree restore matched 110,302 paths before that removal. Its previous off-disk packet is unavailable. A separate source delta was verified against its recorded base. [Source, custody and open gates](../implementation/2026-11-20-source-cleanup-continuity.json) · [Release evidence index](../release-evidence.md)

### Permanent cleanup and source refactoring on 22 November

Both prior generated-output batches, including their move receipts, were
permanently deleted. The cleanup removed 491,604,177 bytes across those batches,
obsolete reports and SQL wrappers, temporary verification files and installer
archives. The historical October review keeps its original link to an inventory
that was removed from the checkout.

| Boundary | Source change |
| --- | --- |
| Flutter member | Six model libraries own the former 1,214-line implementation. Existing imports resolve through a nine-line facade. The public configuration and reviewed content contracts follow the new model paths. [Model exports](../../lib/shared/models/collect_models.dart) |
| React Admin | Account, financial, operator and record routes have separate owners. The root route module fell from 320 to 22 lines, and six unused index modules were deleted. All 59 route entries and 9,450 role and permission decisions matched the predecessor. [Workspace routes](../../admin-web/src/app/WorkspaceRoutes.tsx) |
| Managed Supabase | The native extraction entry point fell from 517 to 117 lines. Dedicated modules admit source SMS and validate financial evidence. Two duplicate scripts were deleted, and tests now use the canonical runtime modules. All 200 differential comparisons matched. [Native parser](../../supabase/functions/_shared/domain/burimunsi/native-auto-parser.js) |

The source export matched 4,169 staged Git objects. Local verification passed
2,713 Flutter tests, 1,009 React Admin tests, 3,834 Edge tests, the frozen Deno
check, the PostgreSQL fixtures and the QA tooling suite. Seven opt-in Edge
tests were skipped. All 15 reviewed public route texts match their previous
digests.

### BuriMunsi full-stack refactor on 22 November

The BuriMunsi pass covers Staff, Admin Sync, the shared receiver, the managed API
and the Admin workflows that provision native access. The file inventory
records 1,103 paths against baseline `0590a466f`. The refactor modified 55
paths, added 36 and removed five. The inventory includes versioned migrations,
upstream source inputs, test fixtures and historical release records.
[File inventory](../assessments/2026-11-22-burimunsi-file-inventory.csv)

| Boundary | Source change |
| --- | --- |
| Android presentation | The Compose shell fell from 1,132 to 205 lines. Screens, sheets and input handling have dedicated files. Member import, document export and SMS disclosure have their own lifecycle handling. Deleted the unused panel stack. [Compose shell](../../native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/BuriApp.kt) · [Activity](../../native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/MainActivity.kt) |
| Android data and receiver | The repository now delegates session authority, command recovery, pairing, records and SMS requests. The inbox scanner delegates encrypted holds, read-only audit, old-row migration and provider queries. Removed the unused cursor updater and the duplicate core capture and acknowledgement logic. Host checks use the receiver predicates that run in the app. [Repository](../../native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/data/NativeRepository.kt) · [Inbox scanner](../../native/burimunsi/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/ObservationRecovery.kt) |
| Build and wire tooling | APK inspection and device evidence moved out of the build command. Both offline build types use one manifest and one endpoint configuration. Deleted the duplicate overlays. JDK preflight requires both Java and its compiler. The receiver extractor reproduced all 17 generated Kotlin files and its provenance byte for byte. Kotlin and Edge wire artifacts passed exact generator comparison. [Build command](../../native/burimunsi/scripts/native_pipeline.py) · [Receiver extraction](../../native/burimunsi/scripts/prepare_receiver.py) · [Wire generator](../../scripts/generate_burimunsi_wire.py) |
| Managed API | Single and batch reconciliation share the evidence checks. Partial SMS evidence, roster-source validation and the four Admin owner routes have shared implementations. Deleted the unused canonical route wrapper and promotion-assessment wrapper. [Reconciliation](../../supabase/functions/_shared/domain/burimunsi/postgres-observation-reconciliation.js) · [Roster source](../../supabase/functions/_shared/domain/burimunsi/smart-onboarding-source.js) |
| Provisioning and ingress | Provisioning, revocation and operator approval share the authority guard, pending-request lookup and lock. The frontdoor delegates bounded response reads and closes a pending stream on cancellation. [Native access](../../admin-web/src/features/burimunsi/nativeAccess.ts) · [Frontdoor](../../deploy/managed-native-ingress/worker.js) |

The BuriMunsi checks exercised 76 Admin provisioning cases, 29 ingress and
handler cases, four PostgreSQL nonce cases, 22 BuriMunsi PostgreSQL cases and
two Deno roster and PostgreSQL cases. The final Edge Node suite passed 3,834
tests. Six of its seven fixture-gated skips passed on a separate native
PostgreSQL run. The Iceberg case requires the networkless Docker fixture.
The 134 pinned files in the SMS continuation matched their recorded SHA-256
digests. The historical entrypoint is available at its exact recorded state
in source-intake commit `c1f2b366f027793c2c7ac2bbea5db702e1591662`.

The full Android host suite, 154 Python pipeline tests and 27 UI contract
checks passed. Gradle built eight APKs, which passed manifest, alignment,
DEX and applicable signing checks. All 385 Android build inputs matched
the staged Git bytes. The build fingerprint was
`71e994b2359f6ba2cbb82b7974e501c48c9e972e9458246024348ded75b53f91`.
The strict source export matched all 4,200 files on readback. The API 36
emulator passed 69 Staff and 89 Admin Sync tests and both startup checks.
The runner removed all four installed sandbox packages.

Permanent cleanup removed eight generated directories and freed 4,132,356,096
allocated bytes. This included the APKs, Gradle run caches, source export,
emulator, screenshots and logs. API 26 device checks, hosted qualification
and signed handset and carrier verification remain open.

### Admin panel full-stack refactor on 22 November

The Admin pass covers the React workspace, Cloudflare host, managed Supabase
API and direct consumers. The inventory records 977 paths against
`74d3fd3c4`. This pass modified 80 paths, added 64 and removed eight.
[File inventory](../assessments/2026-11-22-admin-panel-file-inventory.csv)

| Boundary | Source change |
| --- | --- |
| Admin records and operations | Dedicated modules load records, SMS, gateway devices, receiver grants, member receipts and email events. One panel renders the two existing device-trust workflows. Member and group actions share their directory scope check. Removed four superseded page and panel files. [Record routes](../../admin-web/src/app/workspace/record-routes.tsx) · [Operator routes](../../admin-web/src/app/workspace/operator-routes.tsx) |
| Session and workspace | Sign-in, recovery, owner verification and team services have their own modules. The browser API entry fell from 267 to 80 lines. Team state resets on a session change, and Escape returns focus to the account-menu button. The stylesheet imports foundation, shell, component and responsive rules in their original cascade order. [Browser API](../../admin-web/src/api/client.ts) · [Session controller](../../admin-web/src/session/AdminSessionController.ts) · [Styles](../../admin-web/src/styles/admin.css) |
| Managed API | The Admin bridge fell from 393 to 64 lines. Record reads, mutations, receipt history, reconciliation and MoMo review have dedicated owners. Group and person lookups now read the correct scope before querying. Removed the obsolete password implementation and its duplicate license. [Admin router](../../supabase/functions/_shared/domain/admin_bridge.js) · [Operations](../../supabase/functions/_shared/domain/admin_operations.js) |
| Cloudflare and PWA | The transport entry fell from 379 to 66 lines. Request admission, cookies, deadlines and qualified responses have separate modules. A dispatched request that exceeds its deadline keeps an unknown outcome. Static recovery proceeds while cancellation settles. Package creation removes its own partial output after a failure. A synthetic packager comparison matched the baseline byte for byte. [Worker transport](../../deploy/platform-admin/src/supabase-transport.js) · [PWA package](../../admin-web/scripts/package-pwa.mjs) |

The compiled fixture passed ten Chromium checks for sign-in, session custody,
read recovery, mobile deep links and static-only cache installation. React
passed 1,011 tests and type and lint checks. All 133 Worker and local challenge
tests, 372 direct API consumer tests, 179 historical D1 compatibility tests
and six PWA packaging and cache checks passed. Both Wrangler profiles passed
local dry runs with synthetic public configuration. All three 75-file
packages matched 351 staged build inputs, with source SHA-256
`689c4fffe6eb0942f5f474c8ff4024eb86d5fbc4809af8e36acb50f10d52f803`.

The strict source export matched all 4,256 files on readback. The managed Edge
suite passed 3,835 tests and all five frozen entrypoint checks. Six of seven
fixture-gated skips passed separately on PostgreSQL. The Iceberg Docker fixture
remains open. The Admin PostgreSQL cohort passed 86 checks, including receipt
history, SMS content, the password policy and real 300-second credential
expiry. Separate PostgreSQL tests exercised atomic financial review and
concurrent approval. Two historical invitation privacy cases still fail
against their older fixture schema, which lacks the managed-job ticket relation.
Hosted operator sign-in and exact installed predecessor handoff still need
release evidence.

Permanent cleanup removed eight generated directories and freed 653,611,008
allocated bytes. The removed outputs include the local packages, Worker bundles,
test caches, temporary dependency installs and source export.

### Admin frontend continuation on 22 November

The React package inventory covers 423 paths against `80695183e`. This pass
modified 94 paths, added 37 and removed two. It retains 290 paths, including
locked dependencies, licensed assets, tests, and source with an established
responsibility. [Frontend file inventory](../assessments/2026-11-22-admin-frontend-file-inventory.csv)

| Area | Implementation |
| --- | --- |
| Routing and session | Registered routes own their access rules. Transport admission, password actions, verification and recovery have separate modules. Predecessor authenticator recovery verifies the account before rendering its workspace. [Route access](../../admin-web/src/app/route-access.ts) |
| Financial records and recovery | Canonical records share exact-intent receipt checks. Legacy group status, person custody and journal validation have dedicated modules. Ledger account reviews stay with the record and version that opened them. Reconciliation lists load independently of decision forms. [Canonical recovery](../../admin-web/src/features/core/canonicalMutation.ts) · [Reconciliation queue](../../admin-web/src/features/reconciliation/ReconciliationQueuePage.tsx) |
| Operations and oversight | Gateway trust, receiver grants, email and SMS extraction share request custody. MoMo views separate SMS, payments and source review. A failed local save keeps the original reservation and prevents dispatch. [Operations custody](../../admin-web/src/features/operations/operationRequestCustody.ts) |
| Privacy and workspace | The privacy queue separates evidence reads, journal custody, review dispatch and presentation. Reconciliation, notes and request history bind displayed reads to their originating scope. The navigation drawer and dialogs share keyboard focus handling. [Privacy review](../../admin-web/src/features/privacy/reviewWorkflow.ts) · [Focus handling](../../admin-web/src/ui/useFocusScope.ts) |

Local verification passed 1,019 tests in 135 Vitest files, seven packaging and
cache checks, TypeScript, ESLint and the Revolut design-authority check. A
differential check matched 50,976 access decisions across all 59 registered
workspace routes against the previous implementation. The compiled 83-file
fixture passed 11 Chromium checks, including compact navigation and keyboard
focus, sign-in and return routes, a failed read and retry, and offline shell
installation. Hosted operator journeys and installed predecessor handoff
remain open.

### Collect member app full-stack refactor on 22 November

The member pass covers the Flutter app, its Android and iOS runners, the
browser fixture, and the managed Supabase member routes. The inventory
records 1,521 paths against `80695183e`. This pass modified 82 paths, added
49 and removed five, including the former name of the MoMo source test.
[File inventory](../assessments/2026-11-22-collect-member-file-inventory.csv)

| Area | Source changes |
| --- | --- |
| Flutter app and session | App lifecycle hosts now own notifications, receipt SMS and pending shared group links. The app entry class fell from 515 to 72 lines. The auth client and member repository entry files fell from 1,310 to 162 lines and 1,372 to 219 lines. Session custody, profile changes, offline snapshots and group discovery have dedicated modules. [Lifecycle](../../lib/app/lifecycle/) · [Auth](../../lib/core/cloudflare/collect_cloudflare_auth.dart) · [Repository](../../lib/shared/repositories/collect_repository.dart) |
| Member workflows | Contribution recovery and payment help have separate owners. Activity and Ledger share a refresh controller. Settings screens and privacy receipt rendering have direct imports. The Groups entry opens the metadata form directly on the supported platforms. [Contribution recovery](../../lib/features/payments/contribution_request_recovery.dart) · [History refresh](../../lib/features/history/member_history_refresh.dart) · [Member routes](../../lib/app/router.dart) |
| Native and browser | The Android entry fell from 794 to 84 lines and the iOS delegate from 613 to 177 lines. Separate native handlers own SMS access, MoMo, Play Integrity, protected stores and the sign-in challenge. The browser smoke target runs on loopback with synthetic member state and rejects identical captures of primary screens. [Android entry](../../android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt) · [iOS entry](../../ios/Runner/AppDelegate.swift) · [Browser fixture](../../tool/member_browser_route_smoke.dart) |
| Managed member API | Session projection, OTP, profiles, group creation and joining, contribution intents, balances, history, privacy email and SMS capture have dedicated modules. The refactor kept the 104 operation contracts and all 94 migration files. [Group commands](../../supabase/functions/_shared/domain/groups.js) · [Member history](../../supabase/functions/_shared/domain/member_history.js) · [SMS capture](../../supabase/functions/_shared/domain/member_sms_capture.js) |

Removed the superseded Settings and repository session modules, the no-op
platform helper for group creation and the duplicate managed identity-key
implementation. The MoMo source test now checks the native handler and its
registration. Retired state flags, unused MFA helpers and dead SMS branches
were removed from their calling code.

The isolated Flutter suite passed 2,713 tests, and the retained history
decoder passed six cases on each of the Dart VM and Chrome. The pinned Android
debug build passed 134 JVM tests and three offline emulator smoke cases. The
arm64 iOS simulator build passed all 44 route cases. All 38 browser fixture
routes rendered, with distinct primary screens. The Android and Swift
protected-store fixtures passed 12 tests. Analysis, formatting, capability
generation, source tooling and Revolut Design authority checks passed.

The managed Edge suite passed 3,835 tests with seven fixture-gated skips.
Frozen Deno checked all five entry points. The focused PostgreSQL run passed
six tests and 56 steps, and the history and balances smoke passed through
actual dispatch. A broader PostgreSQL run reproduced the same six
Admin-email, retention and notification failures on the starting revision.
The historical current14 qualifier stopped at its existing source-integrity
gate. The strict export matched 4,300 files on readback.

Removed the local APKs, simulator devices, build outputs, source copies, logs
and four stale golden failure images. Concurrent working-tree edits were
preserved separately. Hosted validation, signed distribution and real carrier
handoff remain open.

### Public website refactor on 22 November

The file-by-file review covered 236 paths against `1077d30da`. It records
48 modified files, 40 added files, 84 retained files and 64 deletions. The
site now has separate Ruby modules for page chrome, marketing and legal
content, share pages, and asset delivery. The browser bundle composes
navigation, group invitations and app links from their own sources. The
static builder stages a complete site before replacing its output. The
deployment validator receives only the public profile inputs it needs.
[Website file inventory](../assessments/2026-11-22-public-website-file-inventory.csv)

Qualification now shares HTTP, route, markup and report checks. The live CI
entry point retains each component report from one run. The obsolete external
audit wrapper was deleted. Its command is now
`bash scripts/public_website_completion_gate.sh --external-audit`.
IndexNow readiness and submission share the validated sitemap URL list.

The strict build produced 53 files and passed 55 static checks. All 15
reviewed page-text digests matched the prior contract. Chromium passed 60
page cases and 16 share-link cases at four viewport sizes. The loopback
fixture passed 37 HTTP checks and 13 audit checks. The local Wrangler dry run
completed. The source export matched 4,339 files at readback and rebuilt the
site from the exported source. [Reviewed copy contract](../release/public-website-current-content-contract.json)

All seven synthetic app screenshots reproduced their approved bytes. The
current capture and review live with the source needed to build the website.
The publisher retains previous hashes and removes transaction copies after
success or verified rollback. The cleanup deleted 63 exact screenshot copies
from older publication packets, reclaiming 24,204,690 bytes of duplicate
content in the checkout. Their canonical images are listed in the inventory.
[Current media receipt](../../content/public-website/app-media/2026-11-22/publication.json)

Hosted deployment and live production qualification remain open. The local
browser media review leaves native, legal and release approval open.

### Collect Admin MCP refactor on 22 November

The package inventory covers 66 paths against `1077d30da`. Domain modules
now own Admin reads, login evidence, retention checks, and desktop journal
custody. Structured input parsing is separate from request dispatch. A lost
input stream cancels active and queued calls, and a closed output stream
releases cleanup after a pending write. [MCP file inventory](../assessments/2026-11-22-admin-mcp-file-inventory.csv)

The catalogue and order of all 15 retained tools matched the baseline. The
refactor could open and write the baseline SQLite journal, which the baseline
implementation could reopen. Syntax validation covered 42 source modules and
the integrated suite passed 384 tests. The adjacent notification operator
consumer passed its 88 tests against the refactored authentication modules.

### Notification Operator refactor on 22 November

The package and shared frame-reader inventory covers 37 paths. The broker
server, connector and private state each have their own module. Tool schemas
now use the same field rules as request validation. Session replacement
fences delayed authentication replies. The journal admits a retry only
against the exact retained record, and reviewing returned content cannot
change the approved handoff. [Operator file inventory](../assessments/2026-11-22-notification-operator-file-inventory.csv)

All eight tool definitions match the baseline. Syntax checks covered 34
modules and fixtures, all 96 fixture tests passed, and the previous and
current implementations could read the same synthetic journal.

### Local workspace consolidation on 22 November

The launcher opens `main-source`. The enclosing folder retains the linked Git
store, the archived project image, and the native production and connector
paths. Both older connector commands forward to the mounted PRO-G40 helper.

The compact local branch reduces the active Git tree from 116,072 to 7,598
paths. Exactly 107,518 removed release paths match the independently verified
archive's Git modes and blob IDs. Other previously absent and relocated paths
remain in the named predecessor ref, alongside the original integration and
review branches. [Restore instructions](../release-evidence.md)

Release and UAT implementations now live under `scripts/release/`, browser
capture helpers under `scripts/qa/browser/`, and three dated root reports under
`docs/assessments/historical/`. The Make command set and manually used release
entry points were verified. Both synthetic Chrome capture modes passed.

### Working checkout refactoring on 22 November

| Boundary | Source change |
| --- | --- |
| Flutter member | Group management, join and invitations now use typed repositories behind the existing routes. Group metadata and payment actions have separate owners. The shared transport client fell from 1,898 to 272 lines, with dedicated modules for authentication, request contracts and Google authorization. [Group repositories](../../lib/shared/repositories/member_group_repository.dart) · [Client](../../lib/core/cloudflare/collect_cloudflare_client.dart) |
| React Admin | Sign-in, managed sign-out and authenticator recovery own their own protocol state. The session controller retains browser authority, epoch, refresh and transition coordination. Its size fell from 728 to 417 lines. [Session controller](../../admin-web/src/session/AdminSessionController.ts) |
| BuriMunsi | Listing downloads, navigation checkpoints, UI state and generation-bound IO have dedicated modules. CSV, XLSX and PDF use the same picker lifecycle. The controller now rejects a cancelled download after its final scope check if the app entered the background. [Listing downloads](../../native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/NativeListingDownloads.kt) |
| Managed Supabase | Observation evidence, scoped listing and reconciliation have separate owners. The existing adapter keeps its entry points and SQL statements. [Observation adapter](../../supabase/functions/_shared/domain/burimunsi/postgres-observations.js) |
| Build and website tooling | Five Make fragments own the member, Admin, verification, release and Supabase targets. All 83 target dry runs match the original recipes. Public marketing sections now have their own renderer file. The source comparison reproduced 18 HTML pages and the redirect table after normalizing the asset version. All 15 reviewed route texts match their recorded digests. [Makefile](../../Makefile) · [Marketing sections](../../scripts/public_marketing_sections.rb) |

The working checkout passed 2,713 Flutter unit and widget tests and strict
analysis, 1,009 React Admin tests and ten compiled browser checks, and 1,311
BuriMunsi controller, cross-layer and repository checks. The full Edge Node
runner, the frozen Deno check and eight disposable PostgreSQL cases passed.
The source integrity and tooling suites passed. A strict export verified all
4,158 source files against the checkout, including the new modules and Make
fragments. The exported copy also passed the local CI policy check and the
reviewed website content contract.

Hosted CI and signed-device validation remain open. The public-site build
requires fresh app captures because the runtime source fingerprint changed.

### Latest review branch verification

| Work package | Verified result | Remaining acceptance |
| --- | --- | --- |
| BuriMunsi Staff and Admin Sync | Both product configurations bind OCR consent and preview to the same picker request. A replacement, including a file selected at the same URI, needs fresh consent. The stream checks current authority before reading each further chunk. Across separate Activity controllers, a delayed checkpoint cannot replace a newer choice. Foreground refresh publishes the current operator even when its fields match the previous profile. The SMS inbox coordinator checks Android SMS permission before querying and before publishing observation pages. Page restoration and continuation now follow the originating operator, collection, route and session generation. A mismatched member detail is refused before it reaches the protected cache or history reader. A fresh or changed beneficiary lookup clears the earlier allocation selection and preserves the new search for retry. Both the review branch and the launcher passed 581 controller and 324 cross-layer checks. The earlier paging repository suite passed 406 checks. [Registration boundary](../../native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/NativeMemberRegistration.kt) · [Cross-layer tests](../../native/burimunsi/cross-layer-tests/MemberDocumentChecks.kt) | Repeat installed allocation recovery, picker, camera and OCR flows on approved devices. |
| React Admin | The QA and production profiles select Cloudflare for the sole React browser Admin and managed Supabase for its API. Directory reads, approvals and saved-request recovery now use the same role and capability rules as the backend. Tokens, proof reads and saved requests now stay with their verified session. Reconciliation accepts valid managed text principal IDs and verifies the current authority and exact retained intent before clearing receipts. The transport applies current HTTP 401 and 426 decisions even when a response body is unreadable. The review branch passed 1,010 React tests and the launcher passed 1,009. Both passed type checking and lint. [Role contract](../../contracts/burimunsi-api/operator-access.json) · [Cloudflare host](../../deploy/platform-admin/README.md) | Verify signed-in roles, open-tab upgrades and protected device delivery on the selected hosts. |
| Managed Supabase | The payer receipt worker verifies all parts of one original gateway attempt before recording send or delivery evidence. The approved OCR disclosure now decodes in the Android client and Edge. A cancelled read stops new dispatches and preserves the original journal reservation if work may have started. The Team roster and role matrix now share one snapshot that checks the current directory grant. The latest PostgreSQL fixture read the roster under an exclusive financial lock and denied the next read after grant revocation. The four writer and retention migrations advanced a separate 89-row fixture through row 93. [Receipt verifier](../../supabase/functions/_shared/opensms-receipts.js) · [Release command](../../scripts/supabase/cloud-release/writer-journal-release.mjs) | Qualify the four pending migrations in the drained, fenced window and reconcile real carrier evidence for a committed receipt. |
| Collect member | A Settings retry now rescans an SMS queue when foreground sync is finishing. The original owner, envelope and acknowledgement stay linked. Payment Help now shares one pending dispatch within the same session and retains the exact original request. Exact intent reads and the recent payment window now preserve newer observations and the verified pending count. All 2,705 ordinary Flutter tests passed on the review branch. The launcher passed all 246 focused payment, session and offline checks. [Receipt queue](../../lib/shared/repositories/collect_repository_sms_intake.dart) | Verify installed offline recovery and the actual USSD return. |
| Release checks and evidence | The Play gate now verifies the actual React package and its hosted bytes at the selected origin. All 31 workflow tests passed with local fixtures. Ten Receipt 150 files remain recoverable. [Play verifier](../../scripts/google_play_optimization_gate.sh) · [Evidence and dump search](../release-evidence.md) | Artifact qualification remains deferred. Original database replay still requires the external dump with the recorded hash. |

Source quality checks now require the writer-journal rehearsal in the pinned Linux PostgreSQL workflow. Its three runner guard tests and the 12-check PostgreSQL 17.11 rehearsal passed locally. The checkout inventory reconciles Java and Kotlin, Gradle, Flutter and Dart, Node, Deno and Supabase CLI declarations. The full QA tooling aggregate and source integrity gate passed. Linux execution in the pinned image remains unverified. [Toolchain and test commands](../ENVIRONMENT.md) · [Supabase workflow](../../.github/workflows/supabase.yml)

On 21 November, the managed Supabase registry matched the 89-migration predecessor in order, names and recorded SQL hashes. The four writer and journal revisions remain pending. GitHub has no Actions run for the reviewed PostgreSQL source commit. The latest CodeQL job on `main` was stopped before execution by an account billing lock. [Read-only verification](../implementation/2026-11-21-source-boundary-refactor.json) · [CodeQL run](https://github.com/ikanisa/COOL/actions/runs/44919661100)

Both verifiers also rechecked the earlier 4,279-file source export after one generated Python cache was moved to separate evidence storage. Its recorded manifest and all selected source bytes matched.

The latest independent source copy matched all 4,312 selected files and 187,577,914 bytes to Git at `c95cd6793`. Auth17, MoMo15, the writer and journal plan, 104 Cloudflare Admin checks, the toolchain inventory and public source checks passed from that copy. [Verification and source digests](../implementation/2026-11-21-source-boundary-refactor.json)

The current 4,312-file source inventory verifies 16 revised files directly against Git and reuses 4,296 exact hashes from the independent copy. The two reviewed payment repository hashes now match the capability registry. Generated Dart copy, all 18 reviewed HTML documents and all 15 route texts matched their predecessors in the local render using retained media metadata. The launcher also matched the 15 route text hashes. The QA tooling suite passed. [Current source verification](../implementation/2026-11-21-source-boundary-refactor.json)

Request-history lists and original-key lookups for Operations and Reconciliations now use the scoped read transaction. A committed request remained visible to its own principal during an exclusive financial write lock. Revocation denied both lists and both lookups. [Admin request handler](../../supabase/functions/_shared/domain/admin_bridge.js) · [PostgreSQL regression](../../supabase/functions/_shared/tests/admin_history.integration.test.ts)

The website text contract verifies all 25 inputs and 15 routes. The Play metadata exporter reproduces both current Fastlane descriptions, and the prior Console observations retain their original bytes. The source export includes the bounded text inputs needed to repeat these checks independently. [Public source comparison](../release/public-content-provenance/2026-11-21-rendered-source-copy-comparison.json) · [Source exporter](../../scripts/qa/collect_release_candidate.py)

Cloudflare is the sole React Admin deployment target in the current review branch and GitHub `main`. The managed Supabase QA and production profiles remain the selected API routes. [GitHub source change](https://github.com/ikanisa/COOL/commit/6c66fdb186e7c7d84b5528939a617888348bda14)

The managed archive source check matched 216 of 217 pinned inputs. The original `principal-mapping-preflight-author-final-20261114.log` remains unavailable. Its recorded digest is in the verification record. Receipt 150 still requires its separate original database dump. [Verification and source digests](../implementation/2026-11-21-source-boundary-refactor.json)

PostgreSQL connections, control leases and fenced transactions now have separate owners from the legacy SQL adapter. A local PostgreSQL 17.11 check verified exact numeric decoding and both Admin history routes during a held financial write lock. The Edge Node suite passed 3,839 tests with seven fixture skips. Both Edge and Admin history database suites now execute through the reviewed current email-proof migrations. All three cases passed on the review branch and the working checkout with separate PostgreSQL 17.11 fixtures. The CI source gate requires all three results. The pinned Linux job remains pending. [Verification and remaining checks](../implementation/2026-11-21-source-boundary-refactor.json)

The Payment Help changes added two reviewed capability inputs. All 18 HTML templates and 15 route texts matched the predecessor byte for byte. [Public source comparison](../release/public-content-provenance/2026-11-21-payment-help-source-copy-comparison.json)

A new self-contained archive packet matches all 110,302 paths in the previously verified release inventory. The packet check streams the stored Git blobs. The ten-file Receipt 150 unit also passed fresh restore and readback. [Evidence index](../release-evidence.md)

### Source work on 21 November

| Work package | Verified result | Remaining acceptance |
| --- | --- | --- |
| Collect member access and offline recovery | Same-owner refresh preserves Settings. Refused and interrupted private reads retain owner-specific markers. A later refusal survives a concurrent success. The Dart VM passed 2,688 ordinary tests and six historical SQL cases. [Implementation](../implementation/2026-11-21-member-cache-authority.json) | Verify sudden interruption on a physical handset and complete the real USSD return. |
| BuriMunsi and React Admin directories | The native selective next page fell from 1,085 ms to 45 ms at p95. React Admin’s final page fell from 314 ms to 69 ms at p95 on the same 100,000-member database. [Query measurements](../assessments/2026-11-20-burimunsi-members-profile.md#selective-names-and-deep-pages-on-21-november) | Verify authenticated hosted performance and representative handset rendering. |
| Admin, Edge and public evidence | React Admin passed 981 tests, type checking and linting. The Node Edge suite passed 3,827 and skipped seven. All 39 product capability inputs verify. Ten browser source files and three reviewed content inputs differ from the prior captures. [Verification record](../implementation/2026-11-21-fullstack-source-verification.json) | Resume browser, device, media and independent restore qualification after the owner lifts the deferral. |

### Source refactoring later on 21 November

| Work package | Verified change |
| --- | --- |
| BuriMunsi Staff and Admin Sync | Member paging, anchored restoration and registration decoding now have dedicated owners. Receiver Pair, Sync, Resume and Replace recheck the active operator, collection and visible scope before dispatch. Receiver resume schedules startup and held journal checks off the lifecycle caller. The 500 controller, 96 cross-layer, 128 observation and 106 gateway checks passed. The receiver service type-checked against Android API 36. |
| Managed Supabase | Core Admin projections and lookups use a guarded repeatable-read transaction that rolls back after reading, with no mutation admission. The exact migration rule and concurrent revocation passed. Standalone native attempt counters use their own database rows. V1 inspection reproduced 512 predecessor outcomes, and V2 still blocks the two unmapped journals. The BuriMunsi PostgreSQL suite passed 22 cases. |
| React Admin | The root router delegates workspace routes. The headless session controller owns session lifecycle and delegates sensitive email verification. The new regression caught an earlier proof reappearing during a later verification. All 982 tests, lint and type checking passed. |
| Collect member and public site | Contribution preparation refreshes current membership and balances independently of notification reads. All 2,689 Flutter unit and widget cases and six retained SQL decoder cases passed. The public renderer keeps structured data and its external script under a policy without inline script permission. The website source tests passed. |

At that checkpoint the retained browser captures differed in 11 of 354 inputs. The content record differed in four of 25 inputs. [Source and verification record](../implementation/2026-11-21-source-boundary-refactor.json)

### Supabase writers, retention and MoMo15

| Work package | Verified source result | Remaining acceptance |
| --- | --- | --- |
| Supabase write locks and grants | Local Admin session revocation and protected Storage journal work now serialize by session or object. They take a shared compatibility lock that still coordinates with financial and policy transactions using the exclusive lock. A new migration limits runtime write privileges to the columns used on seven private tables. Disposable PostgreSQL verified concurrent scopes, same-scope serialization, legacy compatibility and rollback on excess inherited grants. | Apply the additive migrations and check the active managed catalog and authenticated contention when release work resumes. |
| Retention journal ownership | The authorized V2 inventory now includes documented actors and beneficiaries through same-collection payment and posting records. Each journal caps hashed links at 100 and reports truncation. Both journals retain blocked erasure and an unknown total subject count. | Verify the installed functions, roles and subject links on the managed project. Additional or ambiguous parties still require independent evidence. |
| MoMo15 historical source | The original 1,607-byte Wrangler configuration was recovered from the Git object store and matched its recorded SHA-256. All 69 input roles reproduce the original operation inventory byte for byte. The recovered inputs preserve the sealed candidate independently of the active Wrangler configuration. | Compiled artifact and deployment qualification remain deferred. |
| Auth17 operation inventory | Reviewed the changes to payment evidence, queue SLA errors, oversized-request handling and the source freeze. Updated the three pinned source fingerprints and regenerated the inventory. The check passed for 52 source files and 17 migrations. Substituting any of the three earlier files still triggers the fingerprint guard. | Artifact qualification remains deferred. |

The verification record includes the new migration digests, recovery hashes and test results. The Node Edge suite passed 3,829 tests with seven fixture-gated skips. The BuriMunsi PostgreSQL suite passed 22. All eight MoMo15 source tests passed. [Source and verification record](../implementation/2026-11-21-source-boundary-refactor.json)

### T7 review branch recheck on 21 November

The recheck started at `d66a89113`. Auth17 and MoMo15 reproduced their expected inventories. The tracked source contains the React Admin and its same-origin transport. The former Flutter Admin references in the audit now lead to the retained source records. [Recheck evidence](../implementation/2026-11-21-source-boundary-refactor.json)

| Surface | Source result | Remaining acceptance |
| --- | --- | --- |
| BuriMunsi Staff and Admin Sync | Member restoration uses the verified window and viewport revision. Stale callbacks and pagination footers preserve the saved member anchor. List restoration uses the rendered headers. Allocation readback requires the original payment and a receipt version that includes the accepted allocation. | Verify installed process recovery and scrolling on signed packages on the intended handsets. |
| React Admin | BuriMunsi setup, directory and recovery replies stay with the initiating owner session and verification. An operator confirmation also rechecks the displayed group. The incoming MoMo SMS view coalesces outstanding reads and refreshes while visible on focus and reconnection. | Hosted owner, Admin and Staff journeys and the installed browser upgrade remain deferred. |
| Managed Supabase | The forward Storage migration limits inserts to the columns used by the journal. PostgreSQL controls completion fields, proofs and timestamps. Disposable PostgreSQL verified denied inserts, rollback of excessive inherited authority and exact replay through the journal. | The next fenced managed release must bind the four additive migrations in order and verify the installed grant catalog. |
| Collect member and public source | Notification timeouts and service errors preserve a verified financial refresh. HTTP access refusals on private reads block saved data even when the body is unreadable. All 39 capability source pins and nine generated consumers verify. | Physical recovery and USSD return remain open. The captured and current browser sources each contain 354 entries. Of the paths present in both, 20 have different bytes. One preview tool moved. See the latest review for the source-only copy check. Fresh captures and publication remain deferred. |
| CI and evidence custody | CodeQL watches the platform API modules and managed native ingress. Its analysis scope excludes the retained release archive. The plan and audit link to tracked sources and retained evidence records. | Hosted CI remains open. The release evidence index lists the current consumers and their exact inputs. The historical Receipt 150 database rollback requires its original dump. |

### Source admission and evidence custody follow-up on 21 November

An independent PRO-G40 Git object packet now holds the retained release tree.
A fresh offline restore matched all 110,302 paths and 7,637,671,247 bytes
against the original inventory. The restore verified modes and symlinks
inside a private destination. [Custody index](../release-evidence.md) · [Verification record](../implementation/2026-11-21-source-boundary-refactor.json)

The React Admin uses Cloudflare Workers in production and QA. Both profiles
select the active managed Supabase project. The Worker owns its local sign-in
challenge, which the T7 recovery server also uses. [Maintained Admin](../../deploy/platform-admin/README.md)

The T7 review branch and GitHub `main` now carry the hosting cleanup. The
GitHub change also removed the obsolete Makefile test. On that source, 130
Worker and sign-in tests, 372 Admin MCP tests and 56 workflow policy tests
passed locally. GitHub's billing lock stopped CodeQL before its first step.
Artifact qualification remains deferred. [GitHub change](https://github.com/ikanisa/COOL/commit/6c66fdb186e7c7d84b5528939a617888348bda14) · [CodeQL run](https://github.com/ikanisa/COOL/actions/runs/44919661100)

The retained member-history check now resolves nine exact inputs from Git in a
sparse checkout. The original fixture digest still verifies. The Admin Sync
queue preview now performs its final protected session and journal checks off
the UI caller. A newer query or changed operator invalidates an older result.
[Member-history check](../../scripts/qa/retained_member_history.py) · [Queue preview](../../native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/NativeReceiverQueuePreview.kt)

The cutover digest now covers the active React Admin, shared contracts, pinned
receiver source and backend version pins. The full-product export carries the
exact MoMo15 archive and configuration required for its inventory check. The
managed source planner binds the four pending migration bodies to the recorded
89-row predecessor and calculates each expected history digest. Applying the
cohort requires independent managed readback and the established fenced release
procedure. [Cutover source gate](../../scripts/supabase/cutover_gate.py) · [Managed source planner](../../scripts/supabase/cloud-release/writer-journal-plan.mjs)

The independent source export verified 4,279 files from `6df2250c5`.
Auth17, MoMo15 and the managed migration planner ran from the export. The
local source-integrity, design authority, tooling and Supabase source
checks passed. Signed builds, hosted acceptance and refreshed public browser
evidence remain deferred. [Source verification](../implementation/2026-11-21-source-boundary-refactor.json)

### Implementation checkpoint on 20 November

The local review branch is `codex/collect-fullstack-cleanup-20261120`. Commit `f3e234a2` contains the 343 Android and receiver inputs used for the final version 49 build. The original integration branch and its staging area were preserved. A local Git note under `refs/notes/collect-fullstack-qualification` records the clean-checkout checks for the qualified tip when those checks complete.

| Work package | Result in the local checkout | Remaining acceptance evidence |
| --- | --- | --- |
| Delivery and recovery tool dependencies | The member delivery lock now uses Addressable 2.9.2, matching the public default and RubyGems checksum. The retained Cloudflare API tooling resolves Miniflare to Undici 7.30.1. The npm lock changes one transitive package. [Source checks](../implementation/2026-11-20-dependency-source-review.json) | GitHub reported four high and one medium advisory on the former development pin. The archived Ruby packet retains its historical lock. The 21 November source follow-up above records the MoMo15 recovery. |
| BuriMunsi registration and allocation | Editing a name or MoMo number requires fresh identity, terms and consent confirmations. Allocation search, refresh and subsequent pages share the same query and payment identity. The final native source passed 499 ViewModel checks and 96 cross-layer checks. [Registration](../implementation/2026-11-20-burimunsi-registration-consent.json) · [Allocation](../implementation/2026-11-20-burimunsi-allocation-paging.json) | Qualify the signed Staff and Admin Sync packages on their intended devices. |
| Collect account deletion | CAPTCHA cancellation and late refusals belong to the initiating operation. A replacement session can request its own email verification. Recovery looks up the original request UUID. All 217 privacy and CAPTCHA tests passed. [Member source verification](../implementation/2026-11-20-member-privacy-challenge-ownership.json) | Signed-device privacy workflows, native CAPTCHA and real OTP delivery are deferred. |
| React Admin navigation | Sidebar links and direct routes now share one permission decision. All 20 entries and 55 audited routes retained their presentation and handlers. The source passed 981 tests and matched the predecessor across 1,500 permission cases. [React verification](../implementation/2026-11-20-react-admin-navigation.json) | QA v16 and production v37 predate this source change. |
| Public backend source | T7 branch `codex/burimunsi-managed-runtime-contracts-20261120` contains `a686b48f` on the observed public main. Five approved files were already present and 50 were applied. The 208-file runtime has one upstream dependency-lock change from the historical release. The Edge suite passed 3,906 tests, skipped seven opt-in cases and the wire and scheduler checks passed all 25 cases. [Source identity and workflow effects](../implementation/2026-11-20-public-runtime-source.json) | A feature push or draft PR starts Android and React artifact jobs. The commit is local while that work is deferred. |
| React source custody | Materialized and rebuilt the local Git tree `467c9eabbe934ff7ea610b410c5a4561af6e5951` with 538 product, transport and qualification files. The clean materialization passed 960 React, 118 transport, four packaging and five compiled Chrome checks. The original React archive and all 2,154 Flutter retirement records were independently verified. [Source and custody receipt](../implementation/2026-11-20-react-admin-source-qualification.json) | The review commits track the React source. Browser tests verified predecessor updates and rollback with retained packages. Production operator acceptance is recorded below. |
| GitHub default branch | Main reached `eb35a29e` with member receipt PR #85. All 44 changed paths matched its reviewed merge. The earlier React replacement is included. [Source and CI readback](../implementation/2026-11-20-public-runtime-source.json) | Billing stopped 22 PR jobs and 13 main jobs before their steps ran. |
| Full-stack Git source | A clean clone of `0a0ef6f5` contains 334 tracked React files and no Flutter Admin entrypoint. The strict export matched all 4,234 files and 186,524,064 bytes. The React production profile used the configured public inputs and passed the commit and hosting checks across 44 files. [Commit and build evidence](../implementation/2026-11-20-fullstack-source-qualification.json) | Local review branch. Remote CI, hosted roles, physical upgrade and carrier delivery require separate verification. |
| Hosted Admin consolidation | Production and QA serve the sole React panel. Three former custom hosts and the Pages address hand off to React. Cloudflare retired the four June Pages deployments. Both canonical hosts passed 44 static checks after the managed database reopened. Chromium loaded the React entry, registered its service worker, displayed sign-in and received HTTP 200 for the anonymous session on both hosts. [Hosted cutover](../implementation/2026-11-20-react-admin-live-cutover.json) · [Post-release browser verification](../implementation/2026-11-20-managed-seven-release.json) | Complete owner email sign-in and cross-tab sign-out. No active linked Admin or Staff account was available for those hosted journeys. |
| BuriMunsi collection posting | Payment submission revalidates the beneficiary and returned payment ID. All 78 cross-layer assertions and all 158 emulator tests passed. On an unlocked Pixel 4a, 69 Staff and 89 Admin Sync cases passed on Android 13. Both v49 test packages also preserved encrypted v48 fixture records through installed upgrades. [Collection and handset evidence](../implementation/2026-11-20-burimunsi-collection-posting.json) | Qualify distribution-signed packages on their intended channel and verify a genuine carrier outcome. |
| BuriMunsi import lifecycle | A feature-owned Kotlin controller binds each picked document or camera result to the operator, collection, import flow and exact selection. A late read or preview cannot publish over a replacement. Canceling a replacement preserves the original selection. All 30 smart onboarding checks passed. Eight APKs passed inspection, followed by 68 Staff and 86 Admin Sync instrumentation tests on an API 36 emulator. [Import state](../../native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/MemberImportInputs.kt) · [Android verification](../implementation/2026-11-20-burimunsi-android-verification.json) | Physical picker and camera lifecycle and carrier behavior. Collection posting and receiver state still share responsibilities with the main ViewModel. |
| BuriMunsi and React Admin member lists | Profiled first and next pages at 1,000, 10,000 and 100,000 members. Avoiding unnecessary phone and balance work cut the idle first-page p95 for the 100,000-member active-name search from 8,447 ms to 74 ms. Native session revocation now returns 401 before loading the device binding. The independent SQL comparison covered eight sorts and 21 query combinations. [Measurements and query plans](../assessments/2026-11-20-burimunsi-members-profile.md) | The 21 November local profile covers selective searches and deep offsets. Hosted latency and low-end handset rendering remain open. |
| React operator and installation recovery | A sibling tab can resolve the original uncertain approval. Replacing an installation request invalidates stale actions. The Edge handler checks guarded provisioning support again in the transaction. All 960 React tests passed. Disposable PostgreSQL 17 exercised a changed capability with zero recorded effects, successful retry and exact replay. [Operator approval](../../admin-web/src/features/burimunsi/operatorApproval.ts) · [Provisioning service](../../supabase/functions/_shared/domain/burimunsi/admin-provisioning.js) | Verify operator roles and protected delivery on the intended Admin host and receiving handset. |
| PostgreSQL journal authority | The managed release made the audit journal append-only and narrowed runtime updates on receipt and retry journals. The local PostgreSQL tests passed all 13 checks. A separate managed connection verified the release catalog and recorded history. [Grant tests](../../scripts/supabase/cloud-release/burimunsi-runtime-grants.test.mjs) · [Managed release](../implementation/2026-11-20-managed-seven-release.json) | The matching Edge functions are deployed. Verify protected operator denials through an authenticated hosted role. |
| Native session restoration | Extracted the session owner and reproduced ten stale-state failures across Staff and Admin Sync. All 18 session cases now pass, including another activity signing out, same-identity reauthentication, narrower grants and retrying a saved session. [Session owner](../../native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/NativeSessionBootstrap.kt) | Physical lifecycle and managed sign-in qualification. |
| Payment reference | The managed database allocates immutable 12-digit payment references. Restoration preserved existing payment fields and confirmed the allocation and write restrictions. Native detail and search retain provider and source IDs. [Database tests](../../scripts/supabase/cloud-release/burimunsi-payment-reference.test.mjs) · [Restored managed data](../implementation/2026-11-20-managed-restored-data-rehearsal.json) | The live catalog confirms 11 distinct references for 11 payments. Verify authenticated lookup in React and on the signed Android package. |
| Managed history and recovery | All seven SQL migrations are applied. The managed project has 89 ordered history rows. An isolated restore recovered 272 table-data entries, 36 roles, 31 role memberships and all 61 Storage objects. Each migration preserved the payment and ledger counts and amounts. At 15:41 UTC the ordinary scheduler completed with HTTP 200 at epoch 44 and made zero native-provider calls. [Managed release](../implementation/2026-11-20-managed-seven-release.json) · [Restored data](../implementation/2026-11-20-managed-restored-data-rehearsal.json) | Verify provider-equivalent PGroonga catalogs, event-trigger ownership, historical Realtime replay, and original application decryption. A genuine payer receipt and carrier delivery remain unobserved. |
| Deployed runtime and scheduler | Corrected an HTTP 503 when maintenance intentionally held the payment worker. An admitted, unresolved payment still returns HTTP 503. At epoch 48, the authorized probe and the automatic 16:27 UTC run completed with matching response hashes and zero provider calls. The managed project held 11 distinct valid payment references and 11 ledger entries. Both React hosts passed 44 static checks and an anonymous session read. [Live runtime evidence](../implementation/2026-11-20-managed-runtime-epoch48.json) | A genuine pending payer receipt, carrier delivery and authenticated operator workflows remain open. |
| BuriMunsi SMS release compatibility | Recovered the three deployed observation reconciliation routes and the Admin Sync queue caller. Version 49 reuses the original held request and preserves its consent record when present. The managed profile refuses unsupported raw recovery before processing SMS content. The client requires zero financial effects in observation acknowledgements. [Server reconciliation](../implementation/2026-11-20-burimunsi-observation-reconciliation.json) · [Signed-client compatibility](../implementation/2026-11-20-burimunsi-held-sms-compatibility.json) | Qualify the exact production-signed Staff and Admin Sync upgrade pair and confirm provider delivery on an authorized handset. |
| Historical Staff command recovery | An exact pre-PIN Staff-create retry can retrieve its original account and version. The actor, group, operation and body must match. New Staff accounts require an explicit PIN. A new receipt distinguishes an explicit PIN from a missing one. The HTTP and PostgreSQL fixtures check both paths. [Staff replay evidence](../implementation/2026-11-20-staff-replay-and-native-parity.json) | A historical receipt created without the new discriminator cannot distinguish an omitted PIN from an explicit PIN with the same protected digits. |
| Installed BuriMunsi upgrade and Sync status | The clean version 49 build produced eight inspected APKs. The API 36 emulator passed 69 Staff and 89 Admin Sync tests. Replacing each installed version 48 test package with version 49 preserved its identity and encrypted state. A Pixel 4a on Android 13 also passed both installed replacements with encrypted synthetic state. Pause, replacement and retirement invalidate an old Sync success. [Physical handset upgrade](../implementation/2026-11-20-burimunsi-physical-handset-upgrade.json) [Installed upgrade and foreground verification](../implementation/2026-11-20-burimunsi-installed-upgrade-verification.json) | Verify the exact signed distribution packages on physical phones, including carrier results, and confirm the intended organisation can receive the private release. |
| Collect member verification | Corrected the 11 prior failures. The first integrated run passed 2,649 Flutter tests and the Chrome sync case. The original 483,310-byte SQL packet was then recovered. Its six decoder cases pass on both Dart VM and Chrome through the dedicated CI target. [Initial integrated result](../implementation/2026-11-20-collect-integrated-verification.json) · [Recovered history evidence](../implementation/2026-11-20-fullstack-source-qualification.json) · [Current test entrypoint](../../scripts/qa/retained_member_history.py) | Verify real USSD handoff and return on an eligible handset. |
| Member account, groups and receipt consent | Auth, Settings and collection screens use feature-specific interfaces. Consent writes recheck authority and connectivity after durable storage. The full member run passed 2,653 tests. Fifteen public pages and seven browser screenshots retained their reviewed content. [Member verification](../implementation/2026-11-20-member-account-group-consent.json) | Confirm carrier delivery and the physical USSD return. |
| Collect member payment and history | The contribution screen and payment-help sheet now use a typed payment interface. Activity, Group and Ledger use the extracted history interface. Payment status binds each intent to its group and requires a committed ledger record to show credit or reversal. The routed ledger test covers a response for the wrong group. [Payment and history interfaces](../../lib/shared/repositories/member_financial_repositories.dart) · [Member history](../../lib/shared/repositories/collect_repository_member_history.dart) | Exercise the USSD return and privacy workflows on a signed device. |
| Collect member SMS intake | Receipt processing keeps the original envelope and checks the member, session and permission again after each asynchronous callback. The predecessor failed 11 cases. The successor passed 100 matching cases, 615 expanded Flutter checks and all 26 Android JVM tests. The two Swift origin checks accepted five configured origins and rejected five mismatches. [Source and results](../implementation/2026-11-20-collect-member-sms-intake.json) | Verify a consented carrier receipt and complete native iOS challenge presentation. |
| Public capability evidence and website | The historical capture at `a45f210e` matched 354 source inputs and reproduced seven reviewed images. Two local builds matched on 52 files, including all 18 HTML documents. The current engineering registry verifies all 39 capability inputs. [Source and capture identities](../implementation/2026-11-20-member-managed-project-profile.json) | Four browser inputs differed on 20 November. On 21 November there were ten, with three changed content inputs. New capture, rendered comparison and publication qualification are deferred. |
| Public generator | The build command now calls separate route, asset and publication modules. Requiring the Ruby renderer performs no build. All 23 routes and redirects survived. Across 53 build files, only cache versions in 18 HTML documents and the generated timestamp changed. All 15 reviewed page texts, 55 site quality checks, 76 generator tests and 15 navigation tests passed. [Generator entry](../../scripts/public_static_site_build.rb) · [Before and after](../release/public-content-provenance/2026-11-20-site-generator-comparison.json) | Chrome passed 60 route checks and 16 group invitation checks across four viewport sizes. Both Flutter source contracts now follow the extracted asset module. Hosted website publication remains open. [Browser results](../implementation/2026-11-20-public-group-rendered-qa.json) |

## 1. Establish the source and release baseline

| Work package | Implementation | Exit evidence |
| --- | --- | --- |
| Source ownership | Use the launcher-selected linked worktree as the integration root. Reconcile its existing changes by owner. Inventory and separately admit the T7 React source, lock, review host, contracts and tests into a tracked candidate. Exclude local configuration, credentials, dependency caches and generated output from source admission. Record the original React source fingerprint before moving paths. | A fresh checkout materializes every maintained source package. The release manifest maps each build and command to a commit, toolchain, profile and artifact. Two local directories can no longer silently supply different implementations. |
| Reproducible quality gates | Retain the fixture and workflow corrections from this pass. Resolve the mixed Node/Deno test discovery, public capability and capture drift, and the remaining Flutter failures by member workflow. The Admin build and browser tests run from `admin-web/`. Give browser fixtures an explicit execution lane. Bind each check to its source and runner. Review Java/Kotlin, Dart, Node, Deno and Supabase CLI pins as one checked-in inventory. | Clean checkout gates run successfully on their declared operating systems. Each selected test is counted, including skips with reasons. The Admin test builds the cookie-authenticated release entrypoint or exercises the exact release artifact. |
| Evidence custody | Map references that consume `docs/release` files, including migrations, source manifests, acceptance scripts and rollback tooling. Classify retained records by custody and access. Inventory each preserved path, hash, bytes and source commit. Test restoration of complete units from a retained store before removing any working-tree duplicate. Keep active manifests and operational instructions discoverable from the root. | A second checkout can restore and hash-check the complete units with their original path mapping. Current builds, recovery tools and cited release records resolve through the documented source map. Record tracked path count, checkout size and CI duration before and after. |
| Release and restore identity | Compare the exact ordered current-cloud migration bodies with the managed history. Identify the active API, Admin host, scheduler, receiver and outbound SMS producer. Bind database, Auth, runtime roles, object storage and artifacts to the same restore point. | Upgrade from a representative prior snapshot and build from an empty synthetic environment. Restore synthetic database, Auth identities, restricted object bytes and usable roles together. Exercise legitimate and denied queries and compare financial totals. Record the reversible artifact and database recovery procedure. |

Keep the preserved T7 checkout, linked Git object store and immutable release captures intact while these packages run. Use exact path mappings for byte-identical captures. Repository history compaction requires a separate, recoverable migration after evidence consumers are reconciled.

### Phase 1 progress

On 20 November the receipt 150 rollback evidence packet was restored from the committed Git tree into an empty directory on the Mac. All ten paths, regular-file modes, blob identities and 330,330 bytes matched. Three consumers resolved against the restored files. A second restore used independent PRO-G40 Git objects with remote fetch disabled. All ten paths, modes, hashes and three consumers matched again. The PRO-G40 archive measured 57,469 bytes at that checkpoint. Its former location was removed during disk cleanup. The original database dump remains external. [First restore](../implementation/2026-11-20-receipt150-release-unit-restore.json) · [Independent restore](../implementation/2026-11-20-independent-release-unit-restore.json)

Before disk cleanup, a fresh restore on PRO-G40 matched all 2,154 retired Admin paths, their modes and 28,381,865 source bytes. The former Android upgrade folder also held both version 48 packages, both version 49 successors and their instrumentation packages. The external working copies were subsequently removed. The Git records retain the checks that ran. [Admin recovery record](../implementation/2026-11-20-admin-retirement-independent-restore.json) · [Handset upgrade record](../implementation/2026-11-20-burimunsi-physical-handset-upgrade.json)

The strict Flutter analyzer passed and `make format-check` passed across 1,107 Dart files. The focused rerun passed 253 cases covering session custody, public Groups, member history, Admin setup, and MoMo preparation and recovery. A separate Admin roster run passed 66 cases with one skip. The repaired Groups and history fixtures exercise the production shell and the full member-scope reload. Both MoMo fixes release the current operation after a changed receiver or a retained handoff. The regressions verify zero additional handoffs or dialer launches. [Changed receiver and original request regressions](../../test/features/contribution_prelaunch_guard_test.dart#L205).

The Flutter results above describe the 18 November pre-retirement snapshot.
The 19 November consolidation uses `admin-web/` for the Admin build, hosting,
CI artifact and browser smoke. The retirement record identifies the former
Admin sources, scripts, CI and host configurations by path and digest.

| Verification | 19 November result |
| --- | --- |
| React source and package | Fresh `npm ci`, TypeScript checks, lint, 956 React tests and four PWA package tests passed. An isolated clean checkout built the production profile with synthetic public settings. Verification refused a changed commit, configuration, source file and artifact. |
| Compiled browser and transport | Five loopback checks passed, including OTP, cookie session reload, anonymous deep link, sign-out and a service-worker-controlled reopen. All 118 platform Admin transport tests passed. |
| Collect member source | Strict Flutter analysis and format check passed. The compiled member media fixture loaded its assets from the local origin. Nine member payment-help tests passed after the fixture released its session timers before Flutter's test cleanup. |
| Full Flutter suite excluding integration tags | 2,634 passed, 11 failed and one skipped. Failures include seven contribution recovery cases, one USSD accessibility case, two roster filter cases and the Groups dark golden. The same Groups golden difference reproduced against the archived pre-retirement source. |
| Shared gates | At the initial checkpoint, source integrity, Revolut Design authority and local CI policy passed. The tooling suite stopped on a pre-consolidation capability digest. All 39 capability inputs verify on the 21 November source. Rendered content qualification remains deferred. |

The 20 November checkpoint verified the retained member browser sync and refreshed public-site evidence. The managed browser and restored database, Auth catalog and Storage results are recorded in the implementation checkpoint. [React build commands](../../admin-web/README.md)

## 2. Untangle the backend and financial processing

| Work package | Implementation | Exit evidence |
| --- | --- | --- |
| Member and Admin read queries | Profile BuriMunsi Members and Admin Members with representative 1k, 10k and 100k scopes, common filters, ledger volume and concurrent writes. Move the native snapshot work to bounded PostgreSQL pages and aggregate projections. Use stable sort keys, a unique tie-breaker, signed scope/query/revision and indexed normalized search. Keep Admin totals, role scope, active-group logic and exact recorded amounts. | Native and Admin query results match fixtures for each sort, filter, page, scope and stale cursor. One page materializes a bounded number of rows. Compare query plans and p50/p95 first-page and next-page latency. Verify that registration, posting and revocation can run concurrently with list browsing. |
| PostgreSQL authority boundary | Separate the legacy compatibility adapter from current PostgreSQL query services. Identify every caller of the shared compatibility lock. Introduce a read authorization path with equivalent role and current-grant checks. Replace the broad write lock domain by domain only after proving its invariants. Narrow runtime grants by bounded feature and keep protected storage and application context scoped to each transaction. | Allowed and denied route-by-role and route-by-collection fixtures, including revoked grant, invalidated session, pooled transaction rollback and concurrent writes. Database readback confirms the deployed roles, policies and function execution scope match the admitted catalog. |
| Receiver, posting and payer notification | Define one durable lifecycle from received envelope to evidence, member match, ledger effect and payer notification. Retain the selected automatic credit policy and name/suffix match, with an unresolved branch for ambiguous evidence. Preserve exact acknowledgement, original command and attempt IDs, deterministic duplicate handling, audit and reversals. Locate the active payer-SMS producer, then bind each eligible notification intent to the committed payment and balance snapshot with Kinyarwanda copy. | Synthetic mixed-SIM, duplicate, retry, pause/restart and lost-commit cases produce at most one credit and one intended notification. Distinguish queued, posted, unmatched, blocked and provider outcome in metrics. A consented controlled carrier journey ties receipt, ledger balance, outgoing SMS and provider report to the same existing keys. Check independent provider reconciliation and reversals. |
| Short payment reference | Qualify the requested 12-digit display and search reference with independent durable allocation. Carry the original payment and source identifiers through native receipt matching, Admin recovery and reversals. Reuse the candidate field contract after resolving compatibility of allowed payment updates and retention. | Concurrent allocation and retries keep identity stable. Historical records resolve by supported references, stored data restores intact, and authorized retention removes the right copy without resurrecting old identifiers. |
| Privacy and lifecycle | Reconcile V1/V2 retention inventories and current catalog. Move toward the maintained version with explicit caller compatibility and allowlisted resource classes. Bind OCR input, owner, collection, flow and disclosure version to the processing reservation. Verify imports, authentication and delivery provider choices against the source profile. | Unknown classes fail closed. Expiration and deletion cover protected Storage and database pointers, and authorized retention exceptions survive. Picker results are rejected after logout or flow change. Unknown external effects recover by the original server record. |

Keep operator-recorded evidence, ledger posting and provider settlement separately visible in the data and UI. Measure queue age and outcomes by state so that a successful scheduler invocation cannot stand in for reconciled work.

### BuriMunsi migration order

The managed project recorded entry 1 in its original 82-row history. On 20 November it applied entries 2 through 8. An independent connection verified all 89 rows against the ordered history digest. Writes reopened after the database changes at epoch 44. The corrected Edge runtime and automatic scheduler were subsequently verified at epoch 48. [Managed release](../implementation/2026-11-20-managed-seven-release.json)

1. [20261118090305](../../supabase/migrations/20261118090305_burimunsi_automatic_payment_sms.sql) restores the existing automatic receipt journal and original gateway identity.
2. [20261119041000](../../supabase/migrations/20261119041000_burimunsi_ocr_disclosure_binding.sql) adds the protected import flow and disclosure version to new OCR reservations.
3. [20261119041100](../../supabase/migrations/20261119041100_burimunsi_payment_sms_status.sql) records exact unarmed refusals as suppressed and preserves all armed attempts.
4. [20261119114500](../../supabase/migrations/20261119114500_burimunsi_members_keyset.sql) adds stable member ordering helpers, indexes and revision invalidation.
5. [20261119114600](../../supabase/migrations/20261119114600_burimunsi_admin_sms_health.sql) supplies scoped recording and delivery counts to React Admin.
6. [20261119114700](../../supabase/migrations/20261119114700_collect_payment_display_reference.sql) assigns immutable display references and extends the canonical payment backup shape.
7. [20261120075011](../../supabase/migrations/20261120075011_burimunsi_native_journal_runtime_grants.sql) narrows writes to the BuriMunsi runtime audit, receipt and retry journals under the fenced migration role.
8. [20261120104500](../../supabase/migrations/20261120104500_collect_payment_reference_authority.sql) limits payment writes to the predecessor columns, protects the allocator and admits the new column to the supported retention inventory.

The next four SQL revisions narrow writer grants, link retention journals to their subjects, narrow Storage insert grants and add verified posting participants. Each applies to one exact history prefix, advancing the 89-row predecessor through rows 90 to 93. The two journal classes remain blocked in the local inventory. Their installed immutable catalog definition has the same SHA-256. Direct hosted evaluation timed out, so the release command requires both class values again when it inspects the live window. [Ordered migrations](../../scripts/supabase/cloud-release/writer-journal-source.mjs) · [Release preflight](../../scripts/supabase/cloud-release/writer-journal-catalog.mjs)

The working migration bodies have these SHA-256 digests.

| Version | SHA-256 |
| --- | --- |
| 20261118090305 | `103ca560b8915450834ad11a5553921b71c132fb845d5f0a781ca4aeebae762f` |
| 20261119041000 | `23c69a15a42c8b8e4ca03c79bf10561ce3ab2a8ecfdb1877f5feadb3337effc5` |
| 20261119041100 | `5da5ce98a40945230a0da8d50052c903a6efbc2a8183cb4b0ebff78026c0bee3` |
| 20261119114500 | `e8926c2a723ecdb24f220c70a6d8b809988d90d3c95f5b8d4e52d0cba7747873` |
| 20261119114600 | `91c9f9048656d5361d6afd68fe5fc6c2dbc3e8f8f3310d90798ce378f22489ce` |
| 20261119114700 | `6d1e4ab861909758074afba21db6ba39cb23de8497ba474e01d30c8e90b0f33c` |
| 20261120075011 | `975e14d20c982e8d389650b9dfdeeb93d94337189f765508af6938468792d27b` |
| 20261120104500 | `118ad88fa6c967bdf04934c0cb8c4e63fd472a97f9a5f8165d18597bc93c4cd5` |

Rehearse the sequence on a restored, fenced database. Verify former and
current client contracts, retention inventory and exact eligible payment
graphs before promotion. Pair the new external OCR contract with the Android
build that sends the disclosure and flow fields. Older clients continue to
use the current session and supported non-OCR formats. Back up the payment
reference sequence with the data. Confirm a new allocation after the restore.

Run `make burimunsi-postgres-test` for the local PostgreSQL 17 evidence. The
member fixture exercises groups of 1,000, 10,000 and 100,000. PostgreSQL returns
at most one page plus its continuation sentinel to the service. For a selective
text result of at most 100 members, PostgreSQL can sort the complete matched set internally. The payer
receipt fixture checks claim ownership, suppression, lost acknowledgement and
scoped aggregate reads. Use the [current audit results](../assessments/2026-11-18-full-stack-code-audit.md#19-november-burimunsi-remediation)
to distinguish local passes and the remaining managed and device gates.

## 3. Refactor app boundaries through working routes

### BuriMunsi Staff and Admin Sync

- Extract session/bootstrap, member browsing and registration, collection posting, and receiver status from `BuriViewModel` into feature-owned state and use cases behind the existing repository interfaces. Keep a single composition root per flavor and route presentation driven by pure state. Move protected disk reads to IO-owned repositories and revalidate authority before effects.
- Use stable row anchors for restoration. Preserve prior checkpoints through an adapter and verify back navigation, filter changes, list mutations and process death. Keep camera, picker and OCR results bound to their original operator and flow.
- Preserve package IDs, signing lineage, approved permission masks and installed encrypted queue compatibility. Test Staff and Admin Sync separately against the same versioned wire contracts. Measure cold start, first member page, background sync and offline recovery on a representative lower-end device. Qualify the exact signed build and intended organisation visibility for IKANISA's private Managed Google Play distribution.

### Collect member app

- Keep the Flutter app entrypoint and its routing. Extract typed account/session, group read, payment intent/history, receipt consent/intake and privacy boundaries from the catch-all repository and DTOs. Migrate feature by feature through existing providers while preserving deep links, protected caches and owner-bound queued commands.
- Keep load and mutation ownership checking at async boundaries. Add targeted tests for account switches, offline resume, expired links, duplicate command recovery and truthfully pending or unavailable balances. Exercise real USSD handoff and return separately from fixtures.
- Validate Android build variants and their permissions before signing. Keep Android and iOS build configuration explicit, and verify the applicable platform acceptance on each delivery lane used.

### React Admin panel

The React PWA is the sole Admin implementation in the current source tree. The
production, qualification and fixture profiles use the same app and produce
separate artifacts. Native BuriMunsi device capture and Staff workflows continue
from their existing Android apps. The dated retirement record documents the
former browser implementation.

| Priority | Remaining qualification | Exit evidence |
| --- | --- | --- |
| P0 · Operator access | Exercise the intended Supabase origin and each supported Admin role. Verify account admission, OTP delivery, email re-verification, sign-out across tabs, permission revocation and applicable Google or authenticator policy. | Owner, Admin and Staff journeys pass through the actual host. Revoked grants and expired sessions deny the next access. |
| P0 · Financial actions and recovery | Inventory each operator write and its server capability, model and recovery contract. The current React route negotiates guarded approval, PIN setup and installation revocation. Qualify the native grant and protected delivery workflow on the selected host and device. Keep settlement separate from recorded evidence. | Working routes and denied roles agree with the current API. An uncertain write resolves with its original key. The published capabilities reflect verified operations. |
| P0 · Hosted and installed migration | Bind the exact approved React site, selected Supabase profile and predecessor rollback artifact. Test old bookmarks, pending requests, stored drafts, offline tabs, and upgrade after all existing controlled tabs close. | Every current Admin origin resolves to the same panel or its documented redirect. Prove browser and installed-client recovery through the actual host before promotion. |
| P1 · Maintainability | Split route composition, session recovery and resource features behind typed request and response schemas. Preserve permission names, original request keys, errors and layout states while migrating each consumer. | Compiled browser checks cover critical role routes, browser Back and genuinely failed and unavailable states. The request history and permission tests cover changed routes. |

### Public website and common contracts

- Split the public generator by route composition, legal content rendering, shared assets and publication metadata. Keep existing URL and redirect contracts. Resolve source evidence drift by reviewing affected facts and refreshing the applicable capture from the exact qualified fixture. Keep photos, typography and screenshots as product evidence.
- Reuse existing generators for UI copy, BuriMunsi wire types and deployment-profile parsing. Make server schemas own capabilities, permissions, pagination and versioned response shapes. Use shared fixtures to keep Kotlin, Dart, React and Edge consumers aligned. Remove duplicate adapters only after every current caller is identified.
- Use the selected Revolut Design references directly when changing shared components or states. Preserve the Collect and BuriMunsi identities. Verify loading, empty, failure, disabled, authorization, offline and responsive states against the applicable native, operator or public web references. Run `make revolut-design-authority` for affected references, themes and shared components.

## 4. Qualify promotion and retire obsolete paths

1. Demonstrate current-client and predecessor-client compatibility for every changed contract. Include existing stored data, active sessions and pending operations.
2. Capture local tests, clean-checkout CI, artifact digests, role readback, account-scoped browser checks and signed-device tests as distinct evidence. Reconcile capability copy and visual captures against the exact product build. Record unresolved platform, provider and operator checks explicitly.
3. Rehearse recovery using matching data, storage, scheduler and artifact identities. Keep legacy D1/R2 and alternate ingress recovery material indexed by their actual consumer until recovery is proven. Compare any data change with preserved balances and record counts before and after.
4. After the supported paths have a verified handover, remove unused adapters, candidate binaries and obsolete workflow entrypoints through small changes. Rerun ownership, route, secret, build and recovery checks against the resulting checkout.

## Expected repository layout

| Maintained boundary | Source location and contract |
| --- | --- |
| Collect mobile | Root Flutter package, `lib/main.dart`, feature modules, Android and iOS wrappers. Keep reusable runtime logic behind typed ports. |
| Admin | `admin-web/` owns the React Admin frontend and PWA packaging. `deploy/platform-admin/` owns the same-origin Supabase transport. |
| BuriMunsi | `native/burimunsi` with common core, feature-owned state, and separate Staff and Admin Sync composition and permission boundaries. |
| API and jobs | `supabase/functions` and explicit PostgreSQL service adapters. Keep migration sources, current-cloud execution plan and immutable predecessor identities separately indexed. |
| Hosting and tooling | Active transport, static public generator, CI and operator tools with an explicit owner, consumer and environment for each. |
| Retained evidence | Compact active index linking content-addressed archives and restoration instructions. Keep full historical packets and dormant runtime snapshots in verified custody. |
